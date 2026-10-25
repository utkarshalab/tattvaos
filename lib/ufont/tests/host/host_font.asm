; =============================================================================
; Utkarsha OS — lib/ufont/tests/host/host_font.asm
; =============================================================================
; Host tool for tests/host/font_check.py (development machine only).
;
;   host_font o <font.ttf> <in.bin> <out.bin>
;       in:  f64 size, u32 n, u32 code points[n]
;       out: u32 status (0, 1 font refused), u32 units per em, i32 ascent,
;            i32 descent; then per code point: u32 glyph, u32 advance,
;            i32 outline status, u32 verbs, u32 points, the verbs (bytes),
;            the points (f64 x, y) - the outline at size / units per em
;   host_font m <font directory> <in.bin> <out.bin>
;       the shipped fonts found there in a set (ufont_standard order);
;       in:  u32 n, then per query u32 weight, u32 style, u32 length
;            (0xFFFFFFFF: no family), the family's bytes
;       out: per query i32 the face's index in ufont_standard (-1: none)
;
; Exit status: 0 ok, 1 usage, 2 read error, 4 write error.
; =============================================================================

%include "ugfx.inc"
%include "ufont.inc"

%define SYS_WRITE   1
%define SYS_OPEN    2
%define SYS_CLOSE   3
%define SYS_FSTAT   5
%define SYS_MMAP    9
%define SYS_EXIT    60
%define ARENA_SIZE  (256 * 1024 * 1024)
%define OUT_SIZE    (64 * 1024 * 1024)

extern ugfx_path_init
extern ufont_open
extern ufont_glyph
extern ufont_advance
extern ufont_metrics
extern ufont_outline
extern ufont_set_init
extern ufont_set_add
extern ufont_set_face
extern ufont_standard
extern ufont_standard_count

section .text

global _start
_start:
    mov rax, [rsp]                      ; argc
    cmp rax, 5
    jne usage
    mov rbx, [rsp + 16]                 ; mode
    mov r12, [rsp + 24]                 ; font / directory
    mov r13, [rsp + 32]                 ; in
    mov r14, [rsp + 40]                 ; out
    and rsp, -16
    ; the arena and the output buffer
    mov rdi, ARENA_SIZE
    call map_anon
    mov [rel arena], rax
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
    mov r15, rax                        ; the input
    cmp byte [rbx], 'm'
    je match_mode

    ; ---- outlines
    mov rdi, r12
    call map_file
    test rax, rax
    js read_fail
    lea rdi, [rel arena]
    mov rsi, rax
    call ufont_open
    mov rbx, rax
    xor eax, eax
    test rbx, rbx
    setz al
    call put32
    test rbx, rbx
    jz write_out
    mov rdi, rbx
    call ufont_metrics
    push rcx
    push rdx
    call put32                          ; units per em
    pop rax
    call put32                          ; ascent
    pop rax
    call put32                          ; descent
    cvtsi2sd xmm1, dword [rbx + UfontFont_upem]
    movsd xmm0, [r15]
    divsd xmm0, xmm1
    movsd [rel scale], xmm0
    mov r12d, [r15 + 8]                 ; n
    add r15, 12
.cp:
    test r12d, r12d
    jz write_out
    dec r12d
    mov rdi, rbx
    mov esi, [r15]
    add r15, 4
    call ufont_glyph
    mov r13d, eax
    call put32
    mov rdi, rbx
    mov esi, r13d
    call ufont_advance
    call put32
    lea rdi, [rel path]
    lea rsi, [rel arena]
    call ugfx_path_init
    mov rdi, rbx
    mov esi, r13d
    lea rdx, [rel path]
    movsd xmm0, [rel scale]
    lea rcx, [rel arena]
    call ufont_outline
    call put32
    mov eax, [rel path + UgfxPath_verb_count]
    call put32
    mov eax, [rel path + UgfxPath_point_count]
    call put32
    mov rsi, [rel path + UgfxPath_verbs]
    mov ecx, [rel path + UgfxPath_verb_count]
    call put_bytes
    mov rsi, [rel path + UgfxPath_points]
    mov ecx, [rel path + UgfxPath_point_count]
    shl ecx, 4
    call put_bytes
    jmp .cp

    ; ---- matching
match_mode:
    lea rdi, [rel set]
    lea rsi, [rel arena]
    call ufont_set_init
    xor ebx, ebx
.font:
    cmp rbx, [rel ufont_standard_count]
    jae .queries
    imul rax, rbx, UfontStd_SIZE
    lea rcx, [rel ufont_standard]
    lea r13, [rcx + rax]                ; its record
    ; directory / file
    lea rdi, [rel name_buf]
    mov rsi, r12
.dir:
    mov al, [rsi]
    test al, al
    jz .slash
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .dir
.slash:
    mov byte [rdi], '/'
    inc rdi
    mov rsi, [r13 + UfontStd_file]
.file:
    mov al, [rsi]
    mov [rdi], al
    inc rdi
    inc rsi
    test al, al
    jnz .file
    lea rdi, [rel name_buf]
    call map_file
    test rax, rax
    js .next_font
    lea rdi, [rel set]
    mov rsi, rax
    mov rcx, [r13 + UfontStd_family]
    mov r8d, [r13 + UfontStd_weight]
    mov r9d, [r13 + UfontStd_italic]
    push rbx
    sub rsp, 8
    call ufont_set_add
    add rsp, 8
    pop rbx
    test rax, rax
    jnz .next_font
    mov eax, [rel set + UfontSet_count]
    dec eax
    lea rcx, [rel face_std]
    mov [rcx + rax * 4], ebx            ; the face's standard index
.next_font:
    inc rbx
    jmp .font
.queries:
    mov r12d, [r15]
    add r15, 4
.query:
    test r12d, r12d
    jz write_out
    dec r12d
    mov eax, [r15]
    mov [rel desc + UgfxSvgFont_weight], eax
    mov eax, [r15 + 4]
    mov [rel desc + UgfxSvgFont_style], eax
    mov ecx, [r15 + 8]
    add r15, 12
    xor eax, eax
    xor edx, edx
    cmp ecx, -1
    je .no_family
    mov rax, r15
    lea rdx, [r15 + rcx]
    add r15, rcx
.no_family:
    mov [rel desc + UgfxSvgFont_family], rax
    mov [rel desc + UgfxSvgFont_family_end], rdx
    lea rdi, [rel set]
    lea rsi, [rel desc]
    call ufont_set_face
    mov ecx, -1
    test rax, rax
    jz .answer
    lea rdx, [rel set + UfontSet_faces]
    sub rax, rdx
    xor edx, edx
    mov ecx, UfontFace_SIZE
    div ecx
    lea rcx, [rel face_std]
    mov ecx, [rcx + rax * 4]
.answer:
    mov eax, ecx
    call put32
    jmp .query

write_out:
    mov rdi, r14
    mov esi, 0x241                      ; O_WRONLY | O_CREAT | O_TRUNC
    mov edx, 0644o
    mov eax, SYS_OPEN
    syscall
    test rax, rax
    js write_fail
    mov rbx, rax
    mov r12, [rel out_buf]
    mov r13, [rel out_at]
    sub r13, r12
.write:
    test r13, r13
    jz .written
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov eax, SYS_WRITE
    syscall
    test rax, rax
    jle write_fail
    add r12, rax
    sub r13, rax
    jmp .write
.written:
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

; eax -> appended
put32:
    mov rdx, [rel out_at]
    mov [rdx], eax
    add qword [rel out_at], 4
    ret

; rsi = bytes, ecx = count -> appended
put_bytes:
    mov rdi, [rel out_at]
    rep movsb
    mov [rel out_at], rdi
    ret

; rdi = bytes -> rax = an anonymous read / write mapping
map_anon:
    mov rsi, rdi
    xor edi, edi
    mov edx, 3                          ; PROT_READ | PROT_WRITE
    mov r10d, 0x22                      ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    mov eax, SYS_MMAP
    syscall
    ret

; rdi = path -> rax = its bytes (read-only mapping), rdx = length; rax < 0
;   when it cannot be read or is empty
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

; the bump allocator ugfx paths and ufont use: rdi = arena (at, end), rsi =
;   bytes -> rax = 16-aligned block, 0 when full
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
out_buf:    resq 1
out_at:     resq 1
scale:      resq 1
path:       resb UgfxPath_SIZE
desc:       resb UgfxSvgFont_SIZE
alignb 16
set:        resb UfontSet_SIZE
face_std:   resd UFONT_SET_MAX
name_buf:   resb 4096
