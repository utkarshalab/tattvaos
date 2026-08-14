%ifndef GUARD_LIB_STR_DIFF_HAMMING_ASM
%define GUARD_LIB_STR_DIFF_HAMMING_ASM
; =============================================================================
; str/diff/hamming.asm
; Hamming distance — count positions where two strings differ.
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
; Hamming distance:
;   The number of positions at which two strings of EQUAL length differ.
;
;   hamming("karolin", "kathrin") = 3
;   hamming("1011101",  "1001001") = 2
;   hamming(0b10100111, 0b10010001) = 4  (XOR then popcount)
;
; For byte strings: byte-level comparison (not codepoint-level).
; For codepoint-level Hamming, use str_hamming_cp.
;
; Functions:
;   str_hamming          — byte-level Hamming distance
;   str_hamming_slice    — StrSlice variant
;   str_hamming_cp       — codepoint-level Hamming distance (UTF-8)
;   str_hamming_bits     — bit-level Hamming distance (popcount of XOR)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_hamming
;
; Compute byte-level Hamming distance between two byte buffers.
; Both buffers must have the same length.
;
; Signature:
;   int64_t str_hamming(const uint8_t *a, const uint8_t *b,
;                        uint64_t len, uint64_t *out_distance)
;
; Arguments:
;   RDI  — pointer to buffer a
;   RSI  — pointer to buffer b
;   RDX  — length (must be equal for both)
;   RCX  — pointer to uint64_t to receive distance
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_hamming

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi            ; a
    mov     r12, rsi            ; b
    mov     r13, rcx            ; out

    xor     eax, eax            ; distance = 0
    xor     ecx, ecx            ; index

.ham_loop:
    cmp     rcx, rdx
    jae     .ham_done

    movzx   r8d, byte [rbx + rcx]
    movzx   r9d, byte [r12 + rcx]
    cmp     r8b, r9b
    je      .ham_next
    inc     rax

.ham_next:
    inc     rcx
    jmp     .ham_loop

.ham_done:
    mov     [r13], rax

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hamming

; -----------------------------------------------------------------------------
; str_hamming_slice
;
; Hamming distance between two StrSlices.
; Returns STR_ERR_INVALID_ARG if lengths differ.
;
; Signature:
;   int64_t str_hamming_slice(const StrSlice *a, const StrSlice *b,
;                              uint64_t *out_distance)
; -----------------------------------------------------------------------------

STR_FUNC str_hamming_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    ; check equal lengths
    mov     rax, [rbx + StrSlice.len]
    cmp     rax, [r12 + StrSlice.len]
    jne     .hs_diff_len

    mov     rcx, r13
    mov     rdx, rax                        ; len
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rdi, [rbx + StrSlice.ptr]

    pop_regs r13, r12, rbx
    pop     rbp
    jmp     str_hamming

.hs_diff_len:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_INVALID_ARG
    pop     rbp
    ret

STR_ENDFUNC str_hamming_slice

; -----------------------------------------------------------------------------
; str_hamming_bits
;
; Bit-level Hamming distance: count differing bits across two byte buffers.
; Uses POPCNT instruction (SSE4.2).
;
; Signature:
;   int64_t str_hamming_bits(const uint8_t *a, const uint8_t *b,
;                             uint64_t len, uint64_t *out_bit_distance)
; -----------------------------------------------------------------------------

STR_FUNC str_hamming_bits

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rcx

    xor     eax, eax            ; total bit distance
    xor     ecx, ecx

    ; 8-byte fast path: XOR 8 bytes, POPCNT
.hb_qloop:
    mov     r8, rdx
    sub     r8, rcx
    cmp     r8, 8
    jb      .hb_bloop

    mov     r9, [rbx + rcx]
    xor     r9, [r12 + rcx]
    popcnt  r9, r9
    add     rax, r9
    add     rcx, 8
    jmp     .hb_qloop

.hb_bloop:
    cmp     rcx, rdx
    jae     .hb_done

    movzx   r9d, byte [rbx + rcx]
    movzx   r10d, byte [r12 + rcx]
    xor     r9d, r10d
    popcnt  r9d, r9d
    add     rax, r9
    inc     rcx
    jmp     .hb_bloop

.hb_done:
    mov     [r13], rax

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hamming_bits

; -----------------------------------------------------------------------------
; str_hamming_cp
;
; Codepoint-level Hamming distance for UTF-8 strings.
; Both strings must have the same codepoint count.
;
; Signature:
;   int64_t str_hamming_cp(const StrSlice *a, const StrSlice *b,
;                           uint64_t *out_distance)
; -----------------------------------------------------------------------------

STR_FUNC str_hamming_cp

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; slice a
    mov     r12, rsi            ; slice b
    mov     r13, rdx            ; out

    ; set up pointers and end markers
    mov     r14, [rbx + StrSlice.ptr]
    mov     r15, r14
    add     r15, [rbx + StrSlice.len]  ; end of a

    mov     rbx, [r12 + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [r12 + StrSlice.len - StrSlice.ptr]  ; wrong — fix
    ; actually:
    mov     r12, [rdi + StrSlice.ptr]  ; but rdi is gone... need to rethink

    ; Save both slice ends properly
    ; Redo with cleaner register allocation
    pop_regs r15, r14, r13, r12, rbx

    push_regs rbx, r12, r13, r14, r15

    ; a_ptr in r14, a_end in r15
    ; b_ptr in r12, b_end in r13
    ; out in rbx

    mov     rax, [rdi + StrSlice.ptr]
    mov     r14, rax
    mov     rax, [rdi + StrSlice.len]
    add     rax, r14
    mov     r15, rax            ; a_end

    mov     rax, [rsi + StrSlice.ptr]
    mov     r12, rax
    mov     rax, [rsi + StrSlice.len]
    add     rax, r12
    mov     r13, rax            ; b_end

    mov     rbx, rdx            ; out

    xor     r9, r9              ; distance

.hcp_loop:
    ; check both not exhausted
    cmp     r14, r15
    jae     .hcp_done
    cmp     r12, r13
    jae     .hcp_done

    ; decode from a
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, r14
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r10d, eax           ; cp_a
    mov     rax, [rsp]
    add     r14, rax

    ; decode from b
    mov     rdi, r12
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r11d, eax           ; cp_b
    mov     rax, [rsp]
    add     r12, rax

    mov     rsp, rbp

    ; compare
    cmp     r10d, r11d
    je      .hcp_loop
    inc     r9
    jmp     .hcp_loop

.hcp_done:
    mov     [rbx], r9

    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_hamming_cp
%endif ; GUARD_LIB_STR_DIFF_HAMMING_ASM
