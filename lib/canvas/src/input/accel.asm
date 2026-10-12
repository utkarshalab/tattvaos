; ============================================================================
; Pointer Acceleration — Adaptive, Flat, Custom Profiles
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"

section .text

struc AccelProfile {
    .type:          resd 1
    .threshold:     resd 1
    .accel_factor:  resq 1
    .decel_factor:  resq 1
    .custom_fn:     resq 1
}
%define AccelProfile_size    32

%define ACCEL_FLAT        0
%define ACCEL_ADAPTIVE    1
%define ACCEL_CUSTOM      2

; ---------------------------------------------------------------------------
; pointer_accel_create
; ---------------------------------------------------------------------------
global pointer_accel_create
pointer_accel_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov rsi, AccelProfile_size
    call arena_alloc
    test rax, rax
    jz .oom

    ; Default: adaptive
    mov dword [rax + AccelProfile.type], ACCEL_ADAPTIVE
    mov dword [rax + AccelProfile.threshold], 4
    mov rax, FIX_ONE
    shl rax, 1  ; 2.0
    mov qword [rax + AccelProfile.accel_factor], rax
    mov rax, FIX_ONE
    shr rax, 1  ; 0.5
    mov qword [rax + AccelProfile.decel_factor], rax
    mov qword [rax + AccelProfile.custom_fn], 0

    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; pointer_accel_apply
;   Apply acceleration to delta
;   IN:  rdi = accel_profile*, rsi = dx, rdx = dy
;   OUT: rax = new dx, rdx = new dy
; ---------------------------------------------------------------------------
global pointer_accel_apply
pointer_accel_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov eax, [rbx + AccelProfile.type]
    cmp eax, ACCEL_FLAT
    je .flat
    cmp eax, ACCEL_ADAPTIVE
    je .adaptive
    cmp eax, ACCEL_CUSTOM
    je .custom

.flat:
    mov rax, r12
    mov rdx, r13
    ret

.adaptive:
    ; Calculate velocity
    mov r14, r12
    imul r14, r14
    mov rax, r13
    imul rax, rax
    add r14, rax
    ; sqrt(velocity^2)
    ; For simplicity, use linear approximation
    ; If velocity > threshold, apply acceleration
    mov eax, r12
    imul eax, eax
    mov edx, r13
    imul edx, edx
    add eax, edx
    ; Compare with threshold^2
    mov edx, [rbx + AccelProfile.threshold]
    imul edx, edx
    cmp eax, edx
    jle .flat

    ; Apply acceleration factor
    mov rax, r12
    imul rax, [rbx + AccelProfile.accel_factor]
    sar rax, 16
    mov rdx, r13
    imul rdx, [rbx + AccelProfile.accel_factor]
    sar rdx, 16
    ret

.custom:
    ; Call custom function
    mov rax, [rbx + AccelProfile.custom_fn]
    test rax, rax
    jz .flat
    mov rdi, r12
    mov rsi, r13
    call rax
    ret

.flat:
    mov rax, r12
    mov rdx, r13
    ret

; ---------------------------------------------------------------------------
; pointer_accel_set_profile
; ---------------------------------------------------------------------------
global pointer_accel_set_profile
pointer_accel_set_profile:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov dword [rbx + AccelProfile.type], r12d
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; pointer_accel_set_threshold
; ---------------------------------------------------------------------------
global pointer_accel_set_threshold
pointer_accel_set_threshold:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + AccelProfile.threshold], esi
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; pointer_accel_set_factor
; ---------------------------------------------------------------------------
global pointer_accel_set_factor
pointer_accel_set_factor:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + AccelProfile.accel_factor], rsi
    mov qword [rbx + AccelProfile.decel_factor], rdx
    xor rax, rax
    ret

section .data
global accel_version
accel_version: dq 0x010000