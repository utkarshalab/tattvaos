; =============================================================================
; File     : apps/ish/src/env/environment.asm
; Project  : Tattva OS — Ishana Shell
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: Environment variable store.
; =============================================================================

%ifndef ISH_ENVIRONMENT_ASM
%define ISH_ENVIRONMENT_ASM

%include "inc/env.inc"
%include "lib/str/str.asm"

bits 64

section .bss
align 16
env_head:       resq 1
env_count:      resq 1

section .text

; -----------------------------------------------------------------------------
; env_init — Initialize environment with defaults
; -----------------------------------------------------------------------------
global env_init
env_init:
    PROLOGUE_SAVE rbx

    xor     eax, eax
    mov     [env_head], eax
    mov     [env_count], eax

    ; Set default PATH
    mov     rdi, .path_key
    mov     rsi, .path_val
    call    env_set_var

    ; Set default HOME
    mov     rdi, .home_key
    mov     rsi, .home_val
    call    env_set_var

    ; Set default USER
    mov     rdi, .user_key
    mov     rsi, .user_val
    call    env_set_var

    EPILOGUE_RESTORE rbx
    ret

section .data
align 16
.path_key:   db "PATH", 0
.path_val:   db "/bin:/usr/bin", 0
.home_key:   db "HOME", 0
.home_val:   db "/root", 0
.user_key:   db "USER", 0
.user_val:   db "root", 0

section .text

; -----------------------------------------------------------------------------
; env_set_var — Set or create an environment variable
; Input:  rdi = key, rsi = value
; Output: rax = 0 on success
; -----------------------------------------------------------------------------
global env_set_var
env_set_var:
    PROLOGUE_SAVE rbx, rcx

    ; Search for existing variable
    mov     rbx, [env_head]
    test    rbx, rbx
    jz      .env_create

.env_search:
    mov     rdi, [rbx + env_var_t.key]
    mov     rsi, rdi                      ; compare key
    call    str_cmp
    test    rax, rax
    jz      .env_found
    mov     rbx, [rbx + env_var_t.next]
    test    rbx, rbx
    jnz     .env_search

.env_create:
    ; Create new env_var_t (simplified: just store pointer)
    mov     rax, [env_count]
    inc     rax
    mov     [env_count], rax
    ; For now, just store key/value in a simple linked list
    ; Full implementation would allocate from arena
    jmp .env_done

.env_found:
    ; Update existing value (simplified)
.env_done:
    xor     rax, rax
    EPILOGUE_RESTORE rbx, rcx
    ret

; -----------------------------------------------------------------------------
; env_get_var — Get environment variable value
; Input:  rdi = key name
; Output: rax = value string or 0 if not found
; -----------------------------------------------------------------------------
global env_get_var
env_get_var:
    PROLOGUE_SAVE rbx

    mov     rbx, [env_head]
    test    rbx, rbx
    jz      .env_not_found

.env_get_search:
    mov     rsi, [rbx + env_var_t.key]
    call    str_cmp                       ; rdi = key1, rsi = key2
    test    rax, rax
    jz      .env_get_found
    mov     rbx, [rbx + env_var_t.next]
    test    rbx, rbx
    jnz     .env_get_search

.env_not_found:
    xor     rax, rax
    jmp .env_get_done

.env_get_found:
    mov     rax, [rbx + env_var_t.value]

.env_get_done:
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; env_get_home — Get HOME directory
; Output: rax = HOME path or 0
; -----------------------------------------------------------------------------
global env_get_home
env_get_home:
    mov     rdi, .home_key
    call    env_get_var
    ret

section .data
align 16
.home_key:   db "HOME", 0

section .text

; -----------------------------------------------------------------------------
; env_update_pwd — Update PWD and OLDPWD
; -----------------------------------------------------------------------------
global env_update_pwd
env_update_pwd:
    PROLOGUE_SAVE rbx

    ; Save current PWD to OLDPWD
    mov     rdi, .pwd_key
    call    env_get_var
    test    rax, rax
    jz      .pwd_update_done
    mov     rdi, .oldpwd_key
    mov     rsi, rax
    call    env_set_var

    ; Get current dir from shell context (simplified)
    mov     rdi, .pwd_key
    mov     rsi, .root_path
    call    env_set_var

.pwd_update_done:
    EPILOGUE_RESTORE rbx
    ret

section .data
align 16
.pwd_key:     db "PWD", 0
.oldpwd_key:  db "OLDPWD", 0
.root_path:   db "/", 0

section .text

; -----------------------------------------------------------------------------
; env_dump_all — Print all environment variables
; -----------------------------------------------------------------------------
global env_dump_all
env_dump_all:
    PROLOGUE_SAVE rbx

    mov     rbx, [env_head]
    test    rbx, rbx
    jz      .env_dump_done

.env_dump_loop:
    mov     rdi, [rbx + env_var_t.key]
    call    frontend_write_str
    mov     al, '='
    call    frontend_write_char
    mov     rdi, [rbx + env_var_t.value]
    call    frontend_write_str
    mov     al, 0x0A
    call    frontend_write_char
    mov     rbx, [rbx + env_var_t.next]
    test    rbx, rbx
    jnz     .env_dump_loop

.env_dump_done:
    EPILOGUE_RESTORE rbx
    ret

%endif ; ISH_ENVIRONMENT_ASM