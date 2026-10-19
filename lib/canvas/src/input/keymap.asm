; ============================================================================
; Keymap — Keycode to Keysym Mapping with Levels and Groups
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define KEYMAP_MAX_KEYCODES    256
%define KEYMAP_LEVELS          4
%define KEYMAP_GROUPS          4
%define Keymap_SIZE    48
%define KEYSYM_NONE       0
%define KEYSYM_MOD_SHIFT  0xFFE1
%define KEYSYM_MOD_CTRL   0xFFE3
%define KEYSYM_MOD_ALT    0xFFE9
%define KEYSYM_MOD_SUPER  0xFFEB
%define MOD_SHIFT      (1 << 0)
%define MOD_CTRL       (1 << 2)
%define MOD_ALT        (1 << 3)
%define MOD_MOD2       (1 << 4)
%define MOD_MOD3       (1 << 5)
%define MOD_MOD4       (1 << 6)
%define MOD_MOD5       (1 << 6)

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
    mov rsi, KEYMAP_MAX_KEYCODES * KEYMAP_LEVELS * KEYMAP_GROUPS * 4
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
    mov rcx, KEYMAP_MAX_KEYCODES * KEYMAP_LEVELS * KEYMAP_GROUPS / 2
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
    imul r9, rsi, KEYMAP_LEVELS * KEYMAP_GROUPS
    imul r10, rcx, KEYMAP_LEVELS
    add r9, r10
    add r9, rdx
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
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r14d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    cmp r12d, KEYMAP_MAX_KEYCODES
    jae .none

    ; Determine level from modifiers
    xor r12d, r12d
    test rdx, MOD_SHIFT
    jz .no_shift
    mov r12d, 1
.no_shift:

    ; Check for level 3 (AltGr) / level 4
    test rdx, MOD_ALT
    jz .no_altgr
    test rdx, MOD_CTRL
    jnz .no_altgr
    mov r12d, 2
.no_altgr:

    test rdx, MOD_MOD4
    jz .no_mod4
    mov r12d, 3
.no_mod4:

    ; Group selection (for now, group 0)
    mov r13d, 0

    ; Lookup
    mov rbx, [rbx + Keymap.keycodes]
    imul rax, r14, KEYMAP_LEVELS * KEYMAP_GROUPS
    add rax, r12
    mov eax, [rbx + rax * 4]
    test eax, eax
    jz .none
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; keymap_is_modifier
;   Check if keycode is a modifier
;   IN:  rdi = keymap*, rsi = keycode
;   OUT: rax = modifier bitmask
; ---------------------------------------------------------------------------
global keymap_is_modifier
keymap_is_modifier:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    ; Check base level keysym
    mov rax, [rbx + Keymap.keycodes]
    shl r12, 6
    mov eax, [rax + r12]

    cmp eax, KEYSYM_MOD_SHIFT
    je .shift
    cmp eax, KEYSYM_MOD_CTRL
    je .ctrl
    cmp eax, KEYSYM_MOD_ALT
    je .alt
    cmp eax, KEYSYM_MOD_SUPER
    je .super

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.shift:
    mov rax, MOD_SHIFT
    EPILOGUE_RESTORE rbx, r12
    ret
.ctrl:
    mov rax, MOD_CTRL
    EPILOGUE_RESTORE rbx, r12
    ret
.alt:
    mov rax, MOD_ALT
    EPILOGUE_RESTORE rbx, r12
    ret
.super:
    mov rax, MOD_MOD4
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; keymap_compile
;   Compile text keymap to binary
; ---------------------------------------------------------------------------
global keymap_compile
keymap_compile:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ; Native compiled records: u16 keycode, u16 reserved, u32 base, u32 shift.
.record:
    cmp r13, 12
    jb .compile_done
    movzx esi, word [r12]
    mov r8d, [r12 + 4]
    xor edx, edx
    xor ecx, ecx
    mov rdi, rbx
    call keymap_set_entry
    test rax, rax
    js .compile_out
    movzx esi, word [r12]
    mov r8d, [r12 + 8]
    mov edx, 1
    xor ecx, ecx
    mov rdi, rbx
    call keymap_set_entry
    test rax, rax
    js .compile_out
    add r12, 12
    sub r13, 12
    jmp .record
.compile_done:
    test r13, r13
    jnz .compile_bad
    xor eax, eax
    jmp .compile_out
.compile_bad:
    mov rax, -(EINVAL)
.compile_out:
    EPILOGUE_RESTORE rbx, r12, r13
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
