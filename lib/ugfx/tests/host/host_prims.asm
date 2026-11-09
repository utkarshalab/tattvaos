; =============================================================================
; Utkarsha OS — lib/ugfx/tests/host/host_prims.asm
; =============================================================================
; Host test tool: host_prims <commands> <out.raw>
;   commands: u32 width, height, background (BGRA), count; then count times
;             u32 kind (1 line, 2 circle, 3 ellipse) and six i32 arguments:
;             line x0, y0, x1, y1, colour; circle cx, cy, r, colour;
;             ellipse cx, cy, rx, ry, colour (the rest 0).
;   out:      width * height * 4 bytes of BGRA, then each command's return
;             value as an i32.
; Exit status: 0 ok, 1 usage, 2 read error, 3 draw error, 4 write error.
; Used by tests/host/prims_check.py. Development-machine tool only.
; =============================================================================

%define UGFX_PANIC_IMPL 1
%include "ugfx.inc"

extern pixbuf_create
extern line_draw
extern circle_draw
extern ellipse_draw

%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_FSTAT   5
%define SYS_MMAP    9
%define SYS_EXIT    231
%define ARENA_BYTES (64 * 1024 * 1024)
%define MAX_COMMANDS 4096

section .text

global _start
_start:
    mov r12, [rsp + 16]                 ; argv[1]
    mov r13, [rsp + 24]                 ; argv[2]
    mov rax, [rsp]
    and rsp, -16
    cmp rax, 3
    jne .usage
    mov rdi, r12                        ; the commands, mapped
    xor esi, esi
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .read_fail
    mov r14, rax
    sub rsp, 144
    mov rdi, r14
    mov rsi, rsp
    mov eax, SYS_FSTAT
    syscall
    mov r15, [rsp + 48]                 ; size
    add rsp, 144
    cmp r15, 16
    jb .read_fail
    xor edi, edi
    mov rsi, r15
    mov edx, 1
    mov r10d, 2
    mov r8, r14
    xor r9d, r9d
    mov eax, SYS_MMAP
    syscall
    test rax, rax
    js .read_fail
    mov rbx, rax
    mov eax, [rbx + 12]                 ; every command there?
    cmp eax, MAX_COMMANDS
    ja .read_fail
    imul rax, rax, 28
    add rax, 16
    cmp rax, r15
    ja .read_fail
    lea rax, [rel arena_memory]         ; the buffer, cleared to background
    mov [rel arena_state], rax
    add rax, ARENA_BYTES
    mov [rel arena_state + 8], rax
    lea rdi, [rel arena_state]
    mov esi, [rbx]
    mov edx, [rbx + 4]
    xor ecx, ecx
    call pixbuf_create
    test rax, rax
    jle .draw_fail
    mov [rel pixbuf], rax
    mov rdi, [rax + PixBuf_data]
    mov rcx, [rax + PixBuf_size]
    shr rcx, 2
    mov eax, [rbx + 8]
    rep stosd
    xor r14d, r14d                      ; the command
    lea r15, [rbx + 16]
.command:
    cmp r14d, [rbx + 12]
    jae .drawn
    mov rdi, [rel pixbuf]
    mov eax, [r15]
    mov esi, [r15 + 4]
    mov edx, [r15 + 8]
    mov ecx, [r15 + 12]
    mov r8d, [r15 + 16]
    mov r9d, [r15 + 20]
    cmp eax, 1
    je .line
    cmp eax, 2
    je .circle
    cmp eax, 3
    je .ellipse
    jmp .draw_fail
.line:
    call line_draw
    jmp .result
.circle:
    call circle_draw
    jmp .result
.ellipse:
    call ellipse_draw
.result:
    lea rcx, [rel results]
    mov [rcx + r14 * 4], eax
    add r15, 28
    inc r14d
    jmp .command
.drawn:
    mov rdi, r13                        ; the pixels, then the results
    mov esi, 0x241                      ; O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0644o
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .write_fail
    mov r13, rax
    mov rax, [rel pixbuf]
    mov rsi, [rax + PixBuf_data]
    mov rdx, [rax + PixBuf_size]
    call write_all
    lea rsi, [rel results]
    mov edx, [rbx + 12]
    shl rdx, 2
    call write_all
    xor edi, edi
    jmp .exit
.usage:
    mov edi, 1
    jmp .exit
.read_fail:
    mov edi, 2
    jmp .exit
.draw_fail:
    mov edi, 3
    jmp .exit
.write_fail:
    mov edi, 4
.exit:
    mov eax, SYS_EXIT
    syscall
    hlt

; r13 = file, rsi = bytes, rdx = count: all written, or exit 4
write_all:
    test rdx, rdx
    jz .done
    mov rdi, r13
    mov eax, SYS_WRITE
    push rsi
    push rdx
    syscall
    pop rdx
    pop rsi
    test rax, rax
    jle .fail
    add rsi, rax
    sub rdx, rax
    jmp write_all
.done:
    ret
.fail:
    mov edi, 4
    mov eax, SYS_EXIT
    syscall
    hlt

; arena_alloc — rdi = {cursor, end}, rsi = size -> rax = 16-aligned block or 0
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

global panic_null_ptr
panic_null_ptr:
    mov edi, 134
    mov eax, SYS_EXIT
    syscall
    hlt

section .bss
alignb 16
arena_state:    resq 2
pixbuf:         resq 1
results:        resd MAX_COMMANDS
alignb 16
arena_memory:   resb ARENA_BYTES
