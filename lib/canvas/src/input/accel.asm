; ============================================================================
; Pointer Acceleration — Adaptive, Flat, Custom Profiles
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"
%include "inc/fixed.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define AccelProfile_SIZE 32
%define ACCEL_FLAT        0
%define ACCEL_ADAPTIVE    1
%define ACCEL_CUSTOM      2

section .text

struc AccelProfile
    .type:          resd 1
    .threshold:     resd 1
    .accel_factor:  resq 1
    .decel_factor:  resq 1
    .custom_fn:     resq 1
endstruc


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

    mov rbx, rax
    ; Default: adaptive
    mov dword [rbx + AccelProfile.type], ACCEL_ADAPTIVE
    mov dword [rbx + AccelProfile.threshold], 4
    mov rcx, FIX_ONE
    shl rcx, 1  ; 2.0
    mov qword [rbx + AccelProfile.accel_factor], rcx
    mov rcx, FIX_ONE
    shr rcx, 1  ; 0.5
    mov qword [rbx + AccelProfile.decel_factor], rcx
    mov qword [rbx + AccelProfile.custom_fn], 0
    mov rax, rbx

    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

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
    EPILOGUE_RESTORE rbx, r12, r13, r14
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
    mov eax, r12d
    imul eax, eax
    mov edx, r13d
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
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.custom:
    ; Call custom function
    mov rax, [rbx + AccelProfile.custom_fn]
    test rax, rax
    jz .custom_fallback
    mov rdi, r12
    mov rsi, r13
    call rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.custom_fallback:
    mov rax, r12
    mov rdx, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14
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
    EPILOGUE_RESTORE rbx, r12
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
    leave
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
    EPILOGUE_RESTORE rbx
    ret

section .data
global accel_version
accel_version: dq 0x010000
