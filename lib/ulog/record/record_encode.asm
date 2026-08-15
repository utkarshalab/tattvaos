; =============================================================================
; Tattva OS — lib/ulog/record/record_encode.asm
; =============================================================================
; Packs a log_record_t plus its (optional) structured-fields blob into one
; contiguous buffer — what sinks/file.asm and sinks/net.asm actually write,
; since fields_ptr lives in separately-pooled memory the sink can't dereference
; after the record itself has been recycled.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RECORD_ENCODE_ASM
%define LIB_ULOG_RECORD_RECORD_ENCODE_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .text

; -----------------------------------------------------------------------------
; record_encode — header + fields blob, flattened
; Input:  RDI = log_record_t* src, RSI = dest buffer, RDX = dest capacity
; Output: RAX = bytes written, 0 if capacity too small
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global record_encode
record_encode:
    push rbx
    push r12
    push r13
    push rsi
    push rdi

    mov rbx, rdi                     ; src
    mov r12, rsi                      ; dest
    mov r13, rdx                       ; capacity

    cmp r13, LOG_RECORD_SIZE
    jl .fail

    mov rsi, rbx
    mov rdi, r12
    mov rcx, LOG_RECORD_SIZE / 8
    cld
    rep movsq

    cmp qword [rbx + log_record_t.fields_ptr], 0
    je .no_fields

    mov rdi, [rbx + log_record_t.fields_ptr]
    call fields_encoded_size          ; RAX = blob byte size
    mov rcx, rax

    mov rax, r13
    sub rax, LOG_RECORD_SIZE
    cmp rcx, rax
    jg .fail

    mov rsi, [rbx + log_record_t.fields_ptr]
    lea rdi, [r12 + LOG_RECORD_SIZE]
    cld
    rep movsb

    mov rax, LOG_RECORD_SIZE
    add rax, rcx
    jmp .done

.no_fields:
    mov rax, LOG_RECORD_SIZE
    jmp .done

.fail:
    xor rax, rax

.done:
    pop rdi
    pop rsi
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_RECORD_RECORD_ENCODE_ASM
