; Image metadata (img/meta, MED-03): orientation, ICC profiles and XMP from
; JPEG, PNG and TIFF; pixbuf_orient in all eight orientations. Real files
; of every orientation, decoded upright, are in compare_images.py.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"

extern image_meta
extern pixbuf_orient
extern pixbuf_create
extern arena_init

%define TM_STORAGE (2 << 20)            ; PNG's profile is inflated into 1 MiB

section .text

global test_meta_suite
global test_meta_main
test_meta_suite:
test_meta_main:
    PROLOGUE_SAVE rbx
    sub rsp, 8
    xor ebx, ebx
    call tm_jpeg
    add ebx, eax
    call tm_png
    add ebx, eax
    call tm_tiff
    add ebx, eax
    call tm_bad
    add ebx, eax
    call tm_orient
    add ebx, eax
    mov eax, ebx
    add rsp, 8
    EPILOGUE_RESTORE rbx

; the meta's field %1 (a qword; IS_D a dword) must be %2
%macro IS 2
    cmp qword [rel tm_meta + ImageMeta.%1], %2
    jne .fail
%endmacro
%macro IS_D 2
    cmp dword [rel tm_meta + ImageMeta.%1], %2
    jne .fail
%endmacro
%macro AT 2                             ; field %1 points at label %2
    lea rax, [rel %2]
    cmp [rel tm_meta + ImageMeta.%1], rax
    jne .fail
%endmacro
%macro META 3                           ; arena 1 or 0, data, length
    mov edi, %1
    lea rsi, [rel %2]
    mov edx, %3
    call meta_of
    test rax, rax
    jnz .fail
%endmacro

; JPEG: orientation 6 from the first of two big-endian Exif blocks, XMP, a profile in two
; chunks stored out of order (joined in order), a comment that mentions
; ICC_PROFILE, a fill byte; a third chunk after the scan never seen. No
; arena: no profile, and it says one was left. Cut short in the first
; chunk's segment: never whole, so none
tm_jpeg:
    sub rsp, 8
    META 1, jpeg_meta, jpeg_meta_len
    IS_D orientation, 6
    IS_D flags, 0
    AT exif, jpeg_tiff
    IS exif_len, jpeg_tiff_len
    AT xmp, jpeg_xmp
    IS xmp_len, 12
    IS icc_len, 140
    mov rsi, [rel tm_meta + ImageMeta.icc]
    call is_profile
    jne .fail
    META 0, jpeg_meta, jpeg_meta_len
    IS_D orientation, 6
    IS icc, 0
    IS_D flags, IMAGE_META_ICC_LATER
    META 1, jpeg_meta, jpeg_cut - jpeg_meta
    IS_D orientation, 6
    IS icc, 0
    IS_D flags, 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; PNG: orientation 3 from a little-endian eXIf, the profile inflated from
; iCCP, XMP from iTXt; no arena: the rest without the profile. An eXIf
; after IEND never read
tm_png:
    sub rsp, 8
    META 1, png_meta, png_meta_len
    IS_D orientation, 3
    IS_D flags, 0
    AT exif, png_tiff
    AT xmp, png_xmp
    IS xmp_len, 12
    IS icc_len, 140
    mov rsi, [rel tm_meta + ImageMeta.icc]
    call is_profile
    jne .fail
    META 0, png_meta, png_meta_len
    IS_D orientation, 3
    IS icc, 0
    IS_D flags, IMAGE_META_ICC_LATER
    AT xmp, png_xmp
    META 1, png_after, png_after_len
    IS_D orientation, 1
    IS exif, 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; TIFF: IFD0's orientation 8, XMP and profile, pointing into the file
tm_tiff:
    sub rsp, 8
    META 0, tiff_meta, tiff_meta_len
    IS_D orientation, 8
    AT icc, tiff_icc
    IS icc_len, 140
    AT xmp, tiff_xmp
    IS xmp_len, 12
    IS exif, 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; passed over: orientation 9, XMP past the end, a "profile" that is not
; one, one longer than its bytes, one that does not inflate, compressed
; XMP; no data or no ImageMeta refused
tm_bad:
    sub rsp, 8
    META 1, tiff_bad, tiff_bad_len
    IS_D orientation, 1
    IS xmp, 0
    IS icc, 0
    META 0, tiff_long, tiff_long_len
    IS icc, 0
    META 1, png_zxmp, png_zxmp_len
    IS xmp, 0
    META 1, png_badz, png_badz_len
    IS icc, 0
    xor edi, edi
    xor esi, esi
    mov edx, 16
    lea rcx, [rel tm_meta]
    call image_meta
    cmp rax, -(EINVAL)
    jne .fail
    xor edi, edi
    lea rsi, [rel tiff_meta]
    mov edx, tiff_meta_len
    xor ecx, ecx
    call image_meta
    cmp rax, -(EINVAL)
    jne .fail
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; a 3x2 image of 0 to 5 by rows, in each orientation, against orient_expect;
; 1 the image itself
tm_orient:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8
    lea rdi, [rel tm_arena]
    lea rsi, [rel tm_storage]
    mov edx, TM_STORAGE
    call arena_init
    lea rdi, [rel tm_arena]
    mov esi, 3
    mov edx, 2
    mov ecx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jle .fail
    mov r12, rax
    xor ecx, ecx                        ; y
.fill_row:
    mov rdi, rcx
    imul rdi, [r12 + PixBuf.stride]
    add rdi, [r12 + PixBuf.data]
    lea eax, [rcx + rcx * 2]
    mov [rdi], eax
    inc eax
    mov [rdi + 4], eax
    inc eax
    mov [rdi + 8], eax
    inc ecx
    cmp ecx, 2
    jb .fill_row
    mov ebx, 1
    lea r13, [rel orient_expect]
.each:
    lea rdi, [rel tm_arena]
    mov rsi, r12
    mov edx, ebx
    call pixbuf_orient
    test rax, rax
    jz .fail
    cmp ebx, 1
    jne .compare
    cmp rax, r12
    jne .fail
.compare:
    mov ecx, [r13]
    cmp [rax + PixBuf.width], rcx
    jne .fail
    mov ecx, [r13 + 4]
    cmp [rax + PixBuf.height], rcx
    jne .fail
    xor r8d, r8d                        ; the pixel expected
    xor r9d, r9d                        ; y
.row:
    mov r10, r9
    imul r10, [rax + PixBuf.stride]
    add r10, [rax + PixBuf.data]
    xor r11d, r11d                      ; x
.pixel:
    mov edx, [r10 + r11 * 4]
    cmp edx, [r13 + r8 * 4 + 8]
    jne .fail
    inc r8d
    inc r11d
    cmp r11d, [r13]
    jb .pixel
    inc r9d
    cmp r9d, [r13 + 4]
    jb .row
    add r13, 32
    inc ebx
    cmp ebx, 8
    jbe .each
    xor eax, eax
    jmp .out
.fail:
    mov eax, 1
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; edi = 1: a fresh arena, 0: none; rsi = data, edx = its length ->
; image_meta's, into tm_meta
meta_of:
    push rsi
    push rdx
    sub rsp, 8
    test edi, edi
    jz .none
    lea rdi, [rel tm_arena]
    lea rsi, [rel tm_storage]
    mov edx, TM_STORAGE
    call arena_init
    lea rdi, [rel tm_arena]
    jmp .call
.none:
    xor edi, edi
.call:
    add rsp, 8
    pop rdx
    pop rsi
    lea rcx, [rel tm_meta]
    jmp image_meta

; rsi = 140 bytes -> ZF set when they are icc_ref
is_profile:
    lea rdi, [rel icc_ref]
    mov ecx, 140
    repe cmpsb
    ret

section .rodata
; the profile: its size (140), the 'acsp' signature at 36, then 30 bytes of
; 0x22 to end the first chunk and 70 of 0x33 for the second
%macro ICC_PART1 0
    db 0, 0, 0, 140
    times 32 db 0x11
    db 'acsp'
    times 30 db 0x22
%endmacro
%macro ICC_PART2 0
    times 70 db 0x33
%endmacro
icc_ref:
    ICC_PART1
    ICC_PART2

jpeg_meta:
    db 0xFF, 0xD8
    db 0xFF, 0xE1, 0, (jpeg_tiff_end - jpeg_tiff) + 8
    db "Exif", 0, 0
jpeg_tiff:
    db 'MM', 0, 42, 0, 0, 0, 8
    db 0, 1                             ; one entry: orientation 6
    db 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 6, 0, 0
    db 0, 0, 0, 0
jpeg_tiff_end:
jpeg_tiff_len equ jpeg_tiff_end - jpeg_tiff
    db 0xFF, 0xE1, 0, 34                ; a second Exif block: not read
    db "Exif", 0, 0
    db 'MM', 0, 42, 0, 0, 0, 8
    db 0, 1
    db 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 3, 0, 0
    db 0, 0, 0, 0
    db 0xFF, 0xE1, 0, 2 + 29 + 12
    db "http://ns.adobe.com/xap/1.0/", 0
jpeg_xmp:
    db "<x:xmpmeta/>"
    db 0xFF, 0xFE, 0, 2 + 12            ; a comment that is no chunk
    db "ICC_PROFILE", 0
    db 0xFF                             ; fill
    db 0xFF, 0xE2, 0, 2 + 14 + 70
    db "ICC_PROFILE", 0, 2, 2
    ICC_PART2
    db 0xFF, 0xE2, 0, 2 + 14 + 70
jpeg_cut_base:
    db "ICC_PROFILE", 0, 1, 2
    ICC_PART1
    db 0xFF, 0xDA, 0, 2                 ; the scan: nothing more read
    db 0xFF, 0xE2, 0, 2 + 14 + 70
    db "ICC_PROFILE", 0, 2, 2
    ICC_PART2
    db 0xFF, 0xD9
jpeg_meta_len equ $ - jpeg_meta
jpeg_cut equ jpeg_cut_base + 10

png_meta:
    db 0x89, "PNG", 13, 10, 26, 10
    db 0, 0, 0, png_tiff_end - png_tiff
    db 'eXIf'
png_tiff:
    db 'II', 42, 0, 8, 0, 0, 0
    db 1, 0                             ; orientation 3
    db 0x12, 0x01, 3, 0, 1, 0, 0, 0, 3, 0, 0, 0
    db 0, 0, 0, 0
png_tiff_end:
    dd 0
    db 0, 0, 0, png_iccp_end - png_iccp
    db 'iCCP'
png_iccp:
    db "icc", 0, 0
    db 0x78, 0x01                       ; zlib: one stored block
    db 0x01, 140, 0, 0x73, 0xFF
    ICC_PART1
    ICC_PART2
    db 0x38, 0xCB, 0x16, 0x42           ; its Adler-32
png_iccp_end:
    dd 0
    db 0, 0, 0, png_itxt_end - png_itxt
    db 'iTXt'
png_itxt:
    db "XML:com.adobe.xmp", 0, 0, 0, 0, 0
png_xmp:
    db "<x:xmpmeta/>"
png_itxt_end:
    dd 0
    db 0, 0, 0, 0, 'IEND'
    dd 0
png_meta_len equ $ - png_meta

png_after:                              ; IEND, then an eXIf
    db 0x89, "PNG", 13, 10, 26, 10
    db 0, 0, 0, 0, 'IEND'
    dd 0
    db 0, 0, 0, png_late_end - png_late
    db 'eXIf'
png_late:
    db 'II', 42, 0, 8, 0, 0, 0
    db 1, 0
    db 0x12, 0x01, 3, 0, 1, 0, 0, 0, 8, 0, 0, 0
    db 0, 0, 0, 0
png_late_end:
    dd 0
png_after_len equ $ - png_after

tiff_meta:
    db 'II', 42, 0, 8, 0, 0, 0
    db 3, 0
    db 0x12, 0x01, 3, 0, 1, 0, 0, 0, 8, 0, 0, 0
    db 0xBC, 0x02, 1, 0, 12, 0, 0, 0
    dd tiff_xmp - tiff_meta
    db 0x73, 0x87, 7, 0, 140, 0, 0, 0
    dd tiff_icc - tiff_meta
    dd 0
tiff_xmp:
    db "<x:xmpmeta/>"
tiff_icc:
    ICC_PART1
    ICC_PART2
tiff_meta_len equ $ - tiff_meta

tiff_bad:
    db 'MM', 0, 42, 0, 0, 0, 8
    db 0, 3
    db 0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 9, 0, 0      ; orientation 9
    db 0x02, 0xBC, 0, 1, 0, 0, 0x0F, 0xA0, 0, 0, 0, 8 ; 4000 bytes at 8
    db 0x87, 0x73, 0, 7, 0, 0, 0, 140                 ; 140 at 50, no acsp
    db 0, 0, 0, 50
    db 0, 0, 0, 0
    db 0, 0, 0, 140                     ; the right size, no signature
    times 136 db 0x44
tiff_bad_len equ $ - tiff_bad

tiff_long:                              ; a profile that says 200 bytes, 140
    db 'II', 42, 0, 8, 0, 0, 0
    db 1, 0
    db 0x73, 0x87, 7, 0, 140, 0, 0, 0, 26, 0, 0, 0
    dd 0
    db 0, 0, 0, 200
    times 32 db 0x11
    db 'acsp'
    times 100 db 0x22
tiff_long_len equ $ - tiff_long

png_zxmp:                               ; XMP marked compressed
    db 0x89, "PNG", 13, 10, 26, 10
    db 0, 0, 0, png_zxmp_end - png_zxmp_data
    db 'iTXt'
png_zxmp_data:
    db "XML:com.adobe.xmp", 0, 1, 0, 0, 0
    db "<x:xmpmeta/>"
png_zxmp_end:
    dd 0
    db 0, 0, 0, 0, 'IEND'
    dd 0
png_zxmp_len equ $ - png_zxmp

png_badz:                               ; the profile, its Adler-32 wrong
    db 0x89, "PNG", 13, 10, 26, 10
    db 0, 0, 0, png_badz_end - png_badz_data
    db 'iCCP'
png_badz_data:
    db "icc", 0, 0
    db 0x78, 0x01
    db 0x01, 140, 0, 0x73, 0xFF
    ICC_PART1
    ICC_PART2
    db 0x38, 0xCB, 0x16, 0x43
png_badz_end:
    dd 0
    db 0, 0, 0, 0, 'IEND'
    dd 0
png_badz_len equ $ - png_badz

; by orientation 1 to 8: width, height, the pixels by rows
orient_expect:
    dd 3, 2, 0, 1, 2, 3, 4, 5
    dd 3, 2, 2, 1, 0, 5, 4, 3
    dd 3, 2, 5, 4, 3, 2, 1, 0
    dd 3, 2, 3, 4, 5, 0, 1, 2
    dd 2, 3, 0, 3, 1, 4, 2, 5
    dd 2, 3, 3, 0, 4, 1, 5, 2
    dd 2, 3, 5, 2, 4, 1, 3, 0
    dd 2, 3, 2, 5, 1, 4, 0, 3

section .bss
alignb 16
tm_meta:        resb ImageMeta_size
alignb 16
tm_arena:       resb 32
alignb 16
tm_storage:     resb TM_STORAGE
