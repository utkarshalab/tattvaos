; ============================================================================
; Grab — Input Device Grabbing (Pointer, Keyboard)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; Grabs are arena-owned. Destruction detaches all external relationships while
; preserving the next link so list walkers can continue safely.
global grab_destroy
grab_destroy:
    test rax, rax
    jz .destroy_none
    mov rdx, [rax + Grab.next]
    mov qword [rax + Grab.seat], 0
    mov qword [rax + Grab.surface], 0
    mov qword [rax + Grab.owner], 0
    mov qword [rax + Grab.cursor], 0
    mov qword [rax + Grab.confine], 0
    mov rax, rdx
    ret
.destroy_none:
    xor eax, eax
    ret

; struct offsets (hoisted above use)
%define Grab_SIZE 56
%define GRAB_NONE       0
%define GRAB_POINTER    1
%define GRAB_KEYBOARD   2
%define GRAB_TOUCH      3
%define GRAB_MODE_SYNC      0
%define GRAB_MODE_ASYNC     1

section .text

; Grab struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n

; ---------------------------------------------------------------------------
; grab_init
; ---------------------------------------------------------------------------
global grab_init
grab_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.grabs], 0
    mov qword [rbx + Server.grab_count], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; grab_pointer
;   Grab pointer for surface
; ---------------------------------------------------------------------------
global grab_pointer
grab_pointer:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Check if already grabbed
    mov rax, [rbx + Server.grabs]
.grab_loop:
    test rax, rax
    jz .create_grab
    cmp dword [rax + Grab.type], GRAB_POINTER
    je .already_grabbed
    mov rax, [rax + Grab.next]
    jmp .grab_loop

.create_grab:
    ; Allocate grab
    mov rdi, [rbx + Server.arena]
    mov rsi, Grab_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Grab.seat], r12
    mov qword [rbx + Grab.surface], r13
    mov dword [rbx + Grab.type], GRAB_POINTER
    mov qword [rbx + Grab.owner], r14
    mov qword [rbx + Grab.serial], r15
    mov qword [rbx + Grab.cursor], 0
    mov qword [rbx + Grab.confine], 0

    ; Add to grab list
    mov rax, [rdi + Server.grabs]
    mov [rbx + Grab.next], rax
    mov [rdi + Server.grabs], rbx
    inc qword [rdi + Server.grab_count]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.already_grabbed:
    mov rax, -(EBUSY)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; grab_keyboard
; ---------------------------------------------------------------------------
global grab_keyboard
grab_keyboard:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Check existing keyboard grab
    mov rax, [rbx + Server.grabs]
.grab_loop:
    test rax, rax
    jz .create_grab
    cmp dword [rax + Grab.type], GRAB_KEYBOARD
    je .already_grabbed
    mov rax, [rax + Grab.next]
    jmp .grab_loop

.create_grab:
    mov rdi, [rbx + Server.arena]
    mov rsi, Grab_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Grab.seat], r12
    mov qword [rbx + Grab.surface], r13
    mov dword [rbx + Grab.type], GRAB_KEYBOARD
    mov qword [rbx + Grab.owner], r14
    mov qword [rbx + Grab.serial], r15
    mov qword [rbx + Grab.cursor], 0
    mov qword [rbx + Grab.confine], 0

    mov rax, [rbx + Server.grabs]
    mov [rbx + Grab.next], rax
    mov [rbx + Server.grabs], rbx
    inc qword [rbx + Server.grab_count]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.already_grabbed:
    mov rax, -(EBUSY)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; grab_release
;   Release grab
; ---------------------------------------------------------------------------
global grab_release
grab_release:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find and remove grab
    mov rax, [rbx + Server.grabs]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_head

    mov rbx, rax
.find_loop:
    mov rax, [rbx + Grab.next]
    test rax, rax
    jz .not_found
    cmp rax, r12
    je .remove_middle
    mov rbx, rax
    jmp .find_loop

.remove_head:
    mov rax, [r12 + Grab.next]
    mov [rbx + Server.grabs], rax
    jmp .done

.remove_middle:
    mov rax, [r12 + Grab.next]
    mov [rbx + Grab.next], rax

.done:
    dec qword [rbx + Server.grab_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global grab_version
grab_version: dq 0x010000
