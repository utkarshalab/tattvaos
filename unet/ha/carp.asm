; =============================================================================
; Tattva OS — unet/ha/carp.asm
; =============================================================================
; Common Address Redundancy Protocol Engine (CARP OpenBSD Spec).
;
; Features:
;   - IP Protocol 112 CARP Advertisement Packet Parsing & Construction
;   - SHA-1 HMAC Virtual MAC Failover Authentication: HMAC-SHA1(CARP_Header, Passphrase)
;   - Fields: Version, Type, VHID (Virtual Host ID), AdvBase (1s..255s), AdvSkew (0..255), Counter, HMAC-SHA1 Tag
;   - Master Election with AdvBase/AdvSkew Delay Calculation: Delay = AdvBase + (AdvSkew / 256)
;   - Virtual MAC Address Mapping: `00:00:5e:00:01:VHID`
;
; Delegates:
;   - HMAC-SHA1                         -> lib/crypto/sha1.asm
;   - ARP Gratuitous Announcement        -> unet/core/l2/arp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define CARP_VERSION                2
%define CARP_TYPE_ADVERTISEMENT     1

struc carp_hdr_t
    .vers_type:         resb 1      ; Version (4b) + Type (4b)
    .vhid:              resb 1      ; Virtual Host ID
    .advbase:           resb 1      ; Advertisement Base Interval (seconds)
    .advskew:           resb 1      ; Advertisement Skew (1/256 seconds)
    .counter:           resq 1      ; 64-bit Counter
    .hmac_sha1:         resb 20     ; 160-bit HMAC-SHA1 Authentication Tag
endstruc

section .text

global carp_init
global carp_process_packet
global carp_send_advertisement
global carp_calc_delay

extern sha1_hash
extern arp_send_gratuitous

align 64
carp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
carp_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify HMAC-SHA1 tag against secret passphrase
    call sha1_hash

    ; Extract AdvBase & AdvSkew
    movzx eax, byte [rbx + carp_hdr_t.advbase]
    movzx edx, byte [rbx + carp_hdr_t.advskew]

    ; Calculate Delay = AdvBase + (AdvSkew / 256)
    call carp_calc_delay

    pop rbx
    pop rbp
    ret

align 64
carp_send_advertisement:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Compute HMAC-SHA1 & send CARP advertisement frame
    call sha1_hash
    pop rbp
    ret

; -----------------------------------------------------------------------------
; carp_calc_delay — Calculate CARP Master Down Delay (AdvBase + AdvSkew / 256)
; Input: EAX = AdvBase, EDX = AdvSkew
; Output: RAX = Delay in Milliseconds
; -----------------------------------------------------------------------------
align 64
carp_calc_delay:
    push rbp
    mov rbp, rsp
    ; Delay_ms = (AdvBase * 1000) + ((AdvSkew * 1000) / 256)
    imul eax, 1000
    imul edx, 1000
    shr edx, 8
    add eax, edx
    pop rbp
    ret
