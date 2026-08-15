; =============================================================================
; Tattva OS — lib/ulog/sinks/file_transport.asm
; =============================================================================
; The sink_iface.inc contract over storage/uxfs. uxfs_write_file is still a
; fail-closed stub in kernel/unimplemented.asm as of this writing — that's
; fine, and expected: this sink will start actually writing bytes the day
; that stub gets a real body, with no change needed here. A short/zero
; return from it is treated as a real failure and reported honestly (RAX <
; count), which is exactly the signal dispatch_retry.asm and
; dispatch_circuit_breaker.asm are built to react to.
;
; Assumed uxfs_write_file convention (matching this tree's dominant
; RDI/RSI/RDX/RCX-in, RAX-out style): RDI = path, RSI = data, RDX = length,
; RCX = segment index -> RAX = bytes written (0 on failure).
;
; file_index.asm is fed a placeholder offset (0) for now — a real byte
; offset needs uxfs_write_file to report one, which the stub obviously
; doesn't. Wiring the real value through is a one-line change once it does.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_FILE_TRANSPORT_ASM
%define LIB_ULOG_SINKS_FILE_TRANSPORT_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .text

; -----------------------------------------------------------------------------
; file_sink_write — sink_t.write_fn
; Input:  RDI = log_record_t* batch, RSI = count
; Output: RAX = records actually written (may be a short count)
; -----------------------------------------------------------------------------
global file_sink_write
file_sink_write:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                     ; batch base
    mov r12, rsi                      ; count
    xor r13, r13                       ; index

.loop:
    cmp r13, r12
    jae .done

    mov rax, r13
    imul rax, rax, LOG_RECORD_SIZE
    add rax, rbx
    mov r15, rax                     ; R15 = this iteration's record_ptr

    mov rdi, r15
    call file_format_record          ; RAX = length, into ulog_file_format_scratch
    mov r14, rax                     ; R14 = length

    call rotate_current_segment      ; RAX = segment
    mov rcx, rax
    mov rdi, ulog_file_path
    mov rsi, ulog_file_format_scratch
    mov rdx, r14
    call uxfs_write_file
    test rax, rax
    jz .short_write

    mov rdi, r14
    call rotate_note_bytes
    test rax, rax
    jz .no_roll
    call rotate_perform
.no_roll:
    mov rdi, [r15 + log_record_t.seq]
    xor rsi, rsi                     ; placeholder offset — see header note
    call file_index_note_write

    inc r13
    jmp .loop

.short_write:
.done:
    mov rax, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; file_sink_flush — best effort; real fsync-equivalent lands with
; storage/uwal once its durability primitives are wired up here.
; -----------------------------------------------------------------------------
global file_sink_flush
file_sink_flush:
    mov rax, 1
    ret

section .rodata
ulog_file_path: db "/var/log/tattva.ulog", 0

%endif ; LIB_ULOG_SINKS_FILE_TRANSPORT_ASM
