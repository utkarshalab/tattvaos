; =============================================================================
; File     : src/core/errors.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Error code table and error reporting.
; =============================================================================

%ifndef VCS_CORE_ERRORS_ASM
%define VCS_CORE_ERRORS_ASM

%include "include/vcs.inc"

bits 64

section .data
align 16
error_table:
    .ok:            db "OK", 0
    .generic:       db "generic error", 0
    .not_found:     db "not found", 0
    .no_mem:        db "out of memory", 0
    .io:            db "I/O error", 0
    .corrupt:       db "corrupt data", 0
    .conflict:      db "conflict", 0
    .perm:          db "permission denied", 0

section .text

; -----------------------------------------------------------------------------
; errors_init — Initialize error subsystem
; -----------------------------------------------------------------------------
global errors_init
errors_init:
    PROLOGUE_SAVE rbx
    xor     eax, eax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; errors_shutdown — Shutdown error subsystem
; -----------------------------------------------------------------------------
global errors_shutdown
errors_shutdown:
    PROLOGUE_SAVE rbx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; error_string — Get human-readable string for error code
; Input:  edi = error code
; Output: rax = pointer to string
; -----------------------------------------------------------------------------
global error_string
error_string:
    PROLOGUE_SAVE rbx
    cmp     edi, VCS_OK
    je      .ret_ok
    cmp     edi, VCS_ERR_GENERIC
    je      .ret_generic
    cmp     edi, VCS_ERR_NOT_FOUND
    je      .ret_not_found
    cmp     edi, VCS_ERR_NO_MEM
    je      .ret_no_mem
    cmp     edi, VCS_ERR_IO
    je      .ret_io
    cmp     edi, VCS_ERR_CORRUPT
    je      .ret_corrupt
    cmp     edi, VCS_ERR_CONFLICT
    je      .ret_conflict
    cmp     edi, VCS_ERR_PERM
    je      .ret_perm
    xor     rax, rax
    jmp .done
.ret_ok:
    mov     rax, error_table.ok
    jmp .done
.ret_generic:
    mov     rax, error_table.generic
    jmp .done
.ret_not_found:
    mov     rax, error_table.not_found
    jmp .done
.ret_no_mem:
    mov     rax, error_table.no_mem
    jmp .done
.ret_io:
    mov     rax, error_table.io
    jmp .done
.ret_corrupt:
    mov     rax, error_table.corrupt
    jmp .done
.ret_conflict:
    mov     rax, error_table.conflict
    jmp .done
.ret_perm:
    mov     rax, error_table.perm
.done:
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_CORE_ERRORS_ASM