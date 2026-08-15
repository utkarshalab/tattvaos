; =============================================================================
; Tattva OS — lib/ulog/record/record_build.asm
; =============================================================================
; Assembles a log_record_t from raw arguments. Called by emit/emit_async.asm
; and emit/emit_sync.asm — the one place that touches every field, so the
; 64-byte layout in ulog.inc only has to be understood in one place.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RECORD_BUILD_ASM
%define LIB_ULOG_RECORD_RECORD_BUILD_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"
%include "lib/percpu.inc"

section .text

; -----------------------------------------------------------------------------
; record_build — fill a caller-supplied 64-byte log_record_t
; Input:  RDI = log_record_t* dest (uninitialized)
;         SIL = level, DX = module_id, RCX = msg_ptr, R8 = fields_ptr,
;         R9B = fields_cnt
; Output: none. dest is fully populated: seq (seq_alloc), ts_ns (lib/time),
;         trace_id/span_id (context/correlate_stack), checksum (stamped last)
; Clobbers: RAX, RCX, RDX (RBX/R12-R15 used internally but restored)
; -----------------------------------------------------------------------------
global record_build
record_build:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push r9

    mov rbx, rdi                     ; RBX = dest
    mov r12, rsi                      ; level
    mov r13, rdx                       ; module_id
    mov r14, rcx                        ; msg_ptr
    mov r15, r8                          ; fields_ptr

    call log_seq_next
    mov [rbx + log_record_t.seq], rax

    call mono_get_nanos
    mov [rbx + log_record_t.ts_ns], rax

    call correlate_get_trace_id
    mov [rbx + log_record_t.trace_id], rax
    call correlate_get_span_id
    mov [rbx + log_record_t.span_id], rax

    mov [rbx + log_record_t.msg_ptr], r14
    mov [rbx + log_record_t.fields_ptr], r15
    mov dword [rbx + log_record_t.msg_len], 0

    mov word [rbx + log_record_t.module_id], r13w
    mov byte [rbx + log_record_t.level], r12b

    mov eax, [gs:percpu_t.cpu_id]
    mov [rbx + log_record_t.cpu_id], al

    pop r9
    mov [rbx + log_record_t.fields_cnt], r9b

    mov byte [rbx + log_record_t.redacted], 0
    mov byte [rbx + log_record_t.flags], 0
    mov byte [rbx + log_record_t.reserved], 0

    mov rdi, rbx
    call record_checksum_stamp

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_RECORD_RECORD_BUILD_ASM
