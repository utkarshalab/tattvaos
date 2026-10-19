; =============================================================================
; File     : src/core/logging.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Structured logging — levels, fields, sink output.
; =============================================================================

%ifndef VCS_CORE_LOGGING_ASM
%define VCS_CORE_LOGGING_ASM

%include "include/vcs.inc"

bits 64

section .bss
align 16
log_level:  resd 1      ; current log level threshold

section .text

; -----------------------------------------------------------------------------
; logging_init — Initialize logging subsystem
; -----------------------------------------------------------------------------
global logging_init
logging_init:
    PROLOGUE_SAVE rbx
    mov     dword [log_level], 2   ; default: INFO
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; logging_shutdown — Shutdown logging subsystem
; -----------------------------------------------------------------------------
global logging_shutdown
logging_shutdown:
    PROLOGUE_SAVE rbx
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; log_debug — Emit debug log entry
; Input:  rdi = format string
; -----------------------------------------------------------------------------
global log_debug
log_debug:
    PROLOGUE_SAVE rbx
    cmp     dword [log_level], 0
    jl      .done
    ; TODO: format and emit debug entry
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; log_info — Emit info log entry
; Input:  rdi = format string
; -----------------------------------------------------------------------------
global log_info
log_info:
    PROLOGUE_SAVE rbx
    cmp     dword [log_level], 1
    jl      .done
    ; TODO: format and emit info entry
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; log_warn — Emit warning log entry
; Input:  rdi = format string
; -----------------------------------------------------------------------------
global log_warn
log_warn:
    PROLOGUE_SAVE rbx
    cmp     dword [log_level], 2
    jl      .done
    ; TODO: format and emit warn entry
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; log_error — Emit error log entry
; Input:  rdi = format string
; -----------------------------------------------------------------------------
global log_error
log_error:
    PROLOGUE_SAVE rbx
    cmp     dword [log_level], 3
    jl      .done
    ; TODO: format and emit error entry
    EPILOGUE_RESTORE rbx
    ret

.done:
    EPILOGUE_RESTORE rbx
    ret

%endif ; VCS_CORE_LOGGING_ASM