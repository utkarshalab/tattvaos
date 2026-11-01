; ============================================================================
; Unit Test — Inflate and Adler-32 (src/img/inflate.asm, adler32.asm)
; ============================================================================
; test_inflate_suite -> eax = failed cases (each case returns 0 / 1).
; Inflate: stored and fixed-Huffman blocks, a back reference, a full output,
; damaged streams. Adler-32: known values and a resumed checksum. Real
; dynamic-Huffman streams are covered by the PNG corpus.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern inflate
extern adler32
extern memcmp

section .text

global test_inflate_suite
global test_inflate_main
test_inflate_suite:
test_inflate_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE ti_stored
    CASE ti_fixed
    CASE ti_backref
    CASE ti_out_full
    CASE ti_bad_block
    CASE ti_stored_nlen
    CASE ta_known
    CASE ta_resume
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; inflate the stream %1 (length %1_len) into out with room %2
%macro INFLATE 2
    xor edi, edi
    lea rsi, [rel %1]
    mov edx, %1_len
    lea rcx, [rel out]
    mov r8d, %2
    call inflate
%endmacro
; the output is the %2 bytes at %1 (rax = its length) -> jump .fail if not
%macro OUT_IS 2
    cmp rax, %2
    jne .fail
    lea rdi, [rel out]
    lea rsi, [rel %1]
    mov edx, %2
    call memcmp
    test eax, eax
    jnz .fail
%endmacro

ti_stored:
    sub rsp, 8
    INFLATE z_stored, 64
    OUT_IS s_hello, 5
    PASS

ti_fixed:
    sub rsp, 8
    INFLATE z_fixed, 64
    OUT_IS s_hello, 5
    PASS

ti_backref:
    sub rsp, 8
    INFLATE z_backref, 64
    OUT_IS s_abab, 20
    PASS

ti_out_full:
    sub rsp, 8
    INFLATE z_stored, 3
    cmp rax, -(ENOSPC)
    jne .fail
    PASS

ti_bad_block:
    sub rsp, 8
    INFLATE z_badtype, 64
    cmp rax, -(EINVAL)
    jne .fail
    PASS

ti_stored_nlen:
    sub rsp, 8
    INFLATE z_badnlen, 64
    cmp rax, -(EINVAL)
    jne .fail
    PASS

ta_known:
    sub rsp, 8
    lea rdi, [rel s_wikipedia]
    mov esi, 9
    mov edx, 1
    call adler32
    cmp eax, 0x11E60398
    jne .fail
    lea rdi, [rel s_wikipedia]
    xor esi, esi
    mov edx, 1
    call adler32
    cmp eax, 1
    jne .fail
    PASS

ta_resume:
    sub rsp, 8
    lea rdi, [rel s_wikipedia]
    mov esi, 4
    mov edx, 1
    call adler32
    lea rdi, [rel s_wikipedia + 4]
    mov esi, 5
    mov edx, eax
    call adler32
    cmp eax, 0x11E60398
    jne .fail
    PASS

section .rodata
s_hello:        db "hello"
s_abab:         db "abababababababababab"
s_wikipedia:    db "Wikipedia"

z_stored:       db 0x01, 0x05, 0x00, 0xFA, 0xFF, "hello"
z_stored_len    equ $ - z_stored
z_fixed:        db 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00
z_fixed_len     equ $ - z_fixed
z_backref:      db 0x4B, 0x4C, 0x4A, 0xC4, 0x80, 0x00            ; zlib: "ab" then a copy
z_backref_len   equ $ - z_backref
z_badtype:      db 0x07, 0x00                   ; block type 3
z_badtype_len   equ $ - z_badtype
z_badnlen:      db 0x01, 0x05, 0x00, 0xFA, 0xFE, "hello"
z_badnlen_len   equ $ - z_badnlen

section .bss
out:    resb 64
