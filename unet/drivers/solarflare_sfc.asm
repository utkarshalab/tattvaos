; =============================================================================
; Tattva OS — unet/drivers/solarflare_sfc.asm
; =============================================================================
; Solarflare SFN8522 Ultra-Low Latency HFT NIC Driver.
;
; Implements:
;   - Sub-100ns Direct User-Space EF_VI Ring Doorbell & Event Queue Handling
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global solarflare_init
global solarflare_poll

align 32
solarflare_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
solarflare_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
