; ============================================================================
; SVG — decoding SVG images through lib/ugfx
; ============================================================================
; The image pipeline's SVG entry points (image_sniff / image_decode):
;
;   svg_probe(data, len)                         -> 1 if it looks like SVG
;   svg_render(arena, data, len, width, height)  -> PixBuf* or 0
;
; Parsing and drawing are ugfx's (2d/svg.asm; see lib/ugfx/README.md);
; images inside the document (data: URIs) decode through image_decode,
; so any format Canvas reads can be embedded. The image is the
; requested size, or the document's own (viewBox, else width / height,
; else 300 x 150) when width or height is 0; the drawing is fitted and
; centred, transparent around it, currentColor black.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/canvas_client.inc"
%include "ugfx.inc"

extern pixbuf_create
extern ugfx_svg_parse_ex
extern image_decode
extern ugfx_svg_draw
extern ugfx_ctx_init

%define SVG_MAX_SIDE    16384

; frame
%define F_SVG       0                   ; UgfxSvg
%define F_W         UgfxSvg_SIZE        ; u64 image width, height
%define F_H         (F_W + 8)
%define F_PIX       (F_W + 16)
%define F_SIDE      (F_W + 24)          ; f64
%define F_CTX       (F_W + 32)          ; UgfxContext
%define F_SIZE      ((F_CTX + UgfxContext_SIZE + 15) & ~15)

section .rodata
align 8
svg_default_w:      dq 300.0
svg_default_h:      dq 150.0
svg_half:           dq 0.5
svg_max_side:       dq 16384.0

section .text

; ---------------------------------------------------------------------------
; svg_probe — rdi = data, rsi = length -> rax = 1 if "<svg" appears in the
;   first 512 bytes, else 0
; ---------------------------------------------------------------------------
global svg_probe
svg_probe:
    xor eax, eax
    cmp rsi, 4
    jb .done
    mov rcx, rsi
    cmp rcx, 512
    jbe .scan_len
    mov rcx, 512
.scan_len:
    sub rcx, 3
.scan:
    cmp dword [rdi], 0x6776733C          ; "<svg"
    je .yes
    inc rdi
    dec rcx
    jnz .scan
    ret
.yes:
    mov eax, 1
.done:
    ret

; ---------------------------------------------------------------------------
; svg_image — ugfx's image callback: rdi = user, rsi = bytes, rdx = length,
;   ecx = kind (0: a data: URI's bytes, 1: another href), r8 = arena
;   -> rax = PixBuf* (premultiplied) from image_decode, 0 for references
;   (no files are opened here) or what does not decode
; ---------------------------------------------------------------------------
svg_image:
    xor eax, eax
    test ecx, ecx
    jnz .done
    sub rsp, 8
    mov rdi, r8
    xor ecx, ecx                        ; an SVG inside: its own size
    xor r8d, r8d
    call image_decode
    add rsp, 8
.done:
    ret

; ---------------------------------------------------------------------------
; svg_render
;   IN:  rdi = arena, rsi = data, rdx = length, rcx = width, r8 = height
;        (0: the document's size)
;   OUT: rax = PixBuf* (premultiplied BGRA), 0 if it does not parse or
;        memory runs out
; ---------------------------------------------------------------------------
global svg_render
svg_render:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, F_SIZE + 8
    mov rbx, rdi                        ; arena
    mov r14, rcx
    mov r15, r8
    test rdi, rdi
    jz .fail
    test rsi, rsi
    jz .fail
    lea rdi, [rsp + F_SVG]
    mov rcx, rdx
    mov rdx, rsi
    mov rsi, rbx
    lea r8, [rel svg_image]
    xor r9d, r9d
    call ugfx_svg_parse_ex
    test rax, rax
    jnz .fail
    ; the size: requested, else the document's
    test r14, r14
    jz .own_size
    test r15, r15
    jnz .have_size
.own_size:
    movsd xmm0, [rel svg_default_w]
    movsd xmm1, [rel svg_default_h]
    mov eax, [rsp + F_SVG + UgfxSvg_has]
    test eax, 1
    jz .no_viewbox
    movsd xmm0, [rsp + F_SVG + UgfxSvg_viewbox + 16]
    movsd xmm1, [rsp + F_SVG + UgfxSvg_viewbox + 24]
    jmp .round
.no_viewbox:
    xorpd xmm2, xmm2
    test eax, 2
    jz .no_width
    movsd xmm3, [rsp + F_SVG + UgfxSvg_width]
    ucomisd xmm3, xmm2
    jbe .no_width
    movapd xmm0, xmm3
.no_width:
    test eax, 4
    jz .round
    movsd xmm3, [rsp + F_SVG + UgfxSvg_height]
    ucomisd xmm3, xmm2
    jbe .round
    movapd xmm1, xmm3
.round:
    ; whole pixels, at least 1, at most SVG_MAX_SIDE
    minsd xmm0, [rel svg_max_side]
    minsd xmm1, [rel svg_max_side]
    addsd xmm0, [rel svg_half]
    addsd xmm1, [rel svg_half]
    cvttsd2si r14, xmm0
    cvttsd2si r15, xmm1
    test r14, r14
    jg .w_ok
    mov r14d, 1
.w_ok:
    test r15, r15
    jg .have_size
    mov r15d, 1
.have_size:
    cmp r14, SVG_MAX_SIDE
    ja .fail
    cmp r15, SVG_MAX_SIDE
    ja .fail
    mov [rsp + F_W], r14
    mov [rsp + F_H], r15
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .fail
    js .fail
    mov r12, rax
    ; transparent
    mov rdi, [r12 + PixBuf_data]
    mov rcx, [r12 + PixBuf_size]
    xor eax, eax
    rep stosb
    lea rdi, [rsp + F_CTX]
    mov rsi, rbx
    mov rdx, r12
    call ugfx_ctx_init
    test rax, rax
    jnz .fail
    ; the square of side max(w, h), centred on the image
    cvtsi2sd xmm0, r14
    cvtsi2sd xmm1, r15
    movapd xmm2, xmm0
    maxsd xmm2, xmm1
    subsd xmm0, xmm2
    mulsd xmm0, [rel svg_half]
    subsd xmm1, xmm2
    mulsd xmm1, [rel svg_half]
    lea rdi, [rsp + F_SVG]
    lea rsi, [rsp + F_CTX]
    mov edx, 0xFF000000
    call ugfx_svg_draw
    test rax, rax
    jnz .fail
    mov rax, r12
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, F_SIZE + 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

section .data
global svg_version
svg_version: dq 0x020000
