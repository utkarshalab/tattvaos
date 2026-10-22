; ============================================================================
; Tile Diff - Changed-Tile Detection (64x64 grid + per-tile CRC)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define TileDiff_SIZE    48
%define TILE_DEFAULT_W   64
%define TILE_DEFAULT_H   64

section .text

struc TileDiff
    .tile_w:        resd 1
    .tile_h:        resd 1
    .cols:          resd 1
    .rows:          resd 1
    .prev_crc:      resq 1
    .dirty:         resq 1
    .dirty_count:   resq 1
    .arena:         resq 1
endstruc


global tile_diff_init
tile_diff_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov dword [r12 + TileDiff.tile_w], TILE_DEFAULT_W
    mov dword [r12 + TileDiff.tile_h], TILE_DEFAULT_H
    mov eax, r13d
    add eax, TILE_DEFAULT_W - 1
    mov ecx, TILE_DEFAULT_W
    xor edx, edx
    div ecx
    mov [r12 + TileDiff.cols], eax
    mov eax, r14d
    add eax, TILE_DEFAULT_H - 1
    mov ecx, TILE_DEFAULT_H
    xor edx, edx
    div ecx
    mov [r12 + TileDiff.rows], eax
    mov eax, [r12 + TileDiff.cols]
    imul eax, [r12 + TileDiff.rows]
    mov r13d, eax
    mov rdi, rbx
    mov rsi, r13
    shl rsi, 2
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r12 + TileDiff.prev_crc], rax
    mov eax, r13d
    add eax, 7
    shr eax, 3
    mov rdi, rbx
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r12 + TileDiff.dirty], rax
    mov qword [r12 + TileDiff.dirty_count], 0
    mov qword [r12 + TileDiff.arena], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

global tile_diff_update
tile_diff_update:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov qword [rbx + TileDiff.dirty_count], 0
    mov eax, [rbx + TileDiff.cols]
    imul eax, [rbx + TileDiff.rows]
    add eax, 7
    shr eax, 3
    mov rdi, [rbx + TileDiff.dirty]
    mov rcx, rax
    xor eax, eax
    rep stosb
    xor r8d, r8d
    xor r9d, r9d
.row_loop:
    cmp r9d, [rbx + TileDiff.rows]
    jae .done
    xor r10d, r10d
.col_loop:
    cmp r10d, [rbx + TileDiff.cols]
    jae .next_row
    mov eax, r10d
    imul eax, TILE_DEFAULT_W
    mov r11d, eax
    mov rdi, r12
    mov esi, r11d
    shl esi, 2
    add rdi, rsi
    mov eax, r9d
    imul eax, TILE_DEFAULT_H
    imul rax, r13
    add rdi, rax
    mov esi, TILE_DEFAULT_W
    mov eax, r11d
    add eax, esi
    cmp eax, r14d
    jbe .w_ok
    mov esi, r14d
    sub esi, r11d
.w_ok:
    mov edx, TILE_DEFAULT_H
    mov eax, r9d
    imul eax, TILE_DEFAULT_H
    add eax, edx
    cmp eax, r15d
    jbe .h_ok
    mov edx, r15d
    mov eax, r9d
    imul eax, TILE_DEFAULT_H
    sub edx, eax
.h_ok:
    push r8
    push r9
    push r10
    push rsi
    push rdx
    xor r8d, r8d
    mov r9d, 0xFFFFFFFF
    mov r10, rdi
    pop rdx
    pop rsi
.crc_row:
    cmp r8d, edx
    jae .crc_done
    push rdx
    push rsi
    mov rdx, rsi
    shl rdx, 2
    mov rsi, r10
    call crc32_block
    mov r9d, eax
    pop rsi
    pop rdx
    add r10, r13
    inc r8d
    jmp .crc_row
.crc_done:
    mov r8d, r9d
    pop r10
    pop r9
    pop r8
    mov eax, r9d
    imul eax, [rbx + TileDiff.cols]
    add eax, r10d
    mov rdi, [rbx + TileDiff.prev_crc]
    cmp [rdi + rax * 4], r8d
    je .clean
    mov [rdi + rax * 4], r8d
    mov rdi, [rbx + TileDiff.dirty]
    mov rcx, rax
    shr rcx, 3
    and eax, 7
    mov edx, eax
    mov rax, 1
    mov cl, dl
    shl rax, cl
    or [rdi + rcx], al
    inc qword [rbx + TileDiff.dirty_count]
.clean:
    inc r10d
    jmp .col_loop
.next_row:
    inc r9d
    jmp .row_loop
.done:
    mov rax, [rbx + TileDiff.dirty_count]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global crc32_block
crc32_block:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rsi
    mov r12, rdx
    mov eax, 0xFFFFFFFF
.loop:
    test r12, r12
    jz .done
    xor al, [rbx]
    mov ecx, 8
.bit:
    mov edx, eax
    and edx, 1
    neg edx
    shr eax, 1
    and edx, 0xEDB88320
    xor eax, edx
    dec ecx
    jnz .bit
    inc rbx
    dec r12
    jmp .loop
.done:
    not eax
    EPILOGUE_RESTORE rbx, r12
    ret

global tile_diff_is_dirty
tile_diff_is_dirty:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, esi
    mov rcx, rax
    shr rcx, 3
    and eax, 7
    mov dl, [rdi + rcx]
    mov cl, al
    shr dl, cl
    and edx, 1
    mov eax, edx
    leave
    ret

section .data
global tile_diff_version
tile_diff_version: dq 0x010000

