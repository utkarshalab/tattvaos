; =============================================================================
; Utkarsha OS — lib/ufont/tests/host/host_bidi.asm
; =============================================================================
; Host tool for tests/host/bidi_check.py (development machine only).
;
;   host_bidi <in.bin> <out.bin>
;       in:  u32 cases; per case u32 direction (0, 1, 2 from the text), u32
;            n, u32 code points[n]
;       out: per case u32 paragraph level, u8 levels[n] (255: removed),
;            u32 m, u32 order[m] (ufont_bidi_reorder)
;
; Exit status: 0 ok, 1 usage, 2 read error, 3 out of memory, 4 write error.
; =============================================================================

%include "ufont.inc"

%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_FSTAT   5
%define SYS_MMAP    9
%define SYS_EXIT    60
%define ARENA_SIZE  (64 * 1024 * 1024)
%define OUT_SIZE    (512 * 1024 * 1024)

extern ufont_bidi
extern ufont_bidi_reorder

section .text

global _start
_start:
    mov rax, [rsp]
    cmp rax, 3
    jne usage
    mov r13, [rsp + 16]                 ; in
    mov r14, [rsp + 24]                 ; out
    and rsp, -16
    mov rdi, ARENA_SIZE
    call map_anon
    mov [rel arena], rax
    mov [rel arena_mark], rax
    add rax, ARENA_SIZE
    mov [rel arena + 8], rax
    mov rdi, OUT_SIZE
    call map_anon
    mov [rel out_buf], rax
    mov [rel out_at], rax
    mov rdi, r13
    call map_file
    test rax, rax
    js read_fail
    mov r15, rax
    mov r12d, [r15]                     ; cases
    lea r13, [r15 + 4]
.case:
    test r12d, r12d
    jz write_out
    dec r12d
    mov rax, [rel arena_mark]
    mov [rel arena], rax
    mov ebx, [r13 + 4]                  ; n
    ; levels go straight into the output after the paragraph level
    mov rbp, [rel out_at]
    lea rdi, [rel arena]
    lea rsi, [r13 + 8]
    mov edx, ebx
    mov ecx, [r13]
    lea r8, [rbp + 4]
    call ufont_bidi
    cmp eax, -1
    je nomem
    mov [rbp], eax
    lea rdi, [rbp + 4]                  ; the order after the levels and its count
    mov esi, ebx
    lea rdx, [rbp + rbx + 8]
    call ufont_bidi_reorder
    mov [rbp + rbx + 4], eax
    lea rax, [rbp + rax * 4]
    lea rax, [rax + rbx + 8]
    mov [rel out_at], rax
    lea r13, [r13 + rbx * 4 + 8]
    jmp .case

nomem:
    mov edi, 3
    jmp exit

write_out:
    mov rdi, r14
    mov eax, SYS_OPEN
    mov esi, 0x241                      ; O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0o644
    syscall
    test rax, rax
    js write_fail
    mov rbx, rax
    mov rsi, [rel out_buf]
    mov rdx, [rel out_at]
    sub rdx, rsi
.write:
    test rdx, rdx
    jz .closed
    mov rdi, rbx
    mov eax, SYS_WRITE
    push rsi
    push rdx
    syscall
    pop rdx
    pop rsi
    test rax, rax
    jle write_fail
    add rsi, rax
    sub rdx, rax
    jmp .write
.closed:
    mov rdi, rbx
    mov eax, SYS_CLOSE
    syscall
    xor edi, edi
    jmp exit

usage:
    mov edi, 1
    jmp exit
read_fail:
    mov edi, 2
    jmp exit
write_fail:
    mov edi, 4
exit:
    mov eax, SYS_EXIT
    syscall

put32:
    mov rdx, [rel out_at]
    mov [rdx], eax
    add qword [rel out_at], 4
    ret

put_bytes:
    mov rdi, [rel out_at]
    rep movsb
    mov [rel out_at], rdi
    ret

map_anon:
    mov rsi, rdi
    xor edi, edi
    mov edx, 3
    mov r10d, 0x22
    mov r8, -1
    xor r9d, r9d
    mov eax, SYS_MMAP
    syscall
    ret

map_file:
    push rbx
    push r12
    push r13
    mov eax, SYS_OPEN
    xor esi, esi
    syscall
    test rax, rax
    js .out
    mov rbx, rax
    sub rsp, 144
    mov rdi, rbx
    mov rsi, rsp
    mov eax, SYS_FSTAT
    syscall
    mov r12, [rsp + 48]
    add rsp, 144
    test rax, rax
    js .close
    mov rax, -5
    test r12, r12
    jz .close
    xor edi, edi
    mov rsi, r12
    mov edx, 1
    mov r10d, 2
    mov r8, rbx
    xor r9d, r9d
    mov eax, SYS_MMAP
    syscall
.close:
    mov r13, rax
    mov rdi, rbx
    mov eax, SYS_CLOSE
    syscall
    mov rax, r13
    mov rdx, r12
.out:
    pop r13
    pop r12
    pop rbx
    ret

global arena_alloc
arena_alloc:
    mov rax, [rdi]
    add rax, 15
    and rax, -16
    lea rdx, [rax + rsi]
    cmp rdx, [rdi + 8]
    ja .full
    mov [rdi], rdx
    ret
.full:
    xor eax, eax
    ret

section .bss
alignb 16
arena:      resq 2
arena_mark: resq 1
out_buf:    resq 1
out_at:     resq 1
