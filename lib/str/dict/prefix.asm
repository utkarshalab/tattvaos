%ifndef GUARD_LIB_STR_DICT_PREFIX_ASM
%define GUARD_LIB_STR_DICT_PREFIX_ASM
; =============================================================================
; str/dict/prefix.asm
; Prefix / autocomplete range search over the default English dictionary.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   dict/dict.inc
;   dict/lookup.asm   (_dict_cmp_at)
;
; -----------------------------------------------------------------------------
; Since the table is sorted ascending by UTF-8 byte sequence, every word that
; starts with a given prefix occupies one contiguous index range [lo, hi).
; That range is found with two lower_bound searches:
;
;   lo = first index where word >= prefix
;   hi = first index where word >= successor(prefix)
;
; successor(prefix) is prefix with its last byte incremented (carrying into
; earlier bytes on 0xFF, the way you'd increment a big-endian integer) — the
; smallest byte string that is NOT itself prefixed by `prefix`. No real
; English dictionary entry contains a 0xFF byte, so the "no successor exists"
; case (an all-0xFF prefix) never fires in practice, but it is handled
; correctly (falls back to the end of the table) rather than assumed away.
;
; Functions:
;   str_dict_prefix_range   — [lo, hi) index range for a prefix
;   str_dict_prefix_count   — number of words starting with a prefix
;
; Enumerate matches with str_dict_get (lookup.asm) over [lo, hi).
; =============================================================================

%include "lib/str/arch/common/types.inc"
%include "lib/str/arch/common/error.inc"
%include "lib/str/arch/common/macros.inc"
%include "lib/str/dict/dict.inc"

section .text

; -----------------------------------------------------------------------------
; _dict_lower_bound (internal)
;
; First sorted index whose word is >= the given key.
;
; Inputs:
;   RDI = key_ptr
;   RSI = key_len
;
; Returns:
;   RAX = index in [0, dict_word_count]
; -----------------------------------------------------------------------------

_dict_lower_bound:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                  ; key_ptr
    mov     r13, rsi                  ; key_len

    xor     r14, r14                  ; lo = 0
    mov     eax, [dict_word_count]
    mov     rbx, rax                  ; hi = count

.lb_loop:
    cmp     r14, rbx
    jae     .lb_done

    mov     rax, r14
    add     rax, rbx
    shr     rax, 1                    ; mid = (lo + hi) / 2

    push    rax                       ; _dict_cmp_at clobbers RAX
    mov     rdi, rax
    mov     rsi, r12
    mov     rdx, r13
    call    _dict_cmp_at
    pop     rcx                       ; rcx = mid

    cmp     eax, 0
    jl      .lb_go_right              ; word[mid] < key -> lo = mid + 1

    mov     rbx, rcx                  ; word[mid] >= key -> hi = mid
    jmp     .lb_loop

.lb_go_right:
    lea     r14, [rcx + 1]
    jmp     .lb_loop

.lb_done:
    mov     rax, r14
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; _dict_prefix_bounds (internal)
;
; Computes the [lo, hi) index range matching a prefix and writes both ends
; out through caller-supplied pointers.
;
; Inputs:
;   RDI = key_ptr
;   RSI = key_len
;   RDX = out_lo_ptr   (always written)
;   RCX = out_hi_ptr   (always written)
;
; A key_len longer than DICT_MAX_WORD_LEN can never match a table entry —
; every word is <= DICT_MAX_WORD_LEN bytes — so that case short-circuits to
; an empty range without touching the successor-key stack buffer, which is
; sized for exactly DICT_MAX_WORD_LEN bytes.
; -----------------------------------------------------------------------------

_dict_prefix_bounds:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                  ; key_ptr
    mov     r13, rsi                  ; key_len
    mov     r14, rdx                  ; out_lo_ptr
    mov     r15, rcx                  ; out_hi_ptr

    mov     rdi, r12
    mov     rsi, r13
    call    _dict_lower_bound
    mov     rbx, rax                  ; lo
    mov     [r14], rbx

    test    r13, r13
    jnz     .pb_check_len

    mov     eax, [dict_word_count]
    mov     [r15], rax
    jmp     .pb_ret

.pb_check_len:
    cmp     r13, DICT_MAX_WORD_LEN
    jbe     .pb_build_succ

    mov     [r15], rbx                ; too long to ever match: hi = lo
    jmp     .pb_ret

.pb_build_succ:
    sub     rsp, 256

    xor     rcx, rcx
.pb_copy:
    cmp     rcx, r13
    jae     .pb_copy_done
    mov     al, [r12 + rcx]
    mov     [rsp + rcx], al
    inc     rcx
    jmp     .pb_copy
.pb_copy_done:

    mov     rcx, r13
    dec     rcx                       ; i = key_len - 1 (key_len >= 1 here)

.pb_carry:
    cmp     byte [rsp + rcx], 0xFF
    jne     .pb_incr
    test    rcx, rcx
    jz      .pb_no_succ
    dec     rcx
    jmp     .pb_carry

.pb_incr:
    inc     byte [rsp + rcx]
    lea     rsi, [rcx + 1]            ; succ_len
    lea     rdi, [rsp]                ; succ_ptr
    call    _dict_lower_bound
    mov     [r15], rax
    jmp     .pb_cleanup

.pb_no_succ:
    mov     eax, [dict_word_count]
    mov     [r15], rax

.pb_cleanup:
    add     rsp, 256

.pb_ret:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; str_dict_prefix_range
;
; Compute the sorted-index range of words starting with a prefix.
;
; Signature:
;   int64_t str_dict_prefix_range(const StrSlice *prefix,
;                                  uint64_t *out_lo, uint64_t *out_hi)
;
; *out_lo / *out_hi are always written, even when the range is empty, so a
; caller doing incremental autocomplete-as-you-type can use them as an
; insertion point regardless of the return code.
;
; Returns:
;   RAX = STR_OK             out_hi > out_lo  (at least one match)
;   RAX = STR_ERR_NOT_FOUND  range is empty
;   RAX = STR_ERR_NULL       prefix, out_lo, or out_hi is NULL
; -----------------------------------------------------------------------------

STR_FUNC str_dict_prefix_range
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rsi                  ; out_lo_ptr
    mov     r12, rdx                  ; out_hi_ptr
    mov     r13, rdi                  ; prefix StrSlice*

    mov     rdi, [r13 + StrSlice.ptr]
    mov     rsi, [r13 + StrSlice.len]
    mov     rdx, rbx
    mov     rcx, r12
    call    _dict_prefix_bounds

    mov     rax, [rbx]
    mov     rcx, [r12]
    cmp     rcx, rax
    ja      .pr_found

    pop_regs r13, r12, rbx
    ret_err STR_ERR_NOT_FOUND

.pr_found:
    pop_regs r13, r12, rbx
    ret_ok

STR_ENDFUNC str_dict_prefix_range

; -----------------------------------------------------------------------------
; str_dict_prefix_count
;
; Number of words starting with a prefix. Unlike lookup/prefix_range, a zero
; count is a normal answer, not an error — RAX is only ever negative for a
; bad argument.
;
; Signature:
;   int64_t str_dict_prefix_count(const StrSlice *prefix)
;
; Returns:
;   RAX >= 0                 number of matching words
;   RAX = STR_ERR_NULL       prefix is NULL
; -----------------------------------------------------------------------------

STR_FUNC str_dict_prefix_count
    guard_null rdi, STR_ERR_NULL

    sub     rsp, 16                   ; [rsp] = lo, [rsp+8] = hi

    mov     rax, rdi
    mov     rdi, [rax + StrSlice.ptr]
    mov     rsi, [rax + StrSlice.len]
    lea     rdx, [rsp]
    lea     rcx, [rsp + 8]
    call    _dict_prefix_bounds

    mov     rax, [rsp + 8]
    sub     rax, [rsp]

    add     rsp, 16
    pop     rbp
    ret

STR_ENDFUNC str_dict_prefix_count

%endif ; GUARD_LIB_STR_DICT_PREFIX_ASM
