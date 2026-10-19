; Direct scanout -- conservative zero-copy eligibility and backend flip.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define S_CURRENT 48
%define S_Z_ORDER 32
%define SS_BUFFER 0
%define SS_OPAQUE 24
%define SS_TRANSFORM 40
%define SS_SCALE 44
%define B_WIDTH 8
%define B_HEIGHT 12
%define B_STRIDE 16
%define B_FORMAT 20
%define B_BASE 32
%define B_DMA 40
%define B_ACQUIRE_FENCE 56
%define FORMAT_XRGB8888 1
%define FORMAT_ARGB8888 2

section .text
global direct_scanout_init
direct_scanout_init:
    mov qword [rel active_surface], 0
    mov qword [rel active_output], 0
    xor eax, eax
    ret

global direct_scanout_check
direct_scanout_check:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .fail
    test r12, r12
    jz .fail
    test r13, r13
    jz .fail
    mov r14, [r12 + S_CURRENT + SS_BUFFER]
    test r14, r14
    jz .fail
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r14
    call handle_resolve
    test rax, rax
    jz .fail
    mov r15, rax
    mov eax, [r15 + B_WIDTH]
    cmp eax, [r13 + Output.width]
    jne .fail
    mov eax, [r15 + B_HEIGHT]
    cmp eax, [r13 + Output.height]
    jne .fail
    cmp dword [r12 + S_CURRENT + SS_TRANSFORM], 0
    jne .fail
    cmp qword [r12 + S_CURRENT + SS_SCALE], 1 << 16
    jne .fail
    mov eax, [r15 + B_FORMAT]
    cmp eax, FORMAT_XRGB8888
    je .format_ok
    cmp eax, FORMAT_ARGB8888
    jne .fail
.format_ok:
    cmp qword [r15 + B_DMA], 0
    je .fail
    mov eax, [r13 + Output.width]
    shl eax, 2
    cmp [r15 + B_STRIDE], eax
    jb .fail
    ; Opaque region must contain the complete output rectangle.
    mov rax, [r12 + S_CURRENT + SS_OPAQUE]
    test rax, rax
    jz .fail
    cmp qword [rax + Region.count], 0
    je .fail
    mov rax, [rax + Region.rects]
    cmp dword [rax], 0
    jg .fail
    cmp dword [rax + 4], 0
    jg .fail
    mov ecx, [rax]
    add ecx, [rax + 8]
    cmp ecx, [r13 + Output.width]
    jl .fail
    mov ecx, [rax + 4]
    add ecx, [rax + 12]
    cmp ecx, [r13 + Output.height]
    jl .fail
    ; No surface may have a greater z key.
    mov rdi, [rbx + Server.z_order_tree]
    test rdi, rdi
    jz .eligible
    call rbtree_max
    sar rax, 32
    cmp rax, [r12 + S_Z_ORDER]
    jg .fail
.eligible:
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global direct_scanout_enable
direct_scanout_enable:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    call direct_scanout_check
    test rax, rax
    jz .fail
    mov r14, [r12 + S_CURRENT + SS_BUFFER]
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r14
    call handle_resolve
    test rax, rax
    jz .fail
    mov rdx, rax
    mov ecx, [rax + B_ACQUIRE_FENCE]
    mov rdi, [r13 + Output.backend]
    mov rsi, r13
    call backend_flip
    test rax, rax
    js .out
    mov [rel active_surface], r12
    mov [rel active_output], r13
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    mov rax, -(EBUF_FORMAT)
    jmp .out

global direct_scanout_disable
direct_scanout_disable:
    mov qword [rel active_surface], 0
    mov qword [rel active_output], 0
    xor eax, eax
    ret

global direct_scanout_is_active
direct_scanout_is_active:
    xor eax, eax
    cmp qword [rel active_surface], 0
    setne al
    ret

section .bss
align 8
active_surface: resq 1
active_output: resq 1

section .data
global direct_scanout_version
direct_scanout_version: dq 0x010100
