%ifndef GUARD_LIB_STR_UNICODE_DECOMPOSITION_ASM
%define GUARD_LIB_STR_UNICODE_DECOMPOSITION_ASM
; =============================================================================
; str/unicode/decomposition.asm
; Decomposition type queries (DerivedDecompositionType.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   unicode/tables/decomp_table.s    (decomposition index)
;
; Source: UnicodeData.txt field 5 (Decomposition_Type + Decomposition_Mapping),
;         extracted/DerivedDecompositionType.txt
;
; -----------------------------------------------------------------------------
; Unicode decomposition types classify how a codepoint decomposes:
;
;   none       — no decomposition mapping
;   canonical  — canonical decomposition (used by NFD/NFC)
;   font       — font variant       (ℂ → C)
;   noBreak    — no-break version   (NBSP → SP)
;   initial    — Arabic initial form
;   medial     — Arabic medial form
;   final      — Arabic final form
;   isolated   — Arabic isolated form
;   circle     — circled form       (① → 1)
;   super      — superscript        (² → 2)
;   sub        — subscript          (₂ → 2)
;   vertical   — vertical layout form
;   wide       — fullwidth form     (Ａ → A)
;   narrow     — halfwidth form
;   small      — small variant
;   square     — CJK square form   (㎡ → m²)
;   fraction   — vulgar fraction   (½ → 1⁄2)
;   compat     — generic compat    (ﬁ → fi)
;
; The key distinction: canonical decompositions change NOTHING about meaning.
; Compatibility decompositions lose formatting information.
; NFD/NFC use canonical only. NFKD/NFKC use both.
;
; Functions:
;   str_cp_decomp_type         — get the decomposition type enum
;   str_cp_has_decomp          — quick check: has any decomposition
;   str_cp_is_compat_decomp    — is it a compatibility decomposition
;   str_cp_decomp_mapping      — get the decomposition codepoints
;   str_cp_decomp_length       — how many codepoints in decomposition
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Decomposition type constants
DECOMP_NONE         equ 0
DECOMP_CANONICAL    equ 1
DECOMP_FONT         equ 2
DECOMP_NOBREAK      equ 3
DECOMP_INITIAL      equ 4
DECOMP_MEDIAL       equ 5
DECOMP_FINAL        equ 6
DECOMP_ISOLATED     equ 7
DECOMP_CIRCLE       equ 8
DECOMP_SUPER        equ 9
DECOMP_SUB          equ 10
DECOMP_VERTICAL     equ 11
DECOMP_WIDE         equ 12
DECOMP_NARROW       equ 13
DECOMP_SMALL        equ 14
DECOMP_SQUARE       equ 15
DECOMP_FRACTION     equ 16
DECOMP_COMPAT       equ 17

; External table: _ucd_decomp_index[cp] = packed 32-bit value:
;   bits 31..8  = offset into _ucd_decomp_data (24 bits → up to 16M entries)
;   bits  7..4  = length (4 bits → up to 15 codepoints per decomposition)
;   bits  3..0  = decomp type (4 bits → 0..17)
;
; If bits 7..0 == 0, the codepoint has no decomposition.

section .text

; -----------------------------------------------------------------------------
; str_cp_decomp_type
;
; Get the decomposition type of a codepoint.
;
; Signature:
;   uint8_t str_cp_decomp_type(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   AL   — DECOMP_* enum value (0 = no decomposition)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_decomp_type

    ; validate codepoint range
    cmp     edi, CODEPOINT_MAX
    ja      .dt_none

    ; Hangul syllables have canonical decomposition (algorithmic, no table)
    cmp     edi, 0xAC00
    jb      .dt_chk_table
    cmp     edi, 0xD7A3
    jbe     .dt_canonical

.dt_chk_table:
    ; BMP codepoints: direct table lookup
    cmp     edi, 0x10000
    jae     .dt_smp

    ; BMP: index = _ucd_decomp_index[cp]
    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + rdi * 4]    ; packed value

    ; extract type (bits 3..0)
    and     eax, 0x0F
    pop     rbp
    ret

.dt_smp:
    ; SMP codepoints: two-stage lookup
    ; Most SMP codepoints have no decomposition, but CJK compat ideographs,
    ; Mathematical Alphanumeric Symbols, etc. do.

    ; CJK Compatibility Ideographs Supplement: U+2F800-U+2FA1F → canonical
    cmp     edi, 0x2F800
    jb      .dt_chk_math_alpha
    cmp     edi, 0x2FA1F
    jbe     .dt_canonical

.dt_chk_math_alpha:
    ; Mathematical Alphanumeric Symbols: U+1D400-U+1D7FF → font
    cmp     edi, 0x1D400
    jb      .dt_chk_compat_ideo
    cmp     edi, 0x1D7FF
    jbe     .dt_font

.dt_chk_compat_ideo:
    ; CJK Compatibility Ideographs: U+F900-U+FAD9 (BMP — already handled above)
    ; Musical symbols, etc. — mostly no decomposition in SMP
    jmp     .dt_none

.dt_none:
    xor     eax, eax            ; DECOMP_NONE
    pop     rbp
    ret

.dt_canonical:
    mov     eax, DECOMP_CANONICAL
    pop     rbp
    ret

.dt_font:
    mov     eax, DECOMP_FONT
    pop     rbp
    ret

STR_ENDFUNC str_cp_decomp_type

; -----------------------------------------------------------------------------
; str_cp_has_decomp
;
; Quick check: does this codepoint have any decomposition mapping?
;
; Signature:
;   int64_t str_cp_has_decomp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if codepoint has a decomposition, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_has_decomp

    cmp     edi, CODEPOINT_MAX
    ja      .hd_no

    ; Hangul syllables always decompose
    cmp     edi, 0xAC00
    jb      .hd_chk_table
    cmp     edi, 0xD7A3
    jbe     .hd_yes

.hd_chk_table:
    cmp     edi, 0x10000
    jae     .hd_smp

    ; BMP table lookup
    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + rdi * 4]
    ; has decomp if low 8 bits != 0
    test    al, 0xFF
    jz      .hd_no
    jmp     .hd_yes

.hd_smp:
    ; CJK Compat Ideographs Supplement
    cmp     edi, 0x2F800
    jb      .hd_chk_math
    cmp     edi, 0x2FA1F
    jbe     .hd_yes

.hd_chk_math:
    ; Mathematical Alphanumeric Symbols
    cmp     edi, 0x1D400
    jb      .hd_no
    cmp     edi, 0x1D7FF
    jbe     .hd_yes

.hd_no:
    xor     eax, eax
    pop     rbp
    ret

.hd_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_has_decomp

; -----------------------------------------------------------------------------
; str_cp_is_compat_decomp
;
; Check if a codepoint's decomposition is compatibility (not canonical).
; Compatibility decompositions are used by NFKD/NFKC but not NFD/NFC.
;
; Signature:
;   int64_t str_cp_is_compat_decomp(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  = 1 if compatibility decomposition, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_cp_is_compat_decomp

    cmp     edi, CODEPOINT_MAX
    ja      .icd_no

    ; Hangul = canonical, never compat
    cmp     edi, 0xAC00
    jb      .icd_chk_table
    cmp     edi, 0xD7A3
    jbe     .icd_no             ; Hangul is canonical

.icd_chk_table:
    cmp     edi, 0x10000
    jae     .icd_smp

    ; BMP table lookup
    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + rdi * 4]
    and     eax, 0x0F           ; type
    cmp     eax, DECOMP_CANONICAL
    je      .icd_no             ; canonical is not compat
    test    eax, eax
    jz      .icd_no             ; no decomposition at all
    jmp     .icd_yes            ; any other type = compat

.icd_smp:
    ; CJK Compat Ideographs Supplement → canonical (not compat)
    cmp     edi, 0x2F800
    jb      .icd_chk_math
    cmp     edi, 0x2FA1F
    jbe     .icd_no

.icd_chk_math:
    ; Math Alphanumeric → font (= compat)
    cmp     edi, 0x1D400
    jb      .icd_no
    cmp     edi, 0x1D7FF
    jbe     .icd_yes

.icd_no:
    xor     eax, eax
    pop     rbp
    ret

.icd_yes:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_is_compat_decomp

; -----------------------------------------------------------------------------
; str_cp_decomp_mapping
;
; Get the decomposition mapping of a codepoint.
; Writes decomposed codepoints into the caller's buffer.
;
; Signature:
;   int64_t str_cp_decomp_mapping(uint32_t cp, uint32_t *out_buf,
;                                  uint64_t buf_cap, uint64_t *out_count)
;
; Arguments:
;   EDI  — codepoint to decompose
;   RSI  — output buffer for codepoints (uint32_t[])
;   RDX  — buffer capacity (number of uint32_t entries)
;   RCX  — pointer to receive count written (may be NULL)
;
; Returns:
;   RAX  = STR_OK on success
;   RAX  = STR_ERR_BUF_TOO_SMALL if buffer too small
;   RAX  = STR_ERR_NOT_FOUND if no decomposition
; -----------------------------------------------------------------------------

STR_FUNC str_cp_decomp_mapping

    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     r12d, edi           ; cp
    mov     r13, rsi            ; out_buf
    mov     r14, rdx            ; buf_cap
    mov     rbx, rcx            ; out_count

    ; validate
    cmp     r12d, CODEPOINT_MAX
    ja      .dm_not_found

    ; Hangul syllable: algorithmic decomposition
    cmp     r12d, 0xAC00
    jb      .dm_table
    cmp     r12d, 0xD7A3
    ja      .dm_table

    ; Hangul decomposition
    ; SIndex = cp - 0xAC00
    mov     eax, r12d
    sub     eax, 0xAC00

    ; L = 0x1100 + SIndex / 588
    xor     edx, edx
    mov     ecx, 588
    div     ecx
    mov     r8d, eax
    add     r8d, 0x1100         ; L jamo

    ; V = 0x1161 + (SIndex % 588) / 28
    mov     eax, edx
    xor     edx, edx
    mov     ecx, 28
    div     ecx
    mov     r9d, eax
    add     r9d, 0x1161         ; V jamo

    ; T = 0x11A7 + (SIndex % 28)
    ; if T == 0x11A7, no T jamo (LV, not LVT)
    test    edx, edx
    jz      .dm_hangul_lv

    ; LVT: 3 codepoints
    cmp     r14, 3
    jb      .dm_buf_small

    mov     [r13], r8d
    mov     [r13 + 4], r9d
    add     edx, 0x11A7
    mov     [r13 + 8], edx

    test    rbx, rbx
    jz      .dm_hangul_ok3
    mov     qword [rbx], 3
.dm_hangul_ok3:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.dm_hangul_lv:
    ; LV: 2 codepoints
    cmp     r14, 2
    jb      .dm_buf_small

    mov     [r13], r8d
    mov     [r13 + 4], r9d

    test    rbx, rbx
    jz      .dm_hangul_ok2
    mov     qword [rbx], 2
.dm_hangul_ok2:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.dm_table:
    ; BMP table lookup
    cmp     r12d, 0x10000
    jae     .dm_not_found       ; SMP: simplified — not in compact table

    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + r12 * 4]

    ; extract fields
    mov     ecx, eax
    and     ecx, 0x0F           ; type
    test    ecx, ecx
    jz      .dm_not_found       ; no decomposition

    mov     edx, eax
    shr     edx, 4
    and     edx, 0x0F           ; length (1..15)

    shr     eax, 8              ; offset into decomp_data

    ; check buffer capacity
    cmp     r14, rdx
    jb      .dm_buf_small

    ; copy codepoints from _ucd_decomp_data[offset..offset+length)
    lea     rsi, [rel _ucd_decomp_data]
    lea     rsi, [rsi + rax * 4]

    xor     ecx, ecx
.dm_copy:
    cmp     ecx, edx
    jae     .dm_copy_done

    mov     r8d, [rsi + rcx * 4]
    mov     [r13 + rcx * 4], r8d
    inc     ecx
    jmp     .dm_copy

.dm_copy_done:
    test    rbx, rbx
    jz      .dm_ok
    mov     [rbx], rdx          ; write count (already in rdx as 64-bit)

.dm_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.dm_not_found:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_NOT_FOUND
    pop     rbp
    ret

.dm_buf_small:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_cp_decomp_mapping

; -----------------------------------------------------------------------------
; str_cp_decomp_length
;
; Get the number of codepoints in a decomposition mapping.
; Returns 0 if no decomposition exists.
;
; Signature:
;   uint64_t str_cp_decomp_length(uint32_t cp)
;
; Arguments:
;   EDI  — codepoint
;
; Returns:
;   RAX  — decomposition length (0 if none)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_decomp_length

    cmp     edi, CODEPOINT_MAX
    ja      .dl_zero

    ; Hangul
    cmp     edi, 0xAC00
    jb      .dl_table
    cmp     edi, 0xD7A3
    ja      .dl_table

    ; Hangul: check if LV or LVT
    mov     eax, edi
    sub     eax, 0xAC00
    xor     edx, edx
    mov     ecx, 28
    div     ecx
    test    edx, edx
    jz      .dl_two             ; LV → 2 jamo
    mov     rax, 3              ; LVT → 3 jamo
    pop     rbp
    ret

.dl_two:
    mov     rax, 2
    pop     rbp
    ret

.dl_table:
    cmp     edi, 0x10000
    jae     .dl_smp

    lea     rax, [rel _ucd_decomp_index]
    mov     eax, [rax + rdi * 4]
    test    al, 0x0F            ; has decomp type?
    jz      .dl_zero

    shr     eax, 4
    and     eax, 0x0F           ; length
    pop     rbp
    ret

.dl_smp:
    ; CJK Compat Ideographs Supplement: single codepoint canonical
    cmp     edi, 0x2F800
    jb      .dl_chk_math
    cmp     edi, 0x2FA1F
    jbe     .dl_one

.dl_chk_math:
    ; Math Alphanumeric: single codepoint
    cmp     edi, 0x1D400
    jb      .dl_zero
    cmp     edi, 0x1D7FF
    jbe     .dl_one

.dl_zero:
    xor     eax, eax
    pop     rbp
    ret

.dl_one:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_cp_decomp_length

%endif ; GUARD_LIB_STR_UNICODE_DECOMPOSITION_ASM
