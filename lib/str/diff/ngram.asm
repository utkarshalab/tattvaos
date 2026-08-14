%ifndef GUARD_LIB_STR_DIFF_NGRAM_ASM
%define GUARD_LIB_STR_DIFF_NGRAM_ASM
; =============================================================================
; str/diff/ngram.asm
; N-gram extraction and Jaccard similarity.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/copy.asm  (str_copy_bytes)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; Internal helper to check if two StrSlices are equal
_slices_equal:
    mov     rax, [rdi + StrSlice.len]
    cmp     rax, [rsi + StrSlice.len]
    jne     .no

    test    rax, rax
    jz      .yes

    mov     r8, [rdi + StrSlice.ptr]
    mov     r9, [rsi + StrSlice.ptr]
    xor     rcx, rcx
.loop:
    cmp     rcx, rax
    je      .yes
    movzx   r10d, byte [r8 + rcx]
    movzx   r11d, byte [r9 + rcx]
    cmp     r10b, r11b
    jne     .no
    inc     rcx
    jmp     .loop

.yes:
    mov     eax, 1
    ret
.no:
    xor     eax, eax
    ret

; -----------------------------------------------------------------------------
; str_ngram_count
;
; Calculate number of n-grams in the string.
;
; Signature:
;   uint64_t str_ngram_count(const StrSlice *src, uint64_t n)
; -----------------------------------------------------------------------------
STR_FUNC str_ngram_count
    guard_null rdi, 0

    mov     rax, [rdi + StrSlice.len]
    test    rsi, rsi
    jz      .zero
    cmp     rax, rsi
    jb      .zero

    sub     rax, rsi
    inc     rax
    pop     rbp
    ret

.zero:
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_ngram_count

; -----------------------------------------------------------------------------
; str_ngram_extract
;
; Extract all n-grams as views into src.
;
; Signature:
;   int64_t str_ngram_extract(const StrSlice *src, uint64_t n,
;                             StrSlice *out_grams, uint64_t max_count,
;                             uint64_t *out_count)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — n (uint64_t)
;   RDX  — out_grams (StrSlice array)
;   RCX  — max_count (uint64_t)
;   R8   — out_count (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_ngram_extract
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 8              ; align

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; n
    mov     r13, rdx            ; out_grams
    mov     r14, rcx            ; max_count
    mov     r15, r8             ; out_count

    ; count grams
    mov     rdi, rbx
    mov     rsi, r12
    call    str_ngram_count
    mov     [r15], rax          ; write out_count

    test    rax, rax
    jz      .done

    cmp     rax, r14            ; verify max_count
    ja      .too_small

    ; Extract
    mov     r8, [rbx + StrSlice.ptr]
    xor     rcx, rcx            ; i = 0

.loop:
    cmp     rcx, [r15]
    je      .done

    ; Gram starts at r8 + rcx, length is r12
    lea     rsi, [r8 + rcx]
    mov     rax, rcx
    shl     rax, 4              ; i * 16 (STRSLICE_SIZE)
    lea     rdi, [r13 + rax]    ; out_grams[i] pointer

    mov     [rdi + StrSlice.ptr], rsi
    mov     [rdi + StrSlice.len], r12

    inc     rcx
    jmp     .loop

.done:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_ngram_extract

; -----------------------------------------------------------------------------
; str_jaccard_similarity
;
; Calculate Jaccard similarity coefficient based on n-gram sets of a and b.
;
; Signature:
;   int64_t str_jaccard_similarity(const StrSlice *a, const StrSlice *b,
;                                  uint64_t n, double *out_sim)
; -----------------------------------------------------------------------------
STR_FUNC str_jaccard_similarity
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    ; Stack allocations:
    ;   [rsp + 0]    = A (4096 bytes)
    ;   [rsp + 4096] = B (4096 bytes)
    ;   [rsp + 8192] = count_a (8 bytes)
    ;   [rsp + 8200] = count_b (8 bytes)
    ;   [rsp + 8208] = out_sim ptr (8 bytes)
    ; Total = 8232 bytes (keeps 16-byte alignment)
    sub     rsp, 8232

    mov     rbx, rdi            ; a
    mov     r12, rsi            ; b
    mov     r13, rdx            ; n
    mov     [rsp + 8208], rcx   ; save out_sim ptr

    ; check n-gram counts
    mov     rdi, rbx
    mov     rsi, r13
    call    str_ngram_count
    mov     r14, rax            ; count_a

    mov     rdi, r12
    mov     rsi, r13
    call    str_ngram_count
    mov     r15, rax            ; count_b

    ; if both are 0
    test    r14, r14
    jnz     .check_limits
    test    r15, r15
    jnz     .check_limits

    ; both have 0 n-grams -> return 1.0 if identical or both empty
    mov     rax, [rbx + StrSlice.len]
    cmp     rax, [r12 + StrSlice.len]
    jne     .both_zero_different

    ; check content
    mov     rdi, rbx
    mov     rsi, r12
    call    _slices_equal
    test    rax, rax
    jz      .both_zero_different

    ; similarity = 1.0
    mov     rax, [rsp + 8208]
    mov     rcx, 0x3FF0000000000000     ; 1.0 in double IEEE-754
    mov     [rax], rcx
    jmp     .ok

.both_zero_different:
    mov     rax, [rsp + 8208]
    mov     qword [rax], 0      ; 0.0
    jmp     .ok

.check_limits:
    cmp     r14, 256
    ja      .too_large
    cmp     r15, 256
    ja      .too_large

    ; 1. Extract n-grams of a
    mov     rdi, rbx
    mov     rsi, r13
    mov     rdx, rsp            ; A array
    mov     rcx, 256
    lea     r8, [rsp + 8192]    ; &count_a
    call    str_ngram_extract
    test    rax, rax
    jnz     .err

    ; 2. Extract n-grams of b
    mov     rdi, r12
    mov     rsi, r13
    lea     rdx, [rsp + 4096]   ; B array
    mov     rcx, 256
    lea     r8, [rsp + 8200]    ; &count_b
    call    str_ngram_extract
    test    rax, rax
    jnz     .err

    ; 3. Unique A in-place
    mov     r8, [rsp + 8192]    ; count_a
    xor     r9, r9              ; unique_a = 0
    xor     r10, r10            ; i = 0

.unique_a_loop:
    cmp     r10, r8
    je      .unique_a_done

    ; check if A[r10] in A[0 .. r9-1]
    xor     r11, r11            ; j = 0
.unique_a_check:
    cmp     r11, r9
    je      .unique_a_add

    lea     rdi, [rsp + r10 * 16]       ; A[r10]
    lea     rsi, [rsp + r11 * 16]       ; A[r11]
    push    r8
    push    r9
    push    r10
    call    _slices_equal
    pop     r10
    pop     r9
    pop     r8
    test    rax, rax
    jnz     .unique_a_next              ; duplicate found

    inc     r11
    jmp     .unique_a_check

.unique_a_add:
    ; A[r9] = A[r10]
    mov     rax, [rsp + r10 * 16]
    mov     [rsp + r9 * 16], rax
    mov     rax, [rsp + r10 * 16 + 8]
    mov     [rsp + r9 * 16 + 8], rax
    inc     r9                          ; unique_a++

.unique_a_next:
    inc     r10
    jmp     .unique_a_loop

.unique_a_done:
    mov     [rsp + 8192], r9            ; update unique count_a

    ; 4. Unique B in-place
    mov     r8, [rsp + 8200]    ; count_b
    xor     r9, r9              ; unique_b = 0
    xor     r10, r10            ; i = 0

.unique_b_loop:
    cmp     r10, r8
    je      .unique_b_done

    xor     r11, r11
.unique_b_check:
    cmp     r11, r9
    je      .unique_b_add

    lea     rdi, [rsp + 4096 + r10 * 16]
    lea     rsi, [rsp + 4096 + r11 * 16]
    push    r8
    push    r9
    push    r10
    call    _slices_equal
    pop     r10
    pop     r9
    pop     r8
    test    rax, rax
    jnz     .unique_b_next

    inc     r11
    jmp     .unique_b_check

.unique_b_add:
    mov     rax, [rsp + 4096 + r10 * 16]
    mov     [rsp + 4096 + r9 * 16], rax
    mov     rax, [rsp + 4096 + r10 * 16 + 8]
    mov     [rsp + 4096 + r9 * 16 + 8], rax
    inc     r9

.unique_b_next:
    inc     r10
    jmp     .unique_b_loop

.unique_b_done:
    mov     [rsp + 8200], r9            ; update unique count_b

    ; 5. Find intersection size
    xor     r14, r14            ; intersection = 0
    xor     r10, r10            ; i = 0 (loop unique A)
    mov     r8, [rsp + 8192]    ; unique count_a
    mov     r9, [rsp + 8200]    ; unique count_b

.inter_loop:
    cmp     r10, r8
    je      .inter_done

    xor     r11, r11            ; j = 0
.inter_check:
    cmp     r11, r9
    je      .inter_next

    lea     rdi, [rsp + r10 * 16]
    lea     rsi, [rsp + 4096 + r11 * 16]
    push    r8
    push    r9
    push    r10
    call    _slices_equal
    pop     r10
    pop     r9
    pop     r8
    test    rax, rax
    jz      .inter_check_next

    inc     r14                 ; intersection++
    jmp     .inter_next         ; duplicate not possible since sets are uniqued

.inter_check_next:
    inc     r11
    jmp     .inter_check

.inter_next:
    inc     r10
    jmp     .inter_loop

.inter_done:
    ; union = unique_a + unique_b - intersection
    mov     r15, r8
    add     r15, r9
    sub     r15, r14            ; union

    ; Calculate Jaccard similarity: intersection / union
    test    r15, r15
    jz      .sim_one

    cvtsi2sd xmm0, r14
    cvtsi2sd xmm1, r15
    divsd    xmm0, xmm1

    mov     rax, [rsp + 8208]
    movsd   [rax], xmm0
    jmp     .ok

.sim_one:
    mov     rax, [rsp + 8208]
    mov     rcx, 0x3FF0000000000000
    mov     [rax], rcx

.ok:
    add     rsp, 8232
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_large:
    add     rsp, 8232
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.err:
    add     rsp, 8232
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_jaccard_similarity

%endif ; GUARD_LIB_STR_DIFF_NGRAM_ASM
