; =============================================================================
; lib/io/async/batch.asm
; Doorbell plugging and submission batching control.
;
; Enables batching of multiple I/O requests into the submission queues
; while temporarily suppressing the expensive hardware notify doorbell writes.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ASYNC_BATCH_ASM
%define IO_ASYNC_BATCH_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .data
global global_plug_depth
global_plug_depth: dq 0             ; Monotonic plug counter

section .text

; =============================================================================
; io_batch_plug — Increment the batch plug counter to suppress doorbells
; =============================================================================
IO_FUNC io_batch_plug
    lock inc qword [rel global_plug_depth]
IO_ENDFUNC io_batch_plug

; =============================================================================
; io_batch_unplug — Decrement plug counter and trigger doorbell flush if 0
; In : RDI = -> device_t object
; =============================================================================
IO_FUNC io_batch_unplug
    guard_null rdi

    lock dec qword [rel global_plug_depth]
    jnz     .done                   ; Still plugged by nested caller

    ; Plug depth reached 0: execute flush trigger if defined
    mov     rax, [rdi + device_t.flush]
    test    rax, rax
    jz      .done

    call    rax                     ; dev->flush(dev)

.done:
IO_ENDFUNC io_batch_unplug

%endif ; IO_ASYNC_BATCH_ASM
