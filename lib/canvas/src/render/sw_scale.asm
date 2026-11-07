; ============================================================================
; Software Scale — Nearest and Bilinear (SIMD Optimized)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern scale_bilinear
extern scale_nearest

section .text

; ---------------------------------------------------------------------------
; sw_scale_nearest
;   Nearest neighbor scaling
;   IN:  rdi = dst, rsi = src, rdx = src_w, rcx = src_h, r8 = src_stride
;        r9 = dst_w, r10 = dst_h, r11 = dst_stride
; ---------------------------------------------------------------------------
global sw_scale_nearest
sw_scale_nearest:
    jmp scale_nearest                   ; ugfx's, in whole numbers

; ---------------------------------------------------------------------------
; sw_scale_bilinear
;   Bilinear scaling through the canonical native scalar kernel
; ---------------------------------------------------------------------------
global sw_scale_bilinear
sw_scale_bilinear:
    jmp scale_bilinear

section .data
global sw_scale_version
sw_scale_version: dq 0x010000
