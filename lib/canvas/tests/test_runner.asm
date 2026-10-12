; ============================================================================
; Test Runner — Executes All Unit Test Suites
; Built as Tattva image, reports results over serial
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; External test suites
extern test_arena_suite
extern test_str_suite
extern test_ring_suite
extern test_handle_suite
extern test_region_suite
extern test_map_suite
extern test_quota_suite
extern test_record_replay_suite
extern test_jpeg_suite
extern test_icc_suite
extern test_tile_diff_suite
extern test_rfb_suite
extern test_inflate_suite
extern test_png_suite
extern test_ttf_suite

; ---------------------------------------------------------------------------
; test_runner_init
;   Main entry point for test runner image
; ---------------------------------------------------------------------------
global test_runner_init
test_runner_init:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    ; Initialize logging
    mov rdi, LOG_TRACE
    call tv_log_set_level

    ; Print banner
    mov rdi, runner_banner
    mov rsi, runner_banner_len
    call tv_log_write

    ; Run all test suites
    xor rbx, rbx        ; total failures

    ; Test arena
    call test_arena_suite
    add rbx, rax

    ; Test string
    call test_str_suite
    add rbx, rax

    ; Test ring buffer
    call test_ring_suite
    add rbx, rax

    ; Test handle table
    call test_handle_suite
    add rbx, rax

    ; Test region
    call test_region_suite
    add rbx, rax

    ; Test map
    call test_map_suite
    add rbx, rax

    ; Test quotas
    call test_quota_suite
    add rbx, rax

    ; Test record/replay
    call test_record_replay_suite
    add rbx, rax

    ; Test image decoders (probe)
    call test_jpeg_suite
    add rbx, rax

    ; Test ICC/color
    call test_icc_suite
    add rbx, rax

    ; Test tile-diff/codecs
    call test_tile_diff_suite
    add rbx, rax

    ; Test RFB
    call test_rfb_suite
    add rbx, rax

    ; Test inflate/zlib
    call test_inflate_suite
    add rbx, rax

    ; Test PNG
    call test_png_suite
    add rbx, rax

    ; Test TTF
    call test_ttf_suite
    add rbx, rax

    ; Final summary
    mov rdi, runner_summary
    mov rsi, rbx
    call tv_log_printf

    ; Exit with failure count
    mov rax, rbx
    call tv_task_exit

    UNREACHABLE

section .rodata

runner_banner:        db "Canvas Test Runner", 10, "===================", 10, 0
runner_banner_len:    equ $ - runner_banner
runner_summary:       db "=== ALL TESTS COMPLETE: %d suite(s) failed ===", 10, 0