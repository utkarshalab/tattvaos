; ============================================================================
; Tablet Input Handling — Pen, Eraser, Touch, Pressure, Tilt
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/input.inc"
%include "inc/struct_offsets.inc"

extern surface_tablet_axis
extern surface_tablet_proximity
extern surface_tablet_tip
extern surface_tablet_button

%define Tablet_TOOL_TYPE Tablet.tool_type
%define Tablet_TOOL_ID Tablet.tool_id
%define Tablet_X Tablet.x
%define Tablet_Y Tablet.y
%define Tablet_PRESSURE Tablet.pressure
%define Tablet_DISTANCE Tablet.distance
%define Tablet_TILT_X Tablet.tilt_x
%define Tablet_TILT_Y Tablet.tilt_y
%define Tablet_ROTATION Tablet.rotation
%define Tablet_SLIDER Tablet.slider
%define Tablet_WHEEL Tablet.wheel
%define Tablet_BUTTONS Tablet.buttons
%define Tablet_PROXIMITY Tablet.proximity
%define Tablet_TIP_STATE Tablet.tip_state
%define Tablet_PROX_DISTANCE Tablet.prox_distance
%define SEAT_DEVICES Seat.devices
%define SEAT_CAPABILITIES Seat.capabilities
%define SEAT_TABLET Seat.tablet
%define SEAT_POINTER_FOCUS Seat.pointer_focus

section .text

; ============================================================================
; tablet_create
;   Create tablet device
; ============================================================================
global tablet_create
tablet_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi       ; seat
    mov r13, rdx       ; name
    mov r14d, ecx      ; capabilities
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + InputDevice_TYPE], INPUT_TYPE_TABLET
    mov qword [rbx + InputDevice_NAME], r13
    mov qword [rbx + InputDevice_SEAT], r12
    mov dword [rbx + InputDevice_CAPS], r14d
    mov qword [rbx + InputDevice_NEXT], 0

    ; Initialize tablet state
    mov dword [rbx + Tablet_TOOL_TYPE], 0
    mov dword [rbx + Tablet_TOOL_ID], 0
    mov dword [rbx + Tablet_X], 0
    mov dword [rbx + Tablet_Y], 0
    mov dword [rbx + Tablet_PRESSURE], 0
    mov dword [rbx + Tablet_DISTANCE], 0
    mov dword [rbx + Tablet_TILT_X], 0
    mov dword [rbx + Tablet_TILT_Y], 0
    mov dword [rbx + Tablet_ROTATION], 0
    mov dword [rbx + Tablet_SLIDER], 0
    mov dword [rbx + Tablet_WHEEL], 0
    mov dword [rbx + Tablet_BUTTONS], 0
    mov byte [rbx + Tablet_PROXIMITY], 0
    mov dword [rbx + Tablet_PROX_DISTANCE], 0

    ; Add to seat's device list
    mov rax, [r12 + SEAT_DEVICES]
    mov [rbx + InputDevice_NEXT], rax
    mov [r12 + SEAT_DEVICES], rbx

    ; If tablet capability, set as seat tablet
    mov r14d, [r12 + SEAT_CAPABILITIES]
    test r14d, DEVICE_CAP_TABLET
    jz .done
    mov [r12 + SEAT_TABLET], rbx

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; tablet_destroy
;   Destroy tablet device
; ============================================================================
global tablet_destroy
tablet_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Remove from seat's device list
    mov r12, [rbx + InputDevice_SEAT]
    call tablet_unlink_from_seat

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

tablet_unlink_from_seat:
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
; tablet_axis
;   Tablet axis event
; ============================================================================
global tablet_axis
tablet_axis:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi       ; axis
    mov r13d, edx       ; value
    mov r14d, ecx       ; tool_id
    ASSERT_PTR rbx

    ; Update axis value
    cmp r12d, TABLET_AXIS_X
    je .set_x
    cmp r12d, TABLET_AXIS_Y
    je .set_y
    cmp r12d, TABLET_AXIS_PRESSURE
    je .set_pressure
    cmp r12d, TABLET_AXIS_DISTANCE
    je .set_distance
    cmp r12d, TABLET_AXIS_TILT_X
    je .set_tilt_x
    cmp r12d, TABLET_AXIS_TILT_Y
    je .set_tilt_y
    cmp r12d, TABLET_AXIS_ROTATION
    je .set_rotation
    cmp r12d, TABLET_AXIS_SLIDER
    je .set_slider
    cmp r12d, TABLET_AXIS_WHEEL
    je .set_wheel

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.set_x:
    mov dword [rbx + Tablet_X], r13d
    jmp .send_event

.set_y:
    mov dword [rbx + Tablet_Y], r13d
    jmp .send_event

.set_pressure:
    mov dword [rbx + Tablet_PRESSURE], r13d
    jmp .send_event

.set_distance:
    mov dword [rbx + Tablet_DISTANCE], r13d
    jmp .send_event

.set_tilt_x:
    mov dword [rbx + Tablet_TILT_X], r13d
    jmp .send_event

.set_tilt_y:
    mov dword [rbx + Tablet_TILT_Y], r13d
    jmp .send_event

.set_rotation:
    mov dword [rbx + Tablet_ROTATION], r13d
    jmp .send_event

.set_slider:
    mov dword [rbx + Tablet_SLIDER], r13d
    jmp .send_event

.set_wheel:
    mov dword [rbx + Tablet_WHEEL], r13d
    jmp .send_event

.send_event:
    ; Send axis event to focus
    mov rax, [rbx + InputDevice_SEAT]
    mov rax, [rax + SEAT_POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call surface_tablet_axis

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; tablet_proximity
;   Tablet proximity in/out
; ============================================================================
global tablet_proximity
tablet_proximity:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi       ; state (in/out)
    mov r13d, edx       ; tool_type
    mov r14d, ecx       ; tool_id
    ASSERT_PTR rbx

    mov byte [rbx + Tablet_PROXIMITY], r12b
    mov dword [rbx + Tablet_TOOL_TYPE], r13d
    mov dword [rbx + Tablet_TOOL_ID], r14d

    test r12b, r12b
    jnz .send_event
    ; Proximity out resets transient tool state.
        mov dword [rbx + Tablet_X], 0
        mov dword [rbx + Tablet_Y], 0
        mov dword [rbx + Tablet_PRESSURE], 0
        mov dword [rbx + Tablet_DISTANCE], 0
        mov dword [rbx + Tablet_TILT_X], 0
        mov dword [rbx + Tablet_TILT_Y], 0
        mov dword [rbx + Tablet_ROTATION], 0
        mov dword [rbx + Tablet_SLIDER], 0
        mov dword [rbx + Tablet_WHEEL], 0
    mov dword [rbx + Tablet_BUTTONS], 0

    ; Send proximity event
.send_event:
    mov rax, [rbx + InputDevice_SEAT]
    mov rax, [rax + SEAT_POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call surface_tablet_proximity

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; tablet_tip
;   Tablet tip (pen down/up)
; ============================================================================
global tablet_tip
tablet_tip:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi       ; state (down/up)
    mov r13d, edx       ; tool_id
    ASSERT_PTR rbx

    mov byte [rbx + Tablet_TIP_STATE], r12b

    ; Send tip event
    mov rax, [rbx + InputDevice_SEAT]
    mov rax, [rax + SEAT_POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call surface_tablet_tip

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; tablet_button
;   Tablet button press/release
; ============================================================================
global tablet_button
tablet_button:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi       ; button
    mov r13d, edx       ; state
    ASSERT_PTR rbx

    ; Update button state
    mov eax, [rbx + Tablet_BUTTONS]
    test r13d, r13d
    jz .released

    bts eax, r12d
    jmp .update

.released:
    btr eax, r12d

.update:
    mov [rbx + Tablet_BUTTONS], eax

    ; Send button event
    mov rax, [rbx + InputDevice_SEAT]
    mov rax, [rax + SEAT_POINTER_FOCUS]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call surface_tablet_button

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global tablet_version
tablet_version: dq 0x010000
