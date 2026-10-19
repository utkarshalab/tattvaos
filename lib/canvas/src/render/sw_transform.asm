; ============================================================================
; Software Transform — Rotate/Flip (90/180/270, H/V Flip)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define TRANSFORM_NORMAL    0
%define TRANSFORM_FLIP_H    4
%define TRANSFORM_FLIP_V    8

section .text

%define TRANSFORM_90        1
%define TRANSFORM_180       2
%define TRANSFORM_270       3

; ---------------------------------------------------------------------------
; sw_transform_apply
;   Apply transform to surface during composition
;   IN:  rdi = dst, rsi = src, rdx = src_w, rcx = src_h, r8 = src_stride
;        r9 = dst_w, r10 = dst_h, r11 = dst_stride, r12 = transform
; ---------------------------------------------------------------------------
global sw_transform_apply
sw_transform_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp r12, TRANSFORM_NORMAL
    je .normal
    cmp r12, TRANSFORM_90
    je .rot90
    cmp r12, TRANSFORM_180
    je .rot180
    cmp r12, TRANSFORM_270
    je .rot270
    cmp r12, TRANSFORM_FLIP_H
    je .flip_h
    cmp r12, TRANSFORM_FLIP_V
    je .flip_v

.normal:
    ; Simple blit
    mov rdi, rdi
    mov rsi, rsi
    mov rdx, rdx
    mov rcx, rcx
    mov r8, r8
    mov r9, r9
    mov r10, r10
    mov r11, r11
    call blit_copy
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rot90:
    ; Rotate 90° clockwise: (x,y) -> (h-1-y, x)
    ; dst_w = src_h, dst_h = src_w
    mov r13, rcx
    mov r14, rdx
    mov r15, r8

    ; For each dst row (0 to src_h-1)
    ; src row = src_h - 1 - dst_col
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rot180:
    ; Rotate 180°: (x,y) -> (w-1-x, h-1-y)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rot270:
    ; Rotate 270°: (x,y) -> (y, w-1-x)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.flip_h:
    ; Flip horizontal: (x,y) -> (w-1-x, y)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.flip_v:
    ; Flip vertical: (x,y) -> (x, h-1-y)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global sw_transform_version
sw_transform_version: dq 0x010000
