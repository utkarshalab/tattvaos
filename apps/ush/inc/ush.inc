; =============================================================================
; File     : apps/ush/inc/ush.inc
; Project  : Utkarsha OS — Utkarsha Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Core shell context, constants, and return codes.
; =============================================================================

%ifndef USH_INC
%define USH_INC

; -----------------------------------------------------------------------------
; Shell Return Codes (UNIX standard)
; -----------------------------------------------------------------------------
USH_EXIT_SUCCESS          equ 0
USH_EXIT_FAILURE          equ 1
USH_EXIT_CMD_NOT_FOUND    equ 127
USH_EXIT_INVALID_ARGS     equ 128
USH_EXIT_EXIT_BUILTIN     equ 250
USH_EXIT_EOF              equ 255

; -----------------------------------------------------------------------------
; Shell Flags
; -----------------------------------------------------------------------------
USH_FLAG_INTERACTIVE      equ (1 << 0)   ; Interactive mode (prompt, history)
USH_FLAG_LOGIN            equ (1 << 1)   ; Login shell (reads /etc/ushrc, ~/.ushrc)
USH_FLAG_RESTRICTED       equ (1 << 2)   ; Restricted shell (no cd, no exec external)
USH_FLAG_NOEXEC           equ (1 << 3)   ; Syntax check only
USH_FLAG_VERBOSE          equ (1 << 4)   ; Verbose execution trace
USH_FLAG_NOGLOB           equ (1 << 5)   ; Disable pathname expansion
USH_FLAG_NOEXPAND         equ (1 << 6)   ; Disable variable/alias expansion

; -----------------------------------------------------------------------------
; Line Editing Limits
; -----------------------------------------------------------------------------
USH_MAX_LINE_LEN          equ 4096
USH_MAX_ARGS              equ 256
USH_MAX_HISTORY           equ 32
USH_MAX_ALIASES           equ 128
USH_MAX_ENV_VARS          equ 32
USH_PROMPT_MAX_LEN        equ 256

; -----------------------------------------------------------------------------
; Shell Context Structure (USH_CTX_SIZE = 256 bytes)
; -----------------------------------------------------------------------------
struc ush_ctx_t
    .magic                resd 1      ; 0x55534821 ("USH!")
    .version              resd 1      ; Shell version
    .flags                resd 1      ; USH_FLAG_*
    .frontend             resq 1      ; ptr to io_frontend_t
    .prompt               resq 1      ; current prompt string
    .prompt_len           resd 1
    .env                  resq 1      ; ptr to env block (env_var_t *)
    .aliases              resq 1      ; ptr to alias table
    .cmd_registry         resq 1      ; ptr to command registry root
    .history              resq 1      ; ptr to history ring
    .job_table            resq 1      ; ptr to job table
    .current_dir          resq 1      ; current working directory path
    .home_dir             resq 1      ; HOME path
    .exit_code            resd 1      ; last command exit code
    .last_pid             resd 1      ; last background PID
    .line_no              resd 1      ; current input line number
    .running              resd 1      ; main loop flag
    .interrupt_pending    resd 1      ; SIGINT received
    .pad                  resd 1
endstruc

USH_CTX_SIZE              equ 256

; -----------------------------------------------------------------------------
; Command Exit Codes (standard UNIX)
; -----------------------------------------------------------------------------
CMD_SUCCESS               equ 0
CMD_GENERAL_ERROR         equ 1
CMD_MISUSE_SHELL_BUILTIN  equ 2
CMD_CMD_NOT_FOUND         equ 127
CMD_INVALID_EXIT_ARG      equ 128
CMD_SIGNAL_BASE           equ 128

%endif ; USH_INC
