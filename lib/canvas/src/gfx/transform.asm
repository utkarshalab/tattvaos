; ============================================================================
; Transform — Rotate, Flip (90/180/270, horizontal/vertical)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

; struct offsets (hoisted above use)
%define TRANSFORM_NORMAL    0
%define TRANSFORM_FLIP_H    4
%define TRANSFORM_FLIP_V    8

section .text

%define TRANSFORM_90        1
%define TRANSFORM_180       2
%define TRANSFORM_270       3

; ---------------------------------------------------------------------------
; transform_apply
;   Apply transform to pixel buffer
;   IN:  rdi = dst, rsi = src, rdx = width, rcx = height, r8 = stride, r9 = transform
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global transform_apply
transform_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jz .done
    test r14, r14
    jz .done

    cmp r9, TRANSFORM_NORMAL
    je .normal
    cmp r9, TRANSFORM_90
    je .rot90
    cmp r9, TRANSFORM_180
    je .rot180
    cmp r9, TRANSFORM_270
    je .rot270
    cmp r9, TRANSFORM_FLIP_H
    je .flip_h
    cmp r9, TRANSFORM_FLIP_V
    je .flip_v
    jmp .done

.normal:
    call blit_copy
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rot90:
    ; Rotate 90° clockwise: (x,y) -> (h-1-y, x)
    .row_loop:
        push r14
        push rbx
        mov r14, r13

        .pixel_loop:
            mov eax, [r12 + (r14 - 1) * 4]
            mov [rbx], eax
            add rbx, 4
            add r12, r15
            dec r14
            jnz .pixel_loop

        pop rbx
        pop r14
        sub r12, r15
        shl r13, 2
        add r12, r13
        sub r12, r15
        dec r15
        jnz .row_loop
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rot180:
    ; Rotate 180°: (x,y) -> (w-1-x, h-1-y)
    mov r12, rsi
    add r12, r14
    imul r12, r15
    sub r12, 4

    .row_loop:
        push r14
        push rbx
        mov r14, r13

        .pixel_loop:
            mov eax, [r12]
            mov [rbx], eax
            sub r12, 4
            add rbx, 4
            dec r14
            jnz .pixel_loop

        pop rbx
        pop r14
        sub r12, r15
        sub r12, r13
        shl r13, 2
        sub r12, r13
        add r12, r15
        dec r15
        jnz .row_loop
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.rot270:
    ; Rotate 270°: (x,y) -> (y, w-1-x)
    .row_loop:
        push r14
        push rbx
        mov r14, r13

        .pixel_loop:
            mov eax, [r12 + r14 * 4]
            mov [rbx], eax
            add rbx, 4
            sub r12, r15
            dec r14
            jnz .pixel_loop

        pop rbx
        pop r14
        add r12, r15
        shl r13, 2
        sub r12, r13
        dec r15
        jnz .row_loop
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.flip_h:
    ; Flip horizontal: (x,y) -> (w-1-x, y)
    .row_loop:
        push r14
        push rbx
        push r12
        mov r14, r13
        add r12, r13
        shl r12, 2
        sub r12, 4

        .pixel_loop:
            mov eax, [r12]
            mov [rbx], eax
            sub r12, 4
            add rbx, 4
            dec r14
            jnz .pixel_loop

        pop r12
        pop rbx
        pop r14
        add rbx, r15
        add r12, r15
        dec r15
        jnz .row_loop
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.flip_v:
    ; Flip vertical: (x,y) -> (x, h-1-y)
    mov r12, rsi
    add r12, r14
    imul r12, r15
    sub r12, r15

    .row_loop:
        push r14
        push rbx
        mov r14, r13

        .pixel_loop:
            mov eax, [r12]
            mov [rbx], eax
            add rbx, 4
            add r12, 4
            dec r14
            jnz .pixel_loop

        pop rbx
        pop r14
        sub r12, r15
        sub r12, r13
        shl r13, 2
        sub r12, r13
        add r12, r15
        dec r15
        jnz .row_loop
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data

global transform_version
transform_version: dq 0x010000
