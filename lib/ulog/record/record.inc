; =============================================================================
; Tattva OS — lib/ulog/record/record.inc
; =============================================================================
; Internal structs for record transport and staging. Not part of ulog.inc's
; "master schema" on purpose — nothing outside record/, drain/, and init/
; needs to know a ring is SPSC or that the pool is a freelist stack.
;
; Design:
;   - Per-CPU ring: SINGLE producer (that core), SINGLE consumer (the one
;     drain fiber). That means push/pop need no CAS, no lock — just correct
;     head/tail publish ordering. Storage is inline log_record_t slots, not
;     pointers, so there is no separate per-record allocation on push.
;   - Pool: a flat array of log_record_t + freelist stack, used only by
;     batch.asm to stage records that must outlive their ring slot while a
;     sink write is still in flight. Touched only by the drain fiber, so it
;     also needs no atomics — one consumer, one owner.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RECORD_INC
%define LIB_ULOG_RECORD_RECORD_INC

%include "lib/ulog/ulog.inc"
%include "lib/ulog/config/defaults.inc"

; -----------------------------------------------------------------------------
; ring_t — one per CPU, reached through percpu_t.log_ring
; -----------------------------------------------------------------------------
struc ring_t
    .head          resq 1      ; +0   next write index (producer-owned)
    .tail          resq 1      ; +8   next read index (consumer-owned)
    .dropped       resq 1      ; +16  overwrite-oldest count (ring_wrap.asm)
    .high_water    resq 1      ; +24  max observed fill (ring_stats.asm)
    .cpu_id        resd 1      ; +32
    .reserved      resd 1      ; +36
    .slots         resb (LOG_RECORD_SIZE * ULOG_RING_SLOTS_PER_CPU)  ; +40
endstruc

; -----------------------------------------------------------------------------
; ulog_pool_t — one global instance, staging memory for in-flight batches
; -----------------------------------------------------------------------------
struc ulog_pool_t
    .free_top      resq 1      ; +0   index of top free slot, -1 if empty
    .free_stack     resq 1      ; +8   -> array of ULOG_POOL_RECORDS qword indices
    .slots            resq 1      ; +16  -> array of ULOG_POOL_RECORDS log_record_t
    .exhausted_count     resq 1      ; +24  times record_pool_alloc found nothing free
endstruc

%endif ; LIB_ULOG_RECORD_RECORD_INC
