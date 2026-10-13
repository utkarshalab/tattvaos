; ============================================================================
; Flatten — Quadratic Bezier Subdivision to Line Segments
; flatten_quad(ctx, pts): pts = x0,y0,x1,y1,x2,y2 (6 x i64, font units)
; Emits LINE verbs for each accepted segment endpoint
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"

; struct offsets (hoisted above use)
%define FlattenCtx_size    32
%define FLATTEN_MAX_DEPTH   10

section .text

struc FlattenCtx
    .out:           resq 1
    .count:         resq 1
    .cap:           resq 1
    .tolerance:     resq 1
endstruc


; ---------------------------------------------------------------------------
; flatten_emit_line — IN: rdi=ctx, rsi=x, rdx=y
; ---------------------------------------------------------------------------
global flatten_emit_line
flatten_emit_line:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + FlattenCtx.count]
    cmp rax, [rbx + FlattenCtx.cap]
    jae .full
    mov rcx, [rbx + FlattenCtx.out]
    test rcx, rcx
    jz .fail
    imul rax, 9
    add rcx, rax
    mov byte [rcx + 0], VERB_LINE
    mov [rcx + 1], esi
    mov [rcx + 5], edx
    inc qword [rbx + FlattenCtx.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret
.full:
    mov rax, -ENOSPC
    EPILOGUE_RESTORE rbx
    ret
.fail:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; flatten_quad
;   IN: rdi = ctx, rsi = pts[6]
; ---------------------------------------------------------------------------
global flatten_quad
flatten_quad:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    xor edx, edx
    call flatten_rec
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; flatten_rec
;   IN: rdi = ctx, rsi = pts[6] (x0,y0,x1,y1,x2,y2 i64), rdx = depth
;   Frame: [rsp+0..40] own coords, [rsp+48] depth. Child frame below.
; ---------------------------------------------------------------------------
global flatten_rec
flatten_rec:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi   ; ctx
    ASSERT_PTR rbx
    ASSERT_PTR rsi
    sub rsp, 64
    mov rax, [rsi + 0]
    mov [rsp + 0], rax
    mov rax, [rsi + 8]
    mov [rsp + 8], rax
    mov rax, [rsi + 16]
    mov [rsp + 16], rax
    mov rax, [rsi + 24]
    mov [rsp + 24], rax
    mov rax, [rsi + 32]
    mov [rsp + 32], rax
    mov rax, [rsi + 40]
    mov [rsp + 40], rax
    mov [rsp + 48], rdx
    ; flatness d = |x1-(x0+x2)/2| + |y1-(y0+y2)/2|
    mov rax, [rsp + 0]
    add rax, [rsp + 32]
    sar rax, 1
    sub rax, [rsp + 16]
    cmp rax, 0
    jge .dx_ok
    neg rax
.dx_ok:
    mov rcx, rax
    mov rax, [rsp + 8]
    add rax, [rsp + 40]
    sar rax, 1
    sub rax, [rsp + 24]
    cmp rax, 0
    jge .dy_ok
    neg rax
.dy_ok:
    add rax, rcx
    cmp rax, [rbx + FlattenCtx.tolerance]
    jbe .emit
    cmp qword [rsp + 48], FLATTEN_MAX_DEPTH
    jae .emit
    ; q0=(P0+C)/2 -> r8/r9, c1=(C+P2)/2 -> r14/r15, m=(q0+c1)/2 -> r12/r13
    ; (r12-r15 callee-saved: survive the child calls)
    mov rax, [rsp + 0]
    add rax, [rsp + 16]
    sar rax, 1
    mov r8, rax    ; q0x
    mov rax, [rsp + 8]
    add rax, [rsp + 24]
    sar rax, 1
    mov r9, rax    ; q0y
    mov rax, [rsp + 16]
    add rax, [rsp + 32]
    sar rax, 1
    mov r14, rax   ; c1x
    mov rax, [rsp + 24]
    add rax, [rsp + 40]
    sar rax, 1
    mov r15, rax   ; c1y
    mov rax, r8
    add rax, r14
    sar rax, 1
    mov r12, rax   ; mx
    mov rax, r9
    add rax, r15
    sar rax, 1
    mov r13, rax   ; my
    mov rax, [rsp + 48]  ; depth
    inc rax
    push rax       ; child depth (balanced below)
    ; left half: P0, q0, m
    sub rsp, 48
    mov rax, [rsp + 48 + 8 + 0]
    mov [rsp + 0], rax
    mov rax, [rsp + 48 + 8 + 8]
    mov [rsp + 8], rax
    mov [rsp + 16], r8
    mov [rsp + 24], r9
    mov [rsp + 32], r12
    mov [rsp + 40], r13
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, [rsp + 48]
    call flatten_rec
    test rax, rax
    jnz .fail_child
    ; right half: m, c1, P2
    mov [rsp + 0], r12
    mov [rsp + 8], r13
    mov [rsp + 16], r14
    mov [rsp + 24], r15
    mov rax, [rsp + 48 + 8 + 32]
    mov [rsp + 32], rax
    mov rax, [rsp + 48 + 8 + 40]
    mov [rsp + 40], rax
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, [rsp + 48]
    call flatten_rec
    add rsp, 48
    add rsp, 8
    add rsp, 64
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail_child:
    add rsp, 48
    add rsp, 8
    add rsp, 64
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.emit:
    mov rdi, rbx
    mov esi, [rsp + 32]
    mov edx, [rsp + 40]
    call flatten_emit_line
    add rsp, 64
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global flatten_version
flatten_version: dq 0x010000
