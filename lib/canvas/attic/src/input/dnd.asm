; ============================================================================
; Drag and Drop — DnD Source/Destination, Actions, MIME Types
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; Drag Struct
; ============================================================================
%define Drag_SOURCE         0
%define Drag_ICON           8
%define Drag_ACTIONS        16
%define Drag_SOURCE_CLIENT  24
%define Drag_TARGET         32
%define Drag_SERIAL         40
%define Drag_SIZE           48

; Action flags
%define DND_ACTION_NONE    0
%define DND_ACTION_COPY    (1 << 0)
%define DND_ACTION_MOVE    (1 << 1)
%define DND_ACTION_ASK     (1 << 2)
%define DND_ACTION_LINK    (1 << 3)

; ============================================================================
; dnd_start
;   Start drag operation
; ============================================================================
global dnd_start
dnd_start:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; seat
    mov r12, rsi       ; source data_source
    mov r13, rdx       ; icon surface
    mov r14d, ecx      ; actions
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Release old drag
    mov rax, [rbx + Seat_DRAG_SOURCE]
    test rax, rax
    jz .set_new
    call data_source_destroy

.set_new:
    mov [rbx + Seat_DRAG_SOURCE], r12
    mov qword [rbx + Seat_DRAG_ICON], r13
    mov dword [rbx + Seat_DRAG_ACTIONS], r14d
    mov dword [rbx + Seat_DRAG_SERIAL], 0

    ; Set icon as cursor
    test r13, r13
    jz .done

    mov rax, [rbx + Seat_POINTER]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, r13
    call surface_set_cursor

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; dnd_drop
;   Drop at current position
; ============================================================================
global dnd_drop
dnd_drop:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Seat_DRAG_SOURCE]
    test r12, r12
    jz .done

    ; Get target surface under pointer
    mov rax, [rbx + Seat_POINTER]
    test rax, rax
    jz .cancel

    mov rax, [rax + Pointer_FOCUS]
    test rax, rax
    jz .cancel

    ; Send drop event to target
    mov rdi, rax
    mov rsi, r12
    call surface_dnd_drop

    ; Cleanup
    call data_source_destroy
    mov qword [rbx + Seat_DRAG_SOURCE], 0
    mov qword [rbx + Seat_DRAG_ICON], 0
    mov dword [rbx + Seat_DRAG_ACTIONS], 0

    xor rax, rax
    leave
    ret

.cancel:
    ; Send cancel to source
    mov rdi, r12
    call data_source_cancel

    mov qword [rbx + Seat_DRAG_SOURCE], 0
    mov qword [rbx + Seat_DRAG_ICON], 0
    mov dword [rbx + Seat_DRAG_ACTIONS], 0

    xor rax, rax
    leave
    ret

; ============================================================================
; dnd_action
;   Get/set current drag action
; ============================================================================
global dnd_action
dnd_action:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    test rsi, rsi
    jz .get

    mov dword [rbx + Seat_DRAG_ACTIONS], esi
    xor rax, rax
    leave
    ret

.get:
    mov eax, [rdi + Seat_DRAG_ACTIONS]
    leave
    ret

; ============================================================================
; dnd_cancel
;   Cancel drag operation
; ============================================================================
global dnd_cancel
dnd_cancel:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12, [rbx + Seat_DRAG_SOURCE]
    test r12, r12
    jz .done

    ; Send cancel to source
    call data_source_cancel

    ; Cleanup
    call data_source_destroy
    mov qword [rbx + Seat_DRAG_SOURCE], 0
    mov qword [rbx + Seat_DRAG_ICON], 0
    mov dword [rbx + Seat_DRAG_ACTIONS], 0

    ; Reset cursor
    mov rax, [rbx + Seat_POINTER]
    test rax, rax
    jz .done
    mov rdi, rax
    call surface_reset_cursor

    xor rax, rax
    leave
    ret

section .data
global dnd_version
dnd_version: dq 0x010000