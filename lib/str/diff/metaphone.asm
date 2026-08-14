%ifndef GUARD_LIB_STR_DIFF_METAPHONE_ASM
%define GUARD_LIB_STR_DIFF_METAPHONE_ASM
; =============================================================================
; str/diff/metaphone.asm
; Classic Metaphone phonetic encoder.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; Helper to check if uppercase character is a vowel (A, E, I, O, U)
_is_vowel:
    cmp     dil, 'A'
    je      .yes
    cmp     dil, 'E'
    je      .yes
    cmp     dil, 'I'
    je      .yes
    cmp     dil, 'O'
    je      .yes
    cmp     dil, 'U'
    je      .yes
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; Helper to check if a character is ASCII alphabetic
_is_alpha:
    cmp     dil, 'A'
    jb      .no
    cmp     dil, 'Z'
    jbe     .yes
    cmp     dil, 'a'
    jb      .no
    cmp     dil, 'z'
    jbe     .yes
.no:
    xor     eax, eax
    ret
.yes:
    mov     eax, 1
    ret

; -----------------------------------------------------------------------------
; str_metaphone
;
; Classic Metaphone phonetic encoder.
;
; Signature:
;   int64_t str_metaphone(const StrSlice *src, uint8_t *dst,
;                         uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_metaphone
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 136            ; 128 bytes temp buffer `buf` + 8 bytes padding (align stack)

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len ptr

    ; 1. Normalize: copy uppercase alphabetic characters only to `buf` (rsp)
    xor     rcx, rcx            ; src index
    xor     rdx, rdx            ; buf index

.norm_loop:
    cmp     rcx, r12
    je      .norm_done
    cmp     rdx, 127
    jae     .norm_done

    movzx   edi, byte [rbx + rcx]
    push    rcx
    push    rdx
    call    _is_alpha
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .norm_next

    ; convert to uppercase
    movzx   eax, byte [rbx + rcx]
    cmp     al, 'a'
    jb      .norm_write
    cmp     al, 'z'
    ja      .norm_write
    and     al, 0xDF            ; uppercase

.norm_write:
    mov     [rsp + rdx], al
    inc     rdx

.norm_next:
    inc     rcx
    jmp     .norm_loop

.norm_done:
    mov     byte [rsp + rdx], 0 ; null-terminate
    mov     r8, rdx             ; N (normalized length)

    test    r8, r8
    jz      .empty_out

    ; 2. Initial letter rules
    cmp     r8, 2
    jb      .processing_start

    ; KN, GN, PN, AE, WR
    movzx   eax, byte [rsp]
    movzx   ecx, byte [rsp + 1]

    cmp     ax, 'K'
    jne     .gn
    cmp     cx, 'N'
    je      .drop_first
.gn:
    cmp     ax, 'G'
    jne     .pn
    cmp     cx, 'N'
    je      .drop_first
.pn:
    cmp     ax, 'P'
    jne     .ae
    cmp     cx, 'N'
    je      .drop_first
.ae:
    cmp     ax, 'A'
    jne     .wr
    cmp     cx, 'E'
    je      .drop_first
.wr:
    cmp     ax, 'W'
    jne     .check_x
    cmp     cx, 'R'
    je      .drop_first
    jmp     .check_x

.drop_first:
    ; move whole string left by 1
    xor     rcx, rcx
.drop_loop:
    cmp     rcx, r8
    je      .drop_done
    movzx   eax, byte [rsp + rcx + 1]
    mov     [rsp + rcx], al
    inc     rcx
    jmp     .drop_loop
.drop_done:
    dec     r8                  ; N--
    jmp     .processing_start

.check_x:
    cmp     ax, 'X'
    jne     .processing_start
    mov     byte [rsp], 'S'

.processing_start:
    ; 3. Main processing loop
    xor     rcx, rcx            ; i = 0
    xor     rdx, rdx            ; dst_offset = 0

.loop:
    cmp     rcx, r8
    je      .done

    movzx   edi, byte [rsp + rcx]       ; curr
    test    dil, dil
    jz      .done

    ; get context
    movzx   r9d, byte [rsp + rcx + 1]   ; next
    movzx   r10d, byte [rsp + rcx + 2]  ; next2
    xor     r11d, r11d
    test    rcx, rcx
    jz      .get_prev_done
    movzx   r11d, byte [rsp + rcx - 1]  ; prev
.get_prev_done:

    ; Drop duplicate adjacent letters except C
    cmp     dil, r11b
    jne     .rule_vowel
    cmp     dil, 'C'
    je      .rule_vowel
    ; duplicate -> skip
    inc     rcx
    jmp     .loop

.rule_vowel:
    ; is_vowel(curr)
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    call    _is_vowel
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .rule_b

    ; vowels kept only at start of word
    test    rcx, rcx
    jnz     .skip_char
    
    ; write vowel
    cmp     rdx, r14
    jae     .too_small
    mov     [r13 + rdx], dil
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_b:
    cmp     dil, 'B'
    jne     .rule_c

    cmp     r11b, 'M'
    jne     .write_b
    test    r9b, r9b
    jz      .skip_char                  ; drop B if after M at end

.write_b:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'B'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_c:
    cmp     dil, 'C'
    jne     .rule_d

    cmp     r9b, 'H'
    jne     .c_cia
    ; CH -> X
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'X'
    inc     rdx
    add     rcx, 2                      ; skip H
    jmp     .loop

.c_cia:
    cmp     r9b, 'I'
    jne     .c_coh
    cmp     r10b, 'A'
    je      .c_write_s
.c_coh:
    cmp     r9b, 'O'
    jne     .c_cis
    cmp     r10b, 'H'
    je      .c_write_s
.c_cis:
    cmp     r9b, 'I'
    jne     .c_iey
    cmp     r10b, 'S'
    je      .c_write_s
    jmp     .c_iey

.c_write_s:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'S'
    inc     rdx
    inc     rcx
    jmp     .loop

.c_iey:
    cmp     r9b, 'I'
    je      .c_write_s2
    cmp     r9b, 'E'
    je      .c_write_s2
    cmp     r9b, 'Y'
    je      .c_write_s2
    jmp     .c_ck

.c_write_s2:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'S'
    inc     rdx
    inc     rcx
    jmp     .loop

.c_ck:
    cmp     r9b, 'K'
    je      .skip_char                  ; drop C if followed by K
    
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'K'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_d:
    cmp     dil, 'D'
    jne     .rule_g

    cmp     r9b, 'G'
    jne     .d_write_t
    cmp     r10b, 'I'
    je      .d_write_j
    cmp     r10b, 'E'
    je      .d_write_j
    cmp     r10b, 'Y'
    je      .d_write_j
    jmp     .d_write_t

.d_write_j:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'J'
    inc     rdx
    add     rcx, 2                      ; skip G
    jmp     .loop

.d_write_t:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'T'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_g:
    cmp     dil, 'G'
    jne     .rule_h

    cmp     r9b, 'H'
    jne     .g_gn
    
    ; GH followed by vowel -> G, else GH silent
    movzx   edi, r10b
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    call    _is_vowel
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .g_gh_silent

    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'G'
    inc     rdx
.g_gh_silent:
    add     rcx, 2                      ; skip H
    jmp     .loop

.g_gn:
    cmp     r9b, 'N'
    jne     .g_gns
    test    r10b, r10b
    jz      .skip_char                  ; silent
.g_gns:
    cmp     r9b, 'N'
    jne     .g_iey
    cmp     r10b, 'S'
    jne     .g_iey
    movzx   eax, byte [rsp + rcx + 3]
    test    al, al
    jz      .skip_char

.g_iey:
    cmp     r9b, 'I'
    je      .g_write_j
    cmp     r9b, 'E'
    je      .g_write_j
    cmp     r9b, 'Y'
    je      .g_write_j
    jmp     .g_write_k

.g_write_j:
    cmp     r9b, 'G'
    je      .g_write_k                  ; not GG
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'J'
    inc     rdx
    inc     rcx
    jmp     .loop

.g_write_k:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'K'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_h:
    cmp     dil, 'H'
    jne     .rule_f_j_l_m_n_r

    ; H after vowel and not followed by vowel -> silent
    movzx   edi, r11b
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    call    _is_vowel
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .write_h

    movzx   edi, r9b
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    call    _is_vowel
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .skip_char                  ; silent

.write_h:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'H'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_f_j_l_m_n_r:
    cmp     dil, 'F'
    je      .write_asis
    cmp     dil, 'J'
    je      .write_asis
    cmp     dil, 'L'
    je      .write_asis
    cmp     dil, 'M'
    je      .write_asis
    cmp     dil, 'N'
    je      .write_asis
    cmp     dil, 'R'
    je      .write_asis
    jmp     .rule_k

.write_asis:
    cmp     rdx, r14
    jae     .too_small
    mov     [r13 + rdx], dil
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_k:
    cmp     dil, 'K'
    jne     .rule_p

    cmp     r11b, 'C'
    je      .skip_char                  ; drop K if after C
    jmp     .write_asis

.rule_p:
    cmp     dil, 'P'
    jne     .rule_q

    cmp     r9b, 'H'
    jne     .write_asis
    ; PH -> F
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'F'
    inc     rdx
    add     rcx, 2
    jmp     .loop

.rule_q:
    cmp     dil, 'Q'
    jne     .rule_s

    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'K'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_s:
    cmp     dil, 'S'
    jne     .rule_t

    cmp     r9b, 'H'
    jne     .s_sio
    ; SH -> X
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'X'
    inc     rdx
    add     rcx, 2
    jmp     .loop

.s_sio:
    cmp     r9b, 'I'
    jne     .s_write_s
    cmp     r10b, 'O'
    je      .s_write_x
    cmp     r10b, 'A'
    je      .s_write_x
    jmp     .s_write_s

.s_write_x:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'X'
    inc     rdx
    inc     rcx
    jmp     .loop

.s_write_s:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'S'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_t:
    cmp     dil, 'T'
    jne     .rule_v

    cmp     r9b, 'I'
    jne     .t_tch
    cmp     r10b, 'O'
    je      .t_write_x
    cmp     r10b, 'A'
    je      .t_write_x
    jmp     .t_write_t

.t_write_x:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'X'
    inc     rdx
    inc     rcx
    jmp     .loop

.t_tch:
    cmp     r9b, 'C'
    jne     .t_write_t
    cmp     r10b, 'H'
    je      .skip_char                  ; silent T in TCH

.t_write_t:
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'T'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_v:
    cmp     dil, 'V'
    jne     .rule_wy

    ; V -> F
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'F'
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_wy:
    cmp     dil, 'W'
    je      .wy_check
    cmp     dil, 'Y'
    jne     .rule_x

.wy_check:
    ; check if next is vowel
    movzx   edi, r9b
    push    rcx
    push    rdx
    push    r8
    push    r9
    push    r10
    push    r11
    call    _is_vowel
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    test    rax, rax
    jz      .skip_char                  ; silent

    cmp     rdx, r14
    jae     .too_small
    mov     [r13 + rdx], dil
    inc     rdx
    inc     rcx
    jmp     .loop

.rule_x:
    cmp     dil, 'X'
    jne     .rule_z

    ; X -> KS
    mov     rax, rdx
    add     rax, 2
    cmp     rax, r14
    ja      .too_small
    mov     byte [r13 + rdx], 'K'
    mov     byte [r13 + rdx + 1], 'S'
    add     rdx, 2
    inc     rcx
    jmp     .loop

.rule_z:
    cmp     dil, 'Z'
    jne     .skip_char

    ; Z -> S
    cmp     rdx, r14
    jae     .too_small
    mov     byte [r13 + rdx], 'S'
    inc     rdx
    inc     rcx
    jmp     .loop

.skip_char:
    inc     rcx
    jmp     .loop

.done:
    mov     [r15], rdx                  ; write out_len
    add     rsp, 136
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.empty_out:
    mov     qword [r15], 0
    add     rsp, 136
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 136
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_metaphone

%endif ; GUARD_LIB_STR_DIFF_METAPHONE_ASM
