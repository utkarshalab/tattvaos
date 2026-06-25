; =============================================================================
; str/diff/jaro_winkler.asm
; Jaro-Winkler similarity — Jaro with prefix bonus for matching prefixes.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   diff/jaro.asm  (str_jaro)
;
; -----------------------------------------------------------------------------
; Jaro-Winkler:
;
;   jaro_winkler(s1, s2) = jaro(s1, s2)
;                         + (l * p * (1 - jaro(s1, s2)))
;
;   Where:
;     l = length of common prefix (max 4 characters)
;     p = scaling factor (standard value: 0.1)
;
;   The prefix bonus rewards strings that share a common beginning,
;   which is common in name matching (e.g. "MARTHA" and "MARHTA").
;
;   Result range: [0.0, 1.0] × 1,000,000
;
; Properties:
;   - Extends Jaro with prefix bonus
;   - Very commonly used for record linkage and name matching
;   - Standard in genealogy software and fuzzy matching
;   - p = 0.1 is the standard value (gives max boost of 0.4 for l=4)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_jaro

; Fixed-point scale
JW_SCALE        equ 1000000
; p = 0.1 in fixed-point × JW_SCALE = 100000
JW_P_FACTOR     equ 100000
; max prefix length
JW_MAX_PREFIX   equ 4

section .text

; -----------------------------------------------------------------------------
; str_jaro_winkler
;
; Compute Jaro-Winkler similarity.
;
; Signature:
;   int64_t str_jaro_winkler(const uint8_t *s1, uint64_t len1,
;                             const uint8_t *s2, uint64_t len2,
;                             uint64_t *out_similarity)
;
; Arguments:
;   RDI  — s1
;   RSI  — len1
;   RDX  — s2
;   RCX  — len2
;   R8   — out (× 1,000,000)
;
; Returns:
;   RAX  = STR_OK or error
; -----------------------------------------------------------------------------

STR_FUNC str_jaro_winkler

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r8

    ; compute Jaro similarity first
    sub     rsp, 8
    and     rsp, -8

    mov     r8, rsp             ; jaro_out
    call    str_jaro
    test    rax, rax
    jnz     .jw_err

    mov     r9, [rsp]           ; jaro_sim × 1,000,000
    add     rsp, 8

    ; compute prefix length l (max JW_MAX_PREFIX)
    ; l = number of matching chars at start of s1 and s2
    xor     r10, r10            ; l = 0

.jw_prefix:
    cmp     r10, JW_MAX_PREFIX
    jae     .jw_prefix_done
    cmp     r10, r12
    jae     .jw_prefix_done
    cmp     r10, r14
    jae     .jw_prefix_done

    movzx   eax, byte [rbx + r10]
    movzx   ecx, byte [r13 + r10]
    cmp     al, cl
    jne     .jw_prefix_done

    inc     r10
    jmp     .jw_prefix

.jw_prefix_done:
    ; jaro_winkler = jaro + l * p * (1 - jaro)
    ; in fixed-point (× JW_SCALE):
    ; jw = jaro + l * JW_P_FACTOR * (JW_SCALE - jaro) / JW_SCALE

    ; (1 - jaro) in fixed-point = JW_SCALE - jaro_sim
    mov     rax, JW_SCALE
    sub     rax, r9             ; (1 - jaro) × JW_SCALE

    ; l * p * (1 - jaro) = l * JW_P_FACTOR * (JW_SCALE - jaro) / JW_SCALE
    imul    rax, r10            ; l * (JW_SCALE - jaro)
    imul    rax, rax, JW_P_FACTOR  ; l * p * (JW_SCALE - jaro)
    ; rax now = l * p * (1-jaro) * JW_SCALE^2
    ; need to divide by JW_SCALE
    xor     edx, edx
    mov     rcx, JW_SCALE
    div     rcx                 ; rax = l * p * (1-jaro) * JW_SCALE

    ; jw = jaro + bonus
    add     rax, r9

    ; cap at JW_SCALE (1.0)
    cmp     rax, JW_SCALE
    jbe     .jw_write
    mov     rax, JW_SCALE

.jw_write:
    mov     [r15], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.jw_err:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_jaro_winkler

; -----------------------------------------------------------------------------
; str_jaro_winkler_p
;
; Jaro-Winkler with custom p scaling factor.
;
; Signature:
;   int64_t str_jaro_winkler_p(const uint8_t *s1, uint64_t len1,
;                               const uint8_t *s2, uint64_t len2,
;                               uint64_t p_permille,
;                               uint64_t *out_similarity)
;
; Arguments:
;   RDI  — s1
;   RSI  — len1
;   RDX  — s2
;   RCX  — len2
;   R8   — p scaling factor in permille (0..1000, standard = 100 for p=0.1)
;   R9   — out
; -----------------------------------------------------------------------------

STR_FUNC str_jaro_winkler_p

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    ; r8 = p_permille
    mov     r15, r9             ; out

    sub     rsp, 8
    and     rsp, -8

    push    r8                  ; save p_permille

    mov     r8, rsp
    add     r8, 8               ; jaro output slot
    call    str_jaro
    test    rax, rax
    jnz     .jwp_err

    mov     r9, [rsp + 8]       ; jaro_sim
    pop     r8                  ; p_permille
    add     rsp, 8

    ; prefix length
    xor     r10, r10

.jwp_prefix:
    cmp     r10, JW_MAX_PREFIX
    jae     .jwp_done_prefix
    cmp     r10, r12
    jae     .jwp_done_prefix
    cmp     r10, r14
    jae     .jwp_done_prefix

    movzx   eax, byte [rbx + r10]
    movzx   ecx, byte [r13 + r10]
    cmp     al, cl
    jne     .jwp_done_prefix
    inc     r10
    jmp     .jwp_prefix

.jwp_done_prefix:
    ; jw = jaro + l * (p/1000) * (1 - jaro)
    ; all × JW_SCALE:
    ; bonus = l * p_permille * (JW_SCALE - jaro) / 1000 / JW_SCALE

    mov     rax, JW_SCALE
    sub     rax, r9             ; (JW_SCALE - jaro)

    imul    rax, r10            ; × l
    imul    rax, r8             ; × p_permille

    ; divide by 1000 * JW_SCALE
    xor     edx, edx
    mov     rcx, 1000
    div     rcx
    xor     edx, edx
    mov     rcx, JW_SCALE
    div     rcx

    add     rax, r9             ; + jaro

    cmp     rax, JW_SCALE
    jbe     .jwp_write
    mov     rax, JW_SCALE

.jwp_write:
    mov     [r15], rax

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.jwp_err:
    pop     r8
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_jaro_winkler_p

; -----------------------------------------------------------------------------
; str_jaro_winkler_slice — StrSlice wrapper
; -----------------------------------------------------------------------------

STR_FUNC str_jaro_winkler_slice

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
    jmp     str_jaro_winkler

STR_ENDFUNC str_jaro_winkler_slice

; -----------------------------------------------------------------------------
; str_similar_enough
;
; Quick check: are two strings similar enough by Jaro-Winkler?
; Returns 1 if jaro_winkler >= threshold_permille/1000.
;
; Signature:
;   int64_t str_similar_enough(const uint8_t *s1, uint64_t len1,
;                               const uint8_t *s2, uint64_t len2,
;                               uint64_t threshold_permille)
;
; Arguments:
;   RDI..RCX — s1, len1, s2, len2
;   R8       — threshold in permille (0..1000, e.g. 850 = 0.85)
;
; Returns:
;   RAX  = 1  similar enough
;   RAX  = 0  too different
; -----------------------------------------------------------------------------

STR_FUNC str_similar_enough

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx
    mov     r15, r8             ; threshold_permille

    sub     rsp, 8
    and     rsp, -8

    mov     r8, rsp
    call    str_jaro_winkler
    test    rax, rax
    jnz     .se_err

    mov     rax, [rsp]          ; jw_sim × 1,000,000
    add     rsp, 8

    ; threshold × 1000 (convert permille to our scale)
    mov     rcx, r15
    imul    rcx, rcx, 1000      ; threshold × 1,000,000

    cmp     rax, rcx
    setae   al
    movzx   eax, al

    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.se_err:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_similar_enough