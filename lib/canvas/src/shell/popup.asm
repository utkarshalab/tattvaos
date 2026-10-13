; ============================================================================
; Popup — Transient Surfaces (Menus, Tooltips, Dropdowns)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Popup_size    64
%define POPUP_POSITION_CENTER     0
%define POPUP_POSITION_CURSOR     1
%define POPUP_POSITION_RECT       2
%define POPUP_CONSTRAIN_NONE      0
%define POPUP_CONSTRAIN_WINDOW    1
%define POPUP_CONSTRAIN_OUTPUT    2

section .text

struc Popup
    .surface:           resq 1
    .shell:             resq 1
    .parent:            resq 1
    .position:          resd 1
    .x:                 resd 1
    .y:                 resd 1
    .width:             resd 1
    .height:            resd 1
    .constrain:         resb 1
    .grab:              resq 1
endstruc



; ---------------------------------------------------------------------------
; popup_create
;   Create popup for surface
; ---------------------------------------------------------------------------
global popup_create
popup_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate popup
    mov rdi, [rbx + Server.arena]
    mov rsi, Popup_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + Popup.surface], r12
    mov qword [rbx + Popup.shell], r13
    mov qword [rbx + Popup.parent], 0
    mov dword [rbx + Popup.position], POPUP_POSITION_CENTER
    mov dword [rbx + Popup.x], 0
    mov dword [rbx + Popup.y], 0
    mov dword [rbx + Popup.width], 200
    mov dword [rbx + Popup.height], 100
    mov byte [rbx + Popup.constrain], POPUP_CONSTRAIN_OUTPUT
    mov qword [rbx + Popup.grab], 0

    ; Set surface role
    mov dword [r12 + Surface.role], SHELL_ROLE_POPUP
    mov qword [r12 + Surface.role_data], rbx

    ; Add to shell's popup list
    mov r14, [r13 + Shell.popups]
    mov [rbx + Popup.next], r14
    mov [r13 + Shell.popups], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; popup_destroy
; ---------------------------------------------------------------------------
global popup_destroy
popup_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Release grab
    mov rax, [rbx + Popup.grab]
    test rax, rax
    jz .no_grab
    mov rdi, [rbx + Popup.shell]
    mov rsi, rax
    call grab_release

.no_grab:
    ; Remove from shell list
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; popup_set_parent
; ---------------------------------------------------------------------------
global popup_set_parent
popup_set_parent:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + Popup.parent], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; popup_set_position
; ---------------------------------------------------------------------------
global popup_set_position
popup_set_position:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx

    mov dword [rbx + Popup.position], r12d
    mov dword [rbx + Popup.x], r13d
    mov dword [rbx + Popup.y], r14d
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; popup_set_size
; ---------------------------------------------------------------------------
global popup_set_size
popup_set_size:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + Popup.width], esi
    mov [rdi + Popup.height], edx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; popup_set_constrain
; ---------------------------------------------------------------------------
global popup_set_constrain
popup_set_constrain:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 2
    ja .invalid
    mov byte [rdi + Popup.constrain], sil
    xor rax, rax
    leave
    ret

.invalid:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; popup_compute_position
;   Compute popup position relative to parent/output
; ---------------------------------------------------------------------------
global popup_compute_position
popup_compute_position:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx + Popup.position]

    cmp eax, POPUP_POSITION_CENTER
    je .center
    cmp eax, POPUP_POSITION_CURSOR
    je .cursor
    cmp eax, POPUP_POSITION_RECT
    je .rect
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.center:
    ; Center on parent or output
    mov r13, [rbx + Popup.parent]
    test r13, r13
    jnz .center_on_parent

    ; Center on output
    mov r13, [rbx + Popup.shell]
    mov r13, [r13 + Server.outputs]
    test r13, r13
    jz .done

.center_on_parent:
    ; Get parent geometry
    mov r13, [r13 + Surface.current + SurfaceState.buf_x]
    mov r14, [r13 + Surface.current + SurfaceState.buf_y]
    mov r15, [r13 + Surface.current + SurfaceState.width]
    mov r12, [r13 + Surface.current + SurfaceState.height]

    mov eax, [rbx + Popup.width]
    sub r15, rax
    sar r15, 1
    add r13, r15

    mov eax, [rbx + Popup.height]
    sub r12, rax
    sar r12, 1
    add r14, r12

    mov [rbx + Popup.x], r13d
    mov [rbx + Popup.y], r14d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.cursor:
    ; Position at cursor
    mov r13, [rbx + Popup.shell]
    mov r13, [r13 + Server.default_seat]
    mov r13, [r13 + Seat.pointer]
    mov eax, [r13 + Pointer.x]
    mov [rbx + Popup.x], eax
    mov eax, [r13 + Pointer.y]
    mov [rbx + Popup.y], eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rect:
    ; Position relative to rect
    mov r13, [rbx + Popup.x]
    mov r14, [rbx + Popup.y]
    ; x, y already set
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; popup_grab
;   Grab input for popup
; ---------------------------------------------------------------------------
global popup_grab
popup_grab:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Grab pointer and keyboard
    mov rax, [rbx + Popup.shell]
    mov rdi, rax
    mov rsi, [rbx + Popup.surface]
    mov rdx, GRAB_POINTER
    mov rcx, rbx
    mov r8, 0
    call grab_pointer
    test rax, rax
    jnz .fail

    mov qword [rbx + Popup.grab], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.fail:
    mov rax, -(EBUSY)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; popup_ungrab
; ---------------------------------------------------------------------------
global popup_ungrab
popup_ungrab:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Popup.grab]
    test rax, rax
    jz .done

    mov rdi, [rbx + Popup.shell]
    mov rsi, rax
    call grab_release

.done:
    mov qword [rbx + Popup.grab], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global popup_version
popup_version: dq 0x010000
