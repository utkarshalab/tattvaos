; =============================================================================
; File     : apps/ish/inc/cmd_registry.inc
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Command registration table and standard ABI.
; =============================================================================

%ifndef CMD_REGISTRY_INC
%define CMD_REGISTRY_INC

%include "inc/ish.inc"

; -----------------------------------------------------------------------------
; Command Flags
; -----------------------------------------------------------------------------
CMD_FLAG_BUILTIN          equ (1 << 0)   ; Shell builtin (runs in shell fiber)
CMD_FLAG_EXTERNAL         equ (1 << 1)   ; External app (loaded as fiber)
CMD_FLAG_HIDDEN           equ (1 << 2)   ; Don't show in `help`
CMD_FLAG_NOEXPAND         equ (1 << 3)   ; Don't expand args
CMD_FLAG_ROOT_ONLY        equ (1 << 4)   ; Requires admin privileges
CMD_FLAG_DANGEROUS        equ (1 << 5)   ; Requires confirmation (rm -rf, reboot)

; -----------------------------------------------------------------------------
; Command Registry Entry
; -----------------------------------------------------------------------------
struc cmd_entry_t
    .magic                resd 1      ; 0x434D4401 ("CMD\x01")
    .name                 resq 1      ; command string ("ls", "cat")
    .handler              resq 1      ; fn(argc, argv) -> exit_code
    .help                 resq 1      ; help description string
    .usage                resq 1      ; usage string
    .man                  resq 1      ; manual page pointer (optional)
    .flags                resd 1      ; CMD_FLAG_*
    .min_args             resd 1
    .max_args             resd 1
    .category             resq 1      ; "fs", "system", "net", "ai", "obs", "sec"
    .next                 resq 1      ; linked list pointer
endstruc

CMD_ENTRY_SIZE            equ 128

; -----------------------------------------------------------------------------
; Standard Command Signature
;   args:  rdi = argc (u32), rsi = argv (char **)
;   out:   rax = exit code
; -----------------------------------------------------------------------------
%define CMD_FUNC(name) \
global name; \
name:

; -----------------------------------------------------------------------------
; Registry API (declared here, defined in src/exec/dispatcher.asm)
;   exec_register_command(rdi = ptr to cmd_entry_t)
;   exec_lookup(rdi = name) -> rax = ptr to cmd_entry_t or 0
;   exec_init() -> void
; -----------------------------------------------------------------------------

%endif ; CMD_REGISTRY_INC