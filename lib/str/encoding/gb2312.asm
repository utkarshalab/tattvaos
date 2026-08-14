%ifndef GUARD_LIB_STR_ENCODING_GB2312_ASM
%define GUARD_LIB_STR_ENCODING_GB2312_ASM
; =============================================================================
; str/encoding/gb2312.asm
; GB2312 / GBK (Simplified Chinese) ↔ UTF-8 codec.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   encoding/engine.asm                 (EncCodec struct)
;   encoding/tables/gb2312_table.s      (generated mapping)
;
; -----------------------------------------------------------------------------
; GB2312 is the foundational Simplified Chinese encoding. GBK extends it.
;
; Structure:
;   - Single bytes 0x00-0x7F: ASCII
;   - Double bytes: lead byte 0x81-0xFE, trail byte 0x40-0xFE
;     (GB2312 proper uses lead/trail in 0xA1-0xFE; GBK widens the range)
;
; A double-byte sequence maps to a Chinese character via a lookup table.
; The table is large (~7000 GB2312 chars, ~21000 with GBK) so it's in a
; generated data file. We index it by (lead, trail).
;
; This file holds the decode/encode LOGIC; the mapping arrays live in
; tables/gb2312_table.s, produced by tools/gen_encoding_tables.py from the
; Unicode Consortium's GB mapping file.
;
; Functions:
;   str_gb2312_decode_one
;   str_gb2312_encode_one
;   str_gb2312_codec
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .rodata
_gb2312_name: db "GB2312", 0

; External mapping tables (generated):
;   _gb2312_to_unicode : indexed by (lead-0x81)*191 + (trail-0x40) → uint16 cp
;   _gb2312_from_unicode : sorted (cp → gbk bytes) for reverse lookup




GB_LEAD_MIN     equ 0x81
GB_LEAD_MAX     equ 0xFE
GB_TRAIL_MIN    equ 0x40
GB_TRAIL_MAX    equ 0xFE
GB_TRAIL_SPAN   equ 191         ; 0x40..0xFE minus the hole at 0x7F

section .text

; -----------------------------------------------------------------------------
; str_gb2312_decode_one
;
; Signature:
;   int64_t str_gb2312_decode_one(const uint8_t *src, uint64_t src_len,
;                                  uint32_t *out_cp)
;
; Returns: bytes consumed (1 or 2), or negative error.
; -----------------------------------------------------------------------------

STR_FUNC str_gb2312_decode_one

    test    rsi, rsi
    jz      .gd_empty

    movzx   eax, byte [rdi]

    ; ASCII single byte
    cmp     al, 0x80
    jb      .gd_ascii

    ; double-byte: validate lead
    cmp     al, GB_LEAD_MIN
    jb      .gd_invalid
    cmp     al, GB_LEAD_MAX
    ja      .gd_invalid

    ; need a second byte
    cmp     rsi, 2
    jb      .gd_short

    movzx   ecx, byte [rdi + 1]     ; trail
    cmp     cl, GB_TRAIL_MIN
    jb      .gd_invalid
    cmp     cl, GB_TRAIL_MAX
    ja      .gd_invalid
    cmp     cl, 0x7F
    je      .gd_invalid             ; 0x7F is a hole

    ; compute table index: (lead - 0x81) * 191 + (trail - 0x40)
    ; adjust trail to skip the 0x7F hole
    sub     eax, GB_LEAD_MIN
    imul    eax, eax, GB_TRAIL_SPAN

    sub     ecx, GB_TRAIL_MIN
    cmp     byte [rdi + 1], 0x7F
    jb      .gd_no_adjust
    dec     ecx                     ; account for skipped 0x7F
.gd_no_adjust:
    add     eax, ecx

    ; look up codepoint
    lea     r8, [rel _gb2312_to_unicode]
    movzx   eax, word [r8 + rax * 2]
    test    eax, eax
    jz      .gd_invalid             ; unmapped slot

    mov     [rdx], eax
    mov     rax, 2
    pop     rbp
    ret

.gd_ascii:
    mov     [rdx], eax
    mov     rax, 1
    pop     rbp
    ret

.gd_invalid:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.gd_short:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

.gd_empty:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_gb2312_decode_one

; -----------------------------------------------------------------------------
; str_gb2312_encode_one
;
; Signature:
;   int64_t str_gb2312_encode_one(uint32_t cp, uint8_t *dst, uint64_t dst_cap)
;
; ASCII → 1 byte. Chinese → 2 bytes via reverse table (binary search).
; -----------------------------------------------------------------------------

STR_FUNC str_gb2312_encode_one

    test    rdx, rdx
    jz      .ge_nospace

    ; ASCII direct
    cmp     edi, 0x7F
    jbe     .ge_ascii

    ; binary search reverse table for codepoint → GBK bytes
    lea     r8, [rel _gb2312_from_unicode_keys]
    lea     r9, [rel _gb2312_from_unicode_vals]
    mov     r10, [rel _gb2312_from_unicode_count]

    xor     r11, r11            ; lo
    ; hi = count
.ge_search:
    cmp     r11, r10
    jae     .ge_unmappable

    mov     rcx, r11
    add     rcx, r10
    shr     rcx, 1              ; mid

    movzx   eax, word [r8 + rcx * 2]    ; key (cp)
    cmp     eax, edi
    je      .ge_found
    jb      .ge_go_right
    ; go left
    mov     r10, rcx
    jmp     .ge_search
.ge_go_right:
    lea     r11, [rcx + 1]
    jmp     .ge_search

.ge_found:
    ; value is the 2-byte GBK sequence (uint16, lead in high byte)
    cmp     rdx, 2
    jb      .ge_nospace
    movzx   eax, word [r9 + rcx * 2]
    mov     ecx, eax
    shr     ecx, 8
    mov     [rsi], cl           ; lead
    mov     [rsi + 1], al       ; trail
    mov     rax, 2
    pop     rbp
    ret

.ge_ascii:
    mov     [rsi], dil
    mov     rax, 1
    pop     rbp
    ret

.ge_unmappable:
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.ge_nospace:
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_gb2312_encode_one

; -----------------------------------------------------------------------------
; str_gb2312_codec
; -----------------------------------------------------------------------------

section .rodata
align 8
_gb2312_codec_struct:
    dq str_gb2312_decode_one
    dq str_gb2312_encode_one
    dq _gb2312_name
    dq 2
    dq 0x02                     ; ASCII_SUPERSET
    dq 0

section .text

STR_FUNC str_gb2312_codec
    lea     rax, [rel _gb2312_codec_struct]
    pop     rbp
    ret
STR_ENDFUNC str_gb2312_codec
%endif ; GUARD_LIB_STR_ENCODING_GB2312_ASM
