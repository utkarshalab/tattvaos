; ============================================================================
; Pointer Input Handling — Motion, Buttons, Axis, Focus
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/input.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; pointer_create
;   Create pointer device
;   IN: rdi = pointer*, rsi = seat*, rdx = name, rcx = capabilities
;   OUT: rax = 0 OK, -ENOMEM
; ============================================================================
global pointer_create
pointer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + InputDevice_TYPE], INPUT_TYPE_POINTER
    mov qword [rbx + InputDevice_NAME], r13
    mov qword [rbx + InputDevice_SEAT], r12
    mov dword [rbx + InputDevice_CAPS], r14d
    mov qword [rbx + InputDevice_NEXT], 0

    ; Initialize pointer state
    mov qword [rbx + POINTER_X], 0
    mov qword [rbx + POINTER_Y], 0
    mov dword [rbx + POINTER_BUTTONS], 0
    mov qword [rbx + POINTER_SERIAL], 0
    mov qword [rbx + POINTER_FOCUS], 0
    mov qword [rbx + POINTER_CONSTRAINT], 0

    ; Add to seat's device list
    mov rax, [r12 + SEAT_DEVICES]
    mov [rbx + InputDevice_NEXT], rax
    mov [r12 + SEAT_DEVICES], rbx

    ; If pointer capability, set as seat pointer
    test r14d, DEVICE_CAP_POINTER
    jz .done
    mov [r12 + SEAT_POINTER], rbx

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; pointer_destroy
;   Destroy pointer device
; ============================================================================
global pointer_destroy
pointer_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Remove from seat's device list
    mov r12, [rbx + InputDevice_SEAT]
    call .unlink_from_seat

    ; Release focus
    mov rax, [rbx + POINTER_FOCUS]
    test rax, rax
    jz .done
    call surface_unset_pointer_focus

    ; Release constraint
    mov rax, [rbx + POINTER_CONSTRAINT]
    test rax, rax
    jz .done
    call pointer_constraint_destroy

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.unlink_from_seat:
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
; pointer_set_position
;   Set pointer position (absolute)
; ============================================================================
global pointer_set_position
pointer_set_position:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov dword [rbx + POINTER_X], r12d
    mov dword [rbx + POINTER_Y], r13d

    ; Send motion event to focus
    mov rax, [rbx + POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call surface_pointer_motion

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; pointer_motion
;   Relative pointer motion
; ============================================================================
global pointer_motion
pointer_motion:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    ; Update position
    add dword [rbx + POINTER_X], r12d
    add dword [rbx + POINTER_Y], r13d

    ; Send motion event
    mov rax, [rbx + POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, [rbx + POINTER_X]
    mov edx, [rbx + POINTER_Y]
    call surface_pointer_motion

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; pointer_button
;   Pointer button press/release
; ============================================================================
global pointer_button
pointer_button:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi      ; button
    mov r13d, edx      ; state (pressed/released)
    mov r14d, ecx      ; serial
    ASSERT_PTR rbx

    ; Update button state
    mov eax, [rbx + POINTER_BUTTONS]
    test r13d, r13d
    jz .released

    or eax, (1 << r12d)
    jmp .update

.released:
    and eax, ~(1 << r12d)

.update:
    mov [rbx + POINTER_BUTTONS], eax
    mov dword [rbx + POINTER_SERIAL], r14d

    ; Send button event to focus
    mov rax, [rbx + POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call surface_pointer_button

    ; Handle grab
    test r13d, r13d
    jz .done

    ; Start grab on press
    call pointer_grab

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; pointer_axis
;   Pointer axis (scroll)
; ============================================================================
global pointer_axis
pointer_axis:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi      ; axis (vertical/horizontal)
    mov r13d, edx      ; value (fixed 16.16)
    mov r14d, ecx      ; axis_source
    ASSERT_PTR rbx

    ; Send axis event to focus
    mov rax, [rbx + POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call surface_pointer_axis

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; pointer_enter
;   Pointer enters surface
; ============================================================================
global pointer_enter
pointer_enter:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi       ; surface
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Set focus
    mov [rbx + POINTER_FOCUS], r12

    ; Send enter event
    mov rdi, r12
    call surface_pointer_enter

    ; Update cursor
    mov rax, [rbx + POINTER_CURSOR]
    test rax, rax
    jz .done

    mov rdi, rax
    mov rsi, [rbx + POINTER_X]
    mov rdx, [rbx + POINTER_Y]
    call surface_set_cursor

    xor rax, rax
    leave
    ret

; ============================================================================
; pointer_leave
;   Pointer leaves surface
; ============================================================================
global pointer_leave
pointer_leave:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + POINTER_FOCUS]
    test rax, rax
    jz .done

    ; Send leave event
    mov rdi, rax
    call surface_pointer_leave

    mov qword [rbx + POINTER_FOCUS], 0

    xor rax, rax
    leave
    ret

; ============================================================================
; pointer_grab
;   Start pointer grab
; ============================================================================
global pointer_grab
pointer_grab:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Create grab
    mov rdi, 64  ; Grab_SIZE
    call arena_alloc
    test rax, rax
    jz .fail

    mov r12, rax
    mov qword [r12 + Grab.NEXT], 0
    mov dword [r12 + Grab.TYPE], 0  ; pointer grab
    mov qword [r12 + Grab.SEAT], [rbx + InputDevice_SEAT]
    mov qword [r12 + Grab.OWNER], rbx
    mov dword [r12 + Grab.SERIAL], [rbx + POINTER_SERIAL]
    mov qword [r12 + Grab.CURSOR], 0
    mov qword [r12 + Grab.SURFACE], [rbx + POINTER_FOCUS]
    mov qword [r12 + Grab.CONFINE], 0

    ; Add to seat's grab list
    mov rbx, [rbx + InputDevice_SEAT]
    mov rax, [rbx + SEAT_GRABS]
    mov [r12 + Grab.NEXT], rax
    mov [rbx + SEAT_GRABS], r12

    xor rax, rax
    ret

.fail:
    mov rax, -ENOMEM
    ret

; ============================================================================
; pointer_ungrab
;   Release pointer grab
; ============================================================================
global pointer_ungrab
pointer_ungrab:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Find and remove grab
    mov r12, [rbx + InputDevice_SEAT]
    mov rax, [r12 + SEAT_GRABS]
    test rax, rax
    jz .done

    cmp qword [rax + Grab.OWNER], rbx
    jne .find_prev

    mov rax, [rax + Grab.NEXT]
    mov [r12 + SEAT_GRABS], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + Grab.NEXT]
    test rax, rax
    jz .done
    cmp qword [rax + Grab.OWNER], rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rax + Grab.NEXT]
    mov [r12 + Grab.NEXT], rax

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; pointer_constrain
;   Constrain pointer to region
; ============================================================================
global pointer_constrain
pointer_constrain:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi       ; region
    mov r13d, edx      ; type
    mov r14d, ecx      ; lifetime
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create constraint
    mov rdi, 48  ; Constraint_SIZE
    call arena_alloc
    test rax, rax
    jz .fail

    mov r15, rax
    mov dword [rax + Constraint.TYPE], r13d
    mov dword [rax + Constraint.LIFETIME], r14d
    mov qword [rax + Constraint.REGION], r12
    mov qword [rax + Constraint.POINTER], rbx

    ; Set as active constraint
    mov qword [rbx + POINTER_CONSTRAINT], rax

    xor rax, rax
    ret

.fail:
    mov rax, -ENOMEM
    ret

; ============================================================================
; pointer_unconstrain
;   Release pointer constraint
; ============================================================================
global pointer_unconstrain
pointer_unconstrain:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + POINTER_CONSTRAINT]
    test rax, rax
    jz .done

    ; Destroy constraint
    call constraint_destroy

    mov qword [rbx + POINTER_CONSTRAINT], 0

.done:
    xor rax, rax
    leave
    ret

section .data
global pointer_version
pointer_version: dq 0x010000