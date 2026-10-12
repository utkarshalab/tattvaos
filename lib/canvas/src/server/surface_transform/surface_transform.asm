; ============================================================================
; Surface Transform — Scale and Transform State
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"

section .text

; ---------------------------------------------------------------------------
; surface_transform_init
; ---------------------------------------------------------------------------
global surface_transform_init
surface_transform_init:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_transform_apply
;   Apply transform to surface coordinates
;   IN:  rdi = surface*, rsi = x, rdx = y, rcx = out_x*, r8 = out_y*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global surface_transform_apply
surface_transform_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    ; Get transform state
    mov eax, [rbx + Surface.current + SurfaceState.transform]
    mov r12d, [rbx + Surface.current + SurfaceState.scale]

    ; Identity?
    test eax, eax
    jz .identity

    ; Apply rotation
    cmp al, TRANSFORM_90
    je .rot90
    cmp al, TRANSFORM_180
    je .rot180
    cmp al, TRANSFORM_270
    je .rot270
    cmp al, TRANSFORM_FLIP_H
    je .flip_h
    cmp al, TRANSFORM_FLIP_V
    je .flip_v

.identity:
    mov [r14], rsi
    mov [r8], rdx
    ret

.rot90:
    ; (x, y) -> (h - y, x)
    ; Need surface dimensions
    mov eax, [rbx + Surface.current + SurfaceState.buf_x]
    sub eax, r13
    mov [r14], eax
    mov [r8], rsi
    ret

.rot180:
    ; (x, y) -> (w - x, h - y)
    ; TODO
    ret

.rot270:
    ; (x, y) -> (y, w - x)
    ; TODO
    ret

.flip_h:
    ; (x, y) -> (w - x, y)
    ; TODO
    ret

.flip_v:
    ; (x, y) -> (x, h - y)
    ; TODO
    ret

; ---------------------------------------------------------------------------
; surface_transform_rect
;   Transform rectangle
; ---------------------------------------------------------------------------
global surface_transform_rect
surface_transform_rect:
    PROLOGUE
    ; TODO
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_transform_region
;   Transform region
; ---------------------------------------------------------------------------
global surface_transform_region
surface_transform_region:
    PROLOGUE
    ; TODO
    xor rax, rax
    ret

section .data
global surface_transform_version
surface_transform_version: dq 0x010000