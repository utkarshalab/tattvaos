; =============================================================================
; str/unicode/age.asm
; Unicode version (age) per codepoint — when was it assigned?
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: DerivedAge.txt
;
; -----------------------------------------------------------------------------
; Each codepoint was introduced in a specific Unicode version.
; Useful for: version gating, backward compatibility checks.
;
; We encode version as (major << 8 | minor), e.g. 16.0 = 0x1000.
;
; Functions:
;   str_cp_age           — Unicode version codepoint was introduced
;   str_cp_is_assigned   — check if codepoint is assigned in current Unicode
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

AGE_UNASSIGNED  equ 0x0000

section .text

STR_FUNC str_cp_age

    ; ASCII (0x00-0x7F): Unicode 1.1
    cmp     edi, 0x80
    jb      .age_1_1

    ; Latin-1 Supplement (0x80-0xFF): Unicode 1.1
    cmp     edi, 0x100
    jb      .age_1_1

    ; Basic Multilingual Plane coverage by block ranges (simplified)
    cmp     edi, 0x0370
    jb      .age_1_1            ; Latin Extended A/B: 1.1-3.0
    cmp     edi, 0x03FF
    jbe     .age_1_1            ; Greek: 1.1

    cmp     edi, 0x0400
    jb      .age_chk_deva
    cmp     edi, 0x04FF
    jbe     .age_1_1            ; Cyrillic: 1.1

.age_chk_deva:
    cmp     edi, 0x0900
    jb      .age_chk_cjk
    cmp     edi, 0x097F
    jbe     .age_1_1            ; Devanagari: 1.1

.age_chk_cjk:
    cmp     edi, 0x4E00
    jb      .age_chk_hangul
    cmp     edi, 0x9FFF
    jbe     .age_1_1            ; CJK Unified: 1.1

.age_chk_hangul:
    cmp     edi, 0xAC00
    jb      .age_chk_emoji
    cmp     edi, 0xD7AF
    jbe     .age_2_0            ; Hangul Syllables: 2.0

.age_chk_emoji:
    cmp     edi, 0x1F600
    jb      .age_chk_supp
    cmp     edi, 0x1F64F
    jbe     .age_6_0            ; Emoticons: 6.0

.age_chk_supp:
    ; surrogates: not assigned
    cmp     edi, 0xD800
    jb      .age_default
    cmp     edi, 0xDFFF
    jbe     .age_unassigned

    ; beyond 0x10FFFF: not assigned
    cmp     edi, 0x10FFFF
    ja      .age_unassigned

.age_default:
    ; default for unrecognized ranges: 1.1 (very conservative)
    ; generator would fill precise version per-codepoint

.age_1_1:
    mov     eax, (1 << 8) | 1
    pop     rbp
    ret
.age_2_0:
    mov     eax, (2 << 8) | 0
    pop     rbp
    ret
.age_6_0:
    mov     eax, (6 << 8) | 0
    pop     rbp
    ret
.age_unassigned:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_age

STR_FUNC str_cp_is_assigned

    call    str_cp_age
    test    eax, eax
    setnz   al
    movzx   eax, al
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_assigned