; ============================================================================
; cwpgen — CWP IDL Compiler
; Generates: inc/gen/cwp_*.inc, src/proto/gen/gen_*.asm, src/client/gen/client_*.asm
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global cwpgen_main
cwpgen_main:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    ; Parse command line (simplified)
    ; cwpgen <input.cwp> <output_dir>

    mov rdi, banner
    mov rsi, banner_len
    call tv_log_write

    ; TODO: Full implementation
    ; 1. Parse .cwp file
    ; 2. Build AST
    ; 3. Generate output files

    xor rax, rax
    call tv_task_exit
    UNREACHABLE

section .rodata

banner: db "cwpgen - CWP IDL Compiler", 10, 0
banner_len: equ $ - banner

section .data
global cwpgen_version
cwpgen_version: dq 0x010000