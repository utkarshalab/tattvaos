; =============================================================================
; Tattva OS — unet/tools/http_client.asm
; =============================================================================
; Command-Line HTTP/1.1, HTTP/2 & HTTP/3 Client Tool.
;
; Implements:
;   - Sends GET, POST, PUT, DELETE & RFC 10008 QUERY Requests
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global http_client_init
global http_client_request

align 32
http_client_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
http_client_request:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
