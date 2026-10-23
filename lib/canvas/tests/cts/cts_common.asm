; ============================================================================
; CTS Common — Shared CTS Test Helpers
; ============================================================================

%ifndef __CTS_COMMON_ASM__
%define __CTS_COMMON_ASM__

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/test.inc"
%include "inc/externs.inc"

; ============================================================================
; CTS Helper Functions
; ============================================================================

section .text

; ============================================================================
; cts_connect
;   Connect to Canvas server for CTS testing
;   OUT: rax = client handle, negative error
; ============================================================================
global cts_connect
cts_connect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    
    ; TODO: Implement actual connection
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; cts_disconnect
;   Disconnect from Canvas server
; ============================================================================
global cts_disconnect
cts_disconnect:
    PROLOGUE
    ret

; ============================================================================
; cts_create_surface
;   Create a test surface
; ============================================================================
global cts_create_surface
cts_create_surface:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; cts_present
;   Present a surface
; ============================================================================
global cts_present
cts_present:
    PROLOGUE
    xor rax, rax
    ret

; ============================================================================
; cts_wait_for_frame
;   Wait for frame callback
; ============================================================================
global cts_wait_for_frame
cts_wait_for_frame:
    PROLOGUE
    xor rax, rax
    ret

%endif ; __CTS_COMMON_ASM__