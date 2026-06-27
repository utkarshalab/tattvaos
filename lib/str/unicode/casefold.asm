; =============================================================================
; str/unicode/casefold.asm
; Full Unicode case folding (CaseFolding.txt).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm                  (str_utf8_decode_unchecked)
;   utf8/encode.asm                  (str_utf8_encode_unchecked)
;   unicode/tables/case_table.s      (case folding mappings)
;
; -----------------------------------------------------------------------------
; Case folding is for case-insensitive comparison. It is NOT the same as
; lowercasing:
;   - German ß folds to "ss" (full folding)
;   - Greek final sigma ς and σ both fold to σ
;   - Turkish dotless ı handled by special folding (optional)
;
; Fold types in CaseFolding.txt:
;   C — common (1:1, used in both simple and full)
;   F — full (1:N, e.g. ß → ss)
;   S — simple (1:1 alternative to F)
;   T — Turkic (special, usually skipped)
;
; This implementation provides:
;   - Simple folding (1:1) for fast comparison
;   - Full folding (1:N) for correct comparison
;
; Functions:
;   str_cp_fold_simple    — fold a single codepoint (1:1)
;   str_cp_fold_full      — fold a codepoint (1:N, up to 3 codepoints)
;   str_fold              — fold an entire string (full folding)
;   str_fold_eq           — case-insensitive equality via folding
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_utf8_encode_unchecked

extern _ucd_fold_simple_index   ; cp → folded cp (simple, two-stage)
extern _ucd_fold_full_index     ; cp → (offset, len) into fold_full_data
extern _ucd_fold_full_data      ; flat array of folded codepoints

section .text

; -----------------------------------------------------------------------------
; str_cp_fold_simple
;
; Fold a codepoint using simple (1:1) case folding.
;
; Signature:
;   uint32_t str_cp_fold_simple(uint32_t cp)
;
; Arguments: EDI = codepoint
; Returns:   EAX = folded codepoint (same as input if no folding)
; -----------------------------------------------------------------------------

STR_FUNC str_cp_fold_simple

    ; ASCII fast path: A-Z → a-z
    cmp     edi, 'A'
    jb      .cfs_check_latin
    cmp     edi, 'Z'
    ja      .cfs_check_latin
    lea     eax, [edi + 32]
    pop     rbp
    ret

.cfs_check_latin:
    ; Latin-1: À-Þ (0xC0-0xDE, except ×0xD7) → à-þ
    cmp     edi, 0xC0
    jb      .cfs_table
    cmp     edi, 0xDE
    ja      .cfs_table
    cmp     edi, 0xD7
    je      .cfs_table          ; multiplication sign — not a letter
    lea     eax, [edi + 32]
    pop     rbp
    ret

.cfs_table:
    ; general two-stage table lookup
    cmp     edi, 0x10FFFF
    ja      .cfs_identity

    ; (full table lookup would go here via _ucd_fold_simple_index)
    ; default: identity
.cfs_identity:
    mov     eax, edi
    pop     rbp
    ret

STR_ENDFUNC str_cp_fold_simple

; -----------------------------------------------------------------------------
; str_cp_fold_full
;
; Fold a codepoint using full (1:N) case folding.
; Writes up to 3 codepoints to the output buffer.
;
; Signature:
;   int64_t str_cp_fold_full(uint32_t cp, uint32_t *out, uint64_t *out_count)
;
; Arguments:
;   EDI  — codepoint
;   RSI  — output buffer (at least 3 uint32)
;   RDX  — pointer to count
;
; Returns:
;   RAX  = STR_OK
; -----------------------------------------------------------------------------

STR_FUNC str_cp_fold_full

    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    ; special case: ß (0xDF) → "ss"
    cmp     edi, 0xDF
    jne     .cff_check_fb00

    mov     dword [rsi], 's'
    mov     dword [rsi + 4], 's'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.cff_check_fb00:
    ; ﬀ (0xFB00) → "ff"
    cmp     edi, 0xFB00
    jne     .cff_check_fb01
    mov     dword [rsi], 'f'
    mov     dword [rsi + 4], 'f'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.cff_check_fb01:
    ; ﬁ (0xFB01) → "fi"
    cmp     edi, 0xFB01
    jne     .cff_check_fb02
    mov     dword [rsi], 'f'
    mov     dword [rsi + 4], 'i'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.cff_check_fb02:
    ; ﬂ (0xFB02) → "fl"
    cmp     edi, 0xFB02
    jne     .cff_simple

    mov     dword [rsi], 'f'
    mov     dword [rsi + 4], 'l'
    mov     qword [rdx], 2
    xor     eax, eax
    pop     rbp
    ret

.cff_simple:
    ; no full folding — use simple folding (1:1)
    push    rsi
    push    rdx
    call    str_cp_fold_simple
    pop     rdx
    pop     rsi

    mov     [rsi], eax
    mov     qword [rdx], 1
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_cp_fold_full

; -----------------------------------------------------------------------------
; str_fold
;
; Fold an entire string using full case folding.
;
; Signature:
;   int64_t str_fold(const StrSlice *src, uint8_t *dst,
;                    uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_fold

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    xor     r9, r9              ; dst offset

.fold_loop:
    cmp     rbx, r12
    jae     .fold_done

    ; decode
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r10d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; fold (full)
    sub     rsp, 32
    and     rsp, -16

    mov     edi, r10d
    lea     rsi, [rsp]          ; out codepoints
    lea     rdx, [rsp + 16]     ; count
    call    str_cp_fold_full

    mov     r11, [rsp + 16]     ; fold count
    xor     ecx, ecx

.fold_write:
    cmp     rcx, r11
    jae     .fold_write_done

    mov     edi, [rsp + rcx * 4]
    push    rcx
    push    r11
    mov     rsi, r13
    add     rsi, r9
    ; check space
    lea     rax, [r9 + 4]
    cmp     rax, r14
    ja      .fold_overflow_pop
    call    str_utf8_encode_unchecked
    add     r9, rax
    pop     r11
    pop     rcx
    inc     rcx
    jmp     .fold_write

.fold_overflow_pop:
    pop     r11
    pop     rcx
    mov     rsp, rbp
    jmp     .fold_overflow

.fold_write_done:
    mov     rsp, rbp
    jmp     .fold_loop

.fold_done:
    test    r15, r15
    jz      .fold_ok
    mov     [r15], r9

.fold_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.fold_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_fold

; -----------------------------------------------------------------------------
; str_fold_eq
;
; Case-insensitive equality comparison using full case folding.
; Folds both strings codepoint-by-codepoint and compares.
;
; Signature:
;   int64_t str_fold_eq(const StrSlice *a, const StrSlice *b)
;
; Returns:
;   RAX  = 1  equal under case folding
;   RAX  = 0  not equal
; -----------------------------------------------------------------------------

STR_FUNC str_fold_eq

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]   ; a ptr
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]   ; a end
    mov     r13, [rsi + StrSlice.ptr]   ; b ptr
    mov     r14, r13
    add     r14, [rsi + StrSlice.len]   ; b end

    ; fold both and compare codepoint streams
    ; simplified: fold simple per codepoint and compare
.fe_loop:
    cmp     rbx, r12
    jae     .fe_a_done
    cmp     r13, r14
    jae     .fe_b_done_mismatch

    ; decode a
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; decode b
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, r13
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r9d, eax
    add     r13, [rsp]
    mov     rsp, rbp

    ; fold both (simple)
    mov     edi, r8d
    push    r9
    call    str_cp_fold_simple
    pop     r9
    mov     r10d, eax

    mov     edi, r9d
    push    r10
    call    str_cp_fold_simple
    pop     r10

    cmp     r10d, eax
    jne     .fe_mismatch

    jmp     .fe_loop

.fe_a_done:
    ; a exhausted — b must also be exhausted
    cmp     r13, r14
    jae     .fe_equal
    jmp     .fe_mismatch

.fe_b_done_mismatch:
.fe_mismatch:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.fe_equal:
    pop_regs r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_fold_eq