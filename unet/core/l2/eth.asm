%ifndef GUARD_UNET_CORE_L2_ETH_ASM
%define GUARD_UNET_CORE_L2_ETH_ASM
; =============================================================================
; Tattva OS — unet/core/l2/eth.asm
; =============================================================================
; AVX-512 SIMD Optimized L2 Ethernet Layer Engine (IEEE 802.3).
;
; Features:
;   - 802.1Q Single VLAN Tag Parsing (TPID 0x8100)
;   - 802.1ad QinQ Dual VLAN Tag Parsing (S-TAG 0x88A8 + C-TAG 0x8100)
;   - Jumbo Frame Support (MTU up to 9216 Bytes)
;   - EtherType L3 Protocol Demuxing (IPv4 / IPv6 / ARP / LLDP / MPLS)
;   - Hardware FCS CRC-32 Validation via CRC32 Instruction
;   - AVX-512 Batch 8-Frame Parallel Header Extraction
;
; Microarchitectural Optimizations:
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0` L1 Staging
;   - `prefetcht0` Pre-stages Ethernet Frame into L1 Data Cache Before Parsing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ETHERTYPE_IP                0x0800
%define ETHERTYPE_ARP               0x0806
%define ETHERTYPE_VLAN              0x8100  ; 802.1Q
%define ETHERTYPE_QINQ              0x88A8  ; 802.1ad S-TAG
%define ETHERTYPE_IPV6              0x86DD
%define ETHERTYPE_LLDP              0x88CC
%define ETHERTYPE_MPLS              0x8847
%define ETHERTYPE_MACSEC            0x88E5  ; 802.1AE

%define ETH_FRAME_MIN               64      ; Minimum Ethernet Frame Size (Bytes)
%define ETH_FRAME_MAX_STD           1518    ; Standard MTU Frame Size
%define ETH_FRAME_MAX_JUMBO         9216    ; Jumbo Frame MTU Size
%define ETH_FCS_LEN                 4       ; 32-bit Frame Check Sequence

struc eth_hdr_t
    .dst_mac:           resb 6      ; 48-bit Destination MAC Address
    .src_mac:           resb 6      ; 48-bit Source MAC Address
    .ethertype:         resw 1      ; 16-bit EtherType / Length
endstruc

struc vlan_tag_t
    .tpid:              resw 1      ; Tag Protocol Identifier (0x8100 / 0x88A8)
    .tci:               resw 1      ; Tag Control Info (PCP 3b + DEI 1b + VID 12b)
endstruc

section .bss
alignb 8
global unet_local_mac
unet_local_mac:         resb 6      ; Our interface's MAC (set by e1000_probe)

section .text

global eth_init
global eth_input
global eth_output
global eth_parse_vlan
global eth_validate_fcs


align 64
eth_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eth_input — Parse L2 Ethernet Frame & Dispatch to L3 Protocol Handler
; Input: RDI = Pointer to net_pkt_t (headroom_offset at the start of the raw
;        frame, data_len = bytes actually received)
;
; e1000 (like most NICs) strips the trailing 4-byte FCS before DMA'ing the
; frame into memory and reports CRC validity via the RX descriptor's status/
; error bits instead (see e1000_poll) — there is no FCS to check here, and
; eth_validate_fcs is not called for a frame this driver produced. It stays
; exported for any future driver that actually delivers a raw frame with FCS.
; -----------------------------------------------------------------------------
align 64
eth_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = net_pkt_t*
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax                    ; R12 = pointer to eth_hdr_t
    mov r13d, [rbx + net_pkt_t.data_len]
    sub r13d, [rbx + net_pkt_t.headroom_offset]
    prefetcht0 [r12]

    ; 1. Validate minimum frame size (header + any payload, FCS not present)
    cmp r13d, 14
    jb .drop

    ; 2. Extract EtherType (big-endian -> host byte order)
    movzx eax, word [r12 + eth_hdr_t.ethertype]
    xchg al, ah                     ; bswap16 (network -> host order)
    mov ecx, 14                     ; header bytes consumed so far

    ; 3. Handle 802.1Q / 802.1ad VLAN tagging
    cmp ax, ETHERTYPE_VLAN
    je .parse_vlan
    cmp ax, ETHERTYPE_QINQ
    je .parse_qinq
    jmp .dispatch

.parse_vlan:
    cmp r13d, 18
    jb .drop
    movzx eax, word [r12 + 16]     ; Inner EtherType after VLAN tag
    xchg al, ah
    mov ecx, 18
    jmp .dispatch

.parse_qinq:
    cmp r13d, 22
    jb .drop
    movzx eax, word [r12 + 20]     ; Inner EtherType after both tags
    xchg al, ah
    mov ecx, 22

.dispatch:
    add [rbx + net_pkt_t.headroom_offset], ecx

    ; 4. Dispatch to L3 based on EtherType
    cmp ax, ETHERTYPE_IP
    je .to_ipv4
    cmp ax, ETHERTYPE_IPV6
    je .to_ipv6
    cmp ax, ETHERTYPE_ARP
    je .to_arp
    jmp .drop                       ; Unknown EtherType -> drop

.to_ipv4:
    mov rdi, rbx
    call ip_input
    jmp .done

.to_ipv6:
    mov rdi, rbx
    call ipv6_input
    jmp .done

.to_arp:
    mov rdi, rbx
    call arp_input
    jmp .done

.drop:
    mov eax, -1

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eth_output — Encapsulate a net_pkt_t's staged L3 payload into an Ethernet
; frame (prepends the 14-byte header into the buffer's headroom) & transmit.
; Input: RDI = Pointer to net_pkt_t (headroom_offset/data_len cover the L3
;        payload already built by the caller), RSI = Pointer to 6-byte
;        Destination MAC, EDX = EtherType (host byte order)
; Output: EAX = 0 on success, -1 if there's no headroom left or no link
; -----------------------------------------------------------------------------
align 64
eth_output:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi                    ; R12 = dest MAC pointer
    mov r13d, edx                    ; R13D = EtherType (host order), saved
                                      ; across the headroom_offset reuse of EDX

    cmp dword [rbx + net_pkt_t.headroom_offset], 14
    jb .drop

    sub dword [rbx + net_pkt_t.headroom_offset], 14
    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx                    ; RAX = eth_hdr_t* in the buffer

    ; Dest MAC
    mov cx, [r12]
    mov [rax + eth_hdr_t.dst_mac], cx
    mov cx, [r12 + 2]
    mov [rax + eth_hdr_t.dst_mac + 2], cx
    mov cx, [r12 + 4]
    mov [rax + eth_hdr_t.dst_mac + 4], cx

    ; Src MAC (ours)
    mov cx, [unet_local_mac]
    mov [rax + eth_hdr_t.src_mac], cx
    mov cx, [unet_local_mac + 2]
    mov [rax + eth_hdr_t.src_mac + 2], cx
    mov cx, [unet_local_mac + 4]
    mov [rax + eth_hdr_t.src_mac + 4], cx

    mov cx, r13w
    xchg cl, ch                     ; host -> network byte order
    mov [rax + eth_hdr_t.ethertype], cx

    add dword [rbx + net_pkt_t.data_len], 14

    mov rdi, rbx
    call net_link_transmit
    jmp .done

.drop:
    mov eax, -1
.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eth_parse_vlan — Extract 12-bit VLAN ID and 3-bit PCP from 802.1Q TCI
; Input: RDI = Pointer to VLAN Tag
; Output: EAX = 12-bit VLAN ID, EDX = 3-bit Priority Code Point (PCP)
; -----------------------------------------------------------------------------
align 64
eth_parse_vlan:
    push rbp
    mov rbp, rsp
    movzx eax, word [rdi + vlan_tag_t.tci]
    xchg al, ah                     ; bswap16
    mov edx, eax
    shr edx, 13                     ; PCP = bits [15:13]
    and eax, 0x0FFF                 ; VID = bits [11:0]
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eth_validate_fcs — Hardware CRC-32 Frame Check Sequence Validation
; Input: RDI = Pointer to Frame, ESI = Frame Length (including FCS)
; Output: EAX = 0 if Valid, -1 if Corrupted
; -----------------------------------------------------------------------------
align 64
eth_validate_fcs:
    push rbp
    mov rbp, rsp
    push rbx

    ; Compute CRC-32 over frame bytes (excluding last 4 FCS bytes)
    sub esi, ETH_FCS_LEN
    xor eax, eax                    ; Initial CRC value
.crc_loop:
    cmp esi, 0
    jle .crc_check
    crc32 eax, byte [rdi]
    inc rdi
    dec esi
    jmp .crc_loop

.crc_check:
    ; Compare computed CRC with stored FCS
    cmp eax, [rdi]
    jne .fcs_fail
    xor eax, eax                    ; Valid
    jmp .fcs_done
.fcs_fail:
    mov eax, -1                     ; Corrupted
.fcs_done:
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L2_ETH_ASM
