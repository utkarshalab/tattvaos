; ============================================================================
; Keyboard — Key Processing, Modifiers, Repeat
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Keyboard_size    96
%define MOD_SHIFT      (1 << 0)
%define MOD_CAPS       (1 << 1)
%define MOD_CTRL       (1 << 2)
%define MOD_ALT        (1 << 3)
%define MOD_MOD2       (1 << 4)
%define MOD_MOD3       (1 << 5)
%define MOD_MOD4       (1 << 6)
%define MOD_MOD5       (1 << 7)
%define LED_NUM_LOCK    (1 << 0)
%define LED_CAPS_LOCK   (1 << 1)
%define LED_SCROLL_LOCK (1 << 2)
%define KEY_PRESS       1
%define KEY_RELEASE     0
%define MAX_PRESSED_KEYS  64

section .text

struc Keyboard
    .seat:          resq 1
    .keymap:        resq 1
    .modifiers:     resd 1
    .leds:          resb 1
    .repeat:        resq 1
    .pressed_keys:  resq 1
    .pressed_count: resd 1
    .repeat_key:    resd 1
    .repeat_timer:  resq 1
endstruc





; ---------------------------------------------------------------------------
; keyboard_create
;   Create keyboard for seat
; ---------------------------------------------------------------------------
global keyboard_create
keyboard_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate keyboard
    mov rdi, [rbx + Server.arena]
    mov rsi, Keyboard_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + Keyboard.seat], r12
    mov qword [rbx + Keyboard.keymap], 0
    mov dword [rbx + Keyboard.modifiers], 0
    mov byte [rbx + Keyboard.leds], 0
    mov qword [rbx + Keyboard.repeat], 0
    mov qword [rbx + Keyboard.pressed_keys], 0
    mov dword [rbx + Keyboard.pressed_count], 0
    mov dword [rbx + Keyboard.repeat_key], 0
    mov qword [rbx + Keyboard.repeat_timer], 0

    ; Allocate pressed keys array
    mov rdi, [rdi + Server.arena]
    mov rsi, MAX_PRESSED_KEYS
    shl rsi, 2
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Keyboard.pressed_keys], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; keyboard_set_keymap
; ---------------------------------------------------------------------------
global keyboard_set_keymap
keyboard_set_keymap:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov qword [rdi + Keyboard.keymap], rsi
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; keyboard_process_key
;   Process key event
;   IN:  rdi = keyboard*, rsi = keycode, rdx = state (press/release)
; ---------------------------------------------------------------------------
global keyboard_process_key
keyboard_process_key:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    ; Lookup keysym from keymap
    mov r13, [rbx + Keyboard.keymap]
    test r13, r13
    jz .no_keymap

    ; Get keysym for keycode and modifiers
    mov rdi, r13
    mov rsi, r12d
    mov rdx, [rbx + Keyboard.modifiers]
    call keymap_lookup_keysym
    test rax, rax
    jz .no_keysym
    mov r14, rax

    ; Update modifier state
    call keyboard_update_modifiers

    ; Add/remove from pressed keys
    test r12d, r12d
    jz .release

    ; Press
    call keyboard_key_press
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.release:
    ; Release
    call keyboard_key_release
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.no_keymap:
.no_keysym:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; keyboard_update_modifiers
; ---------------------------------------------------------------------------
keyboard_update_modifiers:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rbx + Keyboard.keymap]
    test r12, r12
    jz .done

    ; Check each modifier key in pressed_keys
    mov dword [rbx + Keyboard.modifiers], 0
    mov r13, [rbx + Keyboard.pressed_keys]
    mov ecx, [rbx + Keyboard.pressed_count]
    test ecx, ecx
    jz .done

.mod_loop:
    test ecx, ecx
    jz .done
    movzx r13d, word [r13]
    ; Check if this keycode is a modifier
    mov rdi, r12
    mov rsi, r13d
    call keymap_is_modifier
    test rax, rax
    jz .not_mod
    or dword [rbx + Keyboard.modifiers], eax

.not_mod:
    add r13, 2
    dec ecx
    jmp .mod_loop

.done:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; keyboard_key_press
; ---------------------------------------------------------------------------
keyboard_key_press:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi

    ; Add to pressed keys
    mov r13, [rbx + Keyboard.pressed_keys]
    mov ecx, [rbx + Keyboard.pressed_count]
    cmp ecx, MAX_PRESSED_KEYS
    jae .full

    mov [r13 + ecx * 2], r12w
    inc dword [rbx + Keyboard.pressed_count]

    ; Start repeat timer
    call keyboard_start_repeat

.full:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; keyboard_key_release
; ---------------------------------------------------------------------------
keyboard_key_release:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi

    ; Remove from pressed keys
    mov r13, [rbx + Keyboard.pressed_keys]
    mov ecx, [rbx + Keyboard.pressed_count]
    test ecx, ecx
    jz .done

.rem_loop:
    test ecx, ecx
    jz .done
    cmp word [r13], r12w
    jne .next
    ; Found - remove by shifting
    dec ecx
    mov r14, r13
    add r14, 2
    mov rdi, r13
    mov rsi, r14
    mov rdx, ecx
    shl rdx, 1
    call memcopy
    dec dword [rbx + Keyboard.pressed_count]
    jmp .done

.next:
    add r13, 2
    dec ecx
    jmp .rem_loop

.done:
    ; Stop repeat if this was the repeat key
    cmp dword [rbx + Keyboard.repeat_key], r12d
    jne .done
    call keyboard_stop_repeat

    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; keyboard_start_repeat
; ---------------------------------------------------------------------------
keyboard_start_repeat:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi

    mov dword [rbx + Keyboard.repeat_key], r12d

    ; Register timer: initial delay 250ms, then 33ms (30Hz)
    mov rdi, 250000000  ; 250ms
    mov rsi, keyboard_repeat_callback
    mov rdx, rbx
    call tv_timer_register
    test rax, rax
    jnz .fail
    mov [rbx + Keyboard.repeat_timer], rax

.fail:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; keyboard_stop_repeat
; ---------------------------------------------------------------------------
keyboard_stop_repeat:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Keyboard.repeat_timer]
    test rax, rax
    jz .done
    mov rdi, rax
    call tv_timer_cancel
    mov qword [rdi + Keyboard.repeat_timer], 0
    mov dword [rdi + Keyboard.repeat_key], 0
.done:
    leave
    ret

; ---------------------------------------------------------------------------
; keyboard_repeat_callback
; ---------------------------------------------------------------------------
keyboard_repeat_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12d, [rbx + Keyboard.repeat_key]
    test r12d, r12d
    jz .done

    ; Generate repeat event
    mov rdi, [rbx + Keyboard.seat]
    mov rsi, INPUT_EVENT_KEY
    mov rdx, r12d
    mov rcx, KEY_PRESS
    call seat_deliver_event

    ; Re-arm timer for repeat rate (33ms = 30Hz)
    mov rdi, 33000000  ; 33ms
    mov rsi, keyboard_repeat_callback
    mov rdx, rbx
    call tv_timer_register
    test rax, rax
    jnz .fail
    mov [rbx + Keyboard.repeat_timer], rax

.fail:
.done:
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; keyboard_set_leds
; ---------------------------------------------------------------------------
global keyboard_set_leds
keyboard_set_leds:
    PROLOGUE
    ASSERT_PTR rdi
    mov byte [rdi + Keyboard.leds], dl
    ; TODO: Send to hardware
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; keyboard_get_modifiers
; ---------------------------------------------------------------------------
global keyboard_get_modifiers
keyboard_get_modifiers:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Keyboard.modifiers]
    leave
    ret

section .data
global keyboard_version
keyboard_version: dq 0x010000
