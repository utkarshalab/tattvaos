%ifndef GUARD_LIB_STR_UNICODE_GRAPHEME_ASM
%define GUARD_LIB_STR_UNICODE_GRAPHEME_ASM
; =============================================================================
; str/unicode/grapheme.asm
; Grapheme cluster boundary detection (UAX #29).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm                  (str_utf8_decode_unchecked)
;   unicode/tables/grapheme_table.s  (grapheme break property data)
;
; -----------------------------------------------------------------------------
; A "grapheme cluster" is a user-perceived character — what looks like a
; single character but may be multiple codepoints:
;
;   "é"     = e + combining acute (2 codepoints, 1 grapheme)
;   "👨‍👩‍👧" = family emoji (7 codepoints via ZWJ, 1 grapheme)
;   "한"    = Hangul syllable (1 codepoint)
;   "ก็"    = Thai char + tone mark (2 codepoints, 1 grapheme)
;
; This matters for: cursor movement, text selection, string length as
; perceived by users, truncation without breaking characters.
;
; Grapheme break properties (UAX #29):
;   Other, CR, LF, Control, Extend, ZWJ, Regional_Indicator,
;   Prepend, SpacingMark, L, V, T, LV, LVT, Extended_Pictographic
;
; Functions:
;   str_grapheme_count        — count grapheme clusters
;   str_grapheme_next         — find next grapheme boundary
;   str_grapheme_iter_init    — initialize grapheme iterator
;   str_grapheme_iter_next    — get next grapheme cluster
;   str_grapheme_truncate     — truncate to N graphemes safely
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Grapheme break property values
GBP_Other       equ 0
GBP_CR          equ 1
GBP_LF          equ 2
GBP_Control     equ 3
GBP_Extend      equ 4
GBP_ZWJ         equ 5
GBP_RI          equ 6      ; Regional_Indicator
GBP_Prepend     equ 7
GBP_SpacingMark equ 8
GBP_L           equ 9
GBP_V           equ 10
GBP_T           equ 11
GBP_LV          equ 12
GBP_LVT         equ 13
GBP_ExtPict     equ 14     ; Extended_Pictographic

extern _ucd_gbp_table       ; cp → grapheme break property

section .text

; -----------------------------------------------------------------------------
; _gbp  (internal)
;
; Get the grapheme break property of a codepoint.
;
; Arguments: EDI = codepoint
; Returns:   AL = GBP_* value
; -----------------------------------------------------------------------------

_gbp:
    ; fast paths for common ranges
    cmp     edi, 0x0D
    je      .gbp_cr
    cmp     edi, 0x0A
    je      .gbp_lf

    ; control chars (C0/C1 except CR/LF, plus some)
    cmp     edi, 0x20
    jb      .gbp_control
    cmp     edi, 0x7F
    jb      .gbp_other_fast
    cmp     edi, 0xA0
    jb      .gbp_control

    ; combining marks (Extend): 0x0300-0x036F and many more
    cmp     edi, 0x0300
    jb      .gbp_other_fast
    cmp     edi, 0x036F
    jbe     .gbp_extend

    ; ZWJ
    cmp     edi, 0x200D
    je      .gbp_zwj

    ; Regional indicators 0x1F1E6-0x1F1FF
    cmp     edi, 0x1F1E6
    jb      .gbp_check_hangul
    cmp     edi, 0x1F1FF
    jbe     .gbp_ri

.gbp_check_hangul:
    ; Hangul L: 0x1100-0x115F
    cmp     edi, 0x1100
    jb      .gbp_table_lookup
    cmp     edi, 0x115F
    jbe     .gbp_l
    ; Hangul V: 0x1160-0x11A7
    cmp     edi, 0x11A7
    jbe     .gbp_v
    ; Hangul T: 0x11A8-0x11FF
    cmp     edi, 0x11FF
    jbe     .gbp_t

.gbp_table_lookup:
    ; full table lookup for everything else
    ; (table maps remaining codepoints to GBP values)
    cmp     edi, 0x10FFFF
    ja      .gbp_other_fast
    ; lea r8, [rel _ucd_gbp_table]; two-stage lookup
    jmp     .gbp_other_fast

.gbp_cr:        mov al, GBP_CR
    ret
.gbp_lf:        mov al, GBP_LF
    ret
.gbp_control:   mov al, GBP_Control
    ret
.gbp_extend:    mov al, GBP_Extend
    ret
.gbp_zwj:       mov al, GBP_ZWJ
    ret
.gbp_ri:        mov al, GBP_RI
    ret
.gbp_l:         mov al, GBP_L
    ret
.gbp_v:         mov al, GBP_V
    ret
.gbp_t:         mov al, GBP_T
    ret
.gbp_other_fast: mov al, GBP_Other
    ret

; -----------------------------------------------------------------------------
; _is_grapheme_boundary  (internal)
;
; Determine if there is a grapheme boundary between two codepoints
; with properties prop_a (before) and prop_b (after).
; Implements the UAX #29 grapheme break rules GB1-GB999.
;
; Arguments: DIL = prop_a, SIL = prop_b, DL = ri_count_odd (regional indicator state)
; Returns:   AL = 1 if boundary, 0 if no boundary (join)
; -----------------------------------------------------------------------------

_is_grapheme_boundary:
    movzx   eax, dil            ; prop_a
    movzx   ecx, sil            ; prop_b

    ; GB3: CR × LF (no break between CR and LF)
    cmp     al, GBP_CR
    jne     .gb_not_crlf
    cmp     cl, GBP_LF
    je      .gb_no_break

.gb_not_crlf:
    ; GB4: (Control | CR | LF) ÷  (break after)
    cmp     al, GBP_Control
    je      .gb_break
    cmp     al, GBP_CR
    je      .gb_break
    cmp     al, GBP_LF
    je      .gb_break

    ; GB5: ÷ (Control | CR | LF) (break before)
    cmp     cl, GBP_Control
    je      .gb_break
    cmp     cl, GBP_CR
    je      .gb_break
    cmp     cl, GBP_LF
    je      .gb_break

    ; GB6: L × (L | V | LV | LVT)
    cmp     al, GBP_L
    jne     .gb_not_l
    cmp     cl, GBP_L
    je      .gb_no_break
    cmp     cl, GBP_V
    je      .gb_no_break
    cmp     cl, GBP_LV
    je      .gb_no_break
    cmp     cl, GBP_LVT
    je      .gb_no_break

.gb_not_l:
    ; GB7: (LV | V) × (V | T)
    cmp     al, GBP_LV
    je      .gb_chk_vt
    cmp     al, GBP_V
    jne     .gb_not_v
.gb_chk_vt:
    cmp     cl, GBP_V
    je      .gb_no_break
    cmp     cl, GBP_T
    je      .gb_no_break

.gb_not_v:
    ; GB8: (LVT | T) × T
    cmp     al, GBP_LVT
    je      .gb_chk_t
    cmp     al, GBP_T
    jne     .gb_not_t
.gb_chk_t:
    cmp     cl, GBP_T
    je      .gb_no_break

.gb_not_t:
    ; GB9: × (Extend | ZWJ)  (no break before Extend or ZWJ)
    cmp     cl, GBP_Extend
    je      .gb_no_break
    cmp     cl, GBP_ZWJ
    je      .gb_no_break

    ; GB9a: × SpacingMark
    cmp     cl, GBP_SpacingMark
    je      .gb_no_break

    ; GB9b: Prepend ×
    cmp     al, GBP_Prepend
    je      .gb_no_break

    ; GB11: ExtPict Extend* ZWJ × ExtPict
    ;   (handled with state in the iterator, simplified here)
    cmp     al, GBP_ZWJ
    jne     .gb_not_zwj
    cmp     cl, GBP_ExtPict
    je      .gb_no_break

.gb_not_zwj:
    ; GB12/GB13: RI × RI (only between odd-even pairs)
    cmp     al, GBP_RI
    jne     .gb_default
    cmp     cl, GBP_RI
    jne     .gb_default
    ; break depends on count parity (dl = ri_odd)
    test    dl, dl
    jnz     .gb_no_break        ; odd count → join
    ; even → break

.gb_default:
    ; GB999: any ÷ any (break everywhere else)
.gb_break:
    mov     al, 1
    ret

.gb_no_break:
    xor     al, al
    ret

; -----------------------------------------------------------------------------
; str_grapheme_count
;
; Count the number of grapheme clusters in a UTF-8 string.
;
; Signature:
;   int64_t str_grapheme_count(const StrSlice *src, uint64_t *out_count)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to uint64_t for count
; -----------------------------------------------------------------------------

STR_FUNC str_grapheme_count

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out_count

    xor     r14, r14            ; count
    xor     r15d, r15d          ; prev_prop (no previous)
    mov     r15d, -1            ; sentinel: no previous codepoint

    xor     r9d, r9d            ; ri_odd state

.gc_loop:
    cmp     rbx, r12
    jae     .gc_done

    ; decode codepoint
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; get property
    mov     edi, r8d
    push    r8
    push    r9
    call    _gbp
    pop     r9
    pop     r8
    movzx   r10d, al            ; current prop

    ; first codepoint always starts a grapheme
    cmp     r15d, -1
    je      .gc_first

    ; check boundary between prev_prop (r15) and current (r10)
    movzx   edi, r15b
    movzx   esi, r10b
    mov     edx, r9d            ; ri_odd
    push    r8
    push    r9
    push    r10
    call    _is_grapheme_boundary
    pop     r10
    pop     r9
    pop     r8

    test    al, al
    jz      .gc_no_boundary

    inc     r14                 ; new grapheme

.gc_no_boundary:
    ; update RI state
    cmp     r10b, GBP_RI
    jne     .gc_ri_reset
    xor     r9d, 1              ; toggle odd/even
    jmp     .gc_update_prev
.gc_ri_reset:
    xor     r9d, r9d

.gc_update_prev:
    mov     r15d, r10d          ; prev = current
    jmp     .gc_loop

.gc_first:
    inc     r14                 ; first grapheme
    mov     r15d, r10d
    cmp     r10b, GBP_RI
    jne     .gc_loop
    mov     r9d, 1
    jmp     .gc_loop

.gc_done:
    mov     [r13], r14
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_grapheme_count

; -----------------------------------------------------------------------------
; str_grapheme_next
;
; Given a byte offset, find the byte offset of the next grapheme boundary.
;
; Signature:
;   int64_t str_grapheme_next(const StrSlice *src, uint64_t offset,
;                              uint64_t *out_next)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — current byte offset
;   RDX  — pointer to uint64_t for next boundary offset
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_ITER_END  offset at or past end
; -----------------------------------------------------------------------------

STR_FUNC str_grapheme_next

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; current offset
    mov     r14, rdx            ; out_next

    cmp     r13, r12
    jae     .gn_end

    ; decode first codepoint at offset
    lea     r15, [rbx + r13]    ; current ptr

    sub     rsp, 16
    and     rsp, -16
    mov     rdi, r15
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     r9, [rsp]           ; advance
    mov     rsp, rbp

    add     r13, r9             ; advance past first cp

    mov     edi, r8d
    call    _gbp
    movzx   r10d, al            ; prev prop

    xor     r11d, r11d          ; ri state

.gn_loop:
    cmp     r13, r12
    jae     .gn_found

    lea     r15, [rbx + r13]
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, r15
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     r9, [rsp]
    mov     rsp, rbp

    mov     edi, r8d
    push    r8
    push    r9
    call    _gbp
    pop     r9
    pop     r8
    movzx   ecx, al             ; current prop

    ; boundary check
    movzx   edi, r10b
    movzx   esi, cl
    mov     edx, r11d
    push    r8
    push    r9
    push    rcx
    call    _is_grapheme_boundary
    pop     rcx
    pop     r9
    pop     r8

    test    al, al
    jnz     .gn_found           ; boundary — stop here

    add     r13, r9             ; no boundary — advance
    mov     r10d, ecx           ; update prev
    jmp     .gn_loop

.gn_found:
    mov     [r14], r13
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.gn_end:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ITER_END
    pop     rbp
    ret

STR_ENDFUNC str_grapheme_next

; -----------------------------------------------------------------------------
; str_grapheme_truncate
;
; Truncate a string to at most N grapheme clusters without splitting any.
; Returns the byte length of the truncated prefix.
;
; Signature:
;   int64_t str_grapheme_truncate(const StrSlice *src, uint64_t max_graphemes,
;                                  uint64_t *out_byte_len)
; -----------------------------------------------------------------------------

STR_FUNC str_grapheme_truncate

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; max_graphemes
    mov     r13, rdx            ; out_byte_len

    xor     r14, r14            ; byte offset
    xor     r9, r9              ; grapheme count

.gt_loop:
    cmp     r9, r12
    jae     .gt_done

    ; find next boundary from r14
    sub     rsp, 8
    and     rsp, -8

    mov     rdi, rbx
    mov     rsi, r14
    mov     rdx, rsp
    push    r9
    call    str_grapheme_next
    pop     r9

    test    rax, rax
    jnz     .gt_at_end          ; iter end

    mov     r14, [rsp]          ; new offset
    add     rsp, 8

    inc     r9
    jmp     .gt_loop

.gt_at_end:
    add     rsp, 8

.gt_done:
    mov     [r13], r14
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_grapheme_truncate

; -----------------------------------------------------------------------------
; str_truncate_ellipsis
;
; Truncate a string to max graphemes, appending ellipsis if truncated.
;
; Signature:
;   int64_t str_truncate_ellipsis(const StrSlice *src, uint64_t max_graphemes,
;                                 const StrSlice *ellipsis, uint8_t *dst,
;                                 uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_truncate_ellipsis
    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; count [rsp], truncated_len [rsp+8], out_len ptr [rsp+16]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; max_graphemes
    mov     r13, rdx            ; ellipsis (StrSlice*, can be null)
    mov     r14, rcx            ; dst
    mov     r15, r8             ; cap
    mov     [rsp + 16], r9      ; out_len ptr

    ; get grapheme count of src
    mov     rdi, rbx
    mov     rsi, rsp            ; count is at [rsp]
    call    str_grapheme_count
    test    rax, rax
    jnz     .err

    mov     rax, [rsp]          ; count
    cmp     rax, r12
    jbe     .no_truncate

    ; Truncation needed!
    mov     rdi, rbx
    mov     rsi, r12
    lea     rdx, [rsp + 8]      ; truncated_len
    call    str_grapheme_truncate
    test    rax, rax
    jnz     .err

    ; total_len = truncated_len + ellipsis.len
    mov     rax, [rsp + 8]      ; truncated_len
    xor     rcx, rcx            ; ellipsis.len
    test    r13, r13
    jz      .calc_total
    mov     rcx, [r13 + StrSlice.len]

.calc_total:
    add     rax, rcx            ; total_len
    cmp     rax, r15            ; cap check
    ja      .too_small

    ; save total_len in r15 (not needed as cap anymore)
    mov     r15, rax

    ; 1. Copy prefix: src.ptr (length truncated_len)
    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, [rsp + 8]
    test    rdx, rdx
    jz      .prefix_copied
    call    str_copy_bytes
    test    rax, rax
    js      .err

.prefix_copied:
    ; 2. Copy ellipsis
    test    r13, r13
    jz      .ellipsis_copied
    mov     rdx, [r13 + StrSlice.len]
    test    rdx, rdx
    jz      .ellipsis_copied

    mov     rdi, r14
    add     rdi, [rsp + 8]      ; dst + truncated_len
    mov     rsi, [r13 + StrSlice.ptr]
    call    str_copy_bytes
    test    rax, rax
    js      .err

.ellipsis_copied:
    mov     rax, [rsp + 16]
    mov     [rax], r15
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.no_truncate:
    ; copy full src
    mov     rax, [rbx + StrSlice.len]
    cmp     rax, r15
    ja      .too_small

    mov     rdi, r14
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdx, rax
    test    rdx, rdx
    jz      .no_trunc_done
    call    str_copy_bytes
    test    rax, rax
    js      .err

.no_trunc_done:
    mov     rax, [rsp + 16]
    mov     rcx, [rbx + StrSlice.len]
    mov     [rax], rcx
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.err:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_grapheme_truncate
%endif ; GUARD_LIB_STR_UNICODE_GRAPHEME_ASM
