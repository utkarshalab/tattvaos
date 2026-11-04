; ============================================================================
; Keymap — Keycodes to Characters, US Layout
; ============================================================================
; Keycodes are the numbers the drivers report (rfb_input uses the same ones).
; keymap_key keeps a seat's modifiers and locks up to date and says which
; character a press types, if any:
;
;   Shift, Ctrl, Alt and Super are held while either of their keys is down;
;   Caps Lock and Num Lock toggle on each press.
;   With Ctrl, Alt or Super held a press types nothing: it is a shortcut.
;   Caps Lock shifts letters only; the keypad types digits only with Num Lock.
;
; One layout for now. Another is another table of the same shape.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/event.inc"
%include "inc/struct_offsets.inc"

%define KEY_LEFTCTRL    29
%define KEY_LEFTSHIFT   42
%define KEY_RIGHTSHIFT  54
%define KEY_LEFTALT     56
%define KEY_CAPSLOCK    58
%define KEY_NUMLOCK     69
%define KEY_KP7         71              ; keypad digits: 71-73, 75-77, 79-83
%define KEY_KPMINUS     74
%define KEY_KPPLUS      78
%define KEY_KPDOT       83
%define KEY_RIGHTCTRL   97
%define KEY_RIGHTALT    100
%define KEY_LEFTMETA    125
%define KEY_RIGHTMETA   126

%define KEYMAP_KEYS     128             ; keycodes the table covers

section .text

; ---------------------------------------------------------------------------
; keymap_key
;   One key changed; the seat's held keys already say so
;   IN:  rdi = InputSeat*, esi = keycode, edx = 1 pressed, 0 released
;   OUT: eax = the character it types (Unicode), 0 for none;
;        ecx = 1 if InputSeat.mods or InputSeat.locks changed
; ---------------------------------------------------------------------------
global keymap_key
keymap_key:
    mov esi, esi
    xor r8d, r8d                        ; changed

    ; Locks toggle on a press
    test edx, edx
    jz .held
    mov eax, MOD_CAPS
    cmp esi, KEY_CAPSLOCK
    je .toggle
    mov eax, MOD_NUM
    cmp esi, KEY_NUMLOCK
    jne .held
.toggle:
    xor [rdi + InputSeat.locks], eax
    mov r8d, 1

    ; Held modifiers, from the held keys
.held:
    xor r9d, r9d
%macro HELD 2                           ; keycode, modifier
    test byte [rdi + InputSeat.keys + (%1 >> 3)], 1 << (%1 & 7)
    jz %%up
    or r9d, %2
%%up:
%endmacro
    HELD KEY_LEFTSHIFT, MOD_SHIFT
    HELD KEY_RIGHTSHIFT, MOD_SHIFT
    HELD KEY_LEFTCTRL, MOD_CTRL
    HELD KEY_RIGHTCTRL, MOD_CTRL
    HELD KEY_LEFTALT, MOD_ALT
    HELD KEY_RIGHTALT, MOD_ALT
    HELD KEY_LEFTMETA, MOD_SUPER
    HELD KEY_RIGHTMETA, MOD_SUPER
    cmp r9d, [rdi + InputSeat.mods]
    je .text
    mov [rdi + InputSeat.mods], r9d
    mov r8d, 1

    ; The character
.text:
    test edx, edx
    jz .none
    test r9d, MOD_CTRL | MOD_ALT | MOD_SUPER
    jnz .none
    cmp esi, KEYMAP_KEYS
    jae .none
    lea r10, [rel keymap_us]
    movzx eax, word [r10 + rsi * 4]
    movzx r11d, word [r10 + rsi * 4 + 2]
    test eax, eax
    jz .none
    cmp esi, KEY_KP7
    jb .shift
    cmp esi, KEY_KPDOT
    ja .shift
    cmp esi, KEY_KPMINUS
    je .shift
    cmp esi, KEY_KPPLUS
    je .shift
    test dword [rdi + InputSeat.locks], MOD_NUM
    jz .none                            ; a keypad digit without Num Lock
.shift:
    mov ecx, r9d
    and ecx, MOD_SHIFT
    cmp eax, 'a'
    jb .level
    cmp eax, 'z'
    ja .level
    test dword [rdi + InputSeat.locks], MOD_CAPS
    jz .level
    xor ecx, MOD_SHIFT
.level:
    test ecx, ecx
    cmovnz eax, r11d
    mov ecx, r8d
    ret
.none:
    xor eax, eax
    mov ecx, r8d
    ret

section .rodata

; keycode -> (character, character with Shift), 16 bits each; 0: types nothing
%macro K 3
    times (%1) * 4 - ($ - keymap_us) db 0
    dw %2, %3
%endmacro
align 4
keymap_us:
    K 2, '1', 0x21                      ; !
    K 3, '2', 0x40                      ; @
    K 4, '3', 0x23                      ; #
    K 5, '4', 0x24                      ; $
    K 6, '5', 0x25                      ; %
    K 7, '6', 0x5E                      ; ^
    K 8, '7', 0x26                      ; &
    K 9, '8', 0x2A                      ; *
    K 10, '9', 0x28                     ; (
    K 11, '0', 0x29                     ; )
    K 12, 0x2D, 0x5F                    ; - _
    K 13, 0x3D, 0x2B                    ; = +
    K 16, 'q', 'Q'
    K 17, 'w', 'W'
    K 18, 'e', 'E'
    K 19, 'r', 'R'
    K 20, 't', 'T'
    K 21, 'y', 'Y'
    K 22, 'u', 'U'
    K 23, 'i', 'I'
    K 24, 'o', 'O'
    K 25, 'p', 'P'
    K 26, 0x5B, 0x7B                    ; [ {
    K 27, 0x5D, 0x7D                    ; ] }
    K 30, 'a', 'A'
    K 31, 's', 'S'
    K 32, 'd', 'D'
    K 33, 'f', 'F'
    K 34, 'g', 'G'
    K 35, 'h', 'H'
    K 36, 'j', 'J'
    K 37, 'k', 'K'
    K 38, 'l', 'L'
    K 39, 0x3B, 0x3A                    ; ; :
    K 40, 0x27, 0x22                    ; ' "
    K 41, 0x60, 0x7E                    ; ` ~
    K 43, 0x5C, 0x7C                    ; \ |
    K 44, 'z', 'Z'
    K 45, 'x', 'X'
    K 46, 'c', 'C'
    K 47, 'v', 'V'
    K 48, 'b', 'B'
    K 49, 'n', 'N'
    K 50, 'm', 'M'
    K 51, 0x2C, 0x3C                    ; , <
    K 52, 0x2E, 0x3E                    ; . >
    K 53, 0x2F, 0x3F                    ; / ?
    K 55, 0x2A, 0x2A                    ; keypad *
    K 57, 0x20, 0x20                    ; space
    K 71, '7', '7'                      ; keypad
    K 72, '8', '8'
    K 73, '9', '9'
    K 74, 0x2D, 0x2D
    K 75, '4', '4'
    K 76, '5', '5'
    K 77, '6', '6'
    K 78, 0x2B, 0x2B
    K 79, '1', '1'
    K 80, '2', '2'
    K 81, '3', '3'
    K 82, '0', '0'
    K 83, 0x2E, 0x2E
    K 98, 0x2F, 0x2F                    ; keypad /
    times KEYMAP_KEYS * 4 - ($ - keymap_us) db 0

section .data
global keymap_us_version
keymap_us_version: dq 0x010000
