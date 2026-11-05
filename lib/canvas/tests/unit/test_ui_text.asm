; ============================================================================
; Unit Test — UI Text in the Embedded Font (src/text/ui_text.asm)
; ============================================================================
; test_ui_text_suite -> eax = failed cases (each case returns 0 / 1).
; Text drawn into a black 96x32 buffer: ink lands in the box and nowhere
; else, the clip keeps it out of what it covers, and nothing is drawn for no
; text.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/ui_text.inc"

extern arena_init
extern ui_text_draw
extern ui_text_init

%define HEAP_SIZE   (6 * 1024 * 1024)
%define W           96
%define H           32
%define BLACK       0xFF000000

section .text

global test_ui_text_suite
test_ui_text_suite:
    push rbx
    xor ebx, ebx
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel arena]
    call ui_text_init
    test rax, rax
    jz .ready
    mov eax, 100                        ; the font did not open
    pop rbx
    ret
.ready:
%macro CASE 1
    call clear
    call %1
    add ebx, eax
%endmacro
    CASE tu_ink
    CASE tu_clip
    CASE tu_nothing
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; the buffer black
clear:
    lea rdi, [rel pixels]
    mov eax, BLACK
    mov ecx, W * H
    rep stosd
    ret

; "Hi" in white, size 16, box (8, 4, 48, 24), clip as given in edi..r8d
; (x, y, w, h)
draw_hi:
    sub rsp, 8
    lea rax, [rel pixels]
    mov [rel text + UiText.pixels], rax
    mov qword [rel text + UiText.stride], W * 4
    mov dword [rel text + UiText.x], 8
    mov dword [rel text + UiText.y], 4
    mov dword [rel text + UiText.width], 48
    mov dword [rel text + UiText.height], 24
    mov [rel text + UiText.clip_x], edi
    mov [rel text + UiText.clip_y], esi
    mov [rel text + UiText.clip_w], edx
    mov [rel text + UiText.clip_h], ecx
    mov dword [rel text + UiText.size], 16
    mov dword [rel text + UiText.colour], 0xFFFFFF
    lea rax, [rel s_hi]
    mov [rel text + UiText.text], rax
    mov dword [rel text + UiText.length], 2
    lea rdi, [rel text]
    call ui_text_draw
    add rsp, 8
    ret

; edi = x0, esi = y0, edx = x1, ecx = y1 (exclusive) -> eax = pixels not
; black in that rectangle
count_ink:
    xor eax, eax
    mov r8d, esi
.row:
    cmp r8d, ecx
    jae .done
    mov r9d, edi
.col:
    cmp r9d, edx
    jae .next_row
    mov r10d, r8d
    imul r10d, W
    add r10d, r9d
    lea r11, [rel pixels]
    cmp dword [r11 + r10 * 4], BLACK
    je .black
    inc eax
.black:
    inc r9d
    jmp .col
.next_row:
    inc r8d
    jmp .row
.done:
    ret

; Ink inside the box, none outside it
tu_ink:
    sub rsp, 8
    xor edi, edi
    xor esi, esi
    mov edx, W
    mov ecx, H
    call draw_hi
    test rax, rax
    jnz .fail
    mov edi, 8
    mov esi, 4
    mov edx, 8 + 48
    mov ecx, 4 + 24
    call count_ink
    cmp eax, 20                         ; two letters' worth
    jb .fail
    xor edi, edi                        ; left of the box
    xor esi, esi
    mov edx, 8
    mov ecx, H
    call count_ink
    test eax, eax
    jnz .fail
    mov edi, 8 + 48                     ; right of it
    xor esi, esi
    mov edx, W
    mov ecx, H
    call count_ink
    test eax, eax
    jnz .fail
    PASS

; Nothing drawn outside the clip, though it is in the box
tu_clip:
    sub rsp, 8
    xor edi, edi
    xor esi, esi
    mov edx, 14                         ; up to x 14: most of the H is out
    mov ecx, H
    call draw_hi
    mov edi, 14
    xor esi, esi
    mov edx, W
    mov ecx, H
    call count_ink
    test eax, eax
    jnz .fail
    PASS

; No text, no ink
tu_nothing:
    sub rsp, 8
    xor edi, edi
    xor esi, esi
    mov edx, W
    mov ecx, H
    call draw_hi
    mov dword [rel text + UiText.length], 0
    call clear
    lea rdi, [rel text]
    call ui_text_draw
    xor edi, edi
    xor esi, esi
    mov edx, W
    mov ecx, H
    call count_ink
    test eax, eax
    jnz .fail
    PASS

section .rodata
s_hi:           db "Hi"

section .bss
alignb 16
arena:          resb Arena_size
text:           resb UiText_size
alignb 16
pixels:         resd W * H
alignb 16
heap:           resb HEAP_SIZE
