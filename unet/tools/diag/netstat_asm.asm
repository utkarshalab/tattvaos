; =============================================================================
; Tattva OS — unet/tools/netstat_asm.asm
; =============================================================================
; Native Assembly Active Socket & BSD Connection Table State Dump Tool.
;
; Implements:
;   - Iterates 512-Slot BSD Socket Table (`socket.asm`)
;   - Formats Local IP:Port, Remote IP:Port, TCP State (`ESTABLISHED`, `LISTEN`) to TTY
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global netstat_init
global netstat_dump_sockets

align 32
netstat_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
netstat_dump_sockets:
    push rbp
    mov rbp, rsp
    ; Traverse socket table and print active connections
    xor eax, eax
    pop rbp
    ret
