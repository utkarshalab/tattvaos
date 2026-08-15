; =============================================================================
; Tattva OS — lib/ulog/record/ring_alloc.asm
; =============================================================================
; Allocates and wires up the calling core's ring. Called once per core from
; init/full_init.asm, after lib/mem's heap is up and percpu_t is addressable
; through GS — never from early_init.asm, which runs before either exists.
;
; Also registers the pointer in ulog_rings_by_cpu, a flat cpu_id-indexed
; array — gs: only reaches the CURRENT core's ring, but panic/panic_flush.asm
; runs on whichever core panicked and has to drain every core's backlog, not
; just its own.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RING_ALLOC_ASM
%define LIB_ULOG_RECORD_RING_ALLOC_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"
%include "lib/percpu.inc"

section .bss
alignb 8
global ulog_rings_by_cpu
ulog_rings_by_cpu: resq PERCPU_MAX_CORES

section .text

; -----------------------------------------------------------------------------
; log_ring_alloc_for_this_cpu — allocate, zero, and register this core's ring
; Input:  none
; Output: RAX = ring_t* (0 on allocation failure)
; Clobbers: RAX, RCX, RDI
; -----------------------------------------------------------------------------
global log_ring_alloc_for_this_cpu
log_ring_alloc_for_this_cpu:
    push rbx

    mov rdi, ring_t_size
    call heap_alloc
    test rax, rax
    jz .fail
    mov rbx, rax

    mov rdi, rbx
    mov rcx, ring_t_size / 8
    xor rax, rax
    cld
    rep stosq                       ; zero the whole struct, including .slots

    mov eax, [gs:percpu_t.cpu_id]
    mov [rbx + ring_t.cpu_id], eax

    mov [gs:percpu_t.log_ring], rbx

    cdqe                              ; RAX = sign/zero-extended cpu_id for indexing
    mov [ulog_rings_by_cpu + rax * 8], rbx

    mov rax, rbx
    jmp .done

.fail:
    xor rax, rax

.done:
    pop rbx
    ret

%endif ; LIB_ULOG_RECORD_RING_ALLOC_ASM
