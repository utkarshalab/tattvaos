%ifndef GUARD_UNET_TOOLS_SECURITY_MACSEC_MON_ASM
%define GUARD_UNET_TOOLS_SECURITY_MACSEC_MON_ASM
; =============================================================================
; Tattva OS — unet/tools/security/macsec_mon.asm
; =============================================================================
; IEEE 802.1AE MACsec Link-Layer Security Monitor (`macsec-mon`).
;
; Features:
;   - EtherType 0x88E5 SecTAG Parsing (SCI, AN Association Number, PN Packet Number)
;   - MKA (MACsec Key Agreement IEEE 802.1X-2010) Session Status Monitor
;   - AES-GCM-256 Packet Number Replay Window Verification
;
; Delegates:
;   - Post-Quantum MACsec Engine        -> unet/pqc/pqc_macsec.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global macsec_mon_main


align 64
macsec_mon_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Monitor IEEE 802.1AE MACsec SecTAG frames & MKA key agreement state
    call pqc_macsec_unprotect_frame
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_SECURITY_MACSEC_MON_ASM
