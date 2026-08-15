; =============================================================================
; Tattva OS — lib/ulog/ulog.inc
; =============================================================================
; Master schema for the structured logger: the on-the-wire record shape and
; the level constants every other ulog header builds on.
;
; log_record_t is deliberately exactly 64 bytes — one cache line. record_pool
; hands these out from a flat array, so keeping the struct cache-aligned
; means one record never straddles two lines and a producer on core N never
; false-shares a record another core is still writing.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_ULOG_INC
%define LIB_ULOG_ULOG_INC

%include "lib/ulog/module_ids.inc"
%include "lib/ulog/level/level_defs.inc"

; -----------------------------------------------------------------------------
; log_record_t — one log event, exactly 64 bytes
; -----------------------------------------------------------------------------
struc log_record_t
    .seq            resq 1      ; +0   monotonic, cross-core (record/seq_alloc.asm)
    .ts_ns           resq 1      ; +8   mono_get_nanos() at emit time
    .trace_id         resq 1      ; +16  correlation context, 0 = none (context/correlate_*)
    .span_id           resq 1      ; +24
    .msg_ptr             resq 1      ; +32  format string pointer (static, not owned)
    .fields_ptr           resq 1      ; +40  -> context/fields_encode.asm payload, or 0
    .msg_len                resd 1      ; +48
    .checksum                 resd 1      ; +52  CRC32 over bytes [0, 52) (record/record_checksum.asm)
    .module_id                  resw 1      ; +56  module_ids.inc
    .cpu_id                       resb 1      ; +58
    .level                          resb 1      ; +59  level/level_defs.inc
    .fields_cnt                       resb 1      ; +60
    .redacted                            resb 1      ; +61  context/redact_* set this
    .flags                                  resb 1      ; +62  LOG_FLAG_*
    .reserved                                  resb 1      ; +63
endstruc
%define LOG_RECORD_SIZE   64

; ---- record_t.flags bits ----------------------------------------------------
%define LOG_FLAG_EARLY_BOOT     0x01    ; emitted before full_init (init/early_init.asm)
%define LOG_FLAG_PANIC          0x02    ; emitted via panic/panic_emit.asm
%define LOG_FLAG_RATE_SUMMARY   0x04    ; a ratelimit_suppress.asm "N suppressed" record
%define LOG_FLAG_SELF           0x08    ; self_stats_report.asm reporting on ulog itself

%endif ; LIB_ULOG_ULOG_INC
