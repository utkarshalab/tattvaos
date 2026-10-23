; ============================================================================
; Keyboard Input Handling — Keys, Modifiers, Repeat, Keymap
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/input.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern keymap_create_default
extern keymap_destroy
extern keymap_is_modifier
extern surface_keyboard_key
extern ut_time_now_ns
extern ut_timer_register
extern ut_timer_cancel

%define Keyboard_KEYMAP Keyboard.keymap
%define Keyboard_MODIFIERS Keyboard.modifiers
%define Keyboard_LEDS Keyboard.leds
%define Keyboard_REPEAT Keyboard.repeat
%define Keyboard_PRESSED_KEYS Keyboard.pressed_keys
%define Keyboard_PRESSED_COUNT Keyboard.pressed_count
%define Keyboard_REPEAT_KEY Keyboard.repeat_key
%define Keyboard_REPEAT_TIMER Keyboard.repeat_timer
%define Keyboard_REPEAT_RATE Keyboard.repeat_rate
%define Keyboard_REPEAT_DELAY Keyboard.repeat_delay

section .text

; ============================================================================
; keyboard_create
;   Create keyboard device
; ============================================================================
global keyboard_create
keyboard_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi       ; seat
    mov r13, rdx       ; name
    mov r14d, ecx      ; capabilities
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + InputDevice_TYPE], INPUT_TYPE_KEYBOARD
    mov qword [rbx + InputDevice_NAME], r13
    mov qword [rbx + InputDevice_SEAT], r12
    mov dword [rbx + InputDevice_CAPS], r14d
    mov qword [rbx + InputDevice_NEXT], 0

    ; Initialize keyboard state
    mov qword [rbx + Keyboard_KEYMAP], 0
    mov dword [rbx + Keyboard_MODIFIERS], 0
    mov dword [rbx + Keyboard_LEDS], 0
    mov qword [rbx + Keyboard_REPEAT], 0
    mov qword [rbx + Keyboard_PRESSED_KEYS], 0
    mov dword [rbx + Keyboard_PRESSED_COUNT], 0
    mov qword [rbx + Keyboard_REPEAT_KEY], 0
    mov qword [rbx + Keyboard_REPEAT_TIMER], 0

    mov rdi, [r12 + Seat.arena]
    mov rsi, 64 * 4
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Keyboard_PRESSED_KEYS], rax

    ; Add to seat's device list
    mov rax, [r12 + SEAT_DEVICES]
    mov [rbx + InputDevice_NEXT], rax
    mov [r12 + SEAT_DEVICES], rbx

    ; If keyboard capability, set as seat keyboard
    test r14d, DEVICE_CAP_KEYBOARD
    jz .done
    mov [r12 + SEAT_KEYBOARD], rbx

    ; Create default keymap
    call keymap_create_default
    mov [rbx + Keyboard_KEYMAP], rax

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ============================================================================
; keyboard_destroy
;   Destroy keyboard device
; ============================================================================
global keyboard_destroy
keyboard_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Remove from seat's device list
    mov r12, [rbx + InputDevice_SEAT]
    call keyboard_unlink_from_seat

    ; Release focus
    mov rax, [rbx + Keyboard_KEYMAP]
    test rax, rax
    jz .done
    mov rdi, rax
    call keymap_destroy

    ; Cancel repeat timer
    mov rax, [rbx + Keyboard_REPEAT_TIMER]
    test rax, rax
    jz .done
    mov rdi, rax
    call timer_destroy

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12

keyboard_unlink_from_seat:
    mov r12, [rbx + InputDevice_SEAT]
    mov rax, [r12 + SEAT_DEVICES]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + InputDevice_NEXT]
    mov [r12 + SEAT_DEVICES], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + InputDevice_NEXT]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + InputDevice_NEXT]
    mov [r12 + InputDevice_NEXT], rax

.done:
    ret

; ============================================================================
; keyboard_key
;   Handle key press/release
; ============================================================================
global keyboard_key
keyboard_key:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi      ; keycode
    mov r13d, edx      ; state (pressed/released)
    mov r14d, ecx      ; time
    mov r15d, r8d      ; serial
    ASSERT_PTR rbx

    ; Update pressed keys array
    test r13d, r13d
    jz .released

.pressed:
    ; Check if already pressed
    mov rdi, rbx
    mov esi, r12d
    call keyboard_is_key_pressed
    test rax, rax
    jnz .done

    ; Add to pressed keys
    mov rdi, rbx
    mov esi, r12d
    call keyboard_add_pressed_key

    ; Update modifiers
    mov rdi, rbx
    call keyboard_update_modifiers

    ; Set repeat key
    mov [rbx + Keyboard_REPEAT_KEY], r12d
    mov rdi, rbx
    call timer_start

    jmp .send_event

.released:
    mov rdi, rbx
    mov esi, r12d
    call keyboard_remove_pressed_key
    mov rdi, rbx
    call keyboard_update_modifiers

    ; Clear repeat key
    cmp dword [rbx + Keyboard_REPEAT_KEY], r12d
    jne .send_event
    mov qword [rbx + Keyboard_REPEAT_KEY], 0
    mov qword [rbx + Keyboard_REPEAT_TIMER], 0

.send_event:
    ; Send key event to focus
    mov rax, [rbx + InputDevice_SEAT]
    mov rax, [rax + SEAT_KEYBOARD_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r15d
    call surface_keyboard_key

    ; Update modifiers state
    mov rdi, rbx
    call keyboard_update_leds

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ============================================================================
; .is_key_pressed - Check if key is already pressed
; ============================================================================
keyboard_is_key_pressed:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi

    mov rax, [rbx + Keyboard_PRESSED_KEYS]
    mov rcx, [rbx + Keyboard_PRESSED_COUNT]
    test rcx, rcx
    jz .not_found

.loop:
    cmp dword [rax], r12d
    je .found
    add rax, 4
    dec rcx
    jnz .loop

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.found:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; .add_pressed_key - Add key to pressed keys array
; ============================================================================
keyboard_add_pressed_key:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi

    mov eax, [rbx + Keyboard_PRESSED_COUNT]
    cmp eax, 64
    jge .full

    mov rax, [rbx + Keyboard_PRESSED_KEYS]
    mov ecx, [rbx + Keyboard_PRESSED_COUNT]
    mov [rax + rcx * 4], r12d
    inc dword [rbx + Keyboard_PRESSED_COUNT]

.full:
    EPILOGUE_RESTORE rbx, r12

; ============================================================================
; .remove_pressed_key - Remove key from pressed keys array
; ============================================================================
keyboard_remove_pressed_key:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi

    mov rax, [rbx + Keyboard_PRESSED_KEYS]
    mov rcx, [rbx + Keyboard_PRESSED_COUNT]
    test rcx, rcx
    jz .done

.loop:
    cmp dword [rax], r12d
    je .found
    add rax, 4
    dec rcx
    jnz .loop

    ; Not found
    jmp .done

.found:
    mov r12, rax
    mov r13, [rbx + Keyboard_PRESSED_KEYS]
    sub rax, r13
    shr rax, 2
    mov ecx, [rbx + Keyboard_PRESSED_COUNT]
    dec ecx
    sub ecx, eax
    jz .shift_done
    add r12, 4

.shift_loop:
    mov r13d, [r12]
    mov [r12 - 4], r13d
    add r12, 4
    dec rcx
    jnz .shift_loop

.shift_done:
    dec dword [rbx + Keyboard_PRESSED_COUNT]

.done:
    EPILOGUE_RESTORE rbx, r12, r13

; ============================================================================
; .update_modifiers - Update modifier state
; ============================================================================
keyboard_update_modifiers:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi

    xor r15d, r15d

    ; Check pressed keys for modifiers
    mov r13, [rbx + Keyboard_PRESSED_KEYS]
    mov r14d, [rbx + Keyboard_PRESSED_COUNT]
    test r14d, r14d
    jz .mods_done

.mod_loop:
    mov rdi, [rbx + Keyboard_KEYMAP]
    test rdi, rdi
    jz .next_key
    mov esi, [r13]
    call keymap_is_modifier
    or r15d, eax

.next_key:
    add r13, 4
    dec r14d
    jnz .mod_loop

.mods_done:
    mov [rbx + Keyboard_MODIFIERS], r15d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; .update_leds - Update keyboard LEDs
; ============================================================================
keyboard_update_leds:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, [rbx + Keyboard_MODIFIERS]

    ; Update LED state based on modifiers
    mov r12d, 0
    test dword [rbx + Keyboard_MODIFIERS], MOD_NUM
    jz .no_num
    or r12d, (1 << 0)  ; NumLock LED
.no_num:
    test dword [rbx + Keyboard_MODIFIERS], MOD_CAPS
    jz .no_caps
    or r12d, (1 << 1)  ; CapsLock LED
.no_caps:
    ; ScrollLock, Compose, etc.

    mov [rbx + Keyboard_LEDS], r12d

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12

; ============================================================================
; keyboard_modifiers
;   Get current modifier state
; ============================================================================
global keyboard_modifiers
keyboard_modifiers:
    PROLOGUE
    mov eax, [rdi + Keyboard_MODIFIERS]
    leave
    ret

; ============================================================================
; keyboard_repeat
;   Handle key repeat timer
; ============================================================================
global keyboard_repeat
keyboard_repeat:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12d, [rbx + Keyboard_REPEAT_KEY]
    test r12d, r12d
    jz .done

    ; Check if key still pressed
    mov rdi, rbx
    mov esi, r12d
    call keyboard_is_key_pressed
    test rax, rax
    jz .clear_repeat

    ; Send repeat event
    mov rax, [rbx + InputDevice_SEAT]
    mov rax, [rax + SEAT_KEYBOARD_FOCUS]
    test rax, rax
    jz .reschedule

    mov rdi, rax
    mov esi, r12d
    mov edx, KEY_STATE_REPEAT
    mov ecx, 0  ; time
    mov r8d, 0  ; serial
    call surface_keyboard_key

.reschedule:
    mov rdi, rbx
    call timer_restart
    jmp .done

.clear_repeat:
    mov qword [rbx + Keyboard_REPEAT_KEY], 0
    mov qword [rbx + Keyboard_REPEAT_TIMER], 0

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ============================================================================
; keyboard_set_keymap
;   Set keyboard keymap
; ============================================================================
global keyboard_set_keymap
keyboard_set_keymap:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Destroy old keymap
    mov rax, [rbx + Keyboard_KEYMAP]
    test rax, rax
    jz .set_new
    mov rdi, rax
    call keymap_destroy

.set_new:
    mov [rbx + Keyboard_KEYMAP], r12

    ; Update modifiers
    mov rdi, rbx
    call keyboard_update_modifiers

    ; Update LEDs
    mov rdi, rbx
    call keyboard_update_leds

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12

; ============================================================================
; keyboard_get_keymap
;   Get current keymap
; ============================================================================
global keyboard_get_keymap
keyboard_get_keymap:
    PROLOGUE
    mov rax, [rdi + Keyboard_KEYMAP]
    leave
    ret

; ============================================================================
; keyboard_set_repeat
;   Set key repeat rate/delay
; ============================================================================
global keyboard_set_repeat
keyboard_set_repeat:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + Keyboard_REPEAT_RATE], esi
    mov dword [rbx + Keyboard_REPEAT_DELAY], edx

    xor rax, rax
    EPILOGUE_RESTORE rbx

; Arm the initial key-repeat delay for a keyboard.
global timer_start
timer_start:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    call ut_time_now_ns
    mov ecx, [rbx + Keyboard_REPEAT_DELAY]
    test ecx, ecx
    jnz .have_delay
    mov ecx, 500
.have_delay:
    imul rcx, 1000000
    add rax, rcx
    mov rdi, rax
    lea rsi, [rel keyboard_repeat]
    mov rdx, rbx
    call ut_timer_register
    test rax, rax
    js .timer_start_out
    mov [rbx + Keyboard_REPEAT_TIMER], rax
.timer_start_out:
    EPILOGUE_RESTORE rbx

; Re-arm at the configured repeat frequency after a repeat callback fires.
global timer_restart
timer_restart:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov ecx, [rbx + Keyboard_REPEAT_RATE]
    test ecx, ecx
    jnz .have_rate
    mov ecx, 25
.have_rate:
    mov rax, 1000000000
    xor edx, edx
    div rcx
    mov r12, rax
    call ut_time_now_ns
    add rax, r12
    mov rdi, rax
    lea rsi, [rel keyboard_repeat]
    mov rdx, rbx
    call ut_timer_register
    test rax, rax
    js .timer_restart_out
    mov [rbx + Keyboard_REPEAT_TIMER], rax
.timer_restart_out:
    EPILOGUE_RESTORE rbx, r12

global timer_destroy
timer_destroy:
    test rdi, rdi
    jz .timer_destroyed
    jmp ut_timer_cancel
.timer_destroyed:
    xor eax, eax
    ret

section .data
global keyboard_version
keyboard_version: dq 0x010000
