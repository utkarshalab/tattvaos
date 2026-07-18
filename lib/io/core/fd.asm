; =============================================================================
; lib/io/core/fd.asm
; Global file descriptor table tracking.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_FD_ASM
%define IO_CORE_FD_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .bss
global io_fd_table
io_fd_table: resb fd_t_size * 256    ; Fixed array of 256 file descriptor entries

section .text

; =============================================================================
; io_fd_init — Zero-initialize the global file descriptor table
; In : None
; Out: None
; =============================================================================
IO_FUNC io_fd_init
    push    rdi
    push    rcx
    push    rax

    lea     rdi, [rel io_fd_table]
    mov     rcx, (fd_t_size * 256) / 8  ; Clear by qwords
    xor     rax, rax
    rep     stosq                       ; Zero out entire table

    pop     rax
    pop     rcx
    pop     rdi
    ret
IO_ENDFUNC io_fd_init

%endif ; IO_CORE_FD_ASM
