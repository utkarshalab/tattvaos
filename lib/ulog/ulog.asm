; =============================================================================
; Tattva OS — lib/ulog/ulog.asm
; =============================================================================
; Top-level aggregator for the structured logger — mirrors the pattern
; crypto/uhash/uhash.asm, storage/uxfs/uxfs.asm, and unet/unet.asm already
; use: kernel/entry.asm includes this one file, and everything else in
; lib/ulog/ is reached from here, in dependency order.
;
; Depends only on lib/mem, lib/time, lib/io, and kernel/drivers/serial —
; all already earlier in kernel/entry.asm's include chain. Does not import
; from unet/, storage/, crypto/, or security/ — see sinks/net_transport.asm
; and sinks/file_transport.asm for how those boundaries are respected.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_ULOG_ASM
%define LIB_ULOG_ULOG_ASM

; ---- schema -----------------------------------------------------------------
%include "lib/ulog/module_ids.inc"
%include "lib/ulog/level/level_defs.inc"
%include "lib/ulog/ulog.inc"
%include "lib/ulog/config/defaults.inc"
%include "lib/ulog/sinks/sink_iface.inc"

; ---- record: construction, transport, staging --------------------------------
%include "lib/ulog/record/record.inc"
%include "lib/ulog/record/seq_alloc.asm"
%include "lib/ulog/record/record_checksum.asm"
%include "lib/ulog/record/ring_wrap.asm"
%include "lib/ulog/record/ring_stats.asm"
%include "lib/ulog/record/ring_push.asm"
%include "lib/ulog/record/ring_pop.asm"
%include "lib/ulog/record/ring_alloc.asm"
%include "lib/ulog/record/record_pool.asm"
%include "lib/ulog/record/record_free.asm"
%include "lib/ulog/record/record_build.asm"
%include "lib/ulog/record/record_encode.asm"
%include "lib/ulog/record/record_decode.asm"

; ---- level: filtering, both compile-time and runtime --------------------------
%include "lib/ulog/level/level_gate.asm"
%include "lib/ulog/level/level_runtime.asm"
%include "lib/ulog/level/level_module_map.asm"
%include "lib/ulog/level/level_filter.asm"
%include "lib/ulog/level/level_parse.asm"

; ---- context: structured fields + correlation ----------------------------------
%include "lib/ulog/context/fields_schema.inc"
%include "lib/ulog/context/fields_encode.asm"
%include "lib/ulog/context/fields_decode.asm"
%include "lib/ulog/context/correlate_stack.asm"
%include "lib/ulog/context/correlate_propagate.asm"
%include "lib/ulog/context/redact_registry.asm"
%include "lib/ulog/context/redact_pattern.asm"

; ---- emit: what every fiber actually calls --------------------------------------
%include "lib/ulog/emit/emit_async.asm"
%include "lib/ulog/emit/emit_sync.asm"
%include "lib/ulog/emit/emit_fmt.asm"
%include "lib/ulog/emit/emit_varargs.asm"

; ---- panic: the emergency bypass, isolated from drain/ --------------------------
%include "lib/ulog/panic/panic_nmi_safe.asm"
%include "lib/ulog/panic/panic_lock.asm"
%include "lib/ulog/panic/panic_emit.asm"
%include "lib/ulog/panic/panic_flush.asm"

; ---- format: binary storage vs. rendering, kept separate -------------------------
%include "lib/ulog/format/timestamp_fmt.asm"
%include "lib/ulog/format/hex_dump.asm"
%include "lib/ulog/format/text_render.asm"
%include "lib/ulog/format/json_render.asm"

; ---- sinks: pluggable outputs -----------------------------------------------------
%include "lib/ulog/sinks/sink_registry.asm"
%include "lib/ulog/sinks/sink_health.asm"
%include "lib/ulog/sinks/serial_format.asm"
%include "lib/ulog/sinks/serial_transport.asm"
%include "lib/ulog/sinks/file_format.asm"
%include "lib/ulog/sinks/file_index.asm"
%include "lib/ulog/sinks/rotate.asm"
%include "lib/ulog/sinks/file_transport.asm"
%include "lib/ulog/sinks/net_queue.asm"
%include "lib/ulog/sinks/net_format.asm"
%include "lib/ulog/sinks/net_transport.asm"

; ---- ratelimit: opt-in flood protection --------------------------------------------
%include "lib/ulog/ratelimit/ratelimit_hash.asm"
%include "lib/ulog/ratelimit/ratelimit_window.asm"
%include "lib/ulog/ratelimit/ratelimit_suppress.asm"

; ---- drain: the background daemon fiber and everything it needs --------------------
%include "lib/ulog/drain/backpressure_drop_oldest.asm"
%include "lib/ulog/drain/backpressure_drop_newest.asm"
%include "lib/ulog/drain/backpressure_block.asm"
%include "lib/ulog/drain/batch.asm"
%include "lib/ulog/drain/batch_flush_policy.asm"
%include "lib/ulog/drain/dispatch_circuit_breaker.asm"
%include "lib/ulog/drain/dispatch_retry.asm"
%include "lib/ulog/drain/dispatch.asm"
%include "lib/ulog/drain/drain_wake.asm"
%include "lib/ulog/drain/drain_backoff.asm"
%include "lib/ulog/drain/self_stats.asm"
%include "lib/ulog/drain/self_stats_report.asm"
%include "lib/ulog/drain/drain_fiber.asm"

; ---- init: early/full lifecycle, last — depends on everything above ----------------
%include "lib/ulog/init/early_init.asm"
%include "lib/ulog/init/mode_transition.asm"
%include "lib/ulog/init/full_init.asm"

%endif ; LIB_ULOG_ULOG_ASM
