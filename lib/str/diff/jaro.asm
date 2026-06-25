; =============================================================================
; str/diff/jaro.asm
; Jaro similarity metric for string comparison.
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
; Jaro similarity:
;
;   Given strings s1 (length m) and s2 (length n):
;   Matching window: floor(max(m,n)/2) - 1
;
;   Two characters match if:
;     - They are the same character
;     - Their positions differ by at most the match window
;
;   m_count = number of matching characters
;   t = number of transpositions / 2
;        (matching chars in different order)
;
;   jaro(s1, s2) = 0                           if m_count == 0
;               = (m/|s1| + m/|s2| + (m-t)/m) / 3  otherwise
;
;   Result is in range [0.0, 1.0]:
;     0.0 = completely different
;     1.0 = identical
;
;   We return as fixed-point × 1,000,000 (6 decimal places).
;
; Properties:
;   - Good for short strings and name matching
;   - Handles transpositions (unlike edit distance which counts them as 2 ops)
;   - Basis for Jaro-Winkler (which adds prefix bonus)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; Fixed-point scale: 1.0 = 1,000,000
JARO_SCALE  equ 1000000

section .text

; -----------------------------------------------------------------------------
; str_jaro
;
; Compute Jaro similarity between two byte strings.
; Returns result as fixed-point integer × 1,000,000.
;
; Signature:
;   int64_t str_jaro(const uint8_t *s1, uint64_t len1,
;                    const uint8_t *s2, uint64_t len2,
;                    uint64_t *out_similarity)
;
; Arguments:
;   RDI  — string s1
;   RSI  — len1
;   RDX  — string s2
;   RCX  — len2
;   R8   — pointer to uint64_t for similarity (× 1,000,000)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL  strings too long for stack
; -----------------------------------------------------------------------------

JARO_MAX_LEN    equ 256         ; max string length for stack allocation

STR_FUNC str_jaro

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; s1
    mov     r12, rsi            ; len1
    mov     r13, rdx            ; s2
    mov     r14, rcx            ; len2
    mov     r15, r8             ; out

    ; handle empty strings
    test    r12, r12
    jz      .jaro_empty_check
    test    r14, r14
    jz      .jaro_empty_check
    jmp     .jaro_nonempty

.jaro_empty_check:
    ; if both empty: similarity = 1.0
    test    r12, r12
    jnz     .jaro_zero_sim
    test    r14, r14
    jnz     .jaro_zero_sim
    mov     qword [r15], JARO_SCALE
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.jaro_zero_sim:
    mov     qword [r15], 0
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.jaro_nonempty:
    ; check length limit
    cmp     r12, JARO_MAX_LEN
    ja      .jaro_too_large
    cmp     r14, JARO_MAX_LEN
    ja      .jaro_too_large

    ; compute match window = floor(max(len1,len2)/2) - 1
    mov     r9, r12
    cmp     r9, r14
    jae     .jaro_max_is_len1
    mov     r9, r14
.jaro_max_is_len1:
    shr     r9, 1               ; max/2
    test    r9, r9
    jz      .jaro_window_zero
    dec     r9                  ; window = max/2 - 1
    jmp     .jaro_have_window
.jaro_window_zero:
    xor     r9, r9              ; window = 0

.jaro_have_window:
    ; allocate match arrays on stack: match1[len1] and match2[len2]
    ; each is a byte array (0=unmatched, 1=matched)
    sub     rsp, JARO_MAX_LEN * 2 + 16
    and     rsp, -16

    ; zero match arrays
    mov     rdi, rsp
    mov     ecx, JARO_MAX_LEN * 2
    xor     eax, eax
    rep stosb

    ; match1 at rsp, match2 at rsp + JARO_MAX_LEN

    ; find matches
    xor     r10, r10            ; m_count = 0
    xor     rax, rax            ; i = 0

.jaro_match_outer:
    cmp     rax, r12
    jae     .jaro_match_done

    ; window bounds for s2: [max(0, i-window), min(len2-1, i+window)]
    mov     rcx, rax
    sub     rcx, r9             ; start = i - window
    jns     .jaro_start_ok
    xor     ecx, ecx

.jaro_start_ok:
    mov     rdx, rax
    add     rdx, r9             ; end = i + window
    cmp     rdx, r14
    jb      .jaro_end_ok
    mov     rdx, r14
    dec     rdx

.jaro_end_ok:
    movzx   r11d, byte [rbx + rax]  ; s1[i]

    ; scan s2[start..end] for a match
    push    rax
    push    rdx

.jaro_match_inner:
    cmp     rcx, rdx
    ja      .jaro_match_inner_done

    ; skip if s2[j] already matched
    movzx   r8d, byte [rsp + JARO_MAX_LEN + rcx + 16]  ; match2[j] (offset for pushes)
    ; Note: rsp changed due to push — adjust offset
    ; match2 is at original_rsp + JARO_MAX_LEN
    ; after 2 pushes (16 bytes): match2 at rsp + JARO_MAX_LEN + 16
    test    r8d, r8d
    jnz     .jaro_inner_next

    movzx   r8d, byte [r13 + rcx]       ; s2[j]
    cmp     r8b, r11b
    jne     .jaro_inner_next

    ; match found
    pop     rdx
    pop     rax
    ; mark match1[i] = 1
    mov     byte [rsp + rax], 1
    ; mark match2[j] = 1
    mov     byte [rsp + JARO_MAX_LEN + rcx], 1
    inc     r10                 ; m_count++
    jmp     .jaro_match_outer_next

.jaro_inner_next:
    inc     rcx
    jmp     .jaro_match_inner

.jaro_match_inner_done:
    pop     rdx
    pop     rax

.jaro_match_outer_next:
    inc     rax
    jmp     .jaro_match_outer

.jaro_match_done:
    ; m_count in r10
    test    r10, r10
    jz      .jaro_no_matches

    ; count transpositions
    ; iterate through matched chars of s1 and s2 in order
    ; count where they differ (each difference = half transposition)
    xor     r11, r11            ; transpositions * 2
    xor     rax, rax            ; s2 scan index
    xor     rcx, rcx            ; s1 index

.jaro_trans_outer:
    cmp     rcx, r12
    jae     .jaro_trans_done

    ; skip unmatched in s1
    movzx   r8d, byte [rsp + rcx]   ; match1[i]
    test    r8d, r8d
    jz      .jaro_trans_outer_next

    ; find next matched in s2
.jaro_trans_inner:
    cmp     rax, r14
    jae     .jaro_trans_done

    movzx   r8d, byte [rsp + JARO_MAX_LEN + rax]  ; match2[j]
    test    r8d, r8d
    jnz     .jaro_trans_found
    inc     rax
    jmp     .jaro_trans_inner

.jaro_trans_found:
    ; compare s1[i] with s2[j]
    movzx   r8d, byte [rbx + rcx]
    movzx   r9d, byte [r13 + rax]
    cmp     r8b, r9b
    je      .jaro_trans_match
    inc     r11                 ; transposition

.jaro_trans_match:
    inc     rax

.jaro_trans_outer_next:
    inc     rcx
    jmp     .jaro_trans_outer

.jaro_trans_done:
    ; t = r11 / 2 (transpositions)
    shr     r11, 1              ; t

    ; jaro = (m/len1 + m/len2 + (m-t)/m) / 3
    ; all in fixed-point × 1,000,000

    ; term1 = m * 1000000 / len1
    mov     rax, r10
    imul    rax, rax, JARO_SCALE
    xor     edx, edx
    div     r12
    mov     r8, rax             ; term1

    ; term2 = m * 1000000 / len2
    mov     rax, r10
    imul    rax, rax, JARO_SCALE
    xor     edx, edx
    div     r14
    mov     r9, rax             ; term2

    ; term3 = (m - t) * 1000000 / m
    mov     rax, r10
    sub     rax, r11            ; m - t
    imul    rax, rax, JARO_SCALE
    xor     edx, edx
    div     r10
    ; rax = term3

    ; jaro = (term1 + term2 + term3) / 3
    add     r8, r9
    add     r8, rax
    xor     edx, edx
    mov     rax, r8
    mov     rcx, 3
    div     rcx

    mov     [r15], rax

    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.jaro_no_matches:
    ; m_count = 0: similarity = 0
    mov     qword [r15], 0
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.jaro_too_large:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_jaro

; -----------------------------------------------------------------------------
; str_jaro_slice — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_jaro_slice

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
    jmp     str_jaro

STR_ENDFUNC str_jaro_slice