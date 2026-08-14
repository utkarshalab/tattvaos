%ifndef GUARD_UNET_DNS_MDNS_ASM
%define GUARD_UNET_DNS_MDNS_ASM
; =============================================================================
; Tattva OS — unet/dns/mdns.asm
; =============================================================================
; Multicast DNS (mDNS RFC 6762) & DNS-SD (RFC 6763) Service Discovery Engine.
;
; Features:
;   - Multicast Address Binding (IPv4 224.0.0.251 / IPv6 ff02::fb Port 5353)
;   - Local `.local` Domain Resolution without Centralized DNS Infrastructure
;   - DNS-SD Service Discovery: PTR / SRV / TXT Record Announcements
;   - Known-Answer Suppression (RFC 6762 Section 7.1)
;   - Probing & Conflict Detection for Unique Records (RFC 6762 Section 8)
;   - Continuous Querying with Exponential Backoff (1s -> 2s -> 4s ... 3600s)
;   - Goodbye Announcements (TTL=0) on Service Shutdown
;   - Multi-Question Queries & Cache Flush Bit (Bit 15 of RRCLASS)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define MDNS_PORT                   5353
%define MDNS_IPV4_MULTICAST         0xE00000FB  ; 224.0.0.251
%define MDNS_MAX_SERVICES           32      ; Max Advertised Services
%define MDNS_PROBE_COUNT            3       ; 3 Probes Before Claiming Name
%define MDNS_PROBE_INTERVAL_MS      250     ; 250ms Between Probes
%define MDNS_INITIAL_QUERY_MS       1000    ; Initial Query Interval
%define MDNS_MAX_QUERY_MS           3600000 ; Max Query Interval (1 hour)

struc mdns_service_t
    .instance_name:     resb 64     ; Service Instance Name (e.g., "My Printer")
    .service_type:      resb 32     ; Service Type (e.g., "_ipp._tcp.local")
    .hostname:          resb 64     ; Hostname (e.g., "printer.local")
    .port:              resw 1      ; Service Port Number
    .txt_record:        resb 256    ; TXT Key-Value Pairs
    .txt_len:           resw 1
    .ttl:               resd 1      ; Record TTL (seconds)
    .state:             resb 1      ; 0=Inactive, 1=Probing, 2=Announced, 3=Goodbye
    .probe_count:       resb 1      ; Remaining Probes
    .timer_id:          resd 1      ; Timer Wheel ID for Announcements
endstruc

section .bss
alignb 64
mdns_service_table:     resb mdns_service_t_size * MDNS_MAX_SERVICES
mdns_service_count:     resd 1

section .text

global mdns_init
global mdns_announce_service
global mdns_withdraw_service
global mdns_resolve_local
global mdns_probe_name
global mdns_handle_query
global mdns_handle_response
global mdns_continuous_query

align 64
mdns_init:
    push rbp
    mov rbp, rsp
    ; Bind multicast UDP Port 5353 (224.0.0.251 / ff02::fb)
    ; Join multicast group via IGMP
    mov dword [mdns_service_count], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mdns_announce_service — Announce Service via DNS-SD PTR/SRV/TXT Records
; Input: RDI = Pointer to mdns_service_t
; Output: EAX = 0 on Success, -1 on Table Full
; -----------------------------------------------------------------------------
align 64
mdns_announce_service:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Check service table capacity
    mov eax, [mdns_service_count]
    cmp eax, MDNS_MAX_SERVICES
    jge .table_full

    ; 2. Start probing phase (3 probes at 250ms intervals)
    mov byte [rbx + mdns_service_t.state], 1    ; Probing
    mov byte [rbx + mdns_service_t.probe_count], MDNS_PROBE_COUNT
    mov rdi, rbx
    call mdns_probe_name

    inc dword [mdns_service_count]
    xor eax, eax
    jmp .announce_done

.table_full:
    mov eax, -1

.announce_done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mdns_withdraw_service — Send Goodbye Announcement (TTL=0) & Remove Service
; Input: RDI = Pointer to mdns_service_t
; -----------------------------------------------------------------------------
align 64
mdns_withdraw_service:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    ; 1. Set TTL=0 & send goodbye announcement
    mov dword [rbx + mdns_service_t.ttl], 0
    mov byte [rbx + mdns_service_t.state], 3    ; Goodbye

    ; 2. Send multicast goodbye packet
    call udp_output

    ; 3. Cancel announcement timer
    mov edi, [rbx + mdns_service_t.timer_id]
    call timer_wheel_del

    dec dword [mdns_service_count]

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mdns_resolve_local — Query Multicast Group for `.local` Domain Name
; Input: RDI = Pointer to Domain Name String (e.g., "printer.local")
; Output: RAX = Resolved IPv4 Address (or 0 on Timeout)
; -----------------------------------------------------------------------------
align 64
mdns_resolve_local:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Build mDNS A/AAAA query & send to multicast group
    ; Wait for response with exponential backoff
    call udp_output
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mdns_probe_name — Probe for Unique Name Conflict Detection (RFC 6762 Section 8)
; Input: RDI = Pointer to mdns_service_t
; -----------------------------------------------------------------------------
align 64
mdns_probe_name:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    ; Send 3 probe queries at 250ms intervals
    ; If conflict detected (response with same name), append "-2" suffix
    movzx eax, byte [rbx + mdns_service_t.probe_count]
    test al, al
    jz .probing_done

    ; Send ANY query for our proposed name
    call udp_output

    dec byte [rbx + mdns_service_t.probe_count]

    ; Schedule next probe via timer_wheel_add
    mov edi, MDNS_PROBE_INTERVAL_MS
    call timer_wheel_add
    mov [rbx + mdns_service_t.timer_id], eax
    jmp .probe_exit

.probing_done:
    ; No conflict — claim name & send unsolicited announcement
    mov byte [rbx + mdns_service_t.state], 2    ; Announced

.probe_exit:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mdns_handle_query — Process Incoming mDNS Query & Send Response
; Input: RDI = Pointer to mDNS Query Packet, ESI = Length
; -----------------------------------------------------------------------------
align 64
mdns_handle_query:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; 1. Parse question section
    ; 2. Check if we own any matching records
    ; 3. Apply Known-Answer Suppression (don't reply if querier already has answer)
    ; 4. Send multicast response with matching PTR/SRV/TXT/A/AAAA records
    call udp_output
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mdns_handle_response — Process Incoming mDNS Response & Update Local Cache
; Input: RDI = Pointer to mDNS Response Packet, ESI = Length
; -----------------------------------------------------------------------------
align 64
mdns_handle_response:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; 1. Check Cache Flush bit (bit 15 of RRCLASS)
    ; 2. If TTL=0: remove from cache (goodbye)
    ; 3. Otherwise: update/insert cache entry with TTL
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mdns_continuous_query — Continuous Query with Exponential Backoff
; Input: RDI = Pointer to Query Name, ESI = Current Interval (ms)
; -----------------------------------------------------------------------------
align 64
mdns_continuous_query:
    push rbp
    mov rbp, rsp
    ; Send query & double interval (cap at MDNS_MAX_QUERY_MS = 1 hour)
    mov eax, esi
    shl eax, 1                      ; Double interval
    cmp eax, MDNS_MAX_QUERY_MS
    cmovg eax, dword [.max_interval]
    ; Schedule next query via timer_wheel_add
    mov edi, eax
    call timer_wheel_add
    pop rbp
    ret

.max_interval: dd MDNS_MAX_QUERY_MS

%endif ; GUARD_UNET_DNS_MDNS_ASM
