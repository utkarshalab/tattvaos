%ifndef GUARD_LIB_STR_ENCODING_UTF32_ASM
%define GUARD_LIB_STR_ENCODING_UTF32_ASM
; =============================================================================
; str/encoding/utf32.asm
; UTF-32 LE/BE ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm  (EncCodec struct)
;
; -----------------------------------------------------------------------------
; UTF-32 is the simplest Unicode encoding: each codepoint is stored as a
; single 32-bit integer. Fixed width — no surrogates, no multi-unit logic.
;
;   LE: bytes in little-endian order
;   BE: bytes in big-endian order
;
; Validation: codepoint must be <= 0x10FFFF and not a surrogate
; (0xD800-0xDFFF).
;
; UTF-32 wastes space (4 bytes per char) but offers O(1) random access by
; codepoint index, useful for internal text processing.
;
; Functions:
;   str_utf32le_decode_one / str_utf32be_decode_one
;   str_utf32le_encode_one / str_utf32be_encode_one
;   str_utf32le_codec / str_utf32be_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_utf32le_name: db "UTF-32LE", 0
_utf32be_name: db "UTF-32BE", 0

section .text

; -----------------------------------------------------------------------------
; _validate_cp  (internal)
;
; Check codepoint in EAX is valid (<=0x10FFFF, not surrogate).
; Returns CF=1 if invalid.
; -----------------------------------------------------------------------------

%macro VALIDATE_CP 1        ; %1 = label to jump to on invalid
    cmp     eax, 0x10FFFF
    ja      %1
    cmp     eax, 0xD800
    jb      %%ok
    cmp     eax, 0xDFFF
    jbe     %1
%%ok:
%endmacro

; -----------------------------------------------------------------------------
; str_utf32le_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_utf32le_decode_one

    cmp     rsi, 4
    jb      .ld_short

    ; read 4 bytes LE
    movzx   eax, byte [rdi]
    movzx   ecx, byte [rdi + 1]
    shl     ecx, 8
    or      eax, ecx
    movzx   ecx, byte [rdi + 2]
    shl     ecx, 16
    or      eax, ecx
    movzx   ecx, byte [rdi + 3]
    shl     ecx, 24
    or      eax, ecx

    VALIDATE_CP .ld_invalid

    mov     [rdx], eax
    mov     rax, 4
    pop     rbp
    ret

.ld_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ld_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf32le_decode_one

; -----------------------------------------------------------------------------
; str_utf32be_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_utf32be_decode_one

    cmp     rsi, 4
    jb      .bd_short

    ; read 4 bytes BE
    movzx   eax, byte [rdi]
    shl     eax, 24
    movzx   ecx, byte [rdi + 1]
    shl     ecx, 16
    or      eax, ecx
    movzx   ecx, byte [rdi + 2]
    shl     ecx, 8
    or      eax, ecx
    movzx   ecx, byte [rdi + 3]
    or      eax, ecx

    VALIDATE_CP .bd_invalid

    mov     [rdx], eax
    mov     rax, 4
    pop     rbp
    ret

.bd_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.bd_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_utf32be_decode_one

; -----------------------------------------------------------------------------
; str_utf32le_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_utf32le_encode_one

    mov     eax, edi
    VALIDATE_CP .le_invalid

    cmp     rdx, 4
    jb      .le_nospace

    mov     [rsi], dil
    mov     eax, edi
    shr     eax, 8
    mov     [rsi + 1], al
    mov     eax, edi
    shr     eax, 16
    mov     [rsi + 2], al
    mov     eax, edi
    shr     eax, 24
    mov     [rsi + 3], al

    mov     rax, 4
    pop     rbp
    ret

.le_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.le_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf32le_encode_one

; -----------------------------------------------------------------------------
; str_utf32be_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_utf32be_encode_one

    mov     eax, edi
    VALIDATE_CP .be_invalid

    cmp     rdx, 4
    jb      .be_nospace

    mov     eax, edi
    shr     eax, 24
    mov     [rsi], al
    mov     eax, edi
    shr     eax, 16
    mov     [rsi + 1], al
    mov     eax, edi
    shr     eax, 8
    mov     [rsi + 2], al
    mov     [rsi + 3], dil

    mov     rax, 4
    pop     rbp
    ret

.be_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.be_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_utf32be_encode_one

; -----------------------------------------------------------------------------
; Codec descriptors
; -----------------------------------------------------------------------------

section .rodata
align 8
_utf32le_codec_struct:
    dq str_utf32le_decode_one
    dq str_utf32le_encode_one
    dq _utf32le_name
    dq 4
    dq 0
    dq 0

_utf32be_codec_struct:
    dq str_utf32be_decode_one
    dq str_utf32be_encode_one
    dq _utf32be_name
    dq 4
    dq 0
    dq 0

section .text

STR_FUNC str_utf32le_codec
    lea     rax, [rel _utf32le_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_utf32le_codec

STR_FUNC str_utf32be_codec
    lea     rax, [rel _utf32be_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_utf32be_codec
%endif ; GUARD_LIB_STR_ENCODING_UTF32_ASM
