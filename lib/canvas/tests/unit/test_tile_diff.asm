; ============================================================================
; Unit Test — Tile Diff
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_tile_diff_main
; ============================================================================
global test_tile_diff_main
test_tile_diff_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_rle_roundtrip (stub)
; ============================================================================
global test_rle_roundtrip
test_rle_roundtrip:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_delta_all_same (stub)
; ============================================================================
global test_delta_all_same
test_delta_all_same:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; memcopy (stub)
; ============================================================================
global memcopy
memcopy:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_tile_diff_version
test_tile_diff_version: dq 0x010000