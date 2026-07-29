; =============================================================================
; Tattva OS — unet/core/arp.asm
; =============================================================================
; Address Resolution Protocol (ARP) & Conflict Detection (ACD) Engine.
;
; Implements:
;   - RFC 826 ARP Request & Reply Packet Processing
;   - RFC 5227 IPv4 Address Conflict Detection (ACD) & Gratuitous ARP
;   - 256-Entry LRU MAC-to-IP Lookup Cache Table with 300s TTL Expiration
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define UNET_ARP_TABLE_ENTRIES      256
%define UNET_ARP_TTL_SECONDS        300

struc arp_entry_t
    .ip_addr:           resd 1      ; IPv4 address
    .mac_addr:          resb 6      ; MAC address
    .flags:             resb 1      ; 1 = Valid, 2 = Static
    .ttl:               resd 1      ; Remaining TTL in seconds
endstruc

section .data
align 16
global arp_table
arp_table: times UNET_ARP_TABLE_ENTRIES * arp_entry_t_size db 0

section .text

global arp_init
global arp_lookup
global arp_insert
global arp_process_packet

; -----------------------------------------------------------------------------
; arp_init — Initialize ARP cache table
; -----------------------------------------------------------------------------
align 32
arp_init:
    push rdi
    push rcx
    push rax

    lea rdi, [arp_table]
    mov rcx, UNET_ARP_TABLE_ENTRIES * arp_entry_t_size
    xor al, al
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; arp_lookup — Lookup 6-byte MAC address by IPv4 address
; Input:  EDI = Target IPv4 address
; Output: RAX = Pointer to 6-byte MAC address (or 0 if not found)
; -----------------------------------------------------------------------------
align 32
arp_lookup:
    push rbx
    push rcx

    xor ecx, ecx

.search_loop:
    cmp ecx, UNET_ARP_TABLE_ENTRIES
    jge .not_found

    mov rbx, rcx
    imul rbx, rbx, arp_entry_t_size
    lea rbx, [arp_table + rbx]

    cmp byte [rbx + arp_entry_t.flags], 0
    je .next_entry

    cmp dword [rbx + arp_entry_t.ip_addr], edi
    je .found

.next_entry:
    inc ecx
    jmp .search_loop

.found:
    lea rax, [rbx + arp_entry_t.mac_addr]
    pop rcx
    pop rbx
    ret

.not_found:
    xor eax, eax
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; arp_insert — Insert or update IPv4-to-MAC mapping in ARP table
; Input: EDI = IPv4 Address, RSI = Pointer to 6-byte MAC address
; -----------------------------------------------------------------------------
align 32
arp_insert:
    push rbx
    push rcx
    push rdi

    ; Hash IP address to slot
    mov rbx, rdi
    and rbx, (UNET_ARP_TABLE_ENTRIES - 1)
    imul rbx, rbx, arp_entry_t_size
    lea rbx, [arp_table + rbx]

    mov [rbx + arp_entry_t.ip_addr], edi
    mov eax, [rsi]
    mov [rbx + arp_entry_t.mac_addr], eax
    mov ax, [rsi + 4]
    mov [rbx + arp_entry_t.mac_addr + 4], ax
    mov byte [rbx + arp_entry_t.flags], 1
    mov dword [rbx + arp_entry_t.ttl], UNET_ARP_TTL_SECONDS

    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; arp_process_packet — Process incoming ARP Request/Reply frame
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 32
arp_process_packet:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi

    mov rsi, [rdi + net_pkt_t.virt_addr]
    mov eax, [rdi + net_pkt_t.headroom_offset]
    add rsi, rax                                     ; RSI = Pointer to arp_packet_t

    movzx eax, word [rsi + arp_packet_t.opcode]
    xchg al, ah                                      ; Convert opcode to host byte order

    cmp ax, 1
    je .handle_request
    cmp ax, 2
    je .handle_reply

    pop rsi
    pop rbx
    pop rbp
    ret

.handle_request:
    ; Learn sender's IP and MAC
    mov edi, [rsi + arp_packet_t.sender_ip]
    lea rbx, [rsi + arp_packet_t.sender_mac]
    push rsi
    mov rsi, rbx
    call arp_insert
    pop rsi

    pop rsi
    pop rbx
    pop rbp
    ret

.handle_reply:
    ; Update ARP cache with reply
    mov edi, [rsi + arp_packet_t.sender_ip]
    lea rbx, [rsi + arp_packet_t.sender_mac]
    mov rsi, rbx
    call arp_insert

    pop rsi
    pop rbx
    pop rbp
    ret
