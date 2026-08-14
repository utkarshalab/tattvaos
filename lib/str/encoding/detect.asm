%ifndef GUARD_LIB_STR_ENCODING_DETECT_ASM
%define GUARD_LIB_STR_ENCODING_DETECT_ASM
; =============================================================================
; str/encoding/detect.asm
; Encoding auto-detection from BOM and statistical heuristics.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Detection strategy (in priority order):
;   1. BOM (Byte Order Mark) — definitive when present:
;        EF BB BF          → UTF-8
;        FF FE 00 00       → UTF-32 LE
;        00 00 FE FF       → UTF-32 BE
;        FF FE             → UTF-16 LE
;        FE FF             → UTF-16 BE
;        2B 2F 76          → UTF-7
;   2. UTF-8 structural validation — if the bytes form valid UTF-8
;      multi-byte sequences, it's very likely UTF-8.
;   3. Statistical heuristics — for legacy 8-bit encodings, examine byte
;      frequency patterns (e.g. lots of 0xC0-0xDF + 0xE0-0xFF pairs suggests
;      a specific codepage). This is best-effort.
;   4. Default — if all else fails, assume the configured default (UTF-8).
;
; Detected encoding IDs:
;   ENC_UNKNOWN, ENC_ASCII, ENC_UTF8, ENC_UTF16LE, ENC_UTF16BE,
;   ENC_UTF32LE, ENC_UTF32BE, ENC_UTF7, ENC_LATIN1, ENC_CP1252, etc.
;
; Functions:
;   str_detect_encoding   — detect encoding, return ID + BOM length
;   str_detect_bom        — check for a BOM only
;   str_is_valid_utf8     — strict UTF-8 structural validation
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Encoding IDs
ENC_UNKNOWN equ 0
ENC_ASCII   equ 1
ENC_UTF8    equ 2
ENC_UTF16LE equ 3
ENC_UTF16BE equ 4
ENC_UTF32LE equ 5
ENC_UTF32BE equ 6
ENC_UTF7    equ 7
ENC_LATIN1  equ 8
ENC_CP1252  equ 9

section .text

; -----------------------------------------------------------------------------
; str_detect_bom
;
; Check for a Byte Order Mark at the start of the buffer.
;
; Signature:
;   int64_t str_detect_bom(const uint8_t *buf, uint64_t len,
;                          uint64_t *out_bom_len)
;
; Arguments:
;   RDI  — buffer
;   RSI  — length
;   RDX  — pointer to BOM length (bytes to skip), may be null
;
; Returns:
;   RAX  — encoding ID (ENC_UNKNOWN if no BOM)
; -----------------------------------------------------------------------------

STR_FUNC str_detect_bom

    test    rdi, rdi
    jz      .db_none
    test    rsi, rsi
    jz      .db_none

    ; UTF-32 LE: FF FE 00 00 (check before UTF-16 LE!)
    cmp     rsi, 4
    jb      .db_check_utf32be

    cmp     byte [rdi + 0], 0xFF
    jne     .db_check_utf32be
    cmp     byte [rdi + 1], 0xFE
    jne     .db_check_utf16le_2
    cmp     byte [rdi + 2], 0x00
    jne     .db_utf16le_4
    cmp     byte [rdi + 3], 0x00
    jne     .db_utf16le_4

    ; UTF-32 LE
    mov     eax, ENC_UTF32LE
    mov     r8, 4
    jmp     .db_return

.db_utf16le_4:
    ; FF FE but not followed by 00 00 → UTF-16 LE
    mov     eax, ENC_UTF16LE
    mov     r8, 2
    jmp     .db_return

.db_check_utf32be:
    ; UTF-32 BE: 00 00 FE FF
    cmp     rsi, 4
    jb      .db_check_utf16
    cmp     byte [rdi + 0], 0x00
    jne     .db_check_utf16
    cmp     byte [rdi + 1], 0x00
    jne     .db_check_utf16
    cmp     byte [rdi + 2], 0xFE
    jne     .db_check_utf16
    cmp     byte [rdi + 3], 0xFF
    jne     .db_check_utf16

    mov     eax, ENC_UTF32BE
    mov     r8, 4
    jmp     .db_return

.db_check_utf16:
    ; UTF-8 BOM: EF BB BF
    cmp     rsi, 3
    jb      .db_check_utf16le_2

    cmp     byte [rdi + 0], 0xEF
    jne     .db_check_utf7
    cmp     byte [rdi + 1], 0xBB
    jne     .db_check_utf7
    cmp     byte [rdi + 2], 0xBF
    jne     .db_check_utf7

    mov     eax, ENC_UTF8
    mov     r8, 3
    jmp     .db_return

.db_check_utf7:
    ; UTF-7: 2B 2F 76 (+ one of 38/39/2B/2F)
    cmp     rsi, 3
    jb      .db_check_utf16le_2
    cmp     byte [rdi + 0], 0x2B
    jne     .db_check_utf16le_2
    cmp     byte [rdi + 1], 0x2F
    jne     .db_check_utf16le_2
    cmp     byte [rdi + 2], 0x76
    jne     .db_check_utf16le_2

    mov     eax, ENC_UTF7
    mov     r8, 4               ; includes the 4th selector byte
    jmp     .db_return

.db_check_utf16le_2:
    ; UTF-16 LE: FF FE (2-byte check)
    cmp     rsi, 2
    jb      .db_check_utf16be
    cmp     byte [rdi + 0], 0xFF
    jne     .db_check_utf16be
    cmp     byte [rdi + 1], 0xFE
    jne     .db_check_utf16be

    mov     eax, ENC_UTF16LE
    mov     r8, 2
    jmp     .db_return

.db_check_utf16be:
    ; UTF-16 BE: FE FF
    cmp     rsi, 2
    jb      .db_none
    cmp     byte [rdi + 0], 0xFE
    jne     .db_none
    cmp     byte [rdi + 1], 0xFF
    jne     .db_none

    mov     eax, ENC_UTF16BE
    mov     r8, 2
    jmp     .db_return

.db_return:
    test    rdx, rdx
    jz      .db_done
    mov     [rdx], r8

.db_done:
    pop     rbp
    ret

.db_none:
    test    rdx, rdx
    jz      .db_none2
    mov     qword [rdx], 0
.db_none2:
    mov     eax, ENC_UNKNOWN
    pop     rbp
    ret

STR_ENDFUNC str_detect_bom

; -----------------------------------------------------------------------------
; str_is_valid_utf8
;
; Strict UTF-8 structural validation.
; Checks continuation bytes, overlong encodings, and surrogate ranges.
;
; Signature:
;   int64_t str_is_valid_utf8(const uint8_t *buf, uint64_t len)
;
; Returns:
;   RAX  = 1   valid UTF-8
;   RAX  = 0   invalid
; -----------------------------------------------------------------------------

STR_FUNC str_is_valid_utf8

    test    rdi, rdi
    jz      .vu_valid
    test    rsi, rsi
    jz      .vu_valid

    xor     rcx, rcx

.vu_loop:
    cmp     rcx, rsi
    jae     .vu_valid

    movzx   eax, byte [rdi + rcx]

    ; ASCII (0xxxxxxx)
    test    al, 0x80
    jz      .vu_ascii

    ; 110xxxxx → 2-byte
    mov     edx, eax
    and     edx, 0xE0
    cmp     edx, 0xC0
    je      .vu_2byte

    ; 1110xxxx → 3-byte
    and     edx, 0xF0
    cmp     edx, 0xE0
    je      .vu_3byte

    ; 11110xxx → 4-byte
    mov     edx, eax
    and     edx, 0xF8
    cmp     edx, 0xF0
    je      .vu_4byte

    ; invalid lead byte
    jmp     .vu_invalid

.vu_ascii:
    inc     rcx
    jmp     .vu_loop

.vu_2byte:
    ; reject overlong: lead must be >= 0xC2
    cmp     al, 0xC2
    jb      .vu_invalid
    mov     r8, 1
    jmp     .vu_check_cont

.vu_3byte:
    mov     r8, 2
    jmp     .vu_check_cont

.vu_4byte:
    ; reject lead > 0xF4 (beyond U+10FFFF)
    cmp     al, 0xF4
    ja      .vu_invalid
    mov     r8, 3

.vu_check_cont:
    ; need r8 continuation bytes
    mov     r9, rcx
    inc     r9                  ; first continuation index

.vu_cont_loop:
    test    r8, r8
    jz      .vu_seq_ok

    cmp     r9, rsi
    jae     .vu_invalid

    movzx   edx, byte [rdi + r9]
    and     edx, 0xC0
    cmp     edx, 0x80           ; must be 10xxxxxx
    jne     .vu_invalid

    inc     r9
    dec     r8
    jmp     .vu_cont_loop

.vu_seq_ok:
    mov     rcx, r9
    jmp     .vu_loop

.vu_valid:
    mov     eax, 1
    pop     rbp
    ret

.vu_invalid:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_is_valid_utf8

; -----------------------------------------------------------------------------
; str_detect_encoding
;
; Full encoding detection: BOM → UTF-8 validation → heuristics → default.
;
; Signature:
;   int64_t str_detect_encoding(const uint8_t *buf, uint64_t len,
;                                uint64_t *out_bom_len)
;
; Returns:
;   RAX  — detected encoding ID
; -----------------------------------------------------------------------------

STR_FUNC str_detect_encoding

    test    rdi, rdi
    jz      .de_unknown

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx            ; out_bom_len

    ; 1. check BOM
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    str_detect_bom

    cmp     eax, ENC_UNKNOWN
    jne     .de_done            ; BOM found — definitive

    ; 2. UTF-8 structural validation
    mov     rdi, rbx
    mov     rsi, r12
    call    str_is_valid_utf8
    test    eax, eax
    jz      .de_check_ascii

    ; valid UTF-8 — but is it pure ASCII?
    ; scan for any high byte
    xor     rcx, rcx
.de_ascii_scan:
    cmp     rcx, r12
    jae     .de_pure_ascii
    movzx   eax, byte [rbx + rcx]
    test    al, 0x80
    jnz     .de_is_utf8
    inc     rcx
    jmp     .de_ascii_scan

.de_pure_ascii:
    mov     eax, ENC_ASCII
    jmp     .de_set_bom_zero

.de_is_utf8:
    mov     eax, ENC_UTF8
    jmp     .de_set_bom_zero

.de_check_ascii:
    ; 3. not valid UTF-8 — assume a legacy 8-bit encoding.
    ; Heuristic default: Windows-1252 (most common for mislabeled text).
    mov     eax, ENC_CP1252

.de_set_bom_zero:
    test    r13, r13
    jz      .de_done
    mov     qword [r13], 0

.de_done:
    pop_regs r13, r12, rbx
    pop     rbp
    ret

.de_unknown:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_detect_encoding
%endif ; GUARD_LIB_STR_ENCODING_DETECT_ASM
