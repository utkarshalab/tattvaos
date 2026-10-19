; =============================================================================
; File     : src/core/arena.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Arena allocator — bump allocation, no individual frees.
; =============================================================================

%ifndef VCS_CORE_ARENA_ASM
%define VCS_CORE_ARENA_ASM

%include "include/vcs.inc"

bits 64

section .bss
align 16
arena_list_head:  resq 1

section .text

; -----------------------------------------------------------------------------
; arena_init — Initialize arena subsystem
; -----------------------------------------------------------------------------
global arena_init
arena_init:
    PROLOGUE_SAVE rbx
    xor     eax, eax
    mov     [arena_list_head], rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; arena_shutdown — Release all arenas
; -----------------------------------------------------------------------------
global arena_shutdown
arena_shutdown:
    PROLOGUE_SAVE rbx
    ; TODO: walk arena list and free each
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; arena_alloc — Allocate size bytes from an arena
; Input:  rdi = arena pointer, rsi = size
; Output: rax = allocated pointer or 0 on failure
; -----------------------------------------------------------------------------
global arena_alloc
arena_alloc:
    PROLOGUE_SAVE rbx
    ; TODO: bump-pointer allocation within arena block
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; arena_create — Create a new arena block
; Input:  rdi = initial size
; Output: rax = arena pointer or 0
; -----------------------------------------------------------------------------
global arena_create
arena_create:
    PROLOGUE_SAVE rbx
    xor     rax, rax
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_CORE_ARENA_ASM