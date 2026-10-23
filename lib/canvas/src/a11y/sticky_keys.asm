; ============================================================================
; Sticky Keys — Accessibility Feature for Modifier Keys
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/server_offsets.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define MOD_SHIFT      (1 << 0)
%define MOD_CTRL       (1 << 1)
%define MOD_ALT        (1 << 2)
%define MOD_MOD4       (1 << 3)

section .text

struc StickyKeys
    .enabled:           resb 1
    .lock_modifiers:    resb 1
    .two_keys_off:      resb 1
    .sound_on_press:    resb 1
    .sound_on_release:  resb 1
    .pressed_modifiers: resd 1
    .locked_modifiers:  resd 1
    .press_count:       resd 1
    .last_key_time:     resq 1
endstruc


global sticky_keys_init
sticky_keys_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, StickyKeys_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov byte [rbx + StickyKeys.enabled], 0
    mov byte [rbx + StickyKeys.lock_modifiers], 1
    mov byte [rbx + StickyKeys.two_keys_off], 1
    mov byte [rbx + StickyKeys.sound_on_press], 1
    mov byte [rbx + StickyKeys.sound_on_release], 1
    mov dword [rbx + StickyKeys.pressed_modifiers], 0
    mov dword [rbx + StickyKeys.locked_modifiers], 0
    mov dword [rbx + StickyKeys.press_count], 0
    mov qword [rbx + StickyKeys.last_key_time], 0

    mov qword [rdi + Server.sticky_keys], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

global sticky_keys_enable
sticky_keys_enable:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov byte [rbx + StickyKeys.enabled], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

global sticky_keys_disable
sticky_keys_disable:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov byte [rbx + StickyKeys.enabled], 0
    mov dword [rbx + StickyKeys.pressed_modifiers], 0
    mov dword [rbx + StickyKeys.locked_modifiers], 0
    mov dword [rbx + StickyKeys.press_count], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

global sticky_keys_process_key
sticky_keys_process_key:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    cmp byte [rbx + StickyKeys.enabled], 0
    je .disabled

    call sticky_keys_is_modifier
    test rax, rax
    jz .not_modifier

    test r13d, r13d
    jz .key_release

    mov eax, [rbx + StickyKeys.pressed_modifiers]
    or eax, r12d
    mov [rbx + StickyKeys.pressed_modifiers], eax

    inc dword [rbx + StickyKeys.press_count]

    cmp byte [rbx + StickyKeys.two_keys_off], 0
    je .check_lock
    cmp dword [rbx + StickyKeys.press_count], 2
    jl .check_lock
    call sticky_keys_disable
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.check_lock:
    call ut_time_now_ns
    mov r12, rax
    sub r12, [rbx + StickyKeys.last_key_time]
    cmp r12, 500000000
    ja .update_time

    mov eax, [rbx + StickyKeys.locked_modifiers]
    or eax, r12d
    mov [rbx + StickyKeys.locked_modifiers], eax

    cmp byte [rbx + StickyKeys.sound_on_press], 0
    je .update_time

.update_time:
    mov [rbx + StickyKeys.last_key_time], rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.key_release:
    mov eax, [rbx + StickyKeys.locked_modifiers]
    test eax, r12d
    jz .not_locked

    mov r13d, r12d
    not r13d
    and eax, r13d
    mov [rbx + StickyKeys.locked_modifiers], eax

    cmp byte [rbx + StickyKeys.sound_on_release], 0
    je .ret
.ret:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.not_locked:
    mov eax, [rbx + StickyKeys.pressed_modifiers]
    mov r13d, r12d
    not r13d
    and eax, r13d
    mov [rbx + StickyKeys.pressed_modifiers], eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.disabled:
.not_modifier:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

sticky_keys_is_modifier:
    PROLOGUE
    cmp rdi, 42
    je .is_mod
    cmp rdi, 54
    je .is_mod
    cmp rdi, 29
    je .is_mod
    cmp rdi, 97
    je .is_mod
    cmp rdi, 56
    je .is_mod
    cmp rdi, 100
    je .is_mod
    cmp rdi, 125
    je .is_mod
    cmp rdi, 126
    je .is_mod
    xor rax, rax
    leave
    ret
.is_mod:
    mov rax, 1
    leave
    ret

global sticky_keys_get_modifiers
sticky_keys_get_modifiers:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov eax, [rbx + StickyKeys.pressed_modifiers]
    mov edx, [rbx + StickyKeys.locked_modifiers]
    or eax, edx
    EPILOGUE_RESTORE rbx
    ret

global sticky_keys_set_option
sticky_keys_set_option:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp rsi, 0
    je .set_lock
    cmp rsi, 1
    je .set_two_keys
    cmp rsi, 2
    je .set_sound_press
    cmp rsi, 3
    je .set_sound_release
    jmp .invalid

.set_lock:
    mov byte [rbx + StickyKeys.lock_modifiers], dl
    EPILOGUE_RESTORE rbx
    ret
.set_two_keys:
    mov byte [rbx + StickyKeys.two_keys_off], dl
    EPILOGUE_RESTORE rbx
    ret
.set_sound_press:
    mov byte [rbx + StickyKeys.sound_on_press], dl
    EPILOGUE_RESTORE rbx
    ret
.set_sound_release:
    mov byte [rbx + StickyKeys.sound_on_release], dl
    EPILOGUE_RESTORE rbx
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx
    ret

section .data
global sticky_keys_version
sticky_keys_version: dq 0x010000
