; ============================================================================
; BMP — Windows Bitmap Decoder (uncompressed 24/32-bit + RLE8)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"

; struct offsets (hoisted above use)
%define BMP_MAGIC        0x4D42  ; "BM"
%define BMP_COMP_RGB     0
%define BMP_COMP_RLE8    1
%define BMP_COMP_BITFIELDS 3

section .text


; ---------------------------------------------------------------------------
; bmp_probe
; ---------------------------------------------------------------------------
global bmp_probe
bmp_probe:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 2
    jb .no
    movzx eax, word [rdi]
    cmp eax, BMP_MAGIC
    jne .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; bmp_decode
;   IN: rdi = arena, rsi = data, rdx = len — OUT: rax = PixBuf*
; ---------------------------------------------------------------------------
global bmp_decode
bmp_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, r13
    call bmp_probe
    test rax, rax
    jz .bad
    cmp r13, 54
    jb .bad
    mov eax, [r12 + 10]  ; pixel offset
    mov r14d, eax
    mov eax, [r12 + 18]  ; width (signed)
    mov r15d, eax
    mov eax, [r12 + 22]  ; height (signed; negative = top-down)
    mov ecx, eax
    test r15d, r15d
    jz .bad
    test ecx, ecx
    jz .bad
    mov r11d, 0  ; bottom_up flag
    test ecx, ecx
    jns .bottom_up
    neg ecx
    mov r11d, 1
.bottom_up:
    cmp r15d, 32768
    ja .bad
    cmp ecx, 32768
    ja .bad
    movzx edx, word [r12 + 28]  ; bpp
    cmp edx, 24
    je .bpp_ok
    cmp edx, 32
    je .bpp_ok
    jmp .bad
.bpp_ok:
    mov eax, [r12 + 30]  ; compression
    cmp eax, BMP_COMP_RGB
    je .comp_ok
    cmp eax, BMP_COMP_RLE8
    je .comp_ok
    jmp .bad
.comp_ok:
    ; recompute volatile state after the call below via header reloads;
    ; stash height/bpp in callee-saved regs that survive pixbuf_create
    mov r13d, ecx        ; abs height (callee-saved)
    mov r10d, edx        ; bpp (r10 volatile! reload after call instead)
    push r10
    ; allocate pixbuf
    mov rdi, rbx
    mov esi, r15d
    mov edx, r13d
    mov rcx, DRM_FORMAT_BGRA8888
    push r13
    push r14
    call pixbuf_create
    pop r14
    pop r13
    pop r10
    test rax, rax
    jz .oom
    mov r15, rax
    ; reload bpp + bottom_up from header (volatile regs were clobbered)
    movzx r10d, word [r12 + 28]
    mov eax, [r12 + 22]
    xor r11d, r11d
    test eax, eax
    jns .is_bottom_up
    mov r11d, 1  ; top-down flag
.is_bottom_up:
    ; source pointer
    mov rsi, r12
    add rsi, r14
    mov rdi, [r15 + PixBuf.data]
    mov r8d, [r15 + PixBuf.width]
    mov r9d, [r15 + PixBuf.height]
    ; src stride = ((w*bpp+31)/32)*4
    mov eax, [r12 + 28]
    movzx eax, ax
    imul eax, r8d
    add eax, 31
    shr eax, 5
    shl eax, 2
    mov r14d, eax  ; src stride (r14 free now)
    mov eax, [r12 + 30]
    cmp eax, BMP_COMP_RLE8
    je .rle8
    ; RGB path. Regs: rsi=src base, rdi=dst base, r8d=width, r9d=height,
    ; r10d=bpp, r11d=topdown flag, r13d=row, r14d=src stride, r15=pixbuf.
    ; No calls in the loop, so volatile regs are stable across rows.
    xor r13d, r13d
.row_loop:
    cmp r13d, r9d
    jae .done
    ; src row index = topdown ? row : (h-1-row)
    mov eax, r13d
    test r11d, r11d
    jnz .src_row_ok
    mov eax, r9d
    sub eax, r13d
    dec eax
.src_row_ok:
    imul eax, r14d
    lea rdx, [rsi + rax]      ; src row
    mov eax, [r15 + PixBuf.stride]
    imul eax, r13d
    lea rax, [rdi + rax]      ; dst row
    cmp r10d, 32
    je .row32
    ; 24-bit BGR -> BGRA
    xor ecx, ecx
.px24:
    cmp ecx, r8d
    jae .row_next
    movzx r9d, byte [rdx + rcx * 3]
    movzx r10d, byte [rdx + rcx * 3 + 1]
    movzx r11d, byte [rdx + rcx * 3 + 2]
    mov [rax + rcx * 4], r9b
    mov [rax + rcx * 4 + 1], r10b
    mov [rax + rcx * 4 + 2], r11b
    mov byte [rax + rcx * 4 + 3], 255
    inc ecx
    jmp .px24
.row32:
    xor ecx, ecx
.px32:
    cmp ecx, r8d
    jae .row_next
    mov r9d, [rdx + rcx * 4]
    mov [rax + rcx * 4], r9d
    mov byte [rax + rcx * 4 + 3], 255
    inc ecx
    jmp .px32
.row_next:
    ; reload invariants clobbered by the pixel loop
    mov r8d, [r15 + PixBuf.width]
    mov r9d, [r15 + PixBuf.height]
    movzx r10d, word [r12 + 28]
    mov eax, [r12 + 22]
    xor r11d, r11d
    test eax, eax
    jns .still_bottom
    mov r11d, 1
.still_bottom:
    inc r13d
    jmp .row_loop
.done:
    mov rax, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.rle8:
    ; RLE8 decode into pixbuf (bottom-up aware via same row math)
    mov rdi, r15
    mov rsi, r12
    call bmp_rle8_decode
    test rax, rax
    jnz .bad
    mov rax, r15
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; bmp_rle8_decode
;   IN: rdi = pixbuf (BGRA, cleared?), rsi = bmp base
;   RLE8: <count,value> runs; <0,cmd>: 0=EOL, 1=EOB, 2=delta, else absolute
;   Palette: grayscale ramp (RLE8 BMPs here are 8-bit; map index->gray)
; ---------------------------------------------------------------------------
global bmp_rle8_decode
bmp_rle8_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov eax, [r12 + 10]
    lea r13, [r12 + rax]      ; encoded data
    mov r14d, [r12 + 18]      ; width
    mov eax, [r12 + 22]
    test eax, eax
    jns .bottom_up
    neg eax
.bottom_up:
    mov r15d, eax             ; height
    mov rdi, [rbx + PixBuf.data]
    mov r10d, [rbx + PixBuf.stride]
    xor r11d, r11d            ; x
    xor r12d, r12d            ; y (from bottom)
.decode:
    movzx eax, byte [r13]
    movzx edx, byte [r13 + 1]
    add r13, 2
    test eax, eax
    jz .escape
    ; encoded run: eax copies of palette[edx] (gray ramp)
    mov r8b, dl
.encoded:
    test eax, eax
    jz .decode
    cmp r11d, r14d
    jae .fail
    cmp r12d, r15d
    jae .fail
    mov ecx, r12d
    imul ecx, r10d
    lea rcx, [rdi + rcx]
    lea rcx, [rcx + r11 * 4]
    mov [rcx], r8b
    mov [rcx + 1], r8b
    mov [rcx + 2], r8b
    mov byte [rcx + 3], 255
    inc r11d
    dec eax
    jmp .encoded
.escape:
    cmp edx, 0
    je .eol
    cmp edx, 1
    je .done
    cmp edx, 2
    je .delta
    ; absolute mode: edx raw bytes (+pad to word)
    mov eax, edx
.abs:
    test eax, eax
    jz .abs_pad
    cmp r11d, r14d
    jae .fail
    mov r8b, [r13]
    inc r13
    mov ecx, r12d
    imul ecx, r10d
    lea rcx, [rdi + rcx]
    lea rcx, [rcx + r11 * 4]
    mov [rcx], r8b
    mov [rcx + 1], r8b
    mov [rcx + 2], r8b
    mov byte [rcx + 3], 255
    inc r11d
    dec eax
    jmp .abs
.abs_pad:
    test edx, 1
    jz .decode
    inc r13
    jmp .decode
.eol:
    xor r11d, r11d
    inc r12d
    jmp .decode
.delta:
    movzx eax, byte [r13]
    movzx edx, byte [r13 + 1]
    add r13, 2
    add r11d, eax
    add r12d, edx
    jmp .decode
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global bmp_version
bmp_version: dq 0x010000
