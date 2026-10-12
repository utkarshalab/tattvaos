; ============================================================================
; Client Lifecycle — Global Init/Shutdown, Version
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

global canvas_client_init
canvas_client_init:
    PROLOGUE
    xor rax, rax
    ret

global canvas_client_shutdown
canvas_client_shutdown:
    PROLOGUE
    xor rax, rax
    ret

global canvas_client_version
canvas_client_version:
    PROLOGUE
    mov rax, 0x00010000
    ret

section .data
global canvas_client_mod_version
canvas_client_mod_version: dq 0x010000
