; ============================================================================
; Host Decode Tool — host_decode.asm
; Usage: host_decode <image> <out.raw>
; Decodes any format image_decode supports and writes a 16-byte header
; (u32 width, height, stride, format) followed by width*4 bytes per row.
; Exit status: 0 ok, 1 usage, 2 read error, 3 decode failed, 4 write error.
; Used by tests/host/compare_images.py to check decoders against a reference.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

%define HOST_SYS_READ   0
%define HOST_SYS_WRITE  1
%define HOST_SYS_OPEN   2
%define HOST_SYS_CLOSE  3
%define HOST_SYS_FSTAT  5
%define HOST_SYS_MMAP   9
%define HOST_ARENA_SIZE (512 * 1024 * 1024)

extern arena_init
extern image_decode
extern ut_mem_alloc
extern ut_task_exit

section .text

global _start
_start:
    mov r12, [rsp + 16]         ; argv[1]
    mov r13, [rsp + 24]         ; argv[2]
    mov rax, [rsp]              ; argc
    and rsp, -16
    cmp rax, 3
    jne .usage

    ; Map the input file read-only.
    mov rdi, r12
    xor esi, esi                ; O_RDONLY
    mov eax, HOST_SYS_OPEN
    syscall
    test rax, rax
    js .read_fail
    mov r14, rax                ; fd
    sub rsp, 144                ; struct stat
    mov rdi, r14
    mov rsi, rsp
    mov eax, HOST_SYS_FSTAT
    syscall
    mov r15, [rsp + 48]         ; st_size
    add rsp, 144
    test rax, rax
    js .read_fail
    test r15, r15
    jz .read_fail
    xor edi, edi
    mov rsi, r15
    mov edx, 1                  ; PROT_READ
    mov r10d, 2                 ; MAP_PRIVATE
    mov r8, r14
    xor r9d, r9d
    mov eax, HOST_SYS_MMAP
    syscall
    test rax, rax
    js .read_fail
    mov rbx, rax                ; input bytes
    mov rdi, r14
    mov eax, HOST_SYS_CLOSE
    syscall

    ; Arena backed by one large host mapping.
    mov rdi, HOST_ARENA_SIZE
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .decode_fail
    lea rdi, [rel decode_arena]
    mov rsi, rax
    mov rdx, HOST_ARENA_SIZE
    call arena_init
    test rax, rax
    js .decode_fail

    lea rdi, [rel decode_arena]
    mov rsi, rbx
    mov rdx, r15
    xor ecx, ecx
    xor r8d, r8d
    call image_decode
    test rax, rax
    jz .decode_fail
    mov rbx, rax                ; PixBuf*

    ; Open the output file.
    mov rdi, r13
    mov esi, 0x241              ; O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0644o
    mov eax, HOST_SYS_OPEN
    syscall
    test rax, rax
    js .write_fail
    mov r14, rax

    mov eax, [rbx + PixBuf_width]
    mov [rel out_header], eax
    mov eax, [rbx + PixBuf_height]
    mov [rel out_header + 4], eax
    mov eax, [rbx + PixBuf_stride]
    mov [rel out_header + 8], eax
    mov eax, [rbx + PixBuf_format]
    mov [rel out_header + 12], eax
    lea rsi, [rel out_header]
    mov edx, 16
    call write_all
    test rax, rax
    js .write_fail

    mov r12, [rbx + PixBuf_data]
    mov r13, [rbx + PixBuf_height]
    mov r15, [rbx + PixBuf_width]
    shl r15, 2
.row:
    test r13, r13
    jz .ok
    mov rsi, r12
    mov rdx, r15
    call write_all
    test rax, rax
    js .write_fail
    add r12, [rbx + PixBuf_stride]
    dec r13
    jmp .row

.ok:
    xor edi, edi
    jmp ut_task_exit
.usage:
    lea rsi, [rel usage_msg]
    mov edx, usage_len
    mov edi, 2
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
.write_fail:
    mov edi, 4
    jmp ut_task_exit

; write_all: r14 = fd, rsi = buffer, rdx = length -> rax = 0 or -errno
write_all:
    push rbx
    push r12
    mov rbx, rsi
    mov r12, rdx
.loop:
    test r12, r12
    jz .done
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r12
    mov eax, HOST_SYS_WRITE
    syscall
    test rax, rax
    js .out
    jz .short
    add rbx, rax
    sub r12, rax
    jmp .loop
.short:
    mov rax, -(EIO)
    jmp .out
.done:
    xor eax, eax
.out:
    pop r12
    pop rbx
    ret

section .rodata

usage_msg:      db "usage: host_decode <image> <out.raw>", 10
usage_len       equ $ - usage_msg

section .bss

alignb 16
decode_arena:   resb 64
out_header:     resd 4
