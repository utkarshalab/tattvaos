; ============================================================================
; Keymap — Keycode to Keysym Mapping with Levels and Groups
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define KEYMAP_MAX_KEYCODES    256
%define KEYMAP_LEVELS          4
%define KEYMAP_GROUPS          4
%define Keymap_size    48
%define KEYSYM_NONE       0
%define KEYSYM_MOD_SHIFT  0xFFE1
%define KEYSYM_MOD_CTRL   0xFFE3
%define KEYSYM_MOD_ALT    0xFFE9
%define KEYSYM_MOD_SUPER  0xFFEB

section .text


struc Keymap
    .name:          resq 1
    .keycodes:      resq 1
    .max_keycode:   resd 1
    .levels:        resb 1
    .groups:        resb 1
    .modifiers:     resd 1
endstruc

struc KeyEntry
    .keycode:       resb 1
    .levels:        resd KEYMAP_LEVELS * KEYMAP_GROUPS
endstruc
%define KeyEntry_size    (1 + 4 * KEYMAP_LEVELS * KEYMAP_GROUPS)


; ---------------------------------------------------------------------------
; keymap_init
;   Initialize keymap
; ---------------------------------------------------------------------------
global keymap_init
keymap_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate keycode array
    mov rdi, r12
    mov rsi, KEYMAP_MAX_KEYCODES
    shl rsi, 3  ; 8 bytes per entry (keycode + 4*4 levels)
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Keymap.keycodes], rax

    mov byte [rbx + Keymap.levels], KEYMAP_LEVELS
    mov byte [rbx + Keymap.groups], KEYMAP_GROUPS
    mov dword [rbx + Keymap.max_keycode], KEYMAP_MAX_KEYCODES
    mov dword [rbx + Keymap.modifiers], 0

    ; Zero initialize
    mov rdi, rax
    mov rcx, KEYMAP_MAX_KEYCODES
    xor rax, rax
    rep stosq

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; keymap_set_entry
;   Set key entry
;   IN:  rdi = keymap*, rsi = keycode, rdx = level, rcx = group, r8 = keysym
; ---------------------------------------------------------------------------
global keymap_set_entry
keymap_set_entry:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, KEYMAP_MAX_KEYCODES
    jae .fail
    cmp rdx, KEYMAP_LEVELS
    jae .fail
    cmp rcx, KEYMAP_GROUPS
    jae .fail

    mov rax, [rdi + Keymap.keycodes]
    lea rax, [rax + rsi * 8]
    mov r9, rdx
    shl r9, 2
    add r9, rcx
    mov [rax + r9 * 4], r8d
    xor rax, rax
    leave
    ret

.fail:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; keymap_lookup_keysym
;   Lookup keysym for keycode with modifiers
;   IN:  rdi = keymap*, rsi = keycode, rdx = modifiers
;   OUT: rax = keysym
; ---------------------------------------------------------------------------
global keymap_lookup_keysym
keymap_lookup_keysym:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    cmp r12d, KEYMAP_MAX_KEYCODES
    jae .none

    ; Determine level from modifiers
    mov r12d, 1  ; base level
    test rdx, MOD_SHIFT
    jz .no_shift
    mov r12d, 2  ; shifted level
.no_shift:

    ; Check for level 3 (AltGr) / level 4
    test rdx, MOD_ALT
    jz .no_altgr
    test rdx, MOD_CTRL
    jnz .no_altgr
    mov r12d, 3  ; level 3 (AltGr)
.no_altgr:

    test rdx, MOD_MOD4
    jz .no_mod4
    mov r12d, 4  ; level 4
.no_mod4:

    ; Group selection (for now, group 0)
    mov r13d, 0

    ; Lookup
    mov rbx, [rbx + Keymap.keycodes]
    mov rdi, rbx
    mov rsi, r12d
    ; Calculate index: level * groups + group
    lea rsi, [r12 + r13 * 4]
    mov eax, [rdi + rsi * 4]
    test eax, eax
    jz .none
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; keymap_is_modifier
;   Check if keycode is a modifier
;   IN:  rdi = keymap*, rsi = keycode
;   OUT: rax = modifier bitmask
; ---------------------------------------------------------------------------
global keymap_is_modifier
keymap_is_modifier:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    ; Check base level keysym
    mov rax, [rbx + Keymap.keycodes]
    movzx eax, word [rax + r12 * 8 + 4]  ; level 0, group 0

    cmp eax, KEYSYM_MOD_SHIFT
    je .shift
    cmp eax, KEYSYM_MOD_CTRL
    je .ctrl
    cmp eax, KEYSYM_MOD_ALT
    je .alt
    cmp eax, KEYSYM_MOD_SUPER
    je .super

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.shift:
    mov rax, MOD_SHIFT
    EPILOGUE_RESTORE rbx
    ret
.ctrl:
    mov rax, MOD_CTRL
    EPILOGUE_RESTORE rbx
    ret
.alt:
    mov rax, MOD_ALT
    EPILOGUE_RESTORE rbx
    ret
.super:
    mov rax, MOD_MOD4
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; keymap_compile
;   Compile text keymap to binary
; ---------------------------------------------------------------------------
global keymap_compile
keymap_compile:
    PROLOGUE
    ; TODO: Parse text keymap format
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; keymap_load
;   Load keymap from file
; ---------------------------------------------------------------------------
global keymap_load
keymap_load:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Read file
    push r12
    push r13
    mov rdi, r12
    mov rsi, r13
    call tv_fs_read
    pop r13
    pop r12
    test rax, rax
    js .fail

    ; Parse and compile
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call keymap_compile
    test rax, rax
    js .fail

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; keymap_create_default
;   Create default US keymap
; ---------------------------------------------------------------------------
global keymap_create_default
keymap_create_default:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    call keymap_init
    test rax, rax
    js .fail

    ; Populate with US layout
    ; Keycodes from Linux input-event-codes.h
    ; KEY_A = 30, KEY_B = 48, etc.

    ; Row 1: ESC, F1-F12, Print, Scroll, Pause
    mov rdi, rbx
    mov rsi, 1
    mov rdx, 1
    mov rcx, 0
    mov r8, 0xFF1B  ; ESC
    call keymap_set_entry

    ; Number row
    mov rdi, rbx
    mov rsi, 2
    mov rdx, 1
    mov rcx, 0
    mov r8, '1'
    call keymap_set_entry
    mov rdi, rbx
    mov rsi, 2
    mov rdx, 2
    mov rcx, 0
    mov r8, '!'
    call keymap_set_entry

    ; ... (more key mappings would go here)

    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12
    ret

.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global keymap_version
keymap_version: dq 0x010000
