; ============================================================================
; Unit Test — Record/Replay
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_record_replay_main
; ============================================================================
global test_record_replay_main
test_record_replay_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_record_inactive_by_default (stub)
; ============================================================================
global test_record_inactive_by_default
test_record_inactive_by_default:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_stats_offsets (stub)
; ============================================================================
global test_stats_offsets
test_stats_offsets:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_metrics_offsets (stub)
; ============================================================================
global test_metrics_offsets
test_metrics_offsets:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_record_replay_version
test_record_replay_version: dq 0x010000