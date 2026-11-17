; PNG probe, filters, validation, and one-pixel end-to-end decode tests.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern png_probe
extern png_unfilter_row
extern png_decode
extern png_encode
extern qoi_encode
extern qoi_decode
extern pixbuf_create
extern crc32_ieee
extern pixbuf_premultiply
extern arena_init

section .text

global test_png_suite
global test_png_main
test_png_suite:
test_png_main:
    PROLOGUE_SAVE rbx
    xor ebx,ebx
    call test_png_probe
    add ebx,eax
    call test_png_probe_reject
    add ebx,eax
    call test_png_filters
    add ebx,eax
    call test_png_decode_rgba
    add ebx,eax
    call test_png_iend_crc
    add ebx,eax
    call test_png_encode
    add ebx,eax
    call test_qoi_encode
    add ebx,eax
    call test_qoi_compact
    add ebx,eax
    mov eax,ebx
    EPILOGUE_RESTORE rbx
    ret

global test_png_probe
test_png_probe:
    lea rdi,[rel png_rgba]
    mov esi,png_rgba_end-png_rgba
    call png_probe
    cmp eax,1
    jne .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

global test_png_probe_reject
test_png_probe_reject:
    lea rdi,[rel bad_signature]
    mov esi,bad_signature_end-bad_signature
    call png_probe
    test eax,eax
    jnz .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

; Exercises None, Sub, Up, Average, Paeth, and invalid-filter rejection.
global test_png_filters
global test_png_unfilter_none
global test_png_unfilter_sub
test_png_unfilter_none:
test_png_unfilter_sub:
test_png_filters:
    lea rdi,[rel row_none+1]
    xor esi,esi
    mov edx,3
    mov ecx,1
    call png_unfilter_row
    test eax,eax
    jnz .fail
    lea rdi,[rel row_none+1]
    call .check_10_20_30
    jnz .fail
    lea rdi,[rel row_sub+1]
    xor esi,esi
    mov edx,3
    mov ecx,1
    call png_unfilter_row
    test eax,eax
    jnz .fail
    lea rdi,[rel row_sub+1]
    call .check_10_20_30
    jnz .fail
    lea rdi,[rel row_up+1]
    lea rsi,[rel prior_up]
    mov edx,3
    mov ecx,1
    call png_unfilter_row
    test eax,eax
    jnz .fail
    lea rdi,[rel row_up+1]
    call .check_10_20_30
    jnz .fail
    lea rdi,[rel row_average+1]
    lea rsi,[rel prior_average]
    mov edx,3
    mov ecx,1
    call png_unfilter_row
    test eax,eax
    jnz .fail
    lea rdi,[rel row_average+1]
    call .check_10_20_30
    jnz .fail
    lea rdi,[rel row_paeth+1]
    lea rsi,[rel prior_paeth]
    mov edx,3
    mov ecx,1
    call png_unfilter_row
    test eax,eax
    jnz .fail
    lea rdi,[rel row_paeth+1]
    call .check_10_20_30
    jnz .fail
    lea rdi,[rel row_invalid+1]
    xor esi,esi
    mov edx,1
    mov ecx,1
    call png_unfilter_row
    cmp eax,-EINVAL
    jne .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret
.check_10_20_30:
    cmp byte [rdi],10
    jne .different
    cmp byte [rdi+1],20
    jne .different
    cmp byte [rdi+2],30
    jne .different
    xor eax,eax
    ret
.different:
    mov eax,1
    ret

global test_png_decode_rgba
test_png_decode_rgba:
    lea rdi,[rel png_test_arena]
    lea rsi,[rel png_test_storage]
    mov edx,65536
    call arena_init
    test eax,eax
    jnz .fail
    lea rdi,[rel png_test_arena]
    lea rsi,[rel png_rgba]
    mov edx,png_rgba_end-png_rgba
    call png_decode
    test rax,rax
    jz .fail
    cmp qword [rax+PixBuf.width],1
    jne .fail
    cmp qword [rax+PixBuf.height],1
    jne .fail
    mov rdx,[rax+PixBuf.data]
    cmp dword [rdx],0xffff0000
    jne .fail
    xor eax,eax
    ret
.fail:
    mov eax,1
    ret

section .data
row_none: db 0,10,20,30
row_sub: db 1,10,10,10
row_up: db 2,9,18,27
prior_up: db 1,2,3
row_average: db 3,5,5,5
prior_average: db 10,20,30
row_paeth: db 4,5,5,5
prior_paeth: db 5,15,25
row_invalid: db 5,0

section .rodata
bad_signature: db 0x89,'P','N','X',13,10,26,10
bad_signature_end:
png_rgba:
    db 0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a
    db 0,0,0,13, 'I','H','D','R', 0,0,0,1, 0,0,0,1, 8,6,0,0,0
    db 0x1f,0x15,0xc4,0x89
    db 0,0,0,13, 'I','D','A','T'
    db 0x78,0x9c,0x63,0xf8,0xcf,0xc0,0xf0,0x1f,0,5,0,1,0xff
    db 0x89,0x99,0x3d,0x1d
    db 0,0,0,0, 'I','E','N','D', 0xae,0x42,0x60,0x82
png_rgba_end:

section .text

; MED-11: crc32_ieee is PNG's: "IEND" gives AE 42 60 82
test_png_iend_crc:
    sub rsp, 8
    lea rdi, [rel s_iend]
    mov esi, 4
    call crc32_ieee
    add rsp, 8
    cmp eax, 0xAE426082
    jne .fail
    xor eax, eax
    ret
.fail:
    mov eax, 1
    ret

; A 200x100 image (enc_fill: runs, small steps, jumps, colours seen before,
; see-through pixels) encoded (%1) and decoded again (%2) -> eax = 0 if
; every pixel came back, 1 if not
%define ENC_W   200
%define ENC_H   100
%define ENC_STORAGE (1024 * 1024)
%define PB_WIDTH    0                   ; PixBuf fields (ugfx.inc)
%define PB_HEIGHT   8
%define PB_STRIDE   16
%define PB_DATA     32
%macro ROUND_TRIP 2
    sub rsp, 8
    call enc_fill
    test rax, rax
    js .fail
    lea rdi, [rel enc_arena]
    mov rsi, [rel enc_image]
    call %1
    test rax, rax
    js .fail
    lea rdi, [rel enc_arena]
    mov rsi, rax
    call %2
    test rax, rax
    jle .fail
    mov [rel enc_decoded], rax
    mov rdi, rax                        ; premultiplied, as images are kept
    call pixbuf_premultiply
    mov rdi, [rel enc_decoded]
    call enc_same
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro
test_png_encode:
    ROUND_TRIP png_encode, png_decode
test_qoi_encode:
    ROUND_TRIP qoi_encode, qoi_decode

; QOI's ops used where they fit, by the bytes each image takes (header 14,
; end 8): 64 pixels of two colours far apart by turns, 4 + 4 for the first two, then
; one each from the index; a 64-pixel ramp up by 1 a channel, one each as
; small differences; 200 pixels the colour QOI starts from, four runs
%macro QOI_SIZE 2                       ; pixel maker, bytes expected
    lea rdi, [rel enc_arena]
    lea rsi, [rel enc_storage]
    mov edx, ENC_STORAGE
    call arena_init
    lea rdi, [rel enc_arena]
    mov rsi, [rel enc_width]
    mov edx, 1
    mov ecx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    js .fail
    mov [rel enc_image], rax
    mov rdi, [rax + PB_DATA]
    xor ecx, ecx
%%pixel:
    call %1
    mov [rdi + rcx * 4], edx
    inc ecx
    cmp ecx, 200
    jb %%pixel
    lea rdi, [rel enc_arena]
    mov rsi, [rel enc_image]
    call qoi_encode
    test rax, rax
    js .fail
    cmp rdx, %2
    jne .fail
%endmacro
test_qoi_compact:
    sub rsp, 8
    mov qword [rel enc_width], 64
    QOI_SIZE by_turns, 14 + 4 + 4 + 62 + 8
    QOI_SIZE ramp, 14 + 64 + 8
    mov qword [rel enc_width], 200
    QOI_SIZE same, 14 + 4 + 8
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret

; ecx = x -> edx: grey and dark blue by turns; ramp: x + 1 in each channel;
; same: black, opaque
by_turns:
    mov edx, 0xFF808080
    test ecx, 1
    jz .out
    mov edx, 0xFF102030
.out:
    ret
ramp:
    lea edx, [rcx + 1]
    imul edx, edx, 0x010101
    or edx, 0xFF000000
    ret
same:
    mov edx, 0xFF000000
    ret

; a fresh arena and the image in it -> rax = 0, negative error
enc_fill:
    sub rsp, 8
    lea rdi, [rel enc_arena]
    lea rsi, [rel enc_storage]
    mov edx, ENC_STORAGE
    call arena_init
    lea rdi, [rel enc_arena]
    mov esi, ENC_W
    mov edx, ENC_H
    mov ecx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    js .out
    mov [rel enc_image], rax
    xor r8d, r8d                        ; y
.row:
    mov rax, [rel enc_image]
    mov rdi, r8
    imul rdi, [rax + PB_STRIDE]
    add rdi, [rax + PB_DATA]
    xor ecx, ecx                        ; x
.pixel:
    call enc_pixel
    mov [rdi + rcx * 4], edx
    inc ecx
    cmp ecx, ENC_W
    jb .pixel
    inc r8d
    cmp r8d, ENC_H
    jb .row
    xor eax, eax
.out:
    add rsp, 8
    ret

; ecx = x, r8d = y -> edx = the pixel there (opaque, half see-through at
; x 7, or all 0)
enc_pixel:
    cmp ecx, 6                          ; the first six of a row: one colour
    jb .run
    cmp ecx, 7
    jne .not_half
    mov edx, 0x80404040                 ; straight 128s: back to 64s exactly
    ret
.not_half:
    mov eax, ecx
    xor edx, edx
    push rcx
    mov r9d, 31
    div r9d
    pop rcx
    test edx, edx
    jz .clear                           ; see-through
    mov eax, ecx
    xor edx, edx
    push rcx
    mov r9d, 17
    div r9d
    pop rcx
    test edx, edx
    jz .jump
    lea edx, [rcx * 2 + r8]            ; small steps
    and edx, 0xFF
    shl edx, 8
    lea eax, [rcx * 3]
    and eax, 0xFF
    shl eax, 16
    or edx, eax
    lea eax, [r8 * 4 + r8]
    add eax, ecx
    and eax, 0xFF
    or edx, eax
    or edx, 0xFF000000
    ret
.run:
    mov edx, 0xFF336699
    ret
.jump:
    mov edx, 0xFFC0FFEE
    test r8d, 1
    jz .out
    mov edx, 0xFF336699                 ; seen before: the index
.out:
    ret
.clear:
    xor edx, edx
    ret

; rdi = the decoded PixBuf -> eax = 0 if it is the image, pixel for pixel
enc_same:
    cmp qword [rdi + PB_WIDTH], ENC_W
    jne .differ
    cmp qword [rdi + PB_HEIGHT], ENC_H
    jne .differ
    mov rsi, [rel enc_image]
    xor r8d, r8d
.row:
    mov r9, r8
    imul r9, [rdi + PB_STRIDE]
    add r9, [rdi + PB_DATA]
    mov r10, r8
    imul r10, [rsi + PB_STRIDE]
    add r10, [rsi + PB_DATA]
    xor ecx, ecx
.pixel:
    mov eax, [r9 + rcx * 4]
    cmp eax, [r10 + rcx * 4]
    jne .differ
    inc ecx
    cmp ecx, ENC_W
    jb .pixel
    inc r8d
    cmp r8d, ENC_H
    jb .row
    xor eax, eax
    ret
.differ:
    mov eax, 1
    ret

section .rodata
s_iend:         db "IEND"

section .bss
alignb 16
enc_arena:      resb 32
enc_image:      resq 1
enc_width:      resq 1
enc_decoded:    resq 1
alignb 16
enc_storage:    resb ENC_STORAGE
alignb 16
png_test_arena: resb 32
alignb 16
png_test_storage: resb 65536

section .data
global test_png_version
test_png_version: dq 0x010100
