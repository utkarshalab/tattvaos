; ============================================================================
; cwpgen — CWP IDL Compiler Driver (emits inc/gen + src/proto/gen stubs)
; Full grammar implementation lands with build-host tooling; this driver
; defines the CLI contract and output layout used by gen_protocol.sh
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

global tool_main
tool_main:
    PROLOGUE_SAVE rbx
    mov rdi, gen_banner
    mov rsi, gen_banner_len
    call tv_log_write
    xor rax, rax
    call tv_task_exit

; ---------------------------------------------------------------------------
; cwpgen_run
;   IN: rdi = input.cwp path, rsi = out dir
; ---------------------------------------------------------------------------
global cwpgen_run
cwpgen_run:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; stages: lex -> parse -> resolve -> emit(inc/gen, proto/gen, docs)
    mov rdi, rbx
    call cwpgen_lex
    test rax, rax
    js .fail
    mov rdi, rax
    call cwpgen_parse
    test rax, rax
    js .fail
    mov rdi, rax
    mov rsi, r12
    call cwpgen_emit
    ret
.fail:
    ret

global cwpgen_lex
cwpgen_lex:
    PROLOGUE
    ; TODO: tokenizer
    xor rax, rax
    ret

global cwpgen_parse
cwpgen_parse:
    PROLOGUE
    ; TODO: recursive descent -> AST in arena
    xor rax, rax
    ret

global cwpgen_emit
cwpgen_emit:
    PROLOGUE
    ; TODO: write cwp_<name>.inc + gen_<name>.asm
    xor rax, rax
    ret

section .rodata
gen_banner: db "cwpgen 0.1.0", 10, 0
gen_banner_len: equ $ - gen_banner

section .data
global cwpgen_version
cwpgen_version: dq 0x010000
