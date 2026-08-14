%ifndef GUARD_LIB_STR_ENCODING_GBK_ASM
%define GUARD_LIB_STR_ENCODING_GBK_ASM
; =============================================================================
; str/encoding/gbk.asm
; GBK (Code Page 936) codec — GB2312 superset for Simplified Chinese.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/encode.asm   (str_utf8_encode_unchecked)
;   utf8/decode.asm   (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; GBK extends GB2312 to cover ~21000 Chinese characters (vs GB2312's ~7445).
; It is the de facto standard for Simplified Chinese on Windows (CP936).
;
; Byte structure:
;   0x00-0x7F  — single-byte ASCII
;   0x81-0xFE  — lead byte of double-byte character
;     trail byte:
;       0x40-0x7E  — GBK/3 and GBK/4 extensions (not in GB2312)
;       0x80-0xFE  — includes GB2312 range (0xA1-0xFE) and extensions
;
; GBK ranges (by lead/trail):
;   GBK/1: A1-A9 / A1-FE   (symbols, from GB2312)
;   GBK/2: B0-F7 / A1-FE   (level 1+2 hanzi, from GB2312)
;   GBK/3: 81-A0 / 40-7E, 80-FE  (extension)
;   GBK/4: AA-FE / 40-7E, 80-A0  (extension)
;   GBK/5: A8-A9 / 40-7E, 80-A0  (user-defined, usually empty)
;
; Total double-byte space: 126 lead × 190 trail = 23940 slots
;   trail_index: 0x40-0x7E → 0..62 (63 vals)
;                0x80-0xFE → 63..189 (127 vals)  total 190
;
; Table layout:
;   index = (lead - 0x81) * 190 + trail_index
;   _gbk_to_unicode[index] = uint16 codepoint (0 = unmapped)
;
; Functions:
;   str_gbk_decode_one   — decode one GBK character → codepoint
;   str_gbk_encode_one   — encode one codepoint → GBK bytes
;   str_gbk_to_utf8      — bulk GBK → UTF-8
;   str_gbk_from_utf8    — bulk UTF-8 → GBK
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


extern _gbk_to_unicode              ; uint16[23940] lookup table

GBK_LEAD_MIN       equ 0x81
GBK_LEAD_MAX       equ 0xFE
GBK_TRAIL_LOW_MIN  equ 0x40
GBK_TRAIL_LOW_MAX  equ 0x7E
GBK_TRAIL_HIGH_MIN equ 0x80
GBK_TRAIL_HIGH_MAX equ 0xFE
GBK_TRAIL_SLOTS    equ 190         ; 63 + 127

section .text

; -----------------------------------------------------------------------------
; str_gbk_decode_one
;
; Decode one GBK character from a byte stream.
;
; Signature:
;   int64_t str_gbk_decode_one(const uint8_t *src, uint64_t src_len,
;                               uint32_t *out_cp, uint64_t *out_advance)
;
; Arguments:
;   RDI  — source bytes
;   RSI  — remaining length
;   RDX  — output codepoint
;   RCX  — bytes consumed
; -----------------------------------------------------------------------------

STR_FUNC str_gbk_decode_one

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    test    rsi, rsi
    jz      .gd_end

    movzx   eax, byte [rdi]

    ; single-byte ASCII
    cmp     al, 0x80
    jb      .gd_ascii

    ; double-byte: need lead + trail
    cmp     rsi, 2
    jb      .gd_invalid

    cmp     al, GBK_LEAD_MIN
    jb      .gd_invalid
    cmp     al, GBK_LEAD_MAX
    ja      .gd_invalid

    movzx   r8d, al             ; lead
    movzx   r9d, byte [rdi + 1] ; trail

    ; compute trail index
    cmp     r9d, GBK_TRAIL_LOW_MIN
    jb      .gd_invalid
    cmp     r9d, GBK_TRAIL_LOW_MAX
    jbe     .gd_trail_low

    cmp     r9d, GBK_TRAIL_HIGH_MIN
    jb      .gd_invalid
    cmp     r9d, GBK_TRAIL_HIGH_MAX
    ja      .gd_invalid

    ; high range: 0x80-0xFE → index 63..189
    mov     eax, r9d
    sub     eax, GBK_TRAIL_HIGH_MIN
    add     eax, 63
    jmp     .gd_lookup

.gd_trail_low:
    ; low range: 0x40-0x7E → index 0..62
    mov     eax, r9d
    sub     eax, GBK_TRAIL_LOW_MIN

.gd_lookup:
    ; index = (lead - 0x81) * 190 + trail_index
    mov     r10d, r8d
    sub     r10d, GBK_LEAD_MIN
    imul    r10d, GBK_TRAIL_SLOTS
    add     r10d, eax

    ; table lookup
    lea     r11, [rel _gbk_to_unicode]
    movzx   eax, word [r11 + r10 * 2]

    test    eax, eax
    jz      .gd_invalid         ; unmapped

    mov     [rdx], eax

    test    rcx, rcx
    jz      .gd_ok
    mov     qword [rcx], 2

.gd_ok:
    xor     eax, eax
    pop     rbp
    ret

.gd_ascii:
    mov     [rdx], eax
    test    rcx, rcx
    jz      .gd_ok
    mov     qword [rcx], 1
    xor     eax, eax
    pop     rbp
    ret

.gd_invalid:
    mov     dword [rdx], 0xFFFD     ; replacement character
    test    rcx, rcx
    jz      .gd_inv_ret
    mov     qword [rcx], 1          ; skip 1 byte
.gd_inv_ret:
    mov     rax, STR_ERR_INVALID
    pop     rbp
    ret

.gd_end:
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_gbk_decode_one

; -----------------------------------------------------------------------------
; str_gbk_to_utf8
;
; Bulk convert GBK → UTF-8.
;
; Signature:
;   int64_t str_gbk_to_utf8(const uint8_t *src, uint64_t src_len,
;                            uint8_t *dst, uint64_t dst_cap,
;                            uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_gbk_to_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; src_len
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out_len

    xor     r9, r9              ; src offset
    xor     r10, r10            ; dst offset

.gt_loop:
    cmp     r9, r12
    jae     .gt_done

    ; decode one GBK char
    sub     rsp, 16
    and     rsp, -16

    lea     rdi, [rbx + r9]
    mov     rsi, r12
    sub     rsi, r9
    lea     rdx, [rsp]          ; out_cp
    lea     rcx, [rsp + 8]      ; out_advance

    push    r9
    push    r10
    call    str_gbk_decode_one
    pop     r10
    pop     r9

    mov     r8d, [rsp]          ; codepoint
    mov     r11, [rsp + 8]      ; advance
    mov     rsp, rbp

    add     r9, r11             ; advance src

    ; encode to UTF-8
    lea     rax, [r10 + 4]
    cmp     rax, r14
    ja      .gt_overflow

    mov     edi, r8d
    lea     rsi, [r13 + r10]
    push    r9
    push    r10
    call    str_utf8_encode_unchecked
    pop     r10
    pop     r9

    add     r10, rax
    jmp     .gt_loop

.gt_done:
    test    r15, r15
    jz      .gt_ok
    mov     [r15], r10

.gt_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.gt_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_gbk_to_utf8
%endif ; GUARD_LIB_STR_ENCODING_GBK_ASM
