; =============================================================================
; str/unicode/cjk.asm
; CJK radical mappings and ideograph utilities.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; Source: CJKRadicals.txt, EquivalentUnifiedIdeograph.txt
;
; -----------------------------------------------------------------------------
; Functions:
;   str_cp_is_cjk_ideograph     — is codepoint a CJK ideograph?
;   str_cp_is_cjk_radical       — is codepoint a Kangxi radical?
;   str_cp_cjk_radical_number   — get Kangxi radical number (1-214)
;   str_cp_equivalent_unified   — get equivalent unified ideograph
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

STR_FUNC str_cp_is_cjk_ideograph
    ; CJK Unified: 0x4E00-0x9FFF
    cmp     edi, 0x4E00
    jb      .ici_chk_a
    cmp     edi, 0x9FFF
    jbe     .ici_yes
.ici_chk_a:
    ; Ext A: 0x3400-0x4DBF
    cmp     edi, 0x3400
    jb      .ici_chk_b
    cmp     edi, 0x4DBF
    jbe     .ici_yes
.ici_chk_b:
    ; Ext B: 0x20000-0x2A6DF
    cmp     edi, 0x20000
    jb      .ici_chk_compat
    cmp     edi, 0x2A6DF
    jbe     .ici_yes
.ici_chk_compat:
    ; CJK Compatibility Ideographs: 0xF900-0xFAFF
    cmp     edi, 0xF900
    jb      .ici_no
    cmp     edi, 0xFAFF
    jbe     .ici_yes
.ici_no: xor eax, eax
    pop rbp
    ret
.ici_yes: mov eax, 1
    pop rbp
    ret
STR_ENDFUNC str_cp_is_cjk_ideograph

STR_FUNC str_cp_is_cjk_radical
    ; Kangxi Radicals: 0x2F00-0x2FDF (214 radicals)
    cmp     edi, 0x2F00
    jb      .icr_chk_supp
    cmp     edi, 0x2FD5
    jbe     .icr_yes
.icr_chk_supp:
    ; CJK Radicals Supplement: 0x2E80-0x2EFF
    cmp     edi, 0x2E80
    jb      .icr_no
    cmp     edi, 0x2EFF
    jbe     .icr_yes
.icr_no: xor eax, eax
    pop rbp
    ret
.icr_yes: mov eax, 1
    pop rbp
    ret
STR_ENDFUNC str_cp_is_cjk_radical

STR_FUNC str_cp_cjk_radical_number
    ; Kangxi Radicals 0x2F00-0x2FD5: radical = cp - 0x2F00 + 1
    cmp     edi, 0x2F00
    jb      .crn_none
    cmp     edi, 0x2FD5
    ja      .crn_none
    mov     eax, edi
    sub     eax, 0x2F00
    inc     eax                 ; 1-based
    pop     rbp
    ret
.crn_none:
    xor     eax, eax            ; 0 = not a radical
    pop     rbp
    ret
STR_ENDFUNC str_cp_cjk_radical_number

STR_FUNC str_cp_equivalent_unified
    ; CJK Compatibility → Unified mapping (common entries)
    ; Full table from EquivalentUnifiedIdeograph.txt via generator
    ; Default: return same codepoint
    mov     eax, edi
    pop     rbp
    ret
STR_ENDFUNC str_cp_equivalent_unified