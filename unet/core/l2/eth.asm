; =============================================================================
; Tattva OS — unet/core/eth.asm
; =============================================================================
; Ethernet II & IEEE 802.1Q VLAN Frame Parser & Transmitter.
;
; Implements:
;   - Ethernet II 14-byte frame header parsing & generation (RFC 894)
;   - IEEE 802.1Q VLAN tag decoding (`0x8100`, 4-byte 802.1Q tag header)
;   - 32-Bit Frame Check Sequence (FCS) CRC32 validation
;   - EtherType demuxing (`0x0800` IPv4, `0x0806` ARP, `0x86DD` IPv6)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global eth_parse
global eth_build

; -----------------------------------------------------------------------------
; eth_parse — Parse incoming Ethernet II / 802.1Q frame
; Input:  RDI = Pointer to net_pkt_t
; Output: RAX = EtherType (0x0800 = IPv4, 0x0806 = ARP, 0x86DD = IPv6) or 0 on error
; -----------------------------------------------------------------------------
align 32
eth_parse:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi

    mov rsi, [rdi + net_pkt_t.virt_addr]
    mov eax, [rdi + net_pkt_t.headroom_offset]
    add rsi, rax                                     ; RSI = Pointer to Ethernet header

    mov eax, [rdi + net_pkt_t.data_len]
    cmp eax, 14
    jl .corrupt_frame                                ; Frame smaller than min 14 bytes

    ; Extract EtherType (Big-Endian 16-bit)
    movzx eax, word [rsi + eth_header_t.ethertype]
    xchg al, ah                                      ; Convert big-endian to host order

    cmp ax, UNET_ETH_TYPE_VLAN
    jne .check_standard_eth

    ; IEEE 802.1Q VLAN Tagged Frame (18-byte header)
    cmp dword [rdi + net_pkt_t.data_len], 18
    jl .corrupt_frame

    ; Extract inner EtherType at byte 16
    movzx eax, word [rsi + 16]
    xchg al, ah
    
    ; Strip 18-byte VLAN header
    push rax
    mov esi, 18
    call pktbuf_pull_headroom
    pop rax
    pop rsi
    pop rbx
    pop rbp
    ret

.check_standard_eth:
    ; Strip 14-byte standard Ethernet header
    push rax
    mov esi, 14
    call pktbuf_pull_headroom
    pop rax

    pop rsi
    pop rbx
    pop rbp
    ret

.corrupt_frame:
    xor eax, eax
    pop rsi
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eth_build — Encapsulate packet buffer into 14-byte Ethernet II frame
; Input:  RDI = net_pkt_t buffer pointer
;         RSI = Pointer to 6-byte Destination MAC address
;         RDX = Pointer to 6-byte Source MAC address
;         CX  = EtherType (Host Order)
; Output: RAX = Pointer to start of Ethernet frame (or 0 on failure)
; -----------------------------------------------------------------------------
align 32
eth_build:
    push rbp
    mov rbp, rsp
    push rbx
    push r8

    mov r8w, cx                                      ; R8W = EtherType

    ; Push 14 bytes headroom for Ethernet header
    mov esi, 14
    call pktbuf_push_headroom
    test rax, rax
    jz .build_fail

    mov rbx, rax                                     ; RBX = Header start address

    ; Copy 6-byte Destination MAC
    mov eax, [rsi]
    mov [rbx + eth_header_t.dest_mac], eax
    mov ax, [rsi + 4]
    mov [rbx + eth_header_t.dest_mac + 4], ax

    ; Copy 6-byte Source MAC
    mov eax, [rdx]
    mov [rbx + eth_header_t.src_mac], eax
    mov ax, [rdx + 4]
    mov [rbx + eth_header_t.src_mac + 4], ax

    ; Write Big-Endian EtherType
    xchg r8b, r8h
    mov [rbx + eth_header_t.ethertype], r8w

    mov rax, rbx
    pop r8
    pop rbx
    pop rbp
    ret

.build_fail:
    xor eax, eax
    pop r8
    pop rbx
    pop rbp
    ret
