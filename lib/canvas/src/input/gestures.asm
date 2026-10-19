; ============================================================================
; Gestures — Pinch, Swipe, Rotate Recognition
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"

; struct offsets (hoisted above use)
%define GESTURE_PINCH       1
%define GESTURE_SWIPE       2
%define GESTURE_ROTATE      3
%define GESTURE_TAP         4
%define GESTURE_HOLD        5
%define Gesture_SIZE 64
%define GESTURE_STATE_NONE     0
%define GESTURE_STATE_STARTED  1
%define GESTURE_STATE_UPDATED  2
%define GESTURE_STATE_ENDED    3
%define GESTURE_STATE_CANCELLED 4

section .text


struc Gesture
    .type:          resd 1
    .state:         resd 1
    .fingers:       resd 1
    .center_x:      resd 1
    .center_y:      resd 1
    .start_x:       resd 1
    .start_y:       resd 1
    .prev_x:        resd 1
    .prev_y:        resd 1
    .scale:         resq 1
    .rotation:      resq 1
    .velocity_x:    resd 1
    .velocity_y:    resd 1
    .timer:         resq 1
endstruc


; ---------------------------------------------------------------------------
; gestures_init
; ---------------------------------------------------------------------------
global gestures_init
gestures_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; gestures_process_touch
;   Process touch for gesture recognition
; ---------------------------------------------------------------------------
global gestures_process_touch
gestures_process_touch:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Input touch record: action, finger count, x, y.
    mov eax, [r12]
    mov ecx, [r12 + 4]
    mov [rbx + Gesture.fingers], ecx
    cmp eax, 0
    je .begin
    cmp eax, 2
    je .end
    mov eax, [r12 + 8]
    mov edx, [r12 + 12]
    mov [rbx + Gesture.prev_x], eax
    mov [rbx + Gesture.prev_y], edx
    mov [rbx + Gesture.center_x], eax
    mov [rbx + Gesture.center_y], edx
    mov dword [rbx + Gesture.state], GESTURE_STATE_UPDATED
    cmp ecx, 2
    jb .tap
    mov dword [rbx + Gesture.type], GESTURE_PINCH
    jmp .recognized
.tap:
    mov dword [rbx + Gesture.type], GESTURE_SWIPE
.recognized:
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.begin:
    mov eax, [r12 + 8]
    mov edx, [r12 + 12]
    mov [rbx + Gesture.start_x], eax
    mov [rbx + Gesture.start_y], edx
    mov [rbx + Gesture.center_x], eax
    mov [rbx + Gesture.center_y], edx
    mov dword [rbx + Gesture.state], GESTURE_STATE_STARTED
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.end:
    mov dword [rbx + Gesture.state], GESTURE_STATE_ENDED
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; gestures_get
;   Get current gesture
; ---------------------------------------------------------------------------
global gestures_get
gestures_get:
    mov rax, rdi
    ret

section .data
global gestures_version
gestures_version: dq 0x010000
