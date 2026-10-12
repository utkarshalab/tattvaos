; ============================================================================
; Pointer — Mouse/Touchpad Handling, Acceleration, Constraints
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"

section .text

struc Pointer {
    .seat:          resq 1
    .x:             resd 1
    .y:             resd 1
    .buttons:       resd 1
    .accel:         resq 1
    .constraints:   resq 1
    .grab:          resq 1
    .confined:      resb 1
    .locked:        resb 1
    .lock_x:        resd 1
    .lock_y:        resd 1
    .surface:       resq 1
}
%define Pointer_size    80

%define BUTTON_LEFT       (1 << 0)
%define BUTTON_MIDDLE     (1 << 1)
%define BUTTON_RIGHT      (1 << 2)
%define BUTTON_BACK       (1 << 3)
%define BUTTON_FORWARD    (1 << 4)

%define ACCEL_PROFILE_FLAT        0
%define ACCEL_PROFILE_ADAPTIVE    1
%define ACCEL_PROFILE_CUSTOM      2

; ---------------------------------------------------------------------------
; pointer_create
;   Create pointer for seat
; ---------------------------------------------------------------------------
global pointer_create
pointer_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate pointer
    mov rdi, [rbx + Server.arena]
    mov rsi, Pointer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + Pointer.seat], r12
    mov dword [rbx + Pointer.x], 0
    mov dword [rbx + Pointer.y], 0
    mov dword [rbx + Pointer.buttons], 0
    mov qword [rbx + Pointer.accel], 0
    mov qword [rbx + Pointer.constraints], 0
    mov qword [rbx + Pointer.grab], 0
    mov byte [rbx + Pointer.confined], 0
    mov byte [rbx + Pointer.locked], 0
    mov dword [rbx + Pointer.lock_x], 0
    mov dword [rbx + Pointer.lock_y], 0
    mov qword [rbx + Pointer.surface], 0

    ; Create acceleration profile
    call pointer_accel_create
    test rax, rax
    jz .oom
    mov [rbx + Pointer.accel], rax

    ; Create constraints
    call constraints_create
    test rax, rax
    jz .oom
    mov [rbx + Pointer.constraints], rax

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; pointer_set_position
;   Set pointer position (clamped to output)
; ---------------------------------------------------------------------------
global pointer_set_position
pointer_set_position:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    ; Clamp to output bounds
    mov r14, [rbx + Pointer.seat]
    mov r14, [r14 + Seat.pointer]
    ; TODO: Get output bounds

    mov [rbx + Pointer.x], r12d
    mov [rbx + Pointer.y], r13d

    ; TODO: Send motion event to clients

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; pointer_warp
;   Warp pointer to absolute position
; ---------------------------------------------------------------------------
global pointer_warp
pointer_warp:
    PROLOGUE
    call pointer_set_position
    ret

; ---------------------------------------------------------------------------
; pointer_set_button
;   Set button state
; ---------------------------------------------------------------------------
global pointer_set_button
pointer_set_button:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    test r13d, r13d
    jz .release

    ; Press
    mov eax, [rbx + Pointer.buttons]
    or eax, r12d
    mov [rbx + Pointer.buttons], eax
    ret

.release:
    ; Release
    mov eax, [rbx + Pointer.buttons]
    and eax, ~r12d
    mov [rbx + Pointer.buttons], eax
    ret

; ---------------------------------------------------------------------------
; pointer_get_position
; ---------------------------------------------------------------------------
global pointer_get_position
pointer_get_position:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Pointer.x]
    mov edx, [rdi + Pointer.y]
    ret

; ---------------------------------------------------------------------------
; pointer_get_buttons
; ---------------------------------------------------------------------------
global pointer_get_buttons
pointer_get_buttons:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + Pointer.buttons]
    ret

section .data
global pointer_version
pointer_version: dq 0x010000