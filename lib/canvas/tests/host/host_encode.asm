; ============================================================================
; host_encode — Canvas's image encoders as a host program
; ============================================================================
; host_encode <input> <output> <p|q|j> [quality]: the input decoded
; (image_decode), then encoded as PNG (png_encode), QOI (qoi_encode) or
; JPEG (jpeg_encode, quality 1 to 100, 90 by default) and written. For
; tests/host/encode_check.py, which reads each back with a reference
; decoder. Exit 0; 1 usage, 2 read, 3 decode, 4 encode, 5 write.
; Development-machine test tooling only.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

%define HOST_SYS_WRITE  1
%define HOST_SYS_OPEN   2
%define HOST_SYS_CLOSE  3
%define HOST_SYS_FSTAT  5
%define HOST_SYS_MMAP   9
%define HOST_ARENA_SIZE (512 * 1024 * 1024)

extern arena_init
extern image_decode
extern png_encode
extern qoi_encode
extern jpeg_encode
extern ut_mem_alloc
extern ut_task_exit

section .text

global _start
_start:
    mov rax, [rsp]                      ; argc
    cmp rax, 4
    jb .usage
    cmp rax, 5
    ja .usage
    mov r12, [rsp + 16]                 ; input
    mov r13, [rsp + 24]                 ; output
    mov rcx, [rsp + 32]                 ; format
    movzx ebp, byte [rcx]
    mov r15d, 90                        ; quality
    cmp rax, 5
    jb .args
    mov rsi, [rsp + 40]
    xor r15d, r15d
.digit:
    movzx eax, byte [rsi]
    test eax, eax
    jz .args
    sub eax, '0'
    cmp eax, 9
    ja .usage
    imul r15d, r15d, 10
    add r15d, eax
    inc rsi
    jmp .digit
.args:
    and rsp, -16
    mov rdi, r12
    call map_file
    test rax, rax
    js .read_fail
    mov rbx, rax
    mov r14, rdx
    mov rdi, HOST_ARENA_SIZE
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .decode_fail
    lea rdi, [rel arena]
    mov rsi, rax
    mov rdx, HOST_ARENA_SIZE
    call arena_init
    test rax, rax
    js .decode_fail
    lea rdi, [rel arena]
    mov rsi, rbx
    mov rdx, r14
    xor ecx, ecx
    xor r8d, r8d
    call image_decode
    test rax, rax
    jle .decode_fail
    lea rdi, [rel arena]
    mov rsi, rax
    cmp ebp, 'p'
    je .png
    cmp ebp, 'q'
    je .qoi
    cmp ebp, 'j'
    jne .usage
    mov edx, r15d
    call jpeg_encode
    jmp .encoded
.png:
    call png_encode
    jmp .encoded
.qoi:
    call qoi_encode
.encoded:
    test rax, rax
    js .encode_fail
    jz .encode_fail
    mov rbx, rax
    mov r12, rdx
    mov rdi, r13
    mov esi, 0x241                      ; O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0644o
    mov eax, HOST_SYS_OPEN
    syscall
    test rax, rax
    js .write_fail
    mov r14, rax
.write:
    test r12, r12
    jz .written
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r12
    mov eax, HOST_SYS_WRITE
    syscall
    test rax, rax
    jle .write_fail
    add rbx, rax
    sub r12, rax
    jmp .write
.written:
    mov rdi, r14
    mov eax, HOST_SYS_CLOSE
    syscall
    xor edi, edi
    jmp ut_task_exit
.usage:
    and rsp, -16
    mov edi, 2
    lea rsi, [rel usage_msg]
    mov edx, usage_len
    mov eax, HOST_SYS_WRITE
    syscall
    mov edi, 1
    jmp ut_task_exit
.read_fail:
    mov edi, 2
    jmp ut_task_exit
.decode_fail:
    mov edi, 3
    jmp ut_task_exit
.encode_fail:
    mov edi, 4
    jmp ut_task_exit
.write_fail:
    mov edi, 5
    jmp ut_task_exit

; rdi = a path -> rax = its bytes mapped, rdx = their length; rax negative
map_file:
    push rbx
    push r12
    push r13
    mov eax, HOST_SYS_OPEN
    xor esi, esi
    syscall
    test rax, rax
    js .out
    mov rbx, rax
    sub rsp, 144                        ; struct stat
    mov rdi, rbx
    mov rsi, rsp
    mov eax, HOST_SYS_FSTAT
    syscall
    mov r12, [rsp + 48]                 ; st_size
    add rsp, 144
    test rax, rax
    js .close
    mov rax, -(EIO)
    test r12, r12
    jz .close
    xor edi, edi
    mov rsi, r12
    mov edx, 1                          ; PROT_READ
    mov r10d, 2                         ; MAP_PRIVATE
    mov r8, rbx
    xor r9d, r9d
    mov eax, HOST_SYS_MMAP
    syscall
.close:
    mov r13, rax
    mov rdi, rbx
    mov eax, HOST_SYS_CLOSE
    syscall
    mov rax, r13
    mov rdx, r12
.out:
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
usage_msg:  db "usage: host_encode <input> <output> <p|q|j> [quality]", 10
usage_len   equ $ - usage_msg

section .bss
alignb 16
arena:      resb 32
