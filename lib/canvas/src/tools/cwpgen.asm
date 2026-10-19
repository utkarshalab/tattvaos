; ============================================================================
; cwpgen — CWP IDL Compiler Driver (emits protocol declarations)
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
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, gen_banner
    mov rsi, gen_banner_len
    call tv_log_write
    cmp rbx, 3
    jb .gen_usage
    mov rdi, [r12 + 8]
    mov rsi, [r12 + 16]
    call cwpgen_run
    jmp .gen_exit
.gen_usage:
    mov rdi, gen_usage
    mov rsi, gen_usage_len
    call tv_log_write
    mov rax, -(EINVAL)
.gen_exit:
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
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global cwpgen_lex
cwpgen_lex:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, rbx
.lex_loop:
    movzx eax, byte [r12]
    test al, al
    jz .lex_ok
    cmp al, 9
    je .lex_next
    cmp al, 10
    je .lex_next
    cmp al, 13
    je .lex_next
    cmp al, 32
    jb .lex_bad
    cmp al, 126
    ja .lex_bad
.lex_next:
    inc r12
    jmp .lex_loop
.lex_ok:
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret
.lex_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

global cwpgen_parse
cwpgen_parse:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    xor r12d, r12d               ; brace depth
    xor r13d, r13d               ; saw interface body
.parse_loop:
    movzx eax, byte [rbx]
    test al, al
    jz .parse_end
    cmp al, '{'
    jne .not_open
    inc r12d
    mov r13d, 1
    jmp .parse_next
.not_open:
    cmp al, '}'
    jne .parse_next
    test r12d, r12d
    jz .parse_bad
    dec r12d
.parse_next:
    inc rbx
    jmp .parse_loop
.parse_end:
    test r12d, r12d
    jnz .parse_bad
    test r13d, r13d
    jz .parse_bad
    mov rax, rdi
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.parse_bad:
    mov rax, -(EPROTO)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global cwpgen_emit
cwpgen_emit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; TVFS currently has no write syscall. Emit the validated canonical IDL to
    ; the supplied native output sink (the standard log stream) so build-host
    ; tooling can atomically materialize inc/gen and src/proto/gen artifacts.
    mov rdi, rbx
    call cwpgen_strlen
    mov rsi, rax
    mov rdi, rbx
    call tv_log_write
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

cwpgen_strlen:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    xor eax, eax
.len_loop:
    cmp byte [rbx + rax], 0
    je .len_done
    inc rax
    jmp .len_loop
.len_done:
    EPILOGUE_RESTORE rbx
    ret

section .rodata
gen_banner: db "cwpgen 0.1.0", 10, 0
gen_banner_len: equ $ - gen_banner
gen_usage: db "usage: cwpgen <protocol-source> <output-name>", 10, 0
gen_usage_len: equ $ - gen_usage

section .data
global cwpgen_version
cwpgen_version: dq 0x010000
