; =============================================================================
; str/encoding/euc_kr.asm
; EUC-KR (Korean) ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm                (EncCodec struct)
;   encoding/tables/euc_kr_table.s     (generated mapping)
;
; -----------------------------------------------------------------------------
; EUC-KR is the standard Korean encoding (also known as the basis of the
; Windows CP949 / UHC superset).
;
; Structure:
;   - 0x00-0x7F:  ASCII
;   - Double byte: lead 0xA1-0xFE, trail 0xA1-0xFE → KS X 1001 (Hangul,
;     Hanja, symbols). This covers 2350 precomposed Hangul syllables plus
;     Hanja and symbols.
;
; Mapping is via a generated 94×94 table.
;
; (CP949/UHC extends the lead/trail ranges to cover all 11172 modern Hangul
; syllables; this file implements EUC-KR proper. CP949 can reuse the same
; logic with a wider table.)
;
; Functions:
;   str_euc_kr_decode_one
;   str_euc_kr_encode_one
;   str_euc_kr_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_euc_kr_name: db "EUC-KR", 0

extern _euckr_to_unicode            ; 94×94 indexed table
extern _euckr_from_unicode_keys
extern _euckr_from_unicode_vals
extern _euckr_from_unicode_count

section .text

; -----------------------------------------------------------------------------
; str_euc_kr_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_euc_kr_decode_one

    test    rsi, rsi
    jz      .kd_empty

    movzx   eax, byte [rdi]

    cmp     al, 0x80
    jb      .kd_ascii

    ; lead 0xA1-0xFE
    cmp     al, 0xA1
    jb      .kd_invalid
    cmp     al, 0xFE
    ja      .kd_invalid

    cmp     rsi, 2
    jb      .kd_short

    movzx   ecx, byte [rdi + 1]
    cmp     cl, 0xA1
    jb      .kd_invalid
    cmp     cl, 0xFE
    ja      .kd_invalid

    ; index = (lead-0xA1)*94 + (trail-0xA1)
    sub     eax, 0xA1
    imul    eax, eax, 94
    sub     ecx, 0xA1
    add     eax, ecx

    lea     r8, [rel _euckr_to_unicode]
    movzx   eax, word [r8 + rax * 2]
    test    eax, eax
    jz      .kd_invalid

    mov     [rdx], eax
    mov     rax, 2
    pop     rbp
    ret

.kd_ascii:
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.kd_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.kd_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

.kd_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_euc_kr_decode_one

; -----------------------------------------------------------------------------
; str_euc_kr_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_euc_kr_encode_one

    test    rdx, rdx
    jz      .ke_nospace

    cmp     edi, 0x7F
    jbe     .ke_ascii

    ; binary search reverse table
    lea     r8, [rel _euckr_from_unicode_keys]
    lea     r9, [rel _euckr_from_unicode_vals]
    mov     r10, [rel _euckr_from_unicode_count]
    xor     r11, r11

.ke_search:
    cmp     r11, r10
    jae     .ke_unmappable
    mov     rcx, r11
    add     rcx, r10
    shr     rcx, 1
    movzx   eax, word [r8 + rcx * 2]
    cmp     eax, edi
    je      .ke_found
    jb      .ke_right
    mov     r10, rcx
    jmp     .ke_search
.ke_right:
    lea     r11, [rcx + 1]
    jmp     .ke_search

.ke_found:
    cmp     rdx, 2
    jb      .ke_nospace
    movzx   eax, word [r9 + rcx * 2]
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi], cl
    mov     [rsi + 1], al
    mov     rax, 2
    pop     rbp
    ret

.ke_ascii:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.ke_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ke_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_euc_kr_encode_one

; -----------------------------------------------------------------------------
; str_euc_kr_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_euc_kr_codec_struct:
    dq str_euc_kr_decode_one
    dq str_euc_kr_encode_one
    dq _euc_kr_name
    dq 2
    dq 0x02
    dq 0

section .text

STR_FUNC str_euc_kr_codec
    lea     rax, [rel _euc_kr_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_euc_kr_codec