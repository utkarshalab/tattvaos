; =============================================================================
; Utkarsha OS — lib/ugfx/tests/host/host_raster.asm
; =============================================================================
; Host test tool: host_raster <shape> <out.raw>
;   shape: u32 width, height, rule, colour (premultiplied BGRA), background,
;          contour count; then per contour u32 point count and i32 x, y pairs
;          in 24.8 fixed point.
;   out:   width * height * 4 bytes of BGRA after filling.
; Exit status: 0 ok, 1 usage, 2 read error, 3 raster error, 4 write error.
; Development-machine tool only; brings its own bump arena and panic hook.
; =============================================================================

%define UGFX_PANIC_IMPL 1
%include "ugfx.inc"

extern pixbuf_create
extern ugfx_raster_init
extern ugfx_raster_move_to
extern ugfx_raster_line_to
extern ugfx_raster_close
extern ugfx_raster_fill

%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_FSTAT   5
%define SYS_MMAP    9
%define SYS_EXIT    231
%define ARENA_BYTES (256 * 1024 * 1024)

section .text

global _start
_start:
    mov r12, [rsp + 16]                 ; argv[1]
    mov r13, [rsp + 24]                 ; argv[2]
    mov rax, [rsp]
    and rsp, -16
    cmp rax, 3
    jne .usage
    ; map the shape file
    mov rdi, r12
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
    cmp r15, 24
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
    mov rbx, rax                        ; shape bytes
    lea rax, [rbx + r15]
    mov [rel shape_end], rax
    ; arena and pixel buffer
    lea rax, [rel arena_memory]
    mov [rel arena_state], rax
    add rax, ARENA_BYTES
    mov [rel arena_state + 8], rax
    lea rdi, [rel arena_state]
    mov esi, [rbx]
    mov edx, [rbx + 4]
    mov ecx, 0
    call pixbuf_create
    test rax, rax
    jle .raster_fail
    mov [rel pixbuf], rax
    ; background fill
    mov rdi, [rax + PixBuf_data]
    mov rcx, [rax + PixBuf_size]
    shr rcx, 2
    mov eax, [rbx + 16]
    rep stosd
    lea rdi, [rel raster]
    lea rsi, [rel arena_state]
    mov edx, [rbx]
    mov ecx, [rbx + 4]
    call ugfx_raster_init
    test rax, rax
    jnz .raster_fail
    ; contours
    mov r12d, [rbx + 20]                ; contour count
    lea r14, [rbx + 24]
.contour:
    test r12d, r12d
    jz .contours_done
    lea rax, [r14 + 4]
    cmp rax, [rel shape_end]
    ja .read_fail
    mov r15d, [r14]                     ; points
    add r14, 4
    mov eax, r15d
    shl rax, 3
    add rax, r14
    cmp rax, [rel shape_end]
    ja .read_fail
    test r15d, r15d
    jz .contour_next
    lea rdi, [rel raster]
    mov esi, [r14]
    mov edx, [r14 + 4]
    call ugfx_raster_move_to
    add r14, 8
    dec r15d
.point:
    test r15d, r15d
    jz .contour_close
    lea rdi, [rel raster]
    mov esi, [r14]
    mov edx, [r14 + 4]
    call ugfx_raster_line_to
    add r14, 8
    dec r15d
    jmp .point
.contour_close:
    lea rdi, [rel raster]
    call ugfx_raster_close
.contour_next:
    dec r12d
    jmp .contour
.contours_done:
    lea rdi, [rel raster]
    mov rsi, [rel pixbuf]
    mov edx, [rbx + 12]
    mov ecx, [rbx + 8]
    call ugfx_raster_fill
    test rax, rax
    jnz .raster_fail
    ; write the pixels
    mov rdi, r13
    mov esi, 0x241                      ; O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0644o
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js .write_fail
    mov r14, rax
    mov rax, [rel pixbuf]
    mov r12, [rax + PixBuf_data]
    mov r13, [rax + PixBuf_size]
.write:
    test r13, r13
    jz .ok
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    jle .write_fail
    add r12, rax
    sub r13, rax
    jmp .write
.ok:
    xor edi, edi
    jmp .exit
.usage:
    mov edi, 1
    jmp .exit
.read_fail:
    mov edi, 2
    jmp .exit
.raster_fail:
    mov edi, 3
    jmp .exit
.write_fail:
    mov edi, 4
.exit:
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
    ja .arena_full
    mov [rdi], rdx
    ret
.arena_full:
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
shape_end:      resq 1
pixbuf:         resq 1
raster:         resb UgfxRaster_SIZE
alignb 4096
arena_memory:   resb ARENA_BYTES
