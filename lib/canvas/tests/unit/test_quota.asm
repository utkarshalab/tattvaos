; ============================================================================
; Unit Test — Quota Manager
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; test_quota_main
; ============================================================================
global test_quota_main
test_quota_main:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_quota_mem_ok (stub)
; ============================================================================
global test_quota_mem_ok
test_quota_mem_ok:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_quota_mem_exceeded (stub)
; ============================================================================
global test_quota_mem_exceeded
test_quota_mem_exceeded:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_quota_mem_unlimited (stub)
; ============================================================================
global test_quota_mem_unlimited
test_quota_mem_unlimited:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; test_quota_surf_ok (stub)
; ============================================================================
global test_quota_surf_ok
test_quota_surf_ok:
    PROLOGUE
    xor rax, rax
    ret

section .data
global test_quota_version
test_quota_version: dq 0x010000