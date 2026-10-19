; Surface coordinate transforms (Q16.16 scale followed by orthogonal transform).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define TRANSFORM_NORMAL 0
%define TRANSFORM_90 1
%define TRANSFORM_180 2
%define TRANSFORM_270 3
%define TRANSFORM_FLIP_H 4
%define TRANSFORM_FLIP_V 5

section .text

global surface_transform_init
surface_transform_init:
    xor eax, eax
    ret

; IN surface*, x, y, out_x*, out_y*. Dimensions and output are logical edges.
global surface_transform_apply
surface_transform_apply:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rcx
    mov r13, r8
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    test r13, r13
    jz .invalid
    movsxd r14, esi              ; x
    movsxd r15, edx              ; y
    movsxd rcx, dword [rbx + Surface.current + SurfaceState.width]
    movsxd rdx, dword [rbx + Surface.current + SurfaceState.height]
    mov eax, [rbx + Surface.current + SurfaceState.transform]
    cmp eax, TRANSFORM_90
    je .r90
    cmp eax, TRANSFORM_180
    je .r180
    cmp eax, TRANSFORM_270
    je .r270
    cmp eax, TRANSFORM_FLIP_H
    je .fh
    cmp eax, TRANSFORM_FLIP_V
    je .fv
    test eax, eax
    jnz .invalid
    jmp .scale
.r90:
    mov rax, rdx
    sub rax, r15
    mov r15, r14
    mov r14, rax
    jmp .scale
.r180:
    sub rcx, r14
    sub rdx, r15
    mov r14, rcx
    mov r15, rdx
    jmp .scale
.r270:
    sub rcx, r14
    mov r14, r15
    mov r15, rcx
    jmp .scale
.fh:
    sub rcx, r14
    mov r14, rcx
    jmp .scale
.fv:
    sub rdx, r15
    mov r15, rdx
.scale:
    movsxd rcx, dword [rbx + Surface.current + SurfaceState.scale]
    test rcx, rcx
    jg .scale_ok
    mov rcx, FIX_ONE
.scale_ok:
    mov rax, r14
    imul rax, rcx
    sar rax, FIX_SHIFT
    mov [r12], rax
    mov rax, r15
    imul rax, rcx
    sar rax, FIX_SHIFT
    mov [r13], rax
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; IN surface*, source rect*, destination rect*. Source and destination may alias.
global surface_transform_rect
surface_transform_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    test r13, r13
    jz .invalid
    movsxd r14, dword [r12]
    movsxd r15, dword [r12 + 4]
    mov rsi, r14
    mov rdx, r15
    mov rcx, rsp
    lea r8, [rsp + 8]
    mov rdi, rbx
    call surface_transform_apply
    test rax, rax
    js .out
    movsxd rsi, dword [r12 + 8]
    add rsi, r14
    movsxd rdx, dword [r12 + 12]
    add rdx, r15
    lea rcx, [rsp + 16]
    lea r8, [rsp + 24]
    mov rdi, rbx
    call surface_transform_apply
    test rax, rax
    js .out
    mov rax, [rsp]
    mov rcx, [rsp + 16]
    cmp rax, rcx
    jle .x_ordered
    xchg rax, rcx
.x_ordered:
    mov [r13], eax
    sub rcx, rax
    mov [r13 + 8], ecx
    mov rax, [rsp + 8]
    mov rcx, [rsp + 24]
    cmp rax, rcx
    jle .y_ordered
    xchg rax, rcx
.y_ordered:
    mov [r13 + 4], eax
    sub rcx, rax
    mov [r13 + 12], ecx
    xor eax, eax
    jmp .out
.invalid:
    mov rax, -(EINVAL)
.out:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; IN surface*, source region*, destination region*. Regions may alias.
global surface_transform_region
surface_transform_region:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .invalid
    test r12, r12
    jz .invalid
    mov r14, [r12 + Region.count]
    mov r15, [r12 + Region.rects]
    cmp r12, r13
    je .in_place
    mov rdi, r13
    call region_clear
.copy_loop:
    test r14, r14
    jz .ok
    mov rdi, rbx
    mov rsi, r15
    mov rdx, rsp
    call surface_transform_rect
    test rax, rax
    js .out
    mov rdi, r13
    mov rsi, rsp
    call region_add_rect
    test rax, rax
    js .out
    add r15, 16
    dec r14
    jmp .copy_loop
.in_place:
    test r14, r14
    jz .ok
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r15
    call surface_transform_rect
    test rax, rax
    js .out
    add r15, 16
    dec r14
    jmp .in_place
.ok:
    xor eax, eax
    jmp .out
.invalid:
    mov rax, -(EINVAL)
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global surface_transform_version
surface_transform_version: dq 0x010100
