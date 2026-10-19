; =============================================================================
; File     : src/store/store.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Object store — chunks, files, trees, commits stored on UFS.
; =============================================================================

%ifndef VCS_STORE_ASM
%define VCS_STORE_ASM

%include "include/vcs.inc"

bits 64

section .bss
align 16
store_root:   resq 1      ; object store root directory on UFS

section .text

; -----------------------------------------------------------------------------
; store_init — Initialize object store
; Input:  rdi = root path on UFS
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global store_init
store_init:
    PROLOGUE_SAVE rbx
    mov     [store_root], rdi
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; store_put — Store an object (content-addressed by hash)
; Input:  rdi = obj type, rsi = data, rdx = len, rcx = output hash buffer
; Output: rax = VCS_OK or error
; -----------------------------------------------------------------------------
global store_put
store_put:
    PROLOGUE_SAVE rbx, rcx, rdx
    ; TODO: hash data, write to content-addressed path
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

; -----------------------------------------------------------------------------
; store_get — Retrieve an object by hash
; Input:  rdi = obj type, rsi = hash buffer (32 bytes), rdx = output data
; Output: rax = data length or error
; -----------------------------------------------------------------------------
global store_get
store_get:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; store_exists — Check if object exists by hash
; Input:  rdi = obj type, rsi = hash buffer
; Output: rax = 1 if exists, 0 otherwise
; -----------------------------------------------------------------------------
global store_exists
store_exists:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; store_gc — Garbage collect unreferenced objects
; Input:  none
; Output: rax = number of objects collected
; -----------------------------------------------------------------------------
global store_gc
store_gc:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_STORE_ASM