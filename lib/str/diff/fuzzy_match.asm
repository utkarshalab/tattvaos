; =============================================================================
; str/diff/fuzzy_match.asm
; Phonetic hashing and fuzzy string matching algorithms (Soundex).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; _soundex_code  (internal)
;
; Map ASCII character (upper or lower case) to Soundex digit.
; Returns '0' if ignored, or '1'-'6'.
; -----------------------------------------------------------------------------
_soundex_code:
    cmp     edi, 'a'
    jb      .check_upper
    cmp     edi, 'z'
    ja      .check_upper
    sub     edi, 32             ; convert to upper

.check_upper:
    cmp     edi, 'B'
    je      .code1
    cmp     edi, 'F'
    je      .code1
    cmp     edi, 'P'
    je      .code1
    cmp     edi, 'V'
    je      .code1

    cmp     edi, 'C'
    je      .code2
    cmp     edi, 'G'
    je      .code2
    cmp     edi, 'J'
    je      .code2
    cmp     edi, 'K'
    je      .code2
    cmp     edi, 'Q'
    je      .code2
    cmp     edi, 'S'
    je      .code2
    cmp     edi, 'X'
    je      .code2
    cmp     edi, 'Z'
    je      .code2

    cmp     edi, 'D'
    je      .code3
    cmp     edi, 'T'
    je      .code3

    cmp     edi, 'L'
    je      .code4

    cmp     edi, 'M'
    je      .code5
    cmp     edi, 'N'
    je      .code5

    cmp     edi, 'R'
    je      .code6

    mov     eax, '0'            ; ignored
    ret

.code1: mov eax, '1'; ret
.code2: mov eax, '2'; ret
.code3: mov eax, '3'; ret
.code4: mov eax, '4'; ret
.code5: mov eax, '5'; ret
.code6: mov eax, '6'; ret

; -----------------------------------------------------------------------------
; str_soundex
;
; Calculate the Soundex code for a string. Code is written into dst (normally 4 bytes).
;
; Signature:
;   int64_t str_soundex(const StrSlice *src, uint8_t *dst,
;                        uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_soundex
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; 16 bytes for out_advance + 8 bytes padding

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]   ; end ptr
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    cmp     rbx, r12
    jae     .sound_empty

    ; 1. first character is written as-is (capitalized)
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx

    cmp     eax, 'a'
    jb      .first_upper
    cmp     eax, 'z'
    ja      .first_upper
    sub     eax, 32

.first_upper:
    mov     r8d, eax            ; first char
    cmp     r14, 4
    jb      .overflow

    mov     [r13], al
    mov     qword [r15], 4

    ; get soundex code of first character to prevent adjacent duplicates
    mov     edi, r8d
    call    _soundex_code
    movzx   r10d, al            ; last code written (R10)
    mov     r9, 1               ; write offset

.loop:
    cmp     rbx, r12
    jae     .pad_zeros
    cmp     r9, 4
    jae     .pad_zeros

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx

    mov     edi, eax
    push    r9                  ; preserve
    call    _soundex_code
    pop     r9
    movzx   eax, al

    cmp     eax, '0'
    je      .loop               ; ignore vowels/H/W/Y

    cmp     eax, r10d
    je      .loop               ; collapse duplicates

    mov     [r13 + r9], al
    mov     r10d, eax
    inc     r9
    jmp     .loop

.pad_zeros:
    cmp     r9, 4
    jae     .done
    mov     byte [r13 + r9], '0'
    inc     r9
    jmp     .pad_zeros

.done:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.sound_empty:
    ; write "0000"
    cmp     r14, 4
    jb      .overflow
    mov     dword [r13], 0x30303030     ; "0000" in hex ASCII
    mov     qword [r15], 4
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.overflow:
    add     rsp, 24
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret
STR_ENDFUNC str_soundex
