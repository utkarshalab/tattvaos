; =============================================================================
; Tattva OS — lib/ulog/emit/emit_async.asm
; =============================================================================
; The hot path. Every LOG_TRACE/DEBUG/INFO/WARN call level_gate.asm didn't
; elide lands here. No message-only call allocates anything — the record is
; built on the caller's own stack and copied into the per-CPU ring, which is
; itself pre-allocated. The one exception: a caller-supplied fields blob
; (which may itself be stack memory built by emit/emit_varargs.asm's macros)
; gets heap-copied here, synchronously, before this function returns — so the
; record's fields_ptr stays valid for the record's whole lifetime regardless
; of what the caller's stack frame does next. A message with no fields never
; pays for that copy.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_EMIT_EMIT_ASYNC_ASM
%define LIB_ULOG_EMIT_EMIT_ASYNC_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"
%include "lib/percpu.inc"

section .text

; -----------------------------------------------------------------------------
; emit_async — build a record and push it onto this core's ring
; Input:  RDI = level, RSI = module_id, RDX = msg_ptr, RCX = fields_ptr (0 if
;         none — caller-owned, may be stack memory), R8 = fields_cnt
; Output: none
; -----------------------------------------------------------------------------
global emit_async
emit_async:
    ; Before init/full_init.asm has run, [gs:percpu_t.log_ring] is null —
    ; there is no ring yet. Route straight to the always-safe direct-serial
    ; path instead (fields are dropped, matching panic_emit's own contract;
    ; nothing this early has fields to carry anyway).
    cmp byte [ulog_full_mode_active], 0
    je panic_emit

    push rbx
    push r12
    push r13
    push r14
    push r15
    push r8                          ; fields_cnt, needed again only at the end

    mov r12, rdi                     ; level
    mov r13, rsi                      ; module_id
    mov r14, rdx                       ; msg_ptr
    mov r15, rcx                        ; caller's fields_ptr (0 if none)
    xor rbx, rbx                     ; RBX = resolved fields_ptr for the record

    test r15, r15
    jz .build_record

    mov rdi, r15
    call fields_encoded_size         ; RAX = blob byte size
    mov rdi, rax
    call heap_alloc
    test rax, rax
    jz .build_record                 ; OOM: drop the fields, keep the message —
                                      ; a record without fields beats no record
    mov rbx, rax

    mov rdi, r15
    call fields_encoded_size
    mov rcx, rax
    mov rsi, r15
    mov rdi, rbx
    cld
    rep movsb

.build_record:
    sub rsp, LOG_RECORD_SIZE
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, rbx
    mov r9, [rsp + LOG_RECORD_SIZE]  ; fields_cnt, pushed at entry, sits just
                                      ; above the scratch record we just carved out
    call record_build

    mov rdi, [gs:percpu_t.log_ring]
    mov rsi, rsp
    call log_ring_push

    add rsp, LOG_RECORD_SIZE
    pop r8                           ; discard the fields_cnt slot
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_EMIT_EMIT_ASYNC_ASM
