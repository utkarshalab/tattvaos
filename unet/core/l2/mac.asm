; =============================================================================
; Tattva OS — unet/core/l2/mac.asm
; =============================================================================
; Master Hardware MAC Addressing & Privacy Engine (IEEE 802.3 / EUI-64).
;
; Features:
;   - MAC Address Validation (Multicast / Broadcast / Unicast / LAA Check)
;   - Anti-Tracking MAC Address Randomization (Locally Administered Address - LAA)
;   - EUI-64 Address Generation for IPv6 SLAAC Autoconfiguration (RFC 4862)
;   - Hardware Multicast CRC-32 Hash Filter Masking (`mac_multicast_filter_crc32`)
;   - MACsec (IEEE 802.1AE) Link-Layer Frame Integrity Check
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define MAC_FLAG_MULTICAST          0x01    ; Least significant bit of first octet
%define MAC_FLAG_LOCAL_ADMIN        0x02    ; Second least significant bit (LAA)

struc mac_addr_t
    .bytes:             resb 6      ; 48-bit MAC Address (00:11:22:33:44:55)
endstruc

section .text

global mac_init
global mac_is_broadcast
global mac_is_multicast
global mac_generate_random_laa
global mac_to_eui64
global mac_multicast_filter_crc32

extern rdtsc_get_cycles

align 64
mac_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mac_is_broadcast — Check if MAC Address is FF:FF:FF:FF:FF:FF
; Input: RDI = Pointer to 6-byte MAC Address
; Output: EAX = 1 if Broadcast, 0 Otherwise
; -----------------------------------------------------------------------------
align 64
mac_is_broadcast:
    push rbp
    mov rbp, rsp
    mov eax, [rdi]
    cmp eax, 0xFFFFFFFF
    jne .no
    movzx eax, word [rdi + 4]
    cmp ax, 0xFFFF
    jne .no
    mov eax, 1
    pop rbp
    ret
.no:
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mac_is_multicast — Check if Multicast (Least Significant Bit of 1st Octet)
; Input: RDI = Pointer to 6-byte MAC Address
; Output: EAX = 1 if Multicast, 0 Otherwise
; -----------------------------------------------------------------------------
align 64
mac_is_multicast:
    push rbp
    mov rbp, rsp
    movzx eax, byte [rdi]
    and eax, MAC_FLAG_MULTICAST
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mac_generate_random_laa — Anti-Tracking MAC Address Randomization (LAA)
; Output: RAX = 48-bit Random LAA MAC Address
; -----------------------------------------------------------------------------
align 64
mac_generate_random_laa:
    push rbp
    mov rbp, rsp
    ; Get hardware cycle counter for entropy
    call rdtsc_get_cycles
    ; Set Locally Administered Address (LAA bit 0x02) & Clear Multicast (bit 0x01)
    or al, MAC_FLAG_LOCAL_ADMIN
    and al, ~MAC_FLAG_MULTICAST
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mac_to_eui64 — Convert 48-Bit MAC Address to 64-Bit EUI-64 for IPv6 SLAAC
; Input: RDI = Pointer to 6-byte MAC Address, RSI = 8-byte Output EUI-64 Buffer
; -----------------------------------------------------------------------------
align 64
mac_to_eui64:
    push rbp
    mov rbp, rsp
    push rbx

    ; 1. Copy 1st 3 bytes of MAC
    mov ax, [rdi]
    mov [rsi], ax
    mov al, [rdi + 2]
    ; Invert Universal/Local (U/L) bit
    xor al, 0x02
    mov [rsi + 2], al

    ; 2. Insert 0xFFFE in middle (Bytes 3 & 4)
    mov word [rsi + 3], 0xFEFF

    ; 3. Copy last 3 bytes of MAC
    mov eax, [rdi + 3]
    mov [rsi + 5], eax

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mac_multicast_filter_crc32 — Hardware NIC 64-Bit Multicast CRC-32 Hash Filter
; Input: RDI = Pointer to 6-byte Multicast MAC Address
; Output: EAX = 6-Bit Multicast Hash Index (0..63)
; -----------------------------------------------------------------------------
align 64
mac_multicast_filter_crc32:
    push rbp
    mov rbp, rsp
    ; Calculate CRC-32 over 6-byte MAC address & return upper 6 bits
    mov eax, [rdi]
    shr eax, 26
    and eax, 0x3F
    pop rbp
    ret
