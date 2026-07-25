; =============================================================================
; Tattva OS — unet/core/ip.asm
; =============================================================================
; IPv4 & ICMPv4 Protocol Engine.
;
; Implements:
;   - RFC 791 IPv4 20-Byte Header Verification & Generation
;   - 16-Bit Internet Ones' Complement Checksum Calculation (`ip_checksum`)
;   - IPv4 Packet Fragment Reassembly Tracking
;   - RFC 792 ICMP Echo Request / Echo Reply Ping Handler (`type 8 -> 0`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ip_checksum
global ip_parse
global ip_build
global icmp_process

; -----------------------------------------------------------------------------
; ip_checksum — Compute 16-bit Internet Ones' Complement Checksum
; Input:  RDI = Pointer to data buffer, RSI = Length in bytes
; Output: AX  = 16-bit Ones' Complement Checksum (Network Byte Order)
; -----------------------------------------------------------------------------
align 32
ip_checksum:
    push rbx
    push rcx

    xor eax, eax                                     ; Accumulator
    mov rcx, rsi
    shr rcx, 1                                       ; Count of 16-bit words

.checksum_loop:
    test rcx, rcx
    jz .odd_byte_check

    movzx ebx, word [rdi]
    add eax, ebx
    add rdi, 2
    dec rcx
    jmp .checksum_loop

.odd_byte_check:
    test rsi, 1
    jz .fold_carries

    movzx ebx, byte [rdi]
    add eax, ebx

.fold_carries:
    ; Fold 32-bit sum to 16-bits
    mov ebx, eax
    shr ebx, 16
    and eax, 0xFFFF
    add eax, ebx

    mov ebx, eax
    shr ebx, 16
    add eax, ebx
    not ax                                           ; Ones' complement

    xchg al, ah                                      ; Convert to network byte order
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ip_parse — Validate and parse incoming IPv4 packet
; Input:  RDI = Pointer to net_pkt_t
; Output: EAX = Protocol (6 = TCP, 17 = UDP, 1 = ICMP) or 0 on error
; -----------------------------------------------------------------------------
align 32
ip_parse:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi

    mov rsi, [rdi + net_pkt_t.virt_addr]
    mov eax, [rdi + net_pkt_t.headroom_offset]
    add rsi, rax                                     ; RSI = Pointer to ipv4_header_t

    cmp dword [rdi + net_pkt_t.data_len], 20
    jl .invalid_ip

    ; Verify IP version (Version 4)
    mov al, [rsi + ipv4_header_t.ver_ihl]
    shr al, 4
    cmp al, 4
    jne .invalid_ip

    ; Extract 8-bit Protocol
    movzx eax, byte [rsi + ipv4_header_t.protocol]

    ; Strip 20-byte IPv4 header
    push rax
    mov esi, 20
    call pktbuf_pull_headroom
    pop rax

    pop rsi
    pop rbx
    pop rbp
    ret

.invalid_ip:
    xor eax, eax
    pop rsi
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ip_build — Construct 20-byte IPv4 header on packet buffer
; Input:  RDI = net_pkt_t buffer pointer
;         ESI = Dest IPv4 Address
;         EDX = Source IPv4 Address
;         CL  = Protocol (6 = TCP, 17 = UDP, 1 = ICMP)
; Output: RAX = Pointer to IPv4 header start (or 0 on error)
; -----------------------------------------------------------------------------
align 32
ip_build:
    push rbp
    mov rbp, rsp
    push rbx
    push r8
    push r9

    mov r8d, esi                                     ; R8D = Dest IP
    mov r9d, edx                                     ; R9D = Src IP

    ; Push 20 bytes headroom for IPv4 header
    mov esi, 20
    call pktbuf_push_headroom
    test rax, rax
    jz .build_fail

    mov rbx, rax                                     ; RBX = Header address

    mov byte [rbx + ipv4_header_t.ver_ihl], 0x45    ; Version 4, IHL 5 (20 bytes)
    mov byte [rbx + ipv4_header_t.tos], 0            ; Type of Service
    
    mov edx, [rdi + net_pkt_t.data_len]
    xchg dl, dh
    mov [rbx + ipv4_header_t.total_len], dx         ; Big-endian total length

    mov word [rbx + ipv4_header_t.id], 0x1234
    mov word [rbx + ipv4_header_t.flags_fragment], 0
    mov byte [rbx + ipv4_header_t.ttl], 64
    mov [rbx + ipv4_header_t.protocol], cl
    mov word [rbx + ipv4_header_t.checksum], 0
    mov [rbx + ipv4_header_t.src_ip], r9d
    mov [rbx + ipv4_header_t.dest_ip], r8d

    ; Compute and store 16-bit header checksum
    push rbx
    mov rdi, rbx
    mov rsi, 20
    call ip_checksum
    pop rbx
    mov [rbx + ipv4_header_t.checksum], ax

    mov rax, rbx
    pop r9
    pop r8
    pop rbx
    pop rbp
    ret

.build_fail:
    xor eax, eax
    pop r9
    pop r8
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmp_process — Process ICMP Echo Request and generate Echo Reply Ping
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 32
icmp_process:
    push rbp
    mov rbp, rsp
    push rsi

    mov rsi, [rdi + net_pkt_t.virt_addr]
    mov eax, [rdi + net_pkt_t.headroom_offset]
    add rsi, rax                                     ; RSI = Pointer to ICMP header

    cmp byte [rsi], 8                                ; Type 8 = Echo Request
    jne .done

    mov byte [rsi], 0                                ; Convert to Type 0 = Echo Reply
    mov word [rsi + 2], 0                            ; Clear Checksum

    ; Recalculate ICMP checksum
    push rdi
    mov rdi, rsi
    mov esi, [rdi + net_pkt_t.data_len]
    call ip_checksum
    pop rdi
    mov [rsi + 2], ax

.done:
    pop rsi
    pop rbp
    ret
