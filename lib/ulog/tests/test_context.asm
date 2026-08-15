; =============================================================================
; Tattva OS — lib/ulog/tests/test_context.asm
; =============================================================================
; fields_encode/decode round-tripping, and correlate_stack's nesting — the
; two pieces a caller directly interacts with when attaching structured data
; or a trace context to a log call.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_TESTS_TEST_CONTEXT_ASM
%define LIB_ULOG_TESTS_TEST_CONTEXT_ASM

[BITS 64]

%include "lib/ulog/context/fields_schema.inc"

section .bss
alignb 8
test_fields_buf: resb (fields_blob_hdr_t_size + 2 * FIELD_ENTRY_SIZE)

section .text

; -----------------------------------------------------------------------------
; ulog_test_context — Output: RAX = 0 pass, -1 fail
; -----------------------------------------------------------------------------
global ulog_test_context
ulog_test_context:
    push rbx

    ; ---- fields round-trip ----
    mov rdi, test_fields_buf
    call fields_encode_init

    mov rdi, test_fields_buf
    mov rsi, .key_count
    mov dl, FIELD_TYPE_INT
    mov rcx, 42
    call fields_encode_add
    test rax, rax
    jz .fail

    mov rdi, test_fields_buf
    call fields_decode_count
    cmp rax, 1
    jne .fail

    mov rdi, test_fields_buf
    xor rsi, rsi
    call fields_decode_get
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp qword [rbx + field_entry_t.val], 42
    jne .fail

    ; ---- correlate_stack nesting ----
    mov rdi, 111
    mov rsi, 222
    call correlate_stack_push
    test rax, rax
    jz .fail

    call correlate_get_trace_id
    cmp rax, 111
    jne .fail
    call correlate_get_span_id
    cmp rax, 222
    jne .fail

    call correlate_stack_pop
    call correlate_get_trace_id
    test rax, rax
    jnz .fail                        ; empty stack must report 0

    xor rax, rax
    jmp .done

.fail:
    mov rax, -1

.done:
    pop rbx
    ret

section .rodata
.key_count: db "count", 0

%endif ; LIB_ULOG_TESTS_TEST_CONTEXT_ASM
