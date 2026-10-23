; ============================================================================
; Global Shortcuts — Mediated Global Keyboard Shortcuts
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define SHORTCUT_ACTION_NONE       0
%define SHORTCUT_ACTION_SPAWN      1
%define SHORTCUT_ACTION_COMMAND    2
%define SHORTCUT_ACTION_DBUS       3
%define SHORTCUT_ACTION_KEYSYM     4
%define SHORTCUT_MAX               256

section .text

; ---------------------------------------------------------------------------
; shortcuts_init
;   Initialize shortcuts subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global shortcuts_init
shortcuts_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.shortcuts], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; shortcut_register
;   Register a global shortcut
;   IN:  rdi = server*, rsi = keysym, rdx = modifiers, rcx = action, r8 = action_data
;   OUT: rax = shortcut*, negative error
; ---------------------------------------------------------------------------
global shortcut_register
shortcut_register:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15, r8
    ASSERT_PTR rbx

    ; Allocate shortcut
    mov rdi, [rbx + Server.arena]
    mov rsi, Shortcut_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r10, rax

    ; Initialize shortcut
    mov dword [r10 + Shortcut.keysym], r12d
    mov dword [r10 + Shortcut.modifiers], r13d
    mov dword [r10 + Shortcut.action], r14d
    mov qword [r10 + Shortcut.action_data], r15
    mov qword [r10 + Shortcut.client], 0
    mov qword [r10 + Shortcut.next], 0

    ; Add to server's shortcut list
    mov rax, [rbx + Server.shortcuts]
    mov [r10 + Shortcut.next], rax
    mov [rbx + Server.shortcuts], r10

    mov rax, r10
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; shortcut_unregister
;   Unregister a global shortcut
; ---------------------------------------------------------------------------
global shortcut_unregister
shortcut_unregister:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    lea rcx, [rbx + Server.shortcuts]
.unregister_find:
    mov rax, [rcx]
    test rax, rax
    jz .unregister_missing
    cmp rax, r12
    je .unregister_remove
    lea rcx, [rax + Shortcut.next]
    jmp .unregister_find
.unregister_remove:
    mov rax, [r12 + Shortcut.next]
    mov [rcx], rax
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.unregister_missing:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; shortcut_handle_key
;   Handle key press for shortcuts
; ---------------------------------------------------------------------------
global shortcut_handle_key
shortcut_handle_key:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx

    mov rax, [rbx + Server.shortcuts]
.match:
    test rax, rax
    jz .not_handled
    cmp [rax + Shortcut.keysym], r12d
    jne .match_next
    cmp [rax + Shortcut.modifiers], r13d
    jne .match_next
    mov rcx, [rax + Shortcut.action_data]
    test rcx, rcx
    jz .handled
    mov rdi, r12
    mov esi, r13d
    call rcx
.handled:
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.match_next:
    mov rax, [rax + Shortcut.next]
    jmp .match
.not_handled:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global shortcuts_version
shortcuts_version: dq 0x010000
