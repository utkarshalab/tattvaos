; ============================================================================
; BMP — device-independent bitmap decoder
;   Headers: 12-byte core, 40-byte info, 52/56-byte mask, 108 and 124-byte.
;   Pixels: 1/2/4/8-bit palette, 16/24/32-bit (default masks or BITFIELDS,
;   including an alpha mask), RLE8 and RLE4. Bottom-up and top-down rows.
;   Every read is bounds-checked against the input length.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern pixbuf_create
extern arena_alloc

%define BMP_MAGIC           0x4D42    ; "BM"
%define BMP_COMP_RGB        0
%define BMP_COMP_RLE8       1
%define BMP_COMP_RLE4       2
%define BMP_COMP_BITFIELDS  3
%define BMP_COMP_ALPHABITFIELDS 6
%define BMP_MAX_DIM         32768

; Decoder state on the stack of bmp_decode, addressed through rbx.
%define B_ARENA     0
%define B_DATA      8
%define B_LEN       16
%define B_WIDTH     24
%define B_HEIGHT    28
%define B_TOPDOWN   32
%define B_BPP       36
%define B_COMP      40
%define B_HDRSIZE   44
%define B_PIXOFF    48
%define B_STRIDE    56                ; source row bytes, 4-byte aligned
%define B_PIXBUF    64
%define B_INDEXES   72                ; RLE index plane
%define B_ROW       80
%define B_PALCOUNT  84
%define B_MASK      88                ; u32 mask[4]: R, G, B, A
%define B_SHIFT     104               ; u32 shift[4]
%define B_MAX       120               ; u32 max[4]
%define B_PALETTE   136               ; u32 BGRA palette[256]
%define B_SIZE      1168

section .text

; ---------------------------------------------------------------------------
; bmp_probe — rdi = data, rsi = len -> rax = 1 if it starts with "BM"
; ---------------------------------------------------------------------------
global bmp_probe
bmp_probe:
    xor eax, eax
    test rdi, rdi
    jz .done
    cmp rsi, 2
    jb .done
    cmp word [rdi], BMP_MAGIC
    jne .done
    mov eax, 1
.done:
    ret

; ---------------------------------------------------------------------------
; bmp_decode
;   IN: rdi = arena, rsi = data, rdx = len — OUT: rax = PixBuf* or 0
; ---------------------------------------------------------------------------
global bmp_decode
bmp_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, B_SIZE
    mov rbx, rsp
    mov [rbx + B_ARENA], rdi
    mov [rbx + B_DATA], rsi
    mov [rbx + B_LEN], rdx
    test rdi, rdi
    jz .bad
    test rsi, rsi
    jz .bad
    cmp rdx, 26
    jb .bad
    cmp word [rsi], BMP_MAGIC
    jne .bad
    mov eax, [rsi + 10]
    mov [rbx + B_PIXOFF], rax
    mov eax, [rsi + 14]
    mov [rbx + B_HDRSIZE], eax
    lea rcx, [rax + 14]
    cmp rcx, rdx
    ja .bad
    cmp eax, 12
    je .core_header
    cmp eax, 40
    jb .bad
    mov eax, [rsi + 18]
    mov ecx, [rsi + 22]
    movzx edx, word [rsi + 28]
    mov r8d, [rsi + 30]
    mov r9d, [rsi + 46]               ; colours used
    jmp .header_read
.core_header:
    movzx eax, word [rsi + 18]
    movzx ecx, word [rsi + 20]
    movzx edx, word [rsi + 24]
    xor r8d, r8d
    xor r9d, r9d
.header_read:
    test eax, eax
    jle .bad
    cmp eax, BMP_MAX_DIM
    ja .bad
    mov [rbx + B_WIDTH], eax
    mov dword [rbx + B_TOPDOWN], 0
    test ecx, ecx
    jz .bad
    jns .height_ready
    neg ecx
    mov dword [rbx + B_TOPDOWN], 1
.height_ready:
    cmp ecx, BMP_MAX_DIM
    ja .bad
    mov [rbx + B_HEIGHT], ecx
    mov [rbx + B_BPP], edx
    mov [rbx + B_COMP], r8d
    ; validate bpp/compression pairs
    cmp r8d, BMP_COMP_RGB
    je .comp_rgb
    cmp r8d, BMP_COMP_RLE8
    je .comp_rle8
    cmp r8d, BMP_COMP_RLE4
    je .comp_rle4
    cmp r8d, BMP_COMP_BITFIELDS
    je .comp_fields
    cmp r8d, BMP_COMP_ALPHABITFIELDS
    je .comp_fields
    jmp .bad
.comp_rgb:
    cmp edx, 1
    je .bpp_ok
    cmp edx, 2
    je .bpp_ok
    cmp edx, 4
    je .bpp_ok
    cmp edx, 8
    je .bpp_ok
    cmp edx, 16
    je .bpp_ok
    cmp edx, 24
    je .bpp_ok
    cmp edx, 32
    je .bpp_ok
    jmp .bad
.comp_rle8:
    cmp edx, 8
    je .bpp_ok
    jmp .bad
.comp_rle4:
    cmp edx, 4
    je .bpp_ok
    jmp .bad
.comp_fields:
    cmp edx, 16
    je .bpp_ok
    cmp edx, 32
    je .bpp_ok
    jmp .bad
.bpp_ok:
    ; source stride = ((width * bpp + 31) / 32) * 4
    mov eax, [rbx + B_WIDTH]
    imul rax, rdx
    add rax, 31
    shr rax, 5
    shl rax, 2
    mov [rbx + B_STRIDE], rax
    call bmp_setup_masks
    test eax, eax
    jnz .bad
    cmp dword [rbx + B_BPP], 8
    ja .no_palette
    mov ecx, r9d
    call bmp_read_palette
    test eax, eax
    jnz .bad
.no_palette:
    mov rdi, [rbx + B_ARENA]
    mov esi, [rbx + B_WIDTH]
    mov edx, [rbx + B_HEIGHT]
    mov ecx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jle .bad
    mov [rbx + B_PIXBUF], rax
    mov eax, [rbx + B_COMP]
    cmp eax, BMP_COMP_RLE8
    je .rle
    cmp eax, BMP_COMP_RLE4
    je .rle
    ; uncompressed: all rows must be present
    mov eax, [rbx + B_HEIGHT]
    imul rax, [rbx + B_STRIDE]
    add rax, [rbx + B_PIXOFF]
    cmp rax, [rbx + B_LEN]
    ja .bad
    mov dword [rbx + B_ROW], 0
.row:
    mov eax, [rbx + B_ROW]
    cmp eax, [rbx + B_HEIGHT]
    jae .done
    call bmp_row_pointers             ; r12 = source row, r13 = output row
    call bmp_decode_row
    inc dword [rbx + B_ROW]
    jmp .row
.rle:
    call bmp_decode_rle
    test eax, eax
    jnz .bad
.done:
    mov rax, [rbx + B_PIXBUF]
    add rsp, B_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.bad:
    xor eax, eax
    add rsp, B_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; bmp_setup_masks — rbx = state -> eax = 0 or -EINVAL.
;   Fills mask/shift/max for 16- and 32-bit images.
; ---------------------------------------------------------------------------
bmp_setup_masks:
    xor eax, eax
    mov [rbx + B_MASK + 12], eax      ; no alpha unless a mask says so
    mov ecx, [rbx + B_BPP]
    cmp ecx, 16
    je .masks_16
    cmp ecx, 32
    je .masks_32
    ret
.masks_16:
    mov dword [rbx + B_MASK], 0x7C00
    mov dword [rbx + B_MASK + 4], 0x03E0
    mov dword [rbx + B_MASK + 8], 0x001F
    jmp .masks_fields
.masks_32:
    mov dword [rbx + B_MASK], 0xFF0000
    mov dword [rbx + B_MASK + 4], 0xFF00
    mov dword [rbx + B_MASK + 8], 0xFF
.masks_fields:
    mov eax, [rbx + B_COMP]
    cmp eax, BMP_COMP_BITFIELDS
    je .masks_read
    cmp eax, BMP_COMP_ALPHABITFIELDS
    jne .masks_derive
.masks_read:
    ; masks follow a 40-byte header, or sit inside longer headers, at 54
    mov rdx, [rbx + B_DATA]
    mov ecx, 12
    cmp dword [rbx + B_COMP], BMP_COMP_ALPHABITFIELDS
    je .masks_alpha_len
    cmp dword [rbx + B_HDRSIZE], 56
    jb .masks_len_ready
.masks_alpha_len:
    mov ecx, 16
.masks_len_ready:
    lea rax, [rcx + 54]
    cmp rax, [rbx + B_LEN]
    ja .masks_bad
    mov eax, [rdx + 54]
    mov [rbx + B_MASK], eax
    mov eax, [rdx + 58]
    mov [rbx + B_MASK + 4], eax
    mov eax, [rdx + 62]
    mov [rbx + B_MASK + 8], eax
    cmp ecx, 16
    jb .masks_derive
    mov eax, [rdx + 66]
    mov [rbx + B_MASK + 12], eax
.masks_derive:
    xor ecx, ecx
.masks_channel:
    mov eax, [rbx + B_MASK + rcx * 4]
    xor edx, edx
    test eax, eax
    jz .masks_store
    bsf edx, eax                      ; shift = trailing zeros
    push rcx
    mov ecx, edx
    shr eax, cl
    pop rcx
    lea r8d, [rax + 1]
    test r8d, eax
    jnz .masks_bad                    ; mask bits must be contiguous
.masks_store:
    mov [rbx + B_SHIFT + rcx * 4], edx
    mov [rbx + B_MAX + rcx * 4], eax
    inc ecx
    cmp ecx, 4
    jb .masks_channel
    cmp dword [rbx + B_MAX], 0
    je .masks_bad
    cmp dword [rbx + B_MAX + 4], 0
    je .masks_bad
    cmp dword [rbx + B_MAX + 8], 0
    je .masks_bad
    xor eax, eax
    ret
.masks_bad:
    mov eax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; bmp_read_palette — rbx = state, ecx = colours used (0 = 1 << bpp)
;   -> eax = 0 or -EINVAL. Unlisted entries are opaque black.
; ---------------------------------------------------------------------------
bmp_read_palette:
    push r12
    lea rdi, [rbx + B_PALETTE]
    mov r8d, ecx
    mov eax, 0xFF000000
    mov ecx, 256
    rep stosd
    mov ecx, [rbx + B_BPP]
    mov eax, 1
    shl eax, cl
    test r8d, r8d
    jz .pal_count
    cmp r8d, eax
    jbe .pal_listed
.pal_count:
    mov r8d, eax
.pal_listed:
    mov [rbx + B_PALCOUNT], r8d
    ; palette follows the header (and BITFIELDS masks after a 40-byte one)
    mov r12d, [rbx + B_HDRSIZE]
    add r12, 14
    mov r9d, 4                        ; entry size
    cmp dword [rbx + B_HDRSIZE], 12
    jne .pal_entry_ready
    mov r9d, 3
.pal_entry_ready:
    mov eax, r8d
    imul eax, r9d
    lea rax, [r12 + rax]
    cmp rax, [rbx + B_LEN]
    ja .pal_bad
    mov rdx, [rbx + B_DATA]
    add rdx, r12
    xor ecx, ecx
.pal_entry:
    cmp ecx, r8d
    jae .pal_done
    movzx eax, word [rdx]
    movzx r10d, byte [rdx + 2]
    shl r10d, 16
    or eax, r10d
    or eax, 0xFF000000
    mov [rbx + B_PALETTE + rcx * 4], eax
    add rdx, r9
    inc ecx
    jmp .pal_entry
.pal_done:
    xor eax, eax
    pop r12
    ret
.pal_bad:
    mov eax, -(EINVAL)
    pop r12
    ret

; ---------------------------------------------------------------------------
; bmp_row_pointers — rbx = state, B_ROW = output row
;   -> r12 = source row, r13 = output row (rows are stored bottom-up unless
;   the height was negative).
; ---------------------------------------------------------------------------
bmp_row_pointers:
    mov eax, [rbx + B_ROW]
    cmp dword [rbx + B_TOPDOWN], 0
    jne .rows_ready
    mov eax, [rbx + B_HEIGHT]
    sub eax, [rbx + B_ROW]
    dec eax
.rows_ready:
    imul rax, [rbx + B_STRIDE]
    mov r12, [rbx + B_DATA]
    add r12, [rbx + B_PIXOFF]
    add r12, rax
    mov rdx, [rbx + B_PIXBUF]
    mov eax, [rbx + B_ROW]
    imul rax, [rdx + PixBuf_stride]
    mov r13, [rdx + PixBuf_data]
    add r13, rax
    ret

; ---------------------------------------------------------------------------
; bmp_decode_row — rbx = state, r12 = source row, r13 = output row (BGRA)
; ---------------------------------------------------------------------------
bmp_decode_row:
    push r14
    push r15
    mov r14d, [rbx + B_WIDTH]
    xor r15d, r15d                    ; x
    mov ecx, [rbx + B_BPP]
    cmp ecx, 8
    jbe .row_indexed
    cmp ecx, 24
    je .row_24
.row_masked:
    cmp r15d, r14d
    jae .row_done
    cmp dword [rbx + B_BPP], 16
    jne .masked_32
    movzx eax, word [r12 + r15 * 2]
    jmp .masked_pixel
.masked_32:
    mov eax, [r12 + r15 * 4]
.masked_pixel:
    call bmp_unmask
    mov [r13 + r15 * 4], eax
    inc r15d
    jmp .row_masked
.row_24:
    cmp r15d, r14d
    jae .row_done
    lea rax, [r15 + r15 * 2]
    movzx edx, word [r12 + rax]
    movzx eax, byte [r12 + rax + 2]
    shl eax, 16
    or eax, edx
    or eax, 0xFF000000
    mov [r13 + r15 * 4], eax
    inc r15d
    jmp .row_24
.row_indexed:
    ; index of pixel x: bits MSB-first, bpp bits each
    cmp r15d, r14d
    jae .row_done
    mov eax, r15d
    imul eax, ecx                     ; bit offset
    mov edx, eax
    shr edx, 3
    movzx edx, byte [r12 + rdx]
    and eax, 7
    add eax, ecx
    neg eax
    add eax, 8                        ; right shift = 8 - (bit + bpp)
    xchg ecx, eax
    shr edx, cl
    xchg ecx, eax
    mov eax, 1
    shl eax, cl
    dec eax
    and edx, eax
    mov eax, [rbx + B_PALETTE + rdx * 4]
    mov [r13 + r15 * 4], eax
    inc r15d
    jmp .row_indexed
.row_done:
    pop r15
    pop r14
    ret

; ---------------------------------------------------------------------------
; bmp_unmask — rbx = state, eax = raw 16/32-bit pixel -> eax = BGRA
;   Each channel: ((pixel & mask) >> shift) * 255 / max; no alpha mask = 255.
; ---------------------------------------------------------------------------
bmp_unmask:
    push r12
    push r13
    mov r12d, eax
    xor r13d, r13d                    ; packed result
    mov r8d, 2                        ; output byte for R; G = 1, B = 0
    xor r9d, r9d                      ; channel: R, G, B, A
.unmask_channel:
    mov eax, [rbx + B_MASK + r9 * 4]
    test eax, eax
    jz .unmask_default
    and eax, r12d
    mov ecx, [rbx + B_SHIFT + r9 * 4]
    shr eax, cl
    mov ecx, [rbx + B_MAX + r9 * 4]
    cmp ecx, 255
    je .unmask_value
    imul eax, eax, 255
    xor edx, edx
    div ecx
    jmp .unmask_value
.unmask_default:
    mov eax, 255                      ; only the alpha mask can be absent
.unmask_value:
    mov ecx, r8d
    shl ecx, 3
    shl eax, cl
    or r13d, eax
    dec r8d
    cmp r9d, 2
    jne .unmask_next
    mov r8d, 3                        ; after B comes A in byte 3
.unmask_next:
    inc r9d
    cmp r9d, 4
    jb .unmask_channel
    mov eax, r13d
    pop r13
    pop r12
    ret

; ---------------------------------------------------------------------------
; bmp_decode_rle — rbx = state -> eax = 0 or -EINVAL. RLE8 / RLE4 into an
;   index plane (unset pixels stay index 0), then palette expansion.
;   Rows run bottom-up; writes outside the image are dropped.
; ---------------------------------------------------------------------------
bmp_decode_rle:
    push r12
    push r13
    push r14
    push r15
    mov eax, [rbx + B_WIDTH]
    imul eax, [rbx + B_HEIGHT]
    mov r14, rax                      ; plane size
    mov rdi, [rbx + B_ARENA]
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jle .rle_bad
    mov [rbx + B_INDEXES], rax
    mov rdi, rax
    mov rcx, r14
    xor eax, eax
    rep stosb
    mov r12, [rbx + B_DATA]
    mov r13, [rbx + B_PIXOFF]         ; source position
    xor r14d, r14d                    ; x
    xor r15d, r15d                    ; y, counted from the bottom row
.rle_next:
    lea rax, [r13 + 2]
    cmp rax, [rbx + B_LEN]
    ja .rle_expand                    ; truncated: keep what was decoded
    movzx ecx, byte [r12 + r13]       ; count
    movzx edx, byte [r12 + r13 + 1]   ; value / command
    add r13, 2
    test ecx, ecx
    jz .rle_escape
.rle_run:
    mov eax, edx
    cmp dword [rbx + B_COMP], BMP_COMP_RLE4
    jne .rle_run_put
    shr eax, 4                        ; RLE4: high nibble, then the low one
.rle_run_put:
    push rcx
    push rdx
    call bmp_rle_put
    pop rdx
    pop rcx
    ; RLE4 runs alternate nibbles: swap them after each pixel
    cmp dword [rbx + B_COMP], BMP_COMP_RLE4
    jne .rle_run_step
    rol dl, 4
.rle_run_step:
    dec ecx
    jnz .rle_run
    jmp .rle_next
.rle_escape:
    cmp edx, 0
    je .rle_eol
    cmp edx, 1
    je .rle_expand
    cmp edx, 2
    je .rle_delta
    ; absolute mode: edx literal pixels, padded to a 16-bit boundary
    mov ecx, edx
    mov eax, edx
    cmp dword [rbx + B_COMP], BMP_COMP_RLE4
    jne .abs_bytes
    inc eax
    shr eax, 1                        ; RLE4: two pixels per byte
.abs_bytes:
    lea rdx, [r13 + rax]
    cmp rdx, [rbx + B_LEN]
    ja .rle_expand
    push rax
    lea r9, [r12 + r13]               ; literal pixels
    xor r8d, r8d                      ; pixel index within the run
.abs_pixel:
    cmp r8d, ecx
    jae .abs_done
    cmp dword [rbx + B_COMP], BMP_COMP_RLE4
    je .abs_nibble
    movzx eax, byte [r9 + r8]
    jmp .abs_put
.abs_nibble:
    mov edx, r8d
    shr edx, 1
    movzx eax, byte [r9 + rdx]
    test r8d, 1
    jnz .abs_low
    shr eax, 4
.abs_low:
    and eax, 15
.abs_put:
    push rcx
    push r8
    push r9
    call bmp_rle_put
    pop r9
    pop r8
    pop rcx
    inc r8d
    jmp .abs_pixel
.abs_done:
    pop rax
    inc rax
    and rax, -2                       ; word-aligned
    add r13, rax
    jmp .rle_next
.rle_eol:
    xor r14d, r14d
    inc r15d
    jmp .rle_next
.rle_delta:
    lea rax, [r13 + 2]
    cmp rax, [rbx + B_LEN]
    ja .rle_expand
    movzx eax, byte [r12 + r13]
    add r14d, eax
    movzx eax, byte [r12 + r13 + 1]
    add r15d, eax
    add r13, 2
    jmp .rle_next
.rle_expand:
    mov dword [rbx + B_ROW], 0
.rle_row:
    mov eax, [rbx + B_ROW]
    cmp eax, [rbx + B_HEIGHT]
    jae .rle_done
    ; index plane row 0 is the bottom image row
    mov ecx, [rbx + B_HEIGHT]
    sub ecx, eax
    dec ecx
    cmp dword [rbx + B_TOPDOWN], 0
    je .rle_src_ready
    mov ecx, eax
.rle_src_ready:
    imul ecx, [rbx + B_WIDTH]
    mov rsi, [rbx + B_INDEXES]
    add rsi, rcx
    mov rdx, [rbx + B_PIXBUF]
    imul rax, [rdx + PixBuf_stride]
    mov rdi, [rdx + PixBuf_data]
    add rdi, rax
    xor ecx, ecx
.rle_px:
    cmp ecx, [rbx + B_WIDTH]
    jae .rle_row_next
    movzx eax, byte [rsi + rcx]
    mov eax, [rbx + B_PALETTE + rax * 4]
    mov [rdi + rcx * 4], eax
    inc ecx
    jmp .rle_px
.rle_row_next:
    inc dword [rbx + B_ROW]
    jmp .rle_row
.rle_done:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.rle_bad:
    mov eax, -(EINVAL)
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; bmp_rle_put — rbx = state, eax = index (low bits), r14d = x, r15d = y.
;   Stores the index if (x, y) is inside the image, then advances x.
bmp_rle_put:
    cmp dword [rbx + B_COMP], BMP_COMP_RLE4
    jne .put_check
    and eax, 15
.put_check:
    cmp r14d, [rbx + B_WIDTH]
    jae .put_skip
    cmp r15d, [rbx + B_HEIGHT]
    jae .put_skip
    mov ecx, r15d
    imul ecx, [rbx + B_WIDTH]
    add ecx, r14d
    mov rdx, [rbx + B_INDEXES]
    mov [rdx + rcx], al
.put_skip:
    inc r14d
    ret

section .data
global bmp_version
bmp_version: dq 0x020000
