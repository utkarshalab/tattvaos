%ifndef GUARD_LIB_STR_ENCODING_BIG5_ASM
%define GUARD_LIB_STR_ENCODING_BIG5_ASM
; =============================================================================
; str/encoding/big5.asm
; Big5 (Traditional Chinese) ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm              (EncCodec struct)
;   encoding/tables/big5_table.s     (generated mapping)
;
; -----------------------------------------------------------------------------
; Big5 is the dominant Traditional Chinese encoding (Taiwan, Hong Kong).
;
; Structure:
;   - Single bytes 0x00-0x7F: ASCII
;   - Double bytes: lead 0x81-0xFE, trail 0x40-0x7E or 0xA1-0xFE
;
; The trail byte has two valid ranges with a gap (0x7F-0xA0 invalid).
; Mapping is via a generated table indexed by (lead, trail).
;
; Functions:
;   str_big5_decode_one
;   str_big5_encode_one
;   str_big5_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_big5_name: db "Big5", 0

extern _big5_to_unicode             ; indexed table → uint16 codepoint


; Big5 trail byte: 0x40-0x7E (63 values) + 0xA1-0xFE (94 values) = 157
BIG5_TRAIL_SPAN equ 157

section .text

; -----------------------------------------------------------------------------
; _big5_trail_index  (internal)
;
; Map a trail byte to a 0..156 index, or -1 if invalid.
; Arguments: EAX = trail byte. Returns: EAX = index or -1.
; -----------------------------------------------------------------------------

_big5_trail_index:
    cmp     al, 0x40
    jb      .bti_invalid
    cmp     al, 0x7E
    jbe     .bti_low
    cmp     al, 0xA1
    jb      .bti_invalid
    cmp     al, 0xFE
    ja      .bti_invalid
    ; high range: 0xA1-0xFE → 63 + (trail - 0xA1)
    sub     eax, 0xA1
    add     eax, 63
    ret
.bti_low:
    ; 0x40-0x7E → 0..62
    sub     eax, 0x40
    ret
.bti_invalid:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; str_big5_decode_one
; -----------------------------------------------------------------------------

STR_FUNC str_big5_decode_one

    test    rsi, rsi
    jz      .bd_empty

    movzx   eax, byte [rdi]

    cmp     al, 0x80
    jb      .bd_ascii

    ; lead 0x81-0xFE
    cmp     al, 0x81
    jb      .bd_invalid
    cmp     al, 0xFE
    ja      .bd_invalid

    cmp     rsi, 2
    jb      .bd_short

    push    rax                 ; save lead
    movzx   eax, byte [rdi + 1]
    call    _big5_trail_index
    mov     ecx, eax            ; trail index
    pop     rax                 ; lead

    cmp     ecx, -1
    je      .bd_invalid

    ; index = (lead - 0x81) * 157 + trail_index
    sub     eax, 0x81
    imul    eax, eax, BIG5_TRAIL_SPAN
    add     eax, ecx

    lea     r8, [rel _big5_to_unicode]
    movzx   eax, word [r8 + rax * 2]
    test    eax, eax
    jz      .bd_invalid

    mov     [rdx], eax
    mov     rax, 2
    pop     rbp
    ret

.bd_ascii:
    mov     [rdx], eax
    mov     rax, 1
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

.bd_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_big5_decode_one

; -----------------------------------------------------------------------------
; str_big5_encode_one
; -----------------------------------------------------------------------------

STR_FUNC str_big5_encode_one

    test    rdx, rdx
    jz      .be_nospace

    cmp     edi, 0x7F
    jbe     .be_ascii

    ; binary search reverse table
    lea     r8, [rel _big5_from_unicode_keys]
    lea     r9, [rel _big5_from_unicode_vals]
    mov     r10, [rel _big5_from_unicode_count]
    xor     r11, r11

.be_search:
    cmp     r11, r10
    jae     .be_unmappable

    mov     rcx, r11
    add     rcx, r10
    shr     rcx, 1
    movzx   eax, word [r8 + rcx * 2]
    cmp     eax, edi
    je      .be_found
    jb      .be_right
    mov     r10, rcx
    jmp     .be_search
.be_right:
    lea     r11, [rcx + 1]
    jmp     .be_search

.be_found:
    cmp     rdx, 2
    jb      .be_nospace
    movzx   eax, word [r9 + rcx * 2]
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi], cl
    mov     [rsi + 1], al
    mov     rax, 2
    pop     rbp
    ret

.be_ascii:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.be_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.be_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_big5_encode_one

; -----------------------------------------------------------------------------
; str_big5_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_big5_codec_struct:
    dq str_big5_decode_one
    dq str_big5_encode_one
    dq _big5_name
    dq 2
    dq 0x02
    dq 0

section .text

STR_FUNC str_big5_codec
    lea     rax, [rel _big5_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_big5_codec
%endif ; GUARD_LIB_STR_ENCODING_BIG5_ASM
