%ifndef GUARD_LIB_STR_DIFF_DIFF_ASM
%define GUARD_LIB_STR_DIFF_DIFF_ASM
; =============================================================================
; str/diff/diff.asm
; Myers O(ND) greedy diff algorithm.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_diff_myers
;
; Compute the edit distance / shortest edit script length between two strings
; using the Myers O(ND) greedy algorithm.
;
; Signature:
;   int64_t str_diff_myers(const StrSlice *a, const StrSlice *b,
;                          int64_t *out_distance)
; -----------------------------------------------------------------------------
STR_FUNC str_diff_myers
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 2048           ; stack buffer for V array (up to max D = 120)

    mov     rbx, rdi            ; slice a
    mov     r12, rsi            ; slice b
    mov     r13, rdx            ; out_distance

    mov     r14, [rbx + StrSlice.len]   ; N
    mov     r15, [r12 + StrSlice.len]   ; M

    ; if both empty, distance = 0
    mov     rax, r14
    or      rax, r15
    jz      .diff_zero

    ; Max D = N + M
    mov     r8, r14
    add     r8, r15             ; MAX_D in R8

    ; clamp MAX_D to 120 for stack safety (2048 bytes V array)
    cmp     r8, 120
    jbe     .start_myers
    mov     r8, 120

.start_myers:
    ; V array initialization (V[1] = 0, others arbitrary)
    ; V array offsets: index k maps to [rsp + 1024 + k * 8]
    mov     qword [rsp + 1024 + 8], 0

    xor     r9, r9              ; D = 0

.d_loop:
    cmp     r9, r8
    ja      .fallback_max

    ; k runs from -D to D in steps of 2
    mov     r10, r9
    neg     r10                 ; k = -D

.k_loop:
    cmp     r10, r9
    jg      .next_d

    ; if k == -D or (k != D and V[k-1] < V[k+1]):
    ;     x = V[k+1]
    ; else:
    ;     x = V[k-1] + 1
    cmp     r10, r9
    neg     rax
    mov     rax, r9
    neg     rax                 ; -D
    je      .use_k_plus_1

    cmp     r10, r9
    je      .use_k_minus_1_plus_1

    ; check V[k-1] vs V[k+1]
    lea     rcx, [r10 - 1]
    mov     rax, [rsp + 1024 + rcx * 8]     ; V[k-1]
    lea     rcx, [r10 + 1]
    mov     rdx, [rsp + 1024 + rcx * 8]     ; V[k+1]
    cmp     rax, rdx
    jl      .use_k_plus_1

.use_k_minus_1_plus_1:
    lea     rcx, [r10 - 1]
    mov     rax, [rsp + 1024 + rcx * 8]
    inc     rax                 ; x = V[k-1] + 1
    jmp     .diagonal_traverse

.use_k_plus_1:
    lea     rcx, [r10 + 1]
    mov     rax, [rsp + 1024 + rcx * 8]     ; x = V[k+1]

.diagonal_traverse:
    ; y = x - k
    mov     rcx, rax
    sub     rcx, r10            ; y in RCX

    ; while x < N and y < M and a[x] == b[y]: x++, y++
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rdi, [r12 + StrSlice.ptr]

.match_loop:
    cmp     rax, r14
    jae     .match_done
    cmp     rcx, r15
    jae     .match_done

    movzx   r11d, byte [rsi + rax]
    movzx   r12d, byte [rdi + rcx]
    cmp     r11b, r12b
    jne     .match_done

    inc     rax
    inc     rcx
    jmp     .match_loop

.match_done:
    ; V[k] = x
    mov     [rsp + 1024 + r10 * 8], rax

    ; if x >= N and y >= M, we are done
    cmp     rax, r14
    jb      .next_k
    cmp     rcx, r15
    jae     .found_d

.next_k:
    add     r10, 2
    jmp     .k_loop

.next_d:
    inc     r9
    jmp     .d_loop

.found_d:
    mov     [r13], r9
    add     rsp, 2048
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.diff_zero:
    mov     qword [r13], 0
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.fallback_max:
    ; if D exceeds limit, return max distance N+M
    mov     rax, r14
    add     rax, r15
    mov     [r13], rax
    add     rsp, 2048
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret
STR_ENDFUNC str_diff_myers

%endif ; GUARD_LIB_STR_DIFF_DIFF_ASM
