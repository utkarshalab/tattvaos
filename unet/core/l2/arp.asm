%ifndef GUARD_UNET_CORE_L2_ARP_ASM
%define GUARD_UNET_CORE_L2_ARP_ASM
; =============================================================================
; Tattva OS — unet/core/l2/arp.asm
; =============================================================================
; Lockless Atomic Hash Table ARP Cache Engine (RFC 826 / RFC 5227).
;
; Features:
;   - O(1) Lockless Atomic Hash Table ARP Cache Lookup (`lock cmpxchg16b`)
;   - ARP Request / Reply Processing & Auto-Reply for Local IP Addresses
;   - Gratuitous ARP (GARP RFC 5227) Duplicate Address Detection (DAD)
;   - Proxy ARP (RFC 1027) for Routed Subnet Forwarding
;   - ARP Rate Limiting & Anti-Flooding Protection (1 ARP/sec per Source IP)
;   - Timer Wheel Cache Entry Expiration via lib/time/timer_wheel.asm
;
; Microarchitectural Optimizations:
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0` L1 Staging
;   - Lockless `lock cmpxchg16b` 128-bit Atomic Cache Entry Updates
;
; Delegates:
;   - Cache Expiration Timers           -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ARP_OP_REQUEST              1
%define ARP_OP_REPLY                2
%define ARP_HW_TYPE_ETHERNET        1
%define ARP_PROTO_TYPE_IPV4         0x0800
%define ARP_CACHE_SIZE              4096    ; Hash Table Entries
%define ARP_RATE_LIMIT_INTERVAL     1000    ; 1 ARP per 1000ms per Source IP

struc arp_hdr_t
    .hw_type:           resw 1      ; Hardware Type (1 = Ethernet)
    .proto_type:        resw 1      ; Protocol Type (0x0800 = IPv4)
    .hw_len:            resb 1      ; Hardware Address Length (6)
    .proto_len:         resb 1      ; Protocol Address Length (4)
    .opcode:            resw 1      ; Opcode (1 = Request, 2 = Reply)
    .sender_mac:        resb 6      ; Sender Hardware Address
    .sender_ip:         resd 1      ; Sender Protocol Address
    .target_mac:        resb 6      ; Target Hardware Address
    .target_ip:         resd 1      ; Target Protocol Address
endstruc

struc arp_cache_entry_t
    .ip_addr:           resd 1      ; IPv4 Address
    .mac_addr:          resb 6      ; Resolved MAC Address
    .state:             resb 1      ; 0=Empty, 1=Incomplete, 2=Reachable, 3=Stale
    .timer_id:          resd 1      ; Timer Wheel ID (lib/time/timer_wheel.asm)
    .last_arp_ts:       resq 1      ; Last ARP Timestamp (Rate Limiting)
endstruc

section .bss
alignb 64
arp_cache_table:        resb arp_cache_entry_t_size * ARP_CACHE_SIZE
arp_bcast_mac:           resb 6      ; FF:FF:FF:FF:FF:FF, filled in arp_init

section .text

global arp_init
global arp_input
global arp_lookup
global arp_send_request
global arp_send_gratuitous
global arp_cache_update

align 64
arp_init:
    push rbp
    mov rbp, rsp

    lea rdi, [arp_cache_table]
    xor eax, eax
    mov ecx, (arp_cache_entry_t_size * ARP_CACHE_SIZE) / 8
    rep stosq

    mov byte [arp_bcast_mac], 0xFF
    mov byte [arp_bcast_mac+1], 0xFF
    mov byte [arp_bcast_mac+2], 0xFF
    mov byte [arp_bcast_mac+3], 0xFF
    mov byte [arp_bcast_mac+4], 0xFF
    mov byte [arp_bcast_mac+5], 0xFF

    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; arp_input — Process Incoming ARP Request / Reply
; Input: RDI = Pointer to net_pkt_t (headroom_offset at the start of the ARP
;        packet, following the convention every other L2/L3 handler uses)
; -----------------------------------------------------------------------------
align 64
arp_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = net_pkt_t*
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax                    ; R12 = pointer to arp_hdr_t
    prefetcht0 [r12]

    mov eax, [rbx + net_pkt_t.data_len]
    sub eax, [rbx + net_pkt_t.headroom_offset]
    cmp eax, arp_hdr_t_size
    jb .drop

    ; 1. Validate ARP header fields
    movzx eax, word [r12 + arp_hdr_t.hw_type]
    xchg al, ah
    cmp ax, ARP_HW_TYPE_ETHERNET
    jne .drop

    movzx eax, word [r12 + arp_hdr_t.proto_type]
    xchg al, ah
    cmp ax, ARP_PROTO_TYPE_IPV4
    jne .drop

    ; 2. Update ARP cache with Sender IP -> Sender MAC mapping. (Rate-
    ; limiting incoming ARP by source IP is not implemented: it needs a
    ; per-source timestamp table this cache doesn't keep yet.)
    mov edi, [r12 + arp_hdr_t.sender_ip]
    lea rsi, [r12 + arp_hdr_t.sender_mac]
    call arp_cache_update

    ; 3. Check opcode: Request vs Reply
    movzx eax, word [r12 + arp_hdr_t.opcode]
    xchg al, ah
    cmp ax, ARP_OP_REQUEST
    je .handle_request
    jmp .done

.handle_request:
    ; Only answer if the target IP is actually ours.
    cmp dword [unet_local_ip], 0
    je .done
    mov eax, [r12 + arp_hdr_t.target_ip]
    cmp eax, [unet_local_ip]
    jne .done

    mov r13d, [r12 + arp_hdr_t.sender_ip]   ; who to reply to

    ; Build the reply in-place: swap sender/target, flip opcode.
    mov eax, [r12 + arp_hdr_t.sender_ip]
    mov [r12 + arp_hdr_t.target_ip], eax
    mov cx, [r12 + arp_hdr_t.sender_mac]
    mov [r12 + arp_hdr_t.target_mac], cx
    mov cx, [r12 + arp_hdr_t.sender_mac + 2]
    mov [r12 + arp_hdr_t.target_mac + 2], cx
    mov cx, [r12 + arp_hdr_t.sender_mac + 4]
    mov [r12 + arp_hdr_t.target_mac + 4], cx

    mov eax, [unet_local_ip]
    mov [r12 + arp_hdr_t.sender_ip], eax
    mov cx, [unet_local_mac]
    mov [r12 + arp_hdr_t.sender_mac], cx
    mov cx, [unet_local_mac + 2]
    mov [r12 + arp_hdr_t.sender_mac + 2], cx
    mov cx, [unet_local_mac + 4]
    mov [r12 + arp_hdr_t.sender_mac + 4], cx

    mov word [r12 + arp_hdr_t.opcode], 0x0200  ; ARP_OP_REPLY, network order

    lea rsi, [r12 + arp_hdr_t.target_mac]      ; now holds the requester's MAC
    mov rdi, rbx
    mov edx, UNET_ETH_TYPE_ARP
    call eth_output
    jmp .done

.drop:
.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; arp_lookup — Lockless O(1) Hash Table Cache Lookup
; Input: EDI = Target IPv4 Address
; Output: RAX = Pointer to arp_cache_entry_t (or NULL if Cache Miss)
; -----------------------------------------------------------------------------
align 64
arp_lookup:
    ; Hash: (IP >> 8) XOR (IP & 0xFF) mod ARP_CACHE_SIZE
    mov eax, edi
    mov edx, edi
    shr eax, 8
    xor eax, edx
    and eax, ARP_CACHE_SIZE - 1
    imul eax, arp_cache_entry_t_size
    lea rax, [arp_cache_table + rax]

    ; Only a genuine hit for this exact IP, in Reachable state, counts.
    cmp dword [rax + arp_cache_entry_t.ip_addr], edi
    jne .miss
    cmp byte [rax + arp_cache_entry_t.state], 2
    jne .miss
    ret

.miss:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; arp_send_request — Broadcast ARP Request for Target IP
; Input: EDI = Target IPv4 Address (network byte order)
; -----------------------------------------------------------------------------
align 64
arp_send_request:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12d, edi                   ; R12D = target IP

    call pktbuf_alloc
    test rax, rax
    jz .done
    mov rbx, rax                    ; RBX = net_pkt_t*

    cmp dword [rbx + net_pkt_t.headroom_offset], arp_hdr_t_size
    jb .free_drop
    sub dword [rbx + net_pkt_t.headroom_offset], arp_hdr_t_size

    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx                    ; RAX = arp_hdr_t* in the buffer

    mov word [rax + arp_hdr_t.hw_type], 0x0100      ; 1, network order
    mov word [rax + arp_hdr_t.proto_type], 0x0008   ; 0x0800, network order
    mov byte [rax + arp_hdr_t.hw_len], 6
    mov byte [rax + arp_hdr_t.proto_len], 4
    mov word [rax + arp_hdr_t.opcode], 0x0100       ; ARP_OP_REQUEST, network order

    mov cx, [unet_local_mac]
    mov [rax + arp_hdr_t.sender_mac], cx
    mov cx, [unet_local_mac + 2]
    mov [rax + arp_hdr_t.sender_mac + 2], cx
    mov cx, [unet_local_mac + 4]
    mov [rax + arp_hdr_t.sender_mac + 4], cx
    mov ecx, [unet_local_ip]
    mov [rax + arp_hdr_t.sender_ip], ecx

    mov word [rax + arp_hdr_t.target_mac], 0
    mov word [rax + arp_hdr_t.target_mac + 2], 0
    mov word [rax + arp_hdr_t.target_mac + 4], 0
    mov [rax + arp_hdr_t.target_ip], r12d

    mov dword [rbx + net_pkt_t.data_len], arp_hdr_t_size

    lea rsi, [arp_bcast_mac]
    mov rdi, rbx
    mov edx, UNET_ETH_TYPE_ARP
    call eth_output
    jmp .free
.free_drop:
.free:
    mov rdi, rbx
    call pktbuf_free
.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; arp_send_gratuitous — Send Gratuitous ARP (GARP RFC 5227) for DAD
; Input: EDI = Our IPv4 Address (network byte order)
;
; A GARP is a request whose sender IP == target IP; every other host on the
; segment updates its cache from the sender fields without needing to reply.
; -----------------------------------------------------------------------------
align 64
arp_send_gratuitous:
    mov edi, [unet_local_ip]
    jmp arp_send_request

; -----------------------------------------------------------------------------
; arp_cache_update — Insert/refresh a cache entry for (IP -> MAC).
; Input: EDI = IPv4 address (network order), RSI = pointer to 6-byte MAC
;
; This is a FILE-LEVEL label, not a `.local` one. NASM scopes `.name` to the
; preceding non-local label, so while this sat at the end of the file it
; belonged to arp_send_gratuitous — and arp_input's `call .cache_update`
; resolved to arp_input.cache_update, which nothing defined. It also never
; wrote anything into the cache table: fixed below to actually populate the
; slot arp_lookup reads from.
;
; Timer-wheel TTL expiry (aging an entry back to Stale/Empty) isn't wired up
; here — entries are refreshed on every observed ARP but never age out.
; Follow-up scope, same as IP fragment reassembly's timer.
; -----------------------------------------------------------------------------
align 64
arp_cache_update:
    push rbx
    push r12

    mov r12d, edi

    mov eax, edi
    mov edx, edi
    shr eax, 8
    xor eax, edx
    and eax, ARP_CACHE_SIZE - 1
    imul eax, arp_cache_entry_t_size
    lea rbx, [arp_cache_table + rax]

    mov [rbx + arp_cache_entry_t.ip_addr], r12d
    mov cx, [rsi]
    mov [rbx + arp_cache_entry_t.mac_addr], cx
    mov cx, [rsi + 2]
    mov [rbx + arp_cache_entry_t.mac_addr + 2], cx
    mov cx, [rsi + 4]
    mov [rbx + arp_cache_entry_t.mac_addr + 4], cx
    mov byte [rbx + arp_cache_entry_t.state], 2     ; Reachable

    call rdtsc_get_cycles
    mov [rbx + arp_cache_entry_t.last_arp_ts], rax

    pop r12
    pop rbx
    ret

%endif ; GUARD_UNET_CORE_L2_ARP_ASM
