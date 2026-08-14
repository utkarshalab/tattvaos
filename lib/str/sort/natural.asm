%ifndef GUARD_LIB_STR_SORT_NATURAL_ASM
%define GUARD_LIB_STR_SORT_NATURAL_ASM
; =============================================================================
; str/sort/natural.asm
; Natural sort ordering — numeric runs compared by value, not lexicographically.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   sort/sort_utf8.asm (str_sort_slices uses str_sort)
;   sort/sort.asm      (str_sort)
;
; -----------------------------------------------------------------------------
; Natural sort:
;   "file1"  < "file2"  < "file10"   (numeric: 10 > 2)
;   "item9"  < "item10" < "item100"
;   "1.2.10" < "1.2.9"  → false with natural sort: 10 > 9
;   "abc"    < "abd"                 (non-numeric: lexicographic)
;
; Algorithm:
;   Scan both strings simultaneously.
;   At each position:
;     - If both have digits: extract and compare numeric values.
;       If equal, shorter number comes first (leading zeros matter).
;     - Otherwise: compare single characters.
;
; Functions:
;   str_natural_cmp         — compare two strings with natural ordering
;   str_sort_slices_natural — sort StrSlice[] with natural ordering
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_natural_cmp
;
; Compare two StrSlices with natural ordering.
;
; Signature:
;   int64_t str_natural_cmp(const StrSlice *a, const StrSlice *b)
;
; Returns:
;   RAX  < 0   a before b
;   RAX  = 0   equal
;   RAX  > 0   a after b
; -----------------------------------------------------------------------------

STR_FUNC str_natural_cmp

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; a_ptr
    mov     r12, [rdi + StrSlice.len]   ; a_len
    mov     r13, [rsi + StrSlice.ptr]   ; b_ptr
    mov     r14, [rsi + StrSlice.len]   ; b_len

    xor     r9, r9              ; a index
    xor     r10, r10            ; b index

.nat_loop:
    ; check exhaustion
    cmp     r9, r12
    jae     .nat_a_done
    cmp     r10, r14
    jae     .nat_b_done

    movzx   eax, byte [rbx + r9]
    movzx   ecx, byte [r13 + r10]

    ; check if both are digits
    cmp     al, '0'
    jb      .nat_char_cmp
    cmp     al, '9'
    ja      .nat_char_cmp
    cmp     cl, '0'
    jb      .nat_char_cmp
    cmp     cl, '9'
    ja      .nat_char_cmp

    ; both digits — compare numeric runs
    ; extract full number from a
    mov     r8, r9              ; a_num_start
    xor     r15, r15            ; a_num_value

.nat_a_num:
    cmp     r9, r12
    jae     .nat_a_num_done
    movzx   eax, byte [rbx + r9]
    sub     eax, '0'
    cmp     eax, 9
    ja      .nat_a_num_done

    imul    r15, r15, 10
    add     r15, rax
    inc     r9
    jmp     .nat_a_num

.nat_a_num_done:
    mov     rdx, r9
    sub     rdx, r8             ; a_num_len

    ; extract full number from b
    mov     r11, r10            ; b_num_start
    xor     r8, r8              ; b_num_value (reuse r8)

.nat_b_num:
    cmp     r10, r14
    jae     .nat_b_num_done
    movzx   ecx, byte [r13 + r10]
    sub     ecx, '0'
    cmp     ecx, 9
    ja      .nat_b_num_done

    imul    r8, r8, 10
    add     r8, rcx
    inc     r10
    jmp     .nat_b_num

.nat_b_num_done:
    mov     rcx, r10
    sub     rcx, r11            ; b_num_len

    ; compare numeric values
    cmp     r15, r8
    jne     .nat_num_diff

    ; equal values — shorter (fewer digits) comes first
    ; (handles leading zeros: "007" after "7" if same value)
    cmp     rdx, rcx
    jne     .nat_len_diff

    ; same length and same value — continue
    jmp     .nat_loop

.nat_num_diff:
    sub     r15, r8
    mov     rax, r15
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.nat_len_diff:
    sub     rdx, rcx
    mov     rax, rdx
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.nat_char_cmp:
    ; non-digit comparison — case-insensitive for letters
    cmp     al, 'A'
    jb      .nat_no_fold_a
    cmp     al, 'Z'
    ja      .nat_no_fold_a
    or      al, 0x20
.nat_no_fold_a:
    cmp     cl, 'A'
    jb      .nat_no_fold_b
    cmp     cl, 'Z'
    ja      .nat_no_fold_b
    or      cl, 0x20
.nat_no_fold_b:

    cmp     eax, ecx
    je      .nat_char_equal

    sub     eax, ecx
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.nat_char_equal:
    inc     r9
    inc     r10
    jmp     .nat_loop

.nat_a_done:
    cmp     r10, r14
    jae     .nat_equal
    mov     rax, -1
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.nat_b_done:
    mov     rax, 1
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.nat_equal:
    xor     eax, eax
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_natural_cmp

; -----------------------------------------------------------------------------
; _natural_cmp_cb — callback wrapper for str_sort
; Arguments: RDI=a (StrSlice*), RSI=b (StrSlice*), RDX=ctx
; -----------------------------------------------------------------------------

_natural_cmp_cb:
    push    rbp
    mov     rbp, rsp
    ; ignore ctx (rdx)
    call    str_natural_cmp
    pop     rbp
    ret

; -----------------------------------------------------------------------------
; str_sort_slices_natural
;
; Sort an array of StrSlice with natural ordering.
;
; Signature:
;   int64_t str_sort_slices_natural(StrSlice *arr, uint64_t count)
; -----------------------------------------------------------------------------

STR_FUNC str_sort_slices_natural

    guard_null rdi, STR_ERR_NULL

    cmp     rsi, 2
    jb      .ssn_done

    mov     rdx, STRSLICE_SIZE
    lea     rcx, [rel _natural_cmp_cb]
    xor     r8d, r8d

    pop     rbp
    jmp     str_sort

.ssn_done:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_sort_slices_natural
%endif ; GUARD_LIB_STR_SORT_NATURAL_ASM
