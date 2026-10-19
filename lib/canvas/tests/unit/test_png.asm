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
    cmp qword [rax+PixBuf_width],1
    jne .fail
    cmp qword [rax+PixBuf_height],1
    jne .fail
    mov rdx,[rax+PixBuf_data]
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

section .bss
alignb 16
png_test_arena: resb 32
alignb 16
png_test_storage: resb 65536

section .data
global test_png_version
test_png_version: dq 0x010100
