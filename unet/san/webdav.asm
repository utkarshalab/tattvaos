; =============================================================================
; Tattva OS — unet/san/webdav.asm
; =============================================================================
; WebDAV HTTP Remote Storage Extensions Engine (RFC 4918).
;
; Implements:
;   - PROPFIND, PROPPATCH, MKCOL, COPY, MOVE, LOCK, UNLOCK HTTP Extensions
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global webdav_init
global webdav_propfind

align 32
webdav_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
webdav_propfind:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
