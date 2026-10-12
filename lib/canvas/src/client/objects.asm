; ============================================================================
; Client Objects — Local Handle Map (server handle <-> user pointer)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

struc ClientObjMap {
    .entries:       resq 1
    .cap:           resq 1
    .count:         resq 1
}
%define ClientObjMap_size    24

global client_objects_init
client_objects_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, 128 * 16
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + ClientObjMap.entries], rax
    mov qword [rbx + ClientObjMap.cap], 128
    mov qword [rbx + ClientObjMap.count], 0
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

global client_objects_add
client_objects_add:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + ClientObjMap.count]
    cmp rax, [rbx + ClientObjMap.cap]
    jae .full
    mov rdx, [rbx + ClientObjMap.entries]
    mov [rdx + rax * 16], rsi
    mov [rdx + rax * 16 + 8], rdx
    inc qword [rbx + ClientObjMap.count]
    xor rax, rax
    ret
.full:
    RETURN_ERROR ENOSPC

global client_objects_find
client_objects_find:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + ClientObjMap.entries]
    mov rcx, [rbx + ClientObjMap.count]
    xor edx, edx
.loop:
    cmp rdx, rcx
    jae .none
    cmp [rax + rdx * 16], rsi
    je .found
    inc rdx
    jmp .loop
.found:
    mov rax, [rax + rdx * 16 + 8]
    ret
.none:
    xor rax, rax
    ret

section .data
global canvas_objects_version
canvas_objects_version: dq 0x010000
