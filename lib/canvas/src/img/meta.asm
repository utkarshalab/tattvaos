; ============================================================================
; Meta — EXIF Orientation, Embedded ICC Profiles and XMP
; ============================================================================
; MED-03. image_meta reads what an image file says about itself besides its
; pixels, from JPEG (APP1 Exif and XMP, APP2 ICC_PROFILE in any number of
; chunks, joined in their order), PNG (eXIf, iCCP inflated, uncompressed
; iTXt XML:com.adobe.xmp), WebP (EXIF, ICCP, XMP; webp_inspect) and TIFF
; (IFD0's Orientation 274, XMP 700 and InterColorProfile 34675, as in every
; Exif block). An ICC profile is kept only if it looks like one (icc_probe,
; and no longer than its bytes). Joining JPEG chunks and inflating PNG's
; need an arena: without one the profile is left out and IMAGE_META_ICC_LATER
; set. Anything malformed is passed over, never refused.
;
; pixbuf_orient turns an image upright by its orientation (EXIF 1 to 8);
; image_decode does it for JPEG, PNG and WebP (TIFF's decoder already does).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern pixbuf_create
extern zlib_decompress
extern icc_probe
extern webp_inspect

%define ICC_MAX         (1 << 20)       ; an inflated PNG profile at most
%define TAG_ORIENTATION 274
%define TAG_XMP         700
%define TAG_ICC         34675

; orient_table's columns
%define O_SWAP  0
%define O_AX    1
%define O_AY    2
%define O_BX    3
%define O_BY    4
%define O_CX    5
%define O_CY    6

; image_meta's locals: the JPEG ICC chunk count, chunks seen (then the copy
; cursor), their bytes (then the chunk wanted); then a WebPInfo
%define M_COUNT         0
%define M_SEEN          8
%define M_TOTAL         16
%define M_WEBP          24
%define M_FRAME         ((M_WEBP + WebPInfo_size + 15) & ~15) + 8

section .text

; ---------------------------------------------------------------------------
; image_meta
;   An image file's orientation, ICC profile and XMP
;   IN:  rdi = arena* (0: no joining or inflating), rsi = data, rdx = length,
;        rcx = ImageMeta* (filled; orientation 1 when it says none)
;   OUT: rax = 0, -EINVAL for no data or no ImageMeta
; ---------------------------------------------------------------------------
global image_meta
image_meta:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, M_FRAME
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov rax, -(EINVAL)
    test r12, r12
    jz .return
    test r14, r14
    jz .return
    xor eax, eax
    mov ecx, ImageMeta_size / 8
    mov rdi, r14
    rep stosq
    mov dword [r14 + ImageMeta.orientation], 1
    xor eax, eax
    mov [rsp + M_COUNT], rax
    mov [rsp + M_SEEN], rax
    mov [rsp + M_TOTAL], rax
    cmp r13, 8
    jb .done
    cmp word [r12], 0xD8FF
    je .jpeg
    mov rax, 0x0A1A0A0D474E5089
    cmp [r12], rax
    je .png
    cmp word [r12], 0x4949
    je .tiff
    cmp word [r12], 0x4D4D
    je .tiff
    cmp r13, 12
    jb .done
    cmp dword [r12], 'RIFF'
    jne .done
    cmp dword [r12 + 8], 'WEBP'
    je .webp
    jmp .done

.tiff:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call tiff_meta
    jmp .check

; --- JPEG: segments up to the scan --------------------------------------
.jpeg:
    mov edx, 2
.jpeg_next:
    mov rdi, r12
    mov rsi, r13
    call jpeg_segment
    test eax, eax
    jz .jpeg_done
    mov r15, rdx                        ; the next marker
    lea rdi, [r12 + r8]                 ; the payload, ecx long
    cmp eax, 0xE1
    je .app1
    cmp eax, 0xE2
    jne .jpeg_continue
    call icc_chunk                      ; eax = sequence, edx = count
    test eax, eax
    jz .jpeg_continue
    cmp qword [rsp + M_COUNT], 0
    jne .counted
    mov [rsp + M_COUNT], rdx
.counted:
    cmp [rsp + M_COUNT], rdx
    je .same_count
    mov qword [rsp + M_COUNT], 256      ; chunks that disagree: never whole
.same_count:
    inc qword [rsp + M_SEEN]
    sub ecx, 14
    add [rsp + M_TOTAL], rcx
    cmp edx, 1
    jne .jpeg_continue
    add rdi, 14                         ; one chunk: the profile as it is
    mov [r14 + ImageMeta.icc], rdi
    mov [r14 + ImageMeta.icc_len], rcx
    jmp .jpeg_continue
.app1:
    cmp ecx, 6
    jb .jpeg_continue
    cmp dword [rdi], 'Exif'
    jne .app1_xmp
    cmp word [rdi + 4], 0
    jne .app1_xmp
    add rdi, 6
    sub ecx, 6
    call take_exif
    jmp .jpeg_continue
.app1_xmp:
    cmp qword [r14 + ImageMeta.xmp], 0
    jne .jpeg_continue
    lea rsi, [rel s_xmp_ns]
    mov edx, s_xmp_ns_len
    call has_prefix
    jne .jpeg_continue
    add rdi, rdx
    sub ecx, edx
    mov [r14 + ImageMeta.xmp], rdi
    mov [r14 + ImageMeta.xmp_len], rcx
.jpeg_continue:
    mov rdx, r15
    jmp .jpeg_next
.jpeg_done:
    mov rax, [rsp + M_COUNT]            ; chunks to join: every one, once
    cmp rax, 1
    jbe .check
    cmp rax, [rsp + M_SEEN]
    jne .check
    test rbx, rbx
    jz .later
    mov rdi, rbx
    mov rsi, [rsp + M_TOTAL]
    call arena_alloc
    test rax, rax
    jz .later
    mov [r14 + ImageMeta.icc], rax
    mov rcx, [rsp + M_TOTAL]
    mov [r14 + ImageMeta.icc_len], rcx
    mov [rsp + M_SEEN], rax             ; the copy cursor
    mov qword [rsp + M_TOTAL], 1        ; the chunk wanted
.join:
    mov edx, 2
.join_next:
    mov rdi, r12
    mov rsi, r13
    call jpeg_segment
    test eax, eax
    jz .missing
    mov r15, rdx
    cmp eax, 0xE2
    jne .join_continue
    lea rdi, [r12 + r8]
    call icc_chunk
    cmp rax, [rsp + M_TOTAL]
    jne .join_continue
    lea rsi, [rdi + 14]
    sub ecx, 14
    mov rdi, [rsp + M_SEEN]
    rep movsb
    mov [rsp + M_SEEN], rdi
    inc qword [rsp + M_TOTAL]
    mov rax, [rsp + M_TOTAL]
    cmp rax, [rsp + M_COUNT]
    ja .check
    jmp .join
.join_continue:
    mov rdx, r15
    jmp .join_next
.missing:                               ; a sequence number twice, one not
    mov qword [r14 + ImageMeta.icc], 0
    mov qword [r14 + ImageMeta.icc_len], 0
    jmp .check
.later:
    or dword [r14 + ImageMeta.flags], IMAGE_META_ICC_LATER
    jmp .check

; --- PNG: every chunk up to IEND ----------------------------------------
.png:
    mov r15d, 8
.chunk:
    lea rax, [r15 + 12]
    cmp rax, r13
    ja .check
    mov ecx, [r12 + r15]
    bswap ecx                           ; its length
    lea rax, [r15 + rcx + 12]
    cmp rax, r13
    ja .check
    mov eax, [r12 + r15 + 4]
    lea rdi, [r12 + r15 + 8]            ; its data, ecx long
    lea r15, [r15 + rcx + 12]
    cmp eax, 'IEND'
    je .check
    cmp eax, 'eXIf'
    je .exif
    cmp eax, 'iCCP'
    je .iccp
    cmp eax, 'iTXt'
    je .itxt
    jmp .chunk
.exif:
    call take_exif
    jmp .chunk
.iccp:                                  ; name, 0, method 0, zlib
    cmp qword [r14 + ImageMeta.icc], 0
    jne .chunk
    xor eax, eax
.name:
    cmp eax, ecx
    jae .chunk
    cmp eax, 80
    jae .chunk
    cmp byte [rdi + rax], 0
    je .named
    inc eax
    jmp .name
.named:
    lea edx, [rax + 2]
    cmp edx, ecx
    jae .chunk
    cmp byte [rdi + rax + 1], 0
    jne .chunk
    test rbx, rbx
    jz .png_later
    add rdi, rdx
    sub ecx, edx
    mov [rsp + M_COUNT], rdi            ; the stream
    mov [rsp + M_SEEN], rcx
    mov rdi, rbx
    mov esi, ICC_MAX
    call arena_alloc
    test rax, rax
    jz .png_later
    mov [rsp + M_TOTAL], rax
    mov rdi, rbx
    mov rsi, [rsp + M_COUNT]
    mov rdx, [rsp + M_SEEN]
    mov rcx, rax
    mov r8d, ICC_MAX
    call zlib_decompress
    test rax, rax
    jle .chunk
    mov [r14 + ImageMeta.icc_len], rax
    mov rax, [rsp + M_TOTAL]
    mov [r14 + ImageMeta.icc], rax
    jmp .chunk
.png_later:
    or dword [r14 + ImageMeta.flags], IMAGE_META_ICC_LATER
    jmp .chunk
.itxt:                                  ; keyword, 0, not compressed, method,
    cmp qword [r14 + ImageMeta.xmp], 0  ; language 0, keyword 0, the text
    jne .chunk
    lea rsi, [rel s_xmp_key]
    mov edx, s_xmp_key_len
    call has_prefix
    jne .chunk
    cmp ecx, s_xmp_key_len + 2
    jb .chunk
    cmp byte [rdi + s_xmp_key_len], 0
    jne .chunk
    mov eax, s_xmp_key_len + 2
    mov edx, 2                          ; two strings to pass
.skip:
    cmp eax, ecx
    jae .chunk
    cmp byte [rdi + rax], 0
    je .skipped
    inc eax
    jmp .skip
.skipped:
    inc eax
    dec edx
    jnz .skip
    cmp eax, ecx
    jae .chunk
    sub ecx, eax
    add rdi, rax
    mov [r14 + ImageMeta.xmp], rdi
    mov [r14 + ImageMeta.xmp_len], rcx
    jmp .chunk

; --- WebP: its chunks, as webp_inspect finds them -----------------------
.webp:
    mov rdi, r12
    mov rsi, r13
    lea rdx, [rsp + M_WEBP]
    call webp_inspect
    test eax, eax
    jnz .check
    mov rax, [rsp + M_WEBP + WebPInfo.icc]
    mov [r14 + ImageMeta.icc], rax
    mov rax, [rsp + M_WEBP + WebPInfo.icc_len]
    mov [r14 + ImageMeta.icc_len], rax
    mov rax, [rsp + M_WEBP + WebPInfo.xmp]
    mov [r14 + ImageMeta.xmp], rax
    mov rax, [rsp + M_WEBP + WebPInfo.xmp_len]
    mov [r14 + ImageMeta.xmp_len], rax
    mov rdi, [rsp + M_WEBP + WebPInfo.exif]
    mov rcx, [rsp + M_WEBP + WebPInfo.exif_len]
    test rdi, rdi
    jz .check
    cmp rcx, 6                          ; some writers keep JPEG's prefix
    jb .webp_exif
    cmp dword [rdi], 'Exif'
    jne .webp_exif
    cmp word [rdi + 4], 0
    jne .webp_exif
    add rdi, 6
    sub rcx, 6
.webp_exif:
    call take_exif

.check:                                 ; a profile only if it is one
    mov rdi, [r14 + ImageMeta.icc]
    test rdi, rdi
    jz .done
    mov rsi, [r14 + ImageMeta.icc_len]
    call icc_probe
    test rax, rax
    jz .not_icc
    mov rdi, [r14 + ImageMeta.icc]
    mov eax, [rdi]
    bswap eax
    cmp rax, [r14 + ImageMeta.icc_len]
    jbe .done
.not_icc:
    mov qword [r14 + ImageMeta.icc], 0
    mov qword [r14 + ImageMeta.icc_len], 0
.done:
    xor eax, eax
.return:
    add rsp, M_FRAME
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; pixbuf_orient
;   An image turned upright by its EXIF orientation
;   IN:  rdi = arena*, rsi = PixBuf* (4 bytes a pixel), edx = orientation
;   OUT: rax = the image itself for 1 (or none of 2 to 8), else a new one
;        (rotated, mirrored or both, width and height swapped for 5 to 8),
;        0 out of memory
; ---------------------------------------------------------------------------
global pixbuf_orient
pixbuf_orient:
    mov rax, rsi
    lea ecx, [rdx - 2]
    cmp ecx, 6
    jbe .turn
    ret
.turn:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rsi
    lea r12, [rel orient_table]
    lea r12, [r12 + rcx * 8]
    mov rsi, [rbx + PixBuf.width]
    mov rdx, [rbx + PixBuf.height]
    cmp byte [r12 + O_SWAP], 0
    je .dims
    xchg rsi, rdx
.dims:
    mov rcx, [rbx + PixBuf.format]
    call pixbuf_create
    test rax, rax
    jle .fail
    mov r13, rax
    mov r8, [rbx + PixBuf.stride]
    xor r14d, r14d                      ; where the first row starts
    cmp byte [r12 + O_AX], 0
    je .no_ax
    mov rax, [rbx + PixBuf.width]
    lea r14, [rax * 4 - 4]
.no_ax:
    cmp byte [r12 + O_AY], 0
    je .no_ay
    mov rax, [rbx + PixBuf.height]
    dec rax
    imul rax, r8
    add r14, rax
.no_ay:
    movsx rax, byte [r12 + O_BX]        ; a step right in the result
    shl rax, 2
    movsx r9, byte [r12 + O_BY]
    imul r9, r8
    add r9, rax
    movsx rax, byte [r12 + O_CX]        ; a step down
    shl rax, 2
    movsx r10, byte [r12 + O_CY]
    imul r10, r8
    add r10, rax
    add r14, [rbx + PixBuf.data]
    mov rdi, [r13 + PixBuf.data]
    mov r11, [r13 + PixBuf.height]
    mov rdx, [r13 + PixBuf.width]
.row:
    mov rsi, r14
    xor ecx, ecx
.column:
    mov eax, [rsi]
    mov [rdi + rcx * 4], eax
    add rsi, r9
    inc rcx
    cmp rcx, rdx
    jb .column
    add r14, r10
    add rdi, [r13 + PixBuf.stride]
    dec r11
    jnz .row
    mov rax, r13
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = data, rsi = length, rdx = a marker's offset -> eax = its marker (0:
; none, the scan or the end), r8 = its payload's offset, ecx = its length,
; rdx = the next marker's offset
jpeg_segment:
    lea rax, [rdx + 4]
    cmp rax, rsi
    ja .end
    cmp byte [rdi + rdx], 0xFF
    jne .end
    movzx eax, byte [rdi + rdx + 1]
    cmp eax, 0xFF                       ; fill
    jne .marked
    inc rdx
    jmp jpeg_segment
.marked:
    cmp eax, 0xD9
    je .end
    cmp eax, 0xDA
    je .end
    lea r8, [rdx + 2]
    xor ecx, ecx
    mov r9d, eax
    and r9d, 0xF8
    cmp r9d, 0xD0                       ; restarts
    je .alone
    cmp eax, 0x01
    je .alone
    movzx ecx, word [rdi + rdx + 2]
    rol cx, 8
    cmp ecx, 2
    jb .end
    lea r9, [rdx + rcx + 2]
    cmp r9, rsi
    ja .end
    lea r8, [rdx + 4]
    sub ecx, 2
    mov rdx, r9
    ret
.alone:
    mov rdx, r8
    ret
.end:
    xor eax, eax
    ret

; rdi = an APP2 payload, ecx = its length -> eax = its ICC sequence number
; (0: not a chunk), edx = the count; rdi, rcx kept
icc_chunk:
    lea rsi, [rel s_icc]
    mov edx, s_icc_len
    call has_prefix
    jne .not
    cmp ecx, s_icc_len + 2
    jb .not
    movzx eax, byte [rdi + s_icc_len]
    movzx edx, byte [rdi + s_icc_len + 1]
    test eax, eax
    jz .not
    cmp eax, edx
    ja .not
    ret
.not:
    xor eax, eax
    ret

; rdi = data, ecx = its length, rsi = a prefix, edx = its length -> ZF set
; when the data begins with it; rdi, rcx, rdx kept
has_prefix:
    cmp ecx, edx
    jb .no
    xor r9d, r9d
.byte:
    cmp r9d, edx
    je .yes
    movzx eax, byte [rsi + r9]
    cmp al, [rdi + r9]
    jne .no
    inc r9d
    jmp .byte
.yes:
    cmp eax, eax
    ret
.no:
    test esp, esp
    ret

; rdi = an Exif block (a TIFF header on), rcx = its length, r14 = the
; ImageMeta: the first one kept and read
take_exif:
    cmp qword [r14 + ImageMeta.exif], 0
    jne .out
    mov [r14 + ImageMeta.exif], rdi
    mov [r14 + ImageMeta.exif_len], rcx
    mov rsi, rcx
    mov rdx, r14
    jmp tiff_meta
.out:
    ret

; rdi = a TIFF header, rsi = its bytes, rdx = ImageMeta*: IFD0's orientation
; and, where not found already, its XMP and ICC profile
tiff_meta:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp r12, 8
    jb .out
    movzx r11d, word [rbx]              ; the byte order
    cmp r11d, 0x4949
    je .order
    cmp r11d, 0x4D4D
    jne .out
.order:
    lea rdi, [rbx + 2]
    call rd16
    cmp eax, 42
    jne .out
    lea rdi, [rbx + 4]
    call rd32
    mov r10, rax                        ; IFD0
    lea rax, [r10 + 2]
    cmp rax, r12
    ja .out
    lea rdi, [rbx + r10]
    call rd16
    mov ecx, eax                        ; its entries
    add r10, 2
.entry:
    test ecx, ecx
    jz .out
    lea rax, [r10 + 12]
    cmp rax, r12
    ja .out
    lea rdi, [rbx + r10]
    call rd16
    mov r8d, eax                        ; the tag
    lea rdi, [rbx + r10 + 4]
    call rd32
    mov r9, rax                         ; its count
    cmp r8d, TAG_ORIENTATION
    je .orientation
    cmp r8d, TAG_XMP
    je .xmp
    cmp r8d, TAG_ICC
    je .icc
.next:
    add r10, 12
    dec ecx
    jmp .entry
.orientation:
    lea rdi, [rbx + r10 + 8]
    call rd16
    lea edx, [rax - 1]
    cmp edx, 7
    ja .next
    mov [r13 + ImageMeta.orientation], eax
    jmp .next
.xmp:
    lea rdx, [r13 + ImageMeta.xmp]
    jmp .block
.icc:
    lea rdx, [r13 + ImageMeta.icc]
.block:                                 ; r9 bytes, at an offset past 4
    cmp qword [rdx], 0
    jne .next
    cmp r9, 4
    jbe .next
    lea rdi, [rbx + r10 + 8]
    call rd32
    lea rdi, [rax + r9]                 ; both below 2^32: no wrap
    cmp rdi, r12
    ja .next
    add rax, rbx
    mov [rdx], rax
    mov [rdx + 8], r9
    jmp .next
.out:
    pop r13
    pop r12
    pop rbx
    ret

; tiff_meta's: rdi = 2 or 4 bytes, r11d = the byte order -> eax
rd16:
    movzx eax, word [rdi]
    cmp r11d, 0x4D4D
    jne .out
    rol ax, 8
.out:
    ret
rd32:
    mov eax, [rdi]
    cmp r11d, 0x4D4D
    jne .out
    bswap eax
.out:
    ret

section .rodata
; by orientation 2 to 8 (O_*): width and height swapped, the first pixel
; at the right, at the bottom; a step right, then down, in source x and y
orient_table:
    db 0, 1, 0, -1,  0,  0,  1, 0       ; 2 mirrored left to right
    db 0, 1, 1, -1,  0,  0, -1, 0       ; 3 turned half round
    db 0, 0, 1,  1,  0,  0, -1, 0       ; 4 mirrored top to bottom
    db 1, 0, 0,  0,  1,  1,  0, 0       ; 5 transposed
    db 1, 0, 1,  0, -1,  1,  0, 0       ; 6 a quarter clockwise
    db 1, 1, 1,  0, -1, -1,  0, 0       ; 7 transverse
    db 1, 1, 0,  0,  1, -1,  0, 0       ; 8 a quarter anticlockwise
s_icc:          db "ICC_PROFILE", 0
s_icc_len       equ $ - s_icc
s_xmp_ns:       db "http://ns.adobe.com/xap/1.0/", 0
s_xmp_ns_len    equ $ - s_xmp_ns
s_xmp_key:      db "XML:com.adobe.xmp", 0
s_xmp_key_len   equ $ - s_xmp_key

section .data
global meta_version
meta_version:   dq 0x010000
