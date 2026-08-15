; =============================================================================
; Tattva OS — lib/ulog/config/defaults.inc
; =============================================================================
; Named constants for every tunable ulog ships with. Nothing below should
; ever be duplicated as a bare literal elsewhere in lib/ulog — that's what
; config/runtime_tune.asm and config/boot_args.asm override at runtime.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONFIG_DEFAULTS_INC
%define LIB_ULOG_CONFIG_DEFAULTS_INC

; ---- record pool (record/record_pool.asm) ------------------------------------
%define ULOG_POOL_RECORDS          4096    ; total pre-allocated log_record_t slots

; ---- per-CPU ring (record/ring_alloc.asm) -------------------------------------
%define ULOG_RING_SLOTS_PER_CPU    512     ; must be a power of two (ring_wrap.asm masks)
%define ULOG_RING_MASK             (ULOG_RING_SLOTS_PER_CPU - 1)

; ---- drain fiber (drain/drain_fiber.asm) --------------------------------------
%define ULOG_DRAIN_PRIORITY        3       ; fiber_create priority: 3 = IDLE
%define ULOG_DRAIN_RESTART_POLICY  1       ; fiber_create restart_policy: 1 = ALWAYS

; ---- batching (drain/batch.asm, batch_flush_policy.asm) -----------------------
%define ULOG_BATCH_MAX_RECORDS     64
%define ULOG_BATCH_MAX_NANOS       5000000     ; 5ms — flush on whichever limit hits first

; ---- backoff (drain/drain_backoff.asm) -----------------------------------------
%define ULOG_BACKOFF_MIN_NANOS     100000       ; 100us
%define ULOG_BACKOFF_MAX_NANOS     50000000     ; 50ms

; ---- rate limiting (ratelimit/*) -------------------------------------------------
%define ULOG_RATELIMIT_WINDOW_NANOS 1000000000  ; 1s sliding window
%define ULOG_RATELIMIT_MAX_PER_WINDOW 10         ; identical (module_id, fmt_ptr) per window

; ---- circuit breaker (drain/dispatch_circuit_breaker.asm) ------------------------
%define ULOG_BREAKER_TRIP_THRESHOLD  5           ; consecutive sink failures to trip open
%define ULOG_BREAKER_COOLDOWN_NANOS  2000000000  ; 2s before a half-open retry

; ---- compile-time zero-overhead gate (level/level_gate.asm) ----------------------
; Overridden by the Makefile via -DULOG_BUILD_LEVEL=N for release builds.
%ifndef ULOG_BUILD_LEVEL
%define ULOG_BUILD_LEVEL 0     ; 0 = LVL_TRACE — dev default, keep everything
%endif

%endif ; LIB_ULOG_CONFIG_DEFAULTS_INC
