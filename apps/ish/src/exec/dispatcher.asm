; =============================================================================
; File     : apps/ish/src/exec/dispatcher.asm
; Project  : Utkarsha OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Command lookup and dispatch.
; =============================================================================

%ifndef ISH_DISPATCHER_ASM
%define ISH_DISPATCHER_ASM

%include "inc/ish.inc"
%include "inc/cmd_registry.inc"
%include "inc/executor.inc"
%include "inc/frontend.inc"

bits 64

section .bss
align 16
cmd_registry_root:  resq 1

section .text

; -----------------------------------------------------------------------------
; exec_register_command — Register a command in the registry
; Input:  rdi = ptr to cmd_entry_t (fully initialized)
; Output: none
; -----------------------------------------------------------------------------
global exec_register_command
exec_register_command:
    PROLOGUE_SAVE rbx, rcx, rdx

    mov     rbx, rdi                      ; rbx = new entry
    mov     rcx, [cmd_registry_root]
    test    rcx, rcx
    jz      .first_entry

.find_end:
    mov     rdx, [rcx + cmd_entry_t.next]
    test    rdx, rdx
    jz      .append
    mov     rcx, rdx
    jmp .find_end

.append:
    mov     [rcx + cmd_entry_t.next], rbx
    mov     qword [rbx + cmd_entry_t.next], 0
    jmp .done

.first_entry:
    mov     [cmd_registry_root], rbx
    mov     qword [rbx + cmd_entry_t.next], 0

.done:
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

; -----------------------------------------------------------------------------
; exec_lookup — Find command by name (linear scan)
; Input:  rdi = command name string
; Output: rax = ptr to cmd_entry_t or 0 if not found
; -----------------------------------------------------------------------------
global exec_lookup
exec_lookup:
    PROLOGUE_SAVE rbx

    mov     rbx, [cmd_registry_root]
    test    rbx, rbx
    jz      .not_found

.search:
    mov     rsi, [rbx + cmd_entry_t.name]
    call    str_cmp                       ; rdi = name1, rsi = name2
    test    rax, rax
    jz      .found
    mov     rbx, [rbx + cmd_entry_t.next]
    test    rbx, rbx
    jnz     .search

.not_found:
    xor     rax, rax
    jmp .done

.found:
    mov     rax, rbx

.done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; exec_dispatch — Dispatch command from argc/argv
; Input:  rdi = argc (u32), rsi = argv (char **)
; Output: rax = exit code
; -----------------------------------------------------------------------------
global exec_dispatch
exec_dispatch:
    PROLOGUE_SAVE rbx, rcx, rdx

    test    rdi, rdi
    jz      .no_args
    mov     rbx, [rsi]                    ; rbx = argv[0]
    test    rbx, rbx
    jz      .no_args

    ; Lookup command in registry
    call    exec_lookup
    test    rax, rax
    jz      .not_found

    ; Check if builtin
    mov     ecx, [rax + cmd_entry_t.flags]
    test    ecx, CMD_FLAG_BUILTIN
    jnz     .is_builtin

    ; External command
    call    exec_external
    jmp .done

.is_builtin:
    ; Call builtin handler
    mov     rdx, [rax + cmd_entry_t.handler]
    test    rdx, rdx
    jz      .handler_missing
    ; rdi = argc, rsi = argv already set
    call    rdx
    jmp .done

.not_found:
    mov     rdi, msg_cmd_not_found
    call    frontend_write_str
    mov     eax, ISH_EXIT_CMD_NOT_FOUND
    jmp .done

.handler_missing:
    mov     rax, CMD_GENERAL_ERROR

.no_args:
    xor     rax, rax

.done:
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

; -----------------------------------------------------------------------------
; exec_external — Load and run external app binary as a fiber
; Input:  rdi = argc, rsi = argv
; Output: rax = exit code from child fiber
; -----------------------------------------------------------------------------
global exec_external
exec_external:
    PROLOGUE_SAVE rbx

    ; argv[0] is the command name = app path
    mov     rbx, [rsi]
    call    frontend_write_str
    mov     rdi, msg_not_implemented
    call    frontend_write_str
    mov     eax, ISH_EXIT_FAILURE

    EPILOGUE_RESTORE rbx
    ret

section .rodata
align 16
msg_cmd_not_found:      db "ish: command not found", 0x0A, 0
msg_not_implemented:    db " (external commands not yet implemented)", 0x0A, 0

%endif ; ISH_DISPATCHER_ASM