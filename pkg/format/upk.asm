%ifndef GUARD_PKG_FORMAT_UPK_ASM
%define GUARD_PKG_FORMAT_UPK_ASM
; =============================================================================
; File     : pkg/format/upk.asm
; Project  : Tattva OS
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: .upk package format — .upk package format spec, manifest,
;              and package signature handling.
; =============================================================================

bits 64

section .text

; -----------------------------------------------------------------------------
; upk_parse — Parse a .upk package file
; Input:  rdi = package file path
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global upk_parse
upk_parse:
    ret

; -----------------------------------------------------------------------------
; upk_verify — Verify package signature
; Input:  rdi = package pointer, rsi = size
; Output: rax = 0 if valid, non-zero if invalid
; -----------------------------------------------------------------------------
global upk_verify
upk_verify:
    ret

%endif ; GUARD_PKG_FORMAT_UPK_ASM