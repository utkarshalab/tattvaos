; =============================================================================
; str/diff/lcs.asm
; Longest Common Subsequence (LCS) length and reconstruction.
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
; LCS: find the longest sequence of characters that appears in both strings
; in the same order (not necessarily contiguous).
;
;   lcs("ABCBDAB", "BDCABA") = "BCAB" or "BDAB" (length 4)
;
; Algorithm: standard DP, O(m×n) time, O(min(m,n)) space for length only.
;
; Note: LCS length = (m + n - edit_distance) / 2
;       So edit distance and LCS are mathematically related.
;
; Functions:
;   str_lcs_len           — length of LCS only (space-optimized)
;   str_lcs_slice_len     — StrSlice variant
;   str_lcs              — reconstruct the actual LCS string
;   str_lcs_similarity   — similarity ratio: 2*lcs_len / (m+n)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

LCS_STACK_MAX   equ 512

section .text

; -----------------------------------------------------------------------------
; str_lcs_len
;
; Compute the length of the Longest Common Subsequence.
; Uses two-row DP (O(min(m,n)) space).
;
; Signature:
;   int64_t str_lcs_len(const uint8_t *a, uint64_t a_len,
;                        const uint8_t *b, uint64_t b_len,
;                        uint64_t *out_len)
;
; Arguments:
;   RDI  — string a
;   RSI  — a_len
;   RDX  — string b
;   RCX  — b_len
;   R8   — pointer to uint64_t for LCS length
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL  strings too long for stack
; -----------------------------------------------------------------------------

STR_FUNC str_lcs_len

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    ; ensure b is the shorter string (b = row dimension)
    cmp     rsi, rcx
    jbe     .lcs_no_swap
    xchg    rdi, rdx
    xchg    rsi, rcx

.lcs_no_swap:
    mov     rbx, rdi            ; a (longer)
    mov     r12, rsi            ; m = a_len
    mov     r13, rdx            ; b (shorter)
    mov     r14, rcx            ; n = b_len
    mov     r15, r8             ; out

    ; trivial cases
    test    r12, r12
    jz      .lcs_zero
    test    r14, r14
    jz      .lcs_zero

    ; check stack limit: need 2*(n+1)*8 bytes
    mov     rax, r14
    inc     rax
    shl     rax, 4
    cmp     rax, LCS_STACK_MAX * 16
    ja      .lcs_too_large

    ; allocate two rows
    mov     rcx, r14
    inc     rcx
    shl     rcx, 3              ; row_bytes = (n+1)*8

    sub     rsp, rcx
    sub     rsp, rcx
    and     rsp, -16

    ; prev_row at rsp, curr_row at rsp + row_bytes
    mov     r9, rcx             ; row_bytes

    ; initialize prev_row to all zeros
    xor     rax, rax
    mov     rcx, r14
    inc     rcx

.lcs_init:
    test    rcx, rcx
    jz      .lcs_dp
    mov     [rsp + rax * 8], qword 0
    inc     rax
    dec     rcx
    jmp     .lcs_init

.lcs_dp:
    ; for i = 1..m
    xor     r10, r10            ; i = 0

.lcs_outer:
    inc     r10
    cmp     r10, r12
    ja      .lcs_done

    ; curr_row[0] = 0
    mov     [rsp + r9], qword 0

    movzx   r11d, byte [rbx + r10 - 1]  ; a[i-1]

    ; for j = 1..n
    xor     rcx, rcx            ; j = 0

.lcs_inner:
    inc     rcx
    cmp     rcx, r14
    ja      .lcs_inner_done

    movzx   rax, byte [r13 + rcx - 1]   ; b[j-1]

    cmp     al, r11b
    jne     .lcs_no_match

    ; match: curr[j] = prev[j-1] + 1
    mov     rax, rcx
    dec     rax
    mov     rax, [rsp + rax * 8]        ; prev[j-1]
    inc     rax
    mov     [rsp + r9 + rcx * 8], rax
    jmp     .lcs_inner

.lcs_no_match:
    ; curr[j] = max(prev[j], curr[j-1])
    mov     rax, [rsp + rcx * 8]        ; prev[j]
    mov     rdx, rcx
    dec     rdx
    mov     rdx, [rsp + r9 + rdx * 8]  ; curr[j-1]
    cmp     rax, rdx
    jae     .lcs_take_prev
    mov     rax, rdx
.lcs_take_prev:
    mov     [rsp + r9 + rcx * 8], rax
    jmp     .lcs_inner

.lcs_inner_done:
    ; swap rows: memcpy curr to prev
    xor     rax, rax
.lcs_swap:
    cmp     rax, r14
    ja      .lcs_outer
    mov     rdx, [rsp + r9 + rax * 8]
    mov     [rsp + rax * 8], rdx
    inc     rax
    jmp     .lcs_swap

.lcs_done:
    ; result in prev_row[n]
    mov     rax, [rsp + r14 * 8]
    mov     [r15], rax

    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lcs_zero:
    mov     qword [r8], 0
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lcs_too_large:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_lcs_len

; -----------------------------------------------------------------------------
; str_lcs_slice_len — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_lcs_slice_len

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     r8, r13
    mov     rcx, [r12 + StrSlice.len]
    mov     rdx, [r12 + StrSlice.ptr]
    mov     rsi, [rbx + StrSlice.len]
    mov     rdi, [rbx + StrSlice.ptr]

    pop_regs r13, r12, rbx
    pop     rbp
    jmp     str_lcs_len

STR_ENDFUNC str_lcs_slice_len

; -----------------------------------------------------------------------------
; str_lcs
;
; Reconstruct the actual LCS string into a buffer.
; Uses full O(m×n) DP table (requires more memory).
;
; Signature:
;   int64_t str_lcs(const uint8_t *a, uint64_t a_len,
;                    const uint8_t *b, uint64_t b_len,
;                    uint8_t *out_buf, uint64_t buf_cap,
;                    uint64_t *out_len)
;
; Arguments:
;   RDI  — string a
;   RSI  — a_len
;   RDX  — string b
;   RCX  — b_len
;   R8   — output buffer for LCS string
;   R9   — buffer capacity
;   [rsp+8] — out_len
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL  DP table or output too small
; -----------------------------------------------------------------------------

STR_FUNC str_lcs

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; a
    mov     r12, rsi            ; a_len (m)
    mov     r13, rdx            ; b
    mov     r14, rcx            ; b_len (n)
    mov     r15, r8             ; out_buf
    push    r9                  ; buf_cap
    push    qword [rsp + 56]    ; out_len

    ; trivial: if either empty, LCS is empty
    test    r12, r12
    jz      .lcs_full_empty
    test    r14, r14
    jz      .lcs_full_empty

    ; check stack limit: need (m+1)*(n+1)*8 bytes for full table
    ; that's large — cap at 128×128 = 16384 entries
    mov     rax, r12
    inc     rax
    mov     rcx, r14
    inc     rcx
    imul    rax, rcx
    cmp     rax, 16384
    ja      .lcs_full_too_large

    ; allocate DP table on stack: (m+1)*(n+1) uint64_t entries
    imul    rax, rax, 8
    sub     rsp, rax
    and     rsp, -16

    ; initialize first row and column to 0
    ; row 0: dp[0][j] = 0 for all j
    ; col 0: dp[i][0] = 0 for all i
    ; Since memory starts zeroed on stack... it's not. Zero it.
    mov     rdi, rsp
    mov     rcx, rax
    xor     eax, eax
    rep stosb
    ; but rdi/rcx/rax are clobbered now. Reload.

    ; n+1 columns
    mov     r8, r14
    inc     r8                  ; r8 = n+1 (cols)

    ; fill DP table
    ; dp[i][j] at rsp + (i*(n+1) + j) * 8
    xor     r9, r9              ; i = 0

.lcs_full_outer:
    inc     r9
    cmp     r9, r12
    ja      .lcs_full_backtrack

    movzx   r10d, byte [rbx + r9 - 1]   ; a[i-1]

    xor     r11, r11            ; j = 0

.lcs_full_inner:
    inc     r11
    cmp     r11, r14
    ja      .lcs_full_inner_done

    movzx   eax, byte [r13 + r11 - 1]   ; b[j-1]

    cmp     al, r10b
    jne     .lcs_full_no_match

    ; dp[i][j] = dp[i-1][j-1] + 1
    mov     rax, r9
    dec     rax
    imul    rax, r8
    add     rax, r11
    dec     rax
    mov     rax, [rsp + rax * 8]        ; dp[i-1][j-1]
    inc     rax

    mov     rdx, r9
    imul    rdx, r8
    add     rdx, r11
    mov     [rsp + rdx * 8], rax
    jmp     .lcs_full_inner

.lcs_full_no_match:
    ; dp[i][j] = max(dp[i-1][j], dp[i][j-1])
    ; dp[i-1][j]
    mov     rax, r9
    dec     rax
    imul    rax, r8
    add     rax, r11
    mov     rax, [rsp + rax * 8]

    ; dp[i][j-1]
    mov     rdx, r9
    imul    rdx, r8
    add     rdx, r11
    dec     rdx
    mov     rdx, [rsp + rdx * 8]

    cmp     rax, rdx
    jae     .lcs_full_take_up
    mov     rax, rdx
.lcs_full_take_up:
    mov     rdx, r9
    imul    rdx, r8
    add     rdx, r11
    mov     [rsp + rdx * 8], rax
    jmp     .lcs_full_inner

.lcs_full_inner_done:
    jmp     .lcs_full_outer

.lcs_full_backtrack:
    ; backtrack to reconstruct LCS
    ; start at dp[m][n], walk to dp[0][0]
    mov     r9, r12             ; i = m
    mov     r11, r14            ; j = n

    ; LCS written in reverse — we'll reverse at end
    xor     r10, r10            ; output index

.lcs_bt_loop:
    test    r9, r9
    jz      .lcs_bt_done
    test    r11, r11
    jz      .lcs_bt_done

    ; check if a[i-1] == b[j-1]
    movzx   eax, byte [rbx + r9 - 1]
    movzx   edx, byte [r13 + r11 - 1]
    cmp     al, dl
    jne     .lcs_bt_no_match

    ; match: record character
    pop     rcx                 ; buf_cap
    push    rcx
    cmp     r10, rcx
    jae     .lcs_bt_buf_small

    mov     [r15 + r10], al
    inc     r10
    dec     r9
    dec     r11
    jmp     .lcs_bt_loop

.lcs_bt_no_match:
    ; go in direction of larger dp value
    ; dp[i-1][j] vs dp[i][j-1]
    mov     rax, r9
    dec     rax
    imul    rax, r8
    add     rax, r11
    mov     rax, [rsp + rax * 8]    ; dp[i-1][j]

    mov     rdx, r9
    imul    rdx, r8
    add     rdx, r11
    dec     rdx
    mov     rdx, [rsp + rdx * 8]    ; dp[i][j-1]

    cmp     rax, rdx
    jb      .lcs_bt_go_left
    dec     r9
    jmp     .lcs_bt_loop

.lcs_bt_go_left:
    dec     r11
    jmp     .lcs_bt_loop

.lcs_bt_done:
    ; reverse the output (it's backwards)
    mov     rax, r10            ; lcs_len
    test    rax, rax
    jz      .lcs_write_len

    mov     r9, r15             ; lo
    mov     r11, r15
    add     r11, rax
    dec     r11                 ; hi

.lcs_reverse:
    cmp     r9, r11
    jae     .lcs_write_len
    movzx   ecx, byte [r9]
    movzx   edx, byte [r11]
    mov     [r9], dl
    mov     [r11], cl
    inc     r9
    dec     r11
    jmp     .lcs_reverse

.lcs_write_len:
    pop     rdx                 ; out_len
    pop     rcx                 ; buf_cap (discard)
    test    rdx, rdx
    jz      .lcs_full_ok
    mov     [rdx], r10

.lcs_full_ok:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lcs_full_empty:
    pop     rdx
    pop     rcx
    test    rcx, rcx
    jz      .lcs_fe_ok
    mov     qword [rcx], 0
.lcs_fe_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lcs_full_too_large:
    pop     rdx
    pop     rcx
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.lcs_bt_buf_small:
    mov     rsp, rbp
    pop     rdx
    pop     rcx
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_lcs

; -----------------------------------------------------------------------------
; str_lcs_similarity
;
; Compute similarity ratio between two strings based on LCS.
; similarity = 2 * lcs_len / (m + n)   (Dice coefficient)
; Returns as fixed-point: multiply by 1000, so 1.0 = 1000.
;
; Signature:
;   int64_t str_lcs_similarity(const uint8_t *a, uint64_t a_len,
;                               const uint8_t *b, uint64_t b_len,
;                               uint64_t *out_permille)
; -----------------------------------------------------------------------------

STR_FUNC str_lcs_similarity

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r8

    ; compute LCS length
    sub     rsp, 8
    and     rsp, -8

    mov     r8, rsp
    call    str_lcs_len
    test    rax, rax
    jnz     .lcs_sim_err

    mov     r9, [rsp]           ; lcs_len
    add     rsp, 8

    ; similarity = 2 * lcs_len * 1000 / (m + n)
    mov     rax, r9
    imul    rax, rax, 2000      ; 2 * lcs_len * 1000

    mov     rdx, r12
    add     rdx, r14            ; m + n
    test    rdx, rdx
    jz      .lcs_sim_zero

    xor     edx, edx
    div     rdx                 ; wrong — rdx:rax / rdx
    ; need: rax = 2*lcs*1000, rdx = 0, divide by (m+n)
    mov     rcx, r12
    add     rcx, r14
    xor     edx, edx
    div     rcx
    ; rax = similarity in permille

    mov     [r15], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lcs_sim_zero:
    add     rsp, 8
    mov     qword [r15], 0
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.lcs_sim_err:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_lcs_similarity