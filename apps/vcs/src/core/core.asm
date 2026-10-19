; =============================================================================
; File     : src/core/core.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Core VCS initialization and shutdown.
; =============================================================================

%ifndef VCS_CORE_ASM
%define VCS_CORE_ASM

%include "include/vcs.inc"

bits 64

section .bss
align 16
vcs_initialized:  resb 1      ; 1 = core initialized
vcs_arena_root:   resq 1      ; pointer to root arena

section .text

; -----------------------------------------------------------------------------
; vcs_core_init — Initialize core subsystems (arenas, error strings, logging)
; Input:  none
; Output: rax = VCS_OK on success
; -----------------------------------------------------------------------------
global vcs_core_init
vcs_core_init:
    PROLOGUE_SAVE rbx

    cmp     byte [vcs_initialized], 1
    je      .already_initialized

    ; Initialize arena subsystem
    call    arena_init

    ; Initialize error string table
    call    errors_init

    ; Initialize logging
    call    logging_init

    mov     byte [vcs_initialized], 1

.already_initialized:
    mov     eax, VCS_OK
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; vcs_core_shutdown — Clean shutdown of core subsystems
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global vcs_core_shutdown
vcs_core_shutdown:
    PROLOGUE_SAVE rbx

    cmp     byte [vcs_initialized], 0
    je      .not_initialized

    call    logging_shutdown
    call    errors_shutdown
    call    arena_shutdown

    mov     byte [vcs_initialized], 0

.not_initialized:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; vcs_core_is_initialized — Check if core is initialized
; Output: rax = 1 if initialized, 0 otherwise
; -----------------------------------------------------------------------------
global vcs_core_is_initialized
vcs_core_is_initialized:
    movzx   eax, byte [vcs_initialized]
    ret

%endif ; VCS_CORE_ASM