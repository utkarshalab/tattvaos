; =============================================================================
; File     : apps/ish/inc/ish.inc
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Core shell context, constants, and return codes.
; =============================================================================

%ifndef ISH_INC
%define ISH_INC

; -----------------------------------------------------------------------------
; Shell Return Codes (UNIX standard)
; -----------------------------------------------------------------------------
ISH_EXIT_SUCCESS          equ 0
ISH_EXIT_FAILURE          equ 1
ISH_EXIT_CMD_NOT_FOUND    equ 127
ISH_EXIT_INVALID_ARGS     equ 128
ISH_EXIT_EXIT_BUILTIN     equ 250
ISH_EXIT_EOF              equ 255

; -----------------------------------------------------------------------------
; Shell Flags
; -----------------------------------------------------------------------------
ISH_FLAG_INTERACTIVE      equ (1 << 0)   ; Interactive mode (prompt, history)
ISH_FLAG_LOGIN            equ (1 << 1)   ; Login shell (reads /etc/ishrc, ~/.ishrc)
ISH_FLAG_RESTRICTED       equ (1 << 2)   ; Restricted shell (no cd, no exec external)
ISH_FLAG_NOEXEC           equ (1 << 3)   ; Syntax check only
ISH_FLAG_VERBOSE          equ (1 << 4)   ; Verbose execution trace
ISH_FLAG_NOGLOB           equ (1 << 5)   ; Disable pathname expansion
ISH_FLAG_NOEXPAND         equ (1 << 6)   ; Disable variable/alias expansion

; -----------------------------------------------------------------------------
; Line Editing Limits
; -----------------------------------------------------------------------------
ISH_MAX_LINE_LEN          equ 4096
ISH_MAX_ARGS              equ 256
ISH_MAX_HISTORY           equ 1024
ISH_MAX_ALIASES           equ 128
ISH_MAX_ENV_VARS          equ 4096
ISH_PROMPT_MAX_LEN        equ 256

; -----------------------------------------------------------------------------
; Shell Context Structure (ISH_CTX_SIZE = 256 bytes)
; -----------------------------------------------------------------------------
struc ish_ctx_t
    .magic                resd 1      ; 0x49534821 ("ISH!")
    .version              resd 1      ; Shell version
    .flags                resd 1      ; ISH_FLAG_*
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

ISH_CTX_SIZE              equ 256

; -----------------------------------------------------------------------------
; Command Exit Codes (standard UNIX)
; -----------------------------------------------------------------------------
CMD_SUCCESS               equ 0
CMD_GENERAL_ERROR         equ 1
CMD_MISUSE_SHELL_BUILTIN  equ 2
CMD_CMD_NOT_FOUND         equ 127
CMD_INVALID_EXIT_ARG      equ 128
CMD_SIGNAL_BASE           equ 128

%endif ; ISH_INC