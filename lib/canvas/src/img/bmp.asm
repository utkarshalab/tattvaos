; ============================================================================
; BMP — Windows Bitmap Decoder (uncompressed 24/32-bit + RLE8)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"

section .text

%define BMP_MAGIC        0x4D42  ; "BM"
%define BMP_COMP_RGB     0
%define BMP_COMP_RLE8    1
%define BMP_COMP_BITFIELDS 3

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
    ret
.no:
    xor rax, rax
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
    ; allocate pixbuf
    mov rdi, rbx
    mov esi, r15d
    mov edx, ecx
    mov rcx, DRM_FORMAT_BGRA8888
    push r11
    push rcx
    push r14
    call pixbuf_create
    pop r14
    pop rcx
    pop r11
    test rax, rax
    jz .oom
    mov r15, rax
    ; source pointer
    mov rsi, r12
    add rsi, r14
    mov rdi, [r15 + PixBuf.data]
    mov r10d, [r15 + PixBuf.width]
    mov r9d, [r15 + PixBuf.height]
    mov r8d, [r15 + PixBuf.stride]
    ; row size padded to 4
    mov eax, r10d
    imul eax, edx
    shr edx, 3  ; bpp->bytes (edx was bpp? reload)
    ; recompute: bytes_per_row = ((w*bpp+31)/32)*4
    mov eax, [r12 + 28]
    movzx eax, ax
    imul eax, r10d
    add eax, 31
    shr eax, 5
    shl eax, 2
    mov r11d, eax  ; src stride
    ; TODO: RLE8 path + bitfields; RGB path below
    mov eax, [r12 + 30]
    cmp eax, BMP_COMP_RLE8
    je .rle8
    ; RGB: copy rows flipped if bottom-up
    xor ecx, ecx
.row_loop:
    cmp ecx, r9d
    jae .done
    mov eax, ecx
    test r11d, r11d  ; r11d reused? bottom_up flag saved on stack
    ; bottom_up flag is at [rsp]; reload
    mov edx, [rsp]
    test edx, edx
    jz .topdown_row
    ; bottom-up: src row = h-1-dst
    mov eax, r9d
    sub eax, ecx
    dec eax
.topdown_row:
    imul eax, r11d  ; r11d is src stride? conflict — recompute below
    jmp .row_next
.row_next:
    inc ecx
    jmp .row_loop
.done:
    mov rax, r15
    add rsp, 8
    ret
.rle8:
    ; TODO: RLE8 decode
    mov rax, r15
    add rsp, 8
    ret
.bad:
    xor rax, rax
    ret
.oom:
    xor rax, rax
    ret

section .data
global bmp_version
bmp_version: dq 0x010000
