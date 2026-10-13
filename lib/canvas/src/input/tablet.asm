; ============================================================================
; Tablet — Pen/Stylus Input with Pressure, Tilt, Rotation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define Tablet_size    80
%define TABLET_TOOL_PEN         0
%define TABLET_TOOL_ERASER      1
%define TABLET_TOOL_BRUSH       2
%define TABLET_TOOL_PENCIL      3
%define TABLET_TOOL_AIRBRUSH    4
%define TABLET_TOOL_MOUSE       5
%define TABLET_TOOL_LENS        6
%define TABLET_BUTTON_STYLUS    (1 << 0)
%define TABLET_BUTTON_STYLUS2   (1 << 1)
%define TABLET_PROXIMITY_IN     1
%define TABLET_PROXIMITY_OUT    0

section .text

struc Tablet
    .seat:          resq 1
    .tool_type:     resb 1
    .tool_id:       resd 1
    .x:             resd 1
    .y:             resd 1
    .pressure:      resd 1
    .distance:      resd 1
    .tilt_x:        resd 1
    .tilt_y:        resd 1
    .rotation:      resd 1
    .slider:        resd 1
    .wheel:         resd 1
    .buttons:       resd 1
    .proximity:     resb 1
endstruc




; ---------------------------------------------------------------------------
; tablet_create
; ---------------------------------------------------------------------------
global tablet_create
tablet_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, Tablet_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + Tablet.seat], r12
    mov byte [rbx + Tablet.tool_type], 0
    mov dword [rbx + Tablet.tool_id], 0
    mov dword [rbx + Tablet.x], 0
    mov dword [rbx + Tablet.y], 0
    mov dword [rbx + Tablet.pressure], 0
    mov dword [rbx + Tablet.distance], 0
    mov dword [rbx + Tablet.tilt_x], 0
    mov dword [rbx + Tablet.tilt_y], 0
    mov dword [rbx + Tablet.rotation], 0
    mov dword [rbx + Tablet.slider], 0
    mov dword [rbx + Tablet.wheel], 0
    mov dword [rbx + Tablet.buttons], 0
    mov byte [rbx + Tablet.proximity], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; tablet_process
;   Process tablet event
; ---------------------------------------------------------------------------
global tablet_process
tablet_process:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi      ; type
    mov r13d, edx      ; value
    mov r14, rcx       ; x
    mov r15, r8        ; y
    ASSERT_PTR rbx

    cmp r12d, 0
    je .proximity
    cmp r12d, 1
    je .motion
    cmp r12d, 2
    je .pressure
    cmp r12d, 3
    je .tilt
    cmp r12d, 4
    je .rotation
    cmp r12d, 5
    je .button
    cmp r12d, 6
    je .wheel
    cmp r12d, 7
    je .tool_change
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.proximity:
    mov byte [rbx + Tablet.proximity], r13b
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.motion:
    mov dword [rbx + Tablet.x], r14d
    mov dword [rbx + Tablet.y], r15d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.pressure:
    mov dword [rbx + Tablet.pressure], r13d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.tilt:
    mov dword [rbx + Tablet.tilt_x], r14d
    mov dword [rbx + Tablet.tilt_y], r15d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rotation:
    mov dword [rbx + Tablet.rotation], r13d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.button:
    test r13d, r13d
    jz .btn_release
    mov eax, [rbx + Tablet.buttons]
    or eax, r13d
    mov [rbx + Tablet.buttons], eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.btn_release:
    mov eax, [rbx + Tablet.buttons]
    and eax, ~r13d
    mov [rbx + Tablet.buttons], eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.wheel:
    mov dword [rbx + Tablet.wheel], r13d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.tool_change:
    mov byte [rbx + Tablet.tool_type], r13b
    mov dword [rbx + Tablet.tool_id], r14d
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global tablet_version
tablet_version: dq 0x010000
