; ============================================================================
; UI Text — Labels in the Embedded Font
; ============================================================================
; canvasd carries one font, a Noto Sans subset (assets/fonts/NotoSans-UI.ttf:
; Basic Latin, Latin-1, the bullet and the ellipsis), so its own text needs
; no file system. ui_text_init puts it in a ufont set as "Noto Sans", which
; sans-serif means, and hands the set to SVG text. ui_text_draw sets one line
; in a box as an SVG text element, renders it with svg_render (ufont shapes,
; ugfx fills with anti-aliasing) and lays it over 32-bit BGRX pixels, inside
; a clip. Rendering happens in a scratch arena of its own, rewound after
; each line; the font set keeps what it caches in the arena it was given.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/ui_text.inc"
%include "ufont.inc"
%include "ugfx.inc"

extern arena_alloc
extern arena_init
extern arena_mark
extern arena_rewind
extern svg_render
extern svg_set_fonts
extern ufont_set_add
extern ufont_set_init

%define SVG_MAX     768                 ; the document for one line
%define SCRATCH     (2 * 1024 * 1024)   ; what rendering one line may use

section .text

; ---------------------------------------------------------------------------
; ui_text_init
;   IN:  rdi = arena: the font set's, and SCRATCH taken from it to render in
;   OUT: rax = 0, -ENOMEM, negative error if the font does not open
; ---------------------------------------------------------------------------
global ui_text_init
ui_text_init:
    push rbx
    mov rbx, rdi
    mov esi, SCRATCH
    call arena_alloc
    test rax, rax
    jz .oom
    lea rdi, [rel scratch]
    mov rsi, rax
    mov edx, SCRATCH
    call arena_init
    lea rax, [rel scratch]
    mov [rel text_arena], rax
    lea rdi, [rel font_set]
    mov rsi, rbx
    call ufont_set_init
    lea rdi, [rel font_set]
    lea rsi, [rel ui_font]
    mov edx, ui_font_end - ui_font
    lea rcx, [rel s_family]
    mov r8d, 400
    xor r9d, r9d
    call ufont_set_add
    test rax, rax
    js .out
    lea rdi, [rel font_set]
    call svg_set_fonts
    mov byte [rel ready], 1
    xor eax, eax
.out:
    pop rbx
    ret
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; ui_text_draw
;   One line of text, vertically centred in a box
;   IN:  rdi = UiText*
;   OUT: rax = 0, -ENODEV before ui_text_init, -ENOMEM
; ---------------------------------------------------------------------------
global ui_text_draw
ui_text_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, SVG_MAX + 8                ; the document; 16-byte aligned
    mov rbx, rdi
    mov rax, -(ENODEV)
    cmp byte [rel ready], 0
    je .out
    cmp dword [rbx + UiText.width], 0
    jle .empty
    cmp dword [rbx + UiText.height], 0
    jle .empty

    mov rdi, [rel text_arena]
    call arena_mark
    mov r15, rax

    ; The document
    mov rdi, rsp
    lea rsi, [rel s_head]
    call append
    mov esi, [rbx + UiText.width]
    call append_number
    lea rsi, [rel s_height]
    call append
    mov esi, [rbx + UiText.height]
    call append_number
    lea rsi, [rel s_text]
    call append
    mov esi, [rbx + UiText.size]        ; baseline: the middle of the box
    imul esi, esi, 72                   ; plus half a cap height
    mov eax, esi
    xor edx, edx
    mov ecx, 200
    div ecx
    mov esi, [rbx + UiText.height]
    shr esi, 1
    add esi, eax
    call append_number
    lea rsi, [rel s_size]
    call append
    mov esi, [rbx + UiText.size]
    call append_number
    lea rsi, [rel s_fill]
    call append
    mov esi, [rbx + UiText.colour]
    call append_hex6
    lea rsi, [rel s_close_attrs]
    call append
    mov rsi, [rbx + UiText.text]
    mov ecx, [rbx + UiText.length]
    lea rdx, [rsp + SVG_MAX - 32]       ; room kept for the tail
    call append_escaped
    lea rsi, [rel s_tail]
    call append
    mov rdx, rdi
    sub rdx, rsp                        ; its length

    mov rdi, [rel text_arena]
    mov rsi, rsp
    mov ecx, [rbx + UiText.width]
    mov r8d, [rbx + UiText.height]
    call svg_render
    test rax, rax
    jz .oom
    mov rdi, rbx
    mov rsi, rax
    call lay_over
    mov rdi, [rel text_arena]
    mov rsi, r15
    call arena_rewind
.empty:
    xor eax, eax
.out:
    add rsp, SVG_MAX + 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.oom:
    mov rdi, [rel text_arena]
    mov rsi, r15
    call arena_rewind
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; The rendered line (premultiplied BGRA) over the target, inside the clip.
; rdi = UiText, rsi = PixBuf
lay_over:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d                      ; row in the box
.row:
    cmp r13d, [rbx + UiText.height]
    jae .done
    mov eax, [rbx + UiText.y]
    add eax, r13d                       ; its y in the target
    cmp eax, [rbx + UiText.clip_y]
    jl .next_row
    mov ecx, [rbx + UiText.clip_y]
    add ecx, [rbx + UiText.clip_h]
    cmp eax, ecx
    jge .next_row
    movsxd rax, eax
    imul rax, qword [rbx + UiText.stride]
    add rax, [rbx + UiText.pixels]
    mov r14, rax                        ; the target row
    mov rax, r13
    imul rax, [r12 + PixBuf_stride]
    add rax, [r12 + PixBuf_data]
    mov r15, rax                        ; the line's row
    xor ecx, ecx                        ; column in the box
.pixel:
    cmp ecx, [rbx + UiText.width]
    jae .next_row
    mov eax, [rbx + UiText.x]
    add eax, ecx                        ; its x in the target
    cmp eax, [rbx + UiText.clip_x]
    jl .next_pixel
    mov edx, [rbx + UiText.clip_x]
    add edx, [rbx + UiText.clip_w]
    cmp eax, edx
    jge .next_pixel
    mov r8d, [r15 + rcx * 4]            ; the line: premultiplied
    mov r9d, r8d
    shr r9d, 24                         ; its alpha
    jz .next_pixel
    movsxd rax, eax
    lea r10, [r14 + rax * 4]
    mov r11d, [r10]                     ; under it
    ; each of B, G, R: line + under * (255 - alpha) / 255
    push rcx
    mov ecx, 255
    sub ecx, r9d
    xor edi, edi                        ; the result
%macro CHANNEL 1
    mov eax, r11d
    shr eax, %1
    and eax, 0xFF
    imul eax, ecx
    add eax, 127
    mov edx, eax                        ; / 255, rounded
    shr edx, 8
    add eax, edx
    shr eax, 8
    mov edx, r8d
    shr edx, %1
    and edx, 0xFF
    add eax, edx
    cmp eax, 255
    jbe %%fits
    mov eax, 255
%%fits:
    shl eax, %1
    or edi, eax
%endmacro
    CHANNEL 0
    CHANNEL 8
    CHANNEL 16
    or edi, 0xFF000000
    mov [r10], edi
    pop rcx
.next_pixel:
    inc ecx
    jmp .pixel
.next_row:
    inc r13d
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Copy a NUL-terminated string to rdi. rdi = end of what is there,
; rsi = string -> rdi = new end
append:
.next:
    mov al, [rsi]
    test al, al
    jz .done
    mov [rdi], al
    inc rdi
    inc rsi
    jmp .next
.done:
    ret

; A number, unsigned decimal. rdi = end, esi = number -> rdi = new end
append_number:
    mov eax, esi
    sub rsp, 16                         ; digits backwards
    xor ecx, ecx
.digit:
    xor edx, edx
    mov r8d, 10
    div r8d
    add dl, '0'
    mov [rsp + rcx], dl
    inc ecx
    test eax, eax
    jnz .digit
.out:
    dec ecx
    mov al, [rsp + rcx]
    mov [rdi], al
    inc rdi
    test ecx, ecx
    jnz .out
    add rsp, 16
    ret

; Six hex digits of 0xRRGGBB. rdi = end, esi = colour -> rdi = new end
append_hex6:
    mov ecx, 20
.nibble:
    mov eax, esi
    shr eax, cl
    and eax, 15
    lea rdx, [rel hex]
    mov al, [rdx + rax]
    mov [rdi], al
    inc rdi
    sub ecx, 4
    jns .nibble
    ret

; Text with & < > as entities, stopping at the limit.
; rdi = end, rsi = text, ecx = length, rdx = limit -> rdi = new end
append_escaped:
    test ecx, ecx
    jz .done
.next:
    cmp rdi, rdx
    jae .done
    mov al, [rsi]
    inc rsi
    cmp al, '&'
    je .amp
    cmp al, '<'
    je .lt
    cmp al, '>'
    je .gt
    mov [rdi], al
    inc rdi
    jmp .counted
.amp:
    mov dword [rdi], '&amp'
    mov byte [rdi + 4], ';'
    add rdi, 5
    jmp .counted
.lt:
    mov dword [rdi], '&lt;'
    add rdi, 4
    jmp .counted
.gt:
    mov dword [rdi], '&gt;'
    add rdi, 4
.counted:
    dec ecx
    jnz .next
.done:
    ret

section .rodata
s_family:       db "Noto Sans", 0
s_head:         db '<svg xmlns="http://www.w3.org/2000/svg" width="', 0
s_height:       db '" height="', 0
s_text:         db '"><text x="0" y="', 0
s_size:         db '" font-family="sans-serif" font-size="', 0
s_fill:         db '" fill="#', 0
s_close_attrs:  db '">', 0
s_tail:         db '</text></svg>', 0
hex:            db "0123456789ABCDEF"

align 4
ui_font:        incbin "assets/fonts/NotoSans-UI.ttf"
ui_font_end:

section .bss
alignb 16
font_set:       resb UfontSet_SIZE
text_arena:     resq 1                  ; the scratch arena
scratch:        resb Arena_size
ready:          resb 1
