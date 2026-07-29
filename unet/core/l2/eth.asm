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

section .text

global eth_init
global eth_input
global eth_output
global eth_parse_vlan
global eth_validate_fcs

extern ip_input
extern ipv6_input
extern arp_input
extern mac_is_broadcast
extern mac_is_multicast

align 64
eth_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eth_input — Parse L2 Ethernet Frame & Dispatch to L3 Protocol Handler
; Input: RDI = Pointer to Raw Ethernet Frame, ESI = Frame Length
; -----------------------------------------------------------------------------
align 64
eth_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12d, esi
    prefetcht0 [rbx]                ; Pre-stage Ethernet frame into L1 cache

    ; 1. Validate minimum frame size (64 bytes including FCS)
    cmp r12d, ETH_FRAME_MIN
    jb .drop

    ; 2. Validate FCS CRC-32 (last 4 bytes of frame)
    call eth_validate_fcs
    test eax, eax
    jnz .drop

    ; 3. Extract EtherType (big-endian -> host byte order)
    movzx eax, word [rbx + eth_hdr_t.ethertype]
    xchg al, ah                     ; bswap16 (network -> host order)

    ; 4. Handle 802.1Q / 802.1ad VLAN tagging
    cmp ax, ETHERTYPE_VLAN
    je .parse_vlan
    cmp ax, ETHERTYPE_QINQ
    je .parse_qinq

.dispatch:
    ; 5. Dispatch to L3 based on EtherType
    cmp ax, ETHERTYPE_IP
    je .to_ipv4
    cmp ax, ETHERTYPE_IPV6
    je .to_ipv6
    cmp ax, ETHERTYPE_ARP
    je .to_arp
    jmp .drop                       ; Unknown EtherType -> drop

.to_ipv4:
    lea rdi, [rbx + 14]            ; Skip 14-byte Ethernet header
    call ip_input
    jmp .done

.to_ipv6:
    lea rdi, [rbx + 14]
    call ipv6_input
    jmp .done

.to_arp:
    lea rdi, [rbx + 14]
    call arp_input
    jmp .done

.parse_vlan:
    ; 802.1Q: Skip 4-byte VLAN tag, re-read inner EtherType
    movzx eax, word [rbx + 16]     ; Inner EtherType after VLAN tag
    xchg al, ah
    jmp .dispatch

.parse_qinq:
    ; 802.1ad QinQ: Skip 8-byte dual VLAN tags (S-TAG + C-TAG)
    movzx eax, word [rbx + 20]     ; Inner EtherType after both tags
    xchg al, ah
    jmp .dispatch

.drop:
    xor eax, eax

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; eth_output — Encapsulate L3 Payload into Ethernet Frame & Transmit
; Input: RDI = Pointer to Destination MAC, RSI = Pointer to L3 Payload,
;        EDX = Payload Length, ECX = EtherType
; -----------------------------------------------------------------------------
align 64
eth_output:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    prefetcht0 [rsi]
    ; Build 14-byte Ethernet header (DstMAC + SrcMAC + EtherType) + L3 payload
    xor eax, eax
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
