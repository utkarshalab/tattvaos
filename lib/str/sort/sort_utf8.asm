%ifndef GUARD_LIB_STR_SORT_SORT_UTF8_ASM
%define GUARD_LIB_STR_SORT_SORT_UTF8_ASM
; =============================================================================
; str/sort/sort_utf8.asm
; Sort arrays of StrSlice by UTF-8 string value.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/cmp.asm   (str_cmp, str_eq_ignore_case)
;   sort/sort.asm  (str_sort)
;
; -----------------------------------------------------------------------------
; Functions:
;   str_sort_slices         — sort StrSlice[] by byte-level value
;   str_sort_slices_rev     — descending sort
;   str_sort_slices_nocase  — case-insensitive sort
;   str_sort_slices_by_len  — sort by length first, then value
;   str_cmp_slices          — comparator for StrSlice* pairs
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_cmp_slices
;
; Lexicographic comparator for two StrSlice pointers.
; Used as callback for str_sort.
;
; Signature:
;   int64_t str_cmp_slices(const StrSlice *a, const StrSlice *b, void *ctx)
;
; Returns: <0 / 0 / >0
; -----------------------------------------------------------------------------

STR_FUNC str_cmp_slices

    ; compare two StrSlices lexicographically
    push_regs rbx, r12, r13

    mov     rbx, rdi            ; a
    mov     r12, rsi            ; b

    mov     r8,  [rbx + StrSlice.ptr]
    mov     r9,  [rbx + StrSlice.len]
    mov     r10, [r12 + StrSlice.ptr]
    mov     r11, [r12 + StrSlice.len]

    ; min_len = min(a.len, b.len)
    mov     r13, r9
    cmp     r13, r11
    jbe     .cs_have_min
    mov     r13, r11

.cs_have_min:
    xor     ecx, ecx

.cs_loop:
    cmp     rcx, r13
    jae     .cs_by_len

    movzx   eax, byte [r8 + rcx]
    movzx   edx, byte [r10 + rcx]
    cmp     eax, edx
    jne     .cs_diff

    inc     ecx
    jmp     .cs_loop

.cs_diff:
    sub     eax, edx
    pop_regs r13, r12, rbx
    pop     rbp
    ret

.cs_by_len:
    ; equal prefix — shorter string is less
    mov     rax, r9
    sub     rax, r11            ; a.len - b.len

    pop_regs r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_cmp_slices

; -----------------------------------------------------------------------------
; str_cmp_slices_nocase
;
; Case-insensitive comparator for StrSlice pointers.
; -----------------------------------------------------------------------------

STR_FUNC str_cmp_slices_nocase

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi

    mov     r8,  [rbx + StrSlice.ptr]
    mov     r9,  [rbx + StrSlice.len]
    mov     r10, [r12 + StrSlice.ptr]
    mov     r11, [r12 + StrSlice.len]

    mov     r13, r9
    cmp     r13, r11
    jbe     .csnc_min
    mov     r13, r11

.csnc_min:
    xor     ecx, ecx

.csnc_loop:
    cmp     rcx, r13
    jae     .csnc_by_len

    movzx   eax, byte [r8 + rcx]
    movzx   edx, byte [r10 + rcx]

    ; fold to lowercase
    cmp     al, 'A'
    jb      .csnc_fold_b
    cmp     al, 'Z'
    ja      .csnc_fold_b
    or      al, 0x20

.csnc_fold_b:
    cmp     dl, 'A'
    jb      .csnc_cmp
    cmp     dl, 'Z'
    ja      .csnc_cmp
    or      dl, 0x20

.csnc_cmp:
    cmp     eax, edx
    jne     .csnc_diff
    inc     ecx
    jmp     .csnc_loop

.csnc_diff:
    sub     eax, edx
    pop_regs r13, r12, rbx
    pop     rbp
    ret

.csnc_by_len:
    mov     rax, r9
    sub     rax, r11

    pop_regs r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_cmp_slices_nocase

; -----------------------------------------------------------------------------
; str_sort_slices
;
; Sort an array of StrSlice in ascending lexicographic order.
;
; Signature:
;   int64_t str_sort_slices(StrSlice *arr, uint64_t count)
; -----------------------------------------------------------------------------

STR_FUNC str_sort_slices

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, 2
    jb      .ss_done

    ; call str_sort with elem_size=STRSLICE_SIZE, cmp=str_cmp_slices
    mov     rdx, STRSLICE_SIZE
    lea     rcx, [rel str_cmp_slices]
    xor     r8d, r8d            ; ctx = null

    pop     rbp
    jmp     str_sort

.ss_done:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_sort_slices

; -----------------------------------------------------------------------------
; str_sort_slices_rev
;
; Sort in descending lexicographic order.
; -----------------------------------------------------------------------------

; Reverse comparator (swap a and b)
.cmp_rev:
    ; rdi=b, rsi=a (swapped)
    xchg    rdi, rsi
    jmp     str_cmp_slices

STR_FUNC str_sort_slices_rev

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, 2
    jb      .ssr_done

    mov     rdx, STRSLICE_SIZE
    lea     rcx, [rel .cmp_rev]
    xor     r8d, r8d

    pop     rbp
    jmp     str_sort

.ssr_done:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_sort_slices_rev

; -----------------------------------------------------------------------------
; str_sort_slices_nocase
;
; Case-insensitive sort.
; -----------------------------------------------------------------------------

STR_FUNC str_sort_slices_nocase

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, 2
    jb      .ssnc_done

    mov     rdx, STRSLICE_SIZE
    lea     rcx, [rel str_cmp_slices_nocase]
    xor     r8d, r8d

    pop     rbp
    jmp     str_sort

.ssnc_done:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_sort_slices_nocase

; -----------------------------------------------------------------------------
; str_cmp_by_len
;
; Comparator: sort by length first, then lexicographically.
; -----------------------------------------------------------------------------

.cmp_by_len:
    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    mov     rax, [rbx + StrSlice.len]
    mov     rcx, [r12 + StrSlice.len]
    cmp     rax, rcx
    jne     .cbl_diff

    ; same length — compare bytes
    pop_regs r12, rbx
    jmp     str_cmp_slices

.cbl_diff:
    sub     rax, rcx
    pop_regs r12, rbx
    pop     rbp
    ret

; -----------------------------------------------------------------------------
; str_sort_slices_by_len
;
; Sort by length ascending, then lexicographically for equal lengths.
; -----------------------------------------------------------------------------

STR_FUNC str_sort_slices_by_len

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, 2
    jb      .ssbl_done

    mov     rdx, STRSLICE_SIZE
    lea     rcx, [rel .cmp_by_len]
    xor     r8d, r8d

    pop     rbp
    jmp     str_sort

.ssbl_done:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_sort_slices_by_len
%endif ; GUARD_LIB_STR_SORT_SORT_UTF8_ASM
