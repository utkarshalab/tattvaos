; ============================================================================
; Sniff — Image Format Detection (magic bytes)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; ---------------------------------------------------------------------------
; image_sniff
;   IN: rdi = data, rsi = len — OUT: rax = IMAGE_FMT_*
; ---------------------------------------------------------------------------
global image_sniff
image_sniff:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 8
    jb .unknown
    ; PNG
    mov eax, [rdi]
    cmp eax, 0x474E5089  ; 89 'P' 'N' 'G' LE
    jne .chk_jpeg
    mov eax, [rdi + 4]
    cmp eax, 0x0A1A0A0D
    jne .chk_jpeg
    mov rax, IMAGE_FMT_PNG
    ret
.chk_jpeg:
    cmp rsi, 2
    jb .unknown
    movzx eax, word [rdi]
    cmp eax, 0xD8FF
    jne .chk_gif
    mov rax, IMAGE_FMT_JPEG
    ret
.chk_gif:
    cmp rsi, 6
    jb .unknown
    mov eax, [rdi]
    cmp eax, 0x38464947
    jne .chk_bmp
    mov rax, IMAGE_FMT_GIF
    ret
.chk_bmp:
    cmp rsi, 2
    jb .unknown
    movzx eax, word [rdi]
    cmp eax, 0x4D42
    jne .chk_svg
    mov rax, IMAGE_FMT_BMP
    ret
.chk_svg:
    mov rdi, rdi
    call svg_probe
    test rax, rax
    jz .unknown
    mov rax, IMAGE_FMT_SVG
    ret
.unknown:
    xor rax, rax
    ret

section .data
global sniff_version
sniff_version: dq 0x010000
