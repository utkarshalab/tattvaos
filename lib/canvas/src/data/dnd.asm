; ============================================================================
; Drag and Drop — Drag-and-Drop Protocol
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern grab_release

; struct offsets (hoisted above use)
%define DnD_SIZE    80
%define DND_STATE_NONE        0
%define DND_STATE_ENTER       1
%define DND_STATE_MOTION      2
%define DND_STATE_DROP        3
%define DND_STATE_LEAVE       4
%define DND_STATE_CANCEL      5
%define DND_ACTION_NONE       0
%define DND_ACTION_COPY       (1 << 0)
%define DND_ACTION_MOVE       (1 << 1)
%define DND_ACTION_ASK        (1 << 2)
%define DND_MAX_MIMES         16

section .text

; DnD struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; ---------------------------------------------------------------------------
; dnd_init
; ---------------------------------------------------------------------------
global dnd_init
dnd_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.dnd], 0
    mov qword [rbx + Server.arena], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; dnd_start_drag
;   Start drag operation
;   IN:  rdi = server*, rsi = client*, rdx = surface*, rcx = mime_types, r8 = mime_count, r9 = actions
; ---------------------------------------------------------------------------
global dnd_start_drag
dnd_start_drag:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Check existing drag
    mov rax, [rbx + Server.dnd]
    test rax, rax
    jz .create_dnd

    ; Cancel existing drag
    mov rdi, rbx
    mov rsi, rax
    call dnd_cancel_drag

.create_dnd:
    sub rsp, 16
    mov [rsp], rbx
    mov [rsp + 8], r9
    ; Allocate DnD
    mov rdi, [rbx + Server.arena]
    mov rsi, DnD_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize DnD
    mov qword [rbx + DnD.seat], 0
    mov qword [rbx + DnD.source_client], r12
    mov qword [rbx + DnD.source_surface], r13
    mov qword [rbx + DnD.offered_mimes], r14
    mov dword [rbx + DnD.mime_count], r15d
    mov qword [rbx + DnD.selected_mime], 0
    mov qword [rbx + DnD.selected_mime_len], 0
    mov dword [rbx + DnD.action], 0
    mov eax, [rsp + 8]
    mov dword [rbx + DnD.actions], eax
    mov qword [rbx + DnD.serial], 0
    mov dword [rbx + DnD.state], DND_STATE_NONE

    mov qword [rbx + DnD.target_client], 0
    mov qword [rbx + DnD.target_surface], 0
    mov qword [rbx + DnD.drag_icon], 0

    ; Store DnD
    mov rax, [rsp]
    mov [rax + Server.dnd], rbx

    ; Grab pointer for drag
    mov qword [rbx + DnD.grab], 0

    xor rax, rax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.grab_fail:
    mov rax, -(EBUSY)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; dnd_offer_mime
;   Add mime type to drag offer
; ---------------------------------------------------------------------------
global dnd_offer_mime
dnd_offer_mime:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx + DnD.mime_count]
    cmp eax, DND_MAX_MIMES
    jae .offer_full
    mov rdx, [rbx + DnD.offered_mimes]
    test rdx, rdx
    jz .offer_invalid
    mov [rdx + rax * 8], r12
    inc dword [rbx + DnD.mime_count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.offer_full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12
    ret
.offer_invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; dnd_set_actions
; ---------------------------------------------------------------------------
global dnd_set_actions
dnd_set_actions:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + DnD.actions], esi
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; dnd_enter
;   Target surface entered
; ---------------------------------------------------------------------------
global dnd_enter
dnd_enter:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + DnD.target_surface], r12
    mov qword [rbx + DnD.target_client], r13
    mov dword [rbx + DnD.state], DND_STATE_ENTER

    inc qword [rbx + DnD.serial]

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; dnd_motion
;   Pointer motion during drag
; ---------------------------------------------------------------------------
global dnd_motion
dnd_motion:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    cmp dword [rbx + DnD.state], DND_STATE_ENTER
    jl .not_entered
    cmp dword [rbx + DnD.state], DND_STATE_LEAVE
    jg .not_entered

    mov dword [rbx + DnD.state], DND_STATE_MOTION
    inc qword [rbx + DnD.serial]

.not_entered:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; dnd_drop
;   Drop performed
; ---------------------------------------------------------------------------
global dnd_drop
dnd_drop:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp dword [rbx + DnD.state], DND_STATE_MOTION
    jne .invalid_state

    mov dword [rbx + DnD.state], DND_STATE_DROP

    ; Determine action
    mov eax, [rbx + DnD.actions]
    test eax, DND_ACTION_MOVE
    jz .check_copy
    mov dword [rbx + DnD.action], DND_ACTION_MOVE
    jmp .send_drop

.check_copy:
    test eax, DND_ACTION_COPY
    jz .check_ask
    mov dword [rbx + DnD.action], DND_ACTION_COPY
    jmp .send_drop

.check_ask:
    test eax, DND_ACTION_ASK
    jz .invalid_action
    ; Native policy resolves ASK deterministically to a copy operation.
    mov dword [rbx + DnD.action], DND_ACTION_COPY

.send_drop:
    inc qword [rbx + DnD.serial]

    ; Release grab
    mov rax, [rbx + DnD.grab]
    test rax, rax
    jz .done
    mov rdi, r12
    mov rsi, rax
    call grab_release

.done:
    mov dword [rbx + DnD.state], DND_STATE_NONE
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid_state:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret
.invalid_action:
    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; dnd_leave
;   Target surface left
; ---------------------------------------------------------------------------
global dnd_leave
dnd_leave:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp dword [rbx + DnD.state], DND_STATE_ENTER
    jl .done
    cmp dword [rbx + DnD.state], DND_STATE_DROP
    jg .done

    mov dword [rbx + DnD.state], DND_STATE_LEAVE

    inc qword [rbx + DnD.serial]

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; dnd_cancel_drag
;   Cancel drag operation
; ---------------------------------------------------------------------------
global dnd_cancel_drag
dnd_cancel_drag:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp dword [rbx + DnD.state], DND_STATE_NONE
    je .done

    mov dword [rbx + DnD.state], DND_STATE_CANCEL

    inc qword [r12 + DnD.serial]

    ; Release grab
    mov rax, [r12 + DnD.grab]
    test rax, rax
    jz .done
    mov rdi, [r12 + DnD.seat]
    mov rsi, rax
    call grab_release

.done:
    mov dword [r12 + DnD.state], DND_STATE_NONE
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; dnd_set_drag_icon
; ---------------------------------------------------------------------------
global dnd_set_drag_icon
dnd_set_drag_icon:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + DnD.drag_icon], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global dnd_version
dnd_version: dq 0x010000
