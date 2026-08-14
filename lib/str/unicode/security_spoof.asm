%ifndef GUARD_LIB_STR_UNICODE_SECURITY_SPOOF_ASM
%define GUARD_LIB_STR_UNICODE_SECURITY_SPOOF_ASM
; =============================================================================
; str/unicode/security_spoof.asm
; UTS #39 security spoofing profile checks (restriction levels & mixed-number).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


section .text

; -----------------------------------------------------------------------------
; str_is_highly_restrictive
;
; Check if a string is highly restrictive (ASCII, or single script + Common/Inherited).
;
; Signature:
;   int64_t str_is_highly_restrictive(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_is_highly_restrictive
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 16             ; pre-allocate 16 bytes for out_advance

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]   ; end

    xor     r13d, r13d          ; script bitmask (unique scripts seen)
    xor     r14d, r14d          ; script count

.hr_loop:
    cmp     rbx, r12
    jae     .hr_check

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    add     rbx, [rsp]

    ; get script
    push    rax                 ; dummy alignment
    push    r8                  ; preserve
    mov     edi, eax
    call    str_cp_script
    pop     r8
    pop     rcx
    movzx   ecx, al

    ; skip Common (0) and Inherited (1)
    cmp     ecx, 2
    jb      .hr_loop

    ; check if already seen
    cmp     ecx, 31
    ja      .hr_loop            ; safety overflow

    mov     eax, 1
    shl     eax, cl
    test    r13d, eax
    jnz     .hr_loop

    or      r13d, eax
    inc     r14d
    jmp     .hr_loop

.hr_check:
    cmp     r14d, 2
    jae     .not_highly_restrictive

    mov     eax, 1              ; 0 or 1 script seen -> Highly Restrictive
    add     rsp, 16
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.not_highly_restrictive:
    xor     eax, eax
    add     rsp, 16
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_is_highly_restrictive

; -----------------------------------------------------------------------------
; str_has_mixed_number_systems
;
; Check if string contains digits from more than one number system.
;
; Signature:
;   int64_t str_has_mixed_number_systems(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_has_mixed_number_systems
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13
    sub     rsp, 24             ; pre-allocate 16 bytes for out_advance + 8 bytes padding

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]

    xor     r13d, r13d          ; digit group seen (0 = none, or group_id 1..5)

.mn_loop:
    cmp     rbx, r12
    jae     .mn_none

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    add     rbx, [rsp]

    ; determine digit group ID
    ; 1. ASCII 0-9
    cmp     eax, '0'
    jb      .check_arabic
    cmp     eax, '9'
    jbe     .is_ascii_digit

.check_arabic:
    ; 2. Arabic-Indic ٠-٩ (U+0660..U+0669)
    cmp     eax, 0x0660
    jb      .check_ext_arabic
    cmp     eax, 0x0669
    jbe     .is_arabic_digit

.check_ext_arabic:
    ; 3. Extended Arabic-Indic ۰-۹ (U+06F0..U+06F9)
    cmp     eax, 0x06F0
    jb      .check_deva
    cmp     eax, 0x06F9
    jbe     .is_ext_arabic_digit

.check_deva:
    ; 4. Devanagari ०-९ (U+0966..U+096F)
    cmp     eax, 0x0966
    jb      .check_bengali
    cmp     eax, 0x096F
    jbe     .is_deva_digit

.check_bengali:
    ; 5. Bengali ০-৯ (U+09E6..U+09EF)
    cmp     eax, 0x09E6
    jb      .mn_loop
    cmp     eax, 0x09EF
    jbe     .is_bengali_digit

    jmp     .mn_loop            ; not a digit we track

.is_ascii_digit:
    mov     ecx, 1
    jmp     .check_group
.is_arabic_digit:
    mov     ecx, 2
    jmp     .check_group
.is_ext_arabic_digit:
    mov     ecx, 3
    jmp     .check_group
.is_deva_digit:
    mov     ecx, 4
    jmp     .check_group
.is_bengali_digit:
    mov     ecx, 5

.check_group:
    test    r13d, r13d
    jz      .set_first_group

    cmp     r13d, ecx
    jne     .mixed_detected     ; different digit group seen!

    jmp     .mn_loop

.set_first_group:
    mov     r13d, ecx
    jmp     .mn_loop

.mixed_detected:
    mov     eax, 1
    add     rsp, 24
    pop_regs r13, r12, rbx
    pop     rbp
    ret

.mn_none:
    xor     eax, eax
    add     rsp, 24
    pop_regs r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_has_mixed_number_systems

%endif ; GUARD_LIB_STR_UNICODE_SECURITY_SPOOF_ASM
