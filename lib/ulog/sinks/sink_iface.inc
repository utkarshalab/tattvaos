; =============================================================================
; Tattva OS — lib/ulog/sinks/sink_iface.inc
; =============================================================================
; The pluggable sink contract. Every transport (serial/file/net, and whatever
; obs/udash registers later for a live log tail) implements this shape and
; hands a pointer to sink_registry.asm — drain/dispatch.asm never knows which
; concrete transport it's talking to.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_SINK_IFACE_INC
%define LIB_ULOG_SINKS_SINK_IFACE_INC

; -----------------------------------------------------------------------------
; sink_t — one registered output
;   .write_fn(RDI = log_record_t* batch, RSI = count) -> RAX = records written
;            A short write (RAX < RSI) is a partial-failure signal that
;            dispatch_retry.asm and dispatch_circuit_breaker.asm act on.
;   .flush_fn() -> RAX = 1 ok, 0 failed. Called by panic_flush.asm too, so it
;            must not depend on the drain fiber's own state.
; -----------------------------------------------------------------------------
struc sink_t
    .write_fn        resq 1      ; +0
    .flush_fn         resq 1      ; +8
    .name_ptr           resq 1      ; +16  null-terminated, for self_stats_report.asm
    .min_level             resb 1      ; +24  level/level_defs.inc threshold, this sink only
    .enabled                  resb 1      ; +25  0/1, sink_registry.asm toggle
    .healthy                    resb 1      ; +26  sink_health.asm
    .breaker_open                  resb 1      ; +27  dispatch_circuit_breaker.asm
    .fail_count                       resd 1      ; +28  consecutive failures
    .breaker_trip_ns                     resq 1      ; +32  mono_get_nanos() at trip time
endstruc
%define SINK_T_SIZE   40

%define ULOG_MAX_SINKS   8

%endif ; LIB_ULOG_SINKS_SINK_IFACE_INC
