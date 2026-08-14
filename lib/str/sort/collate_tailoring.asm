%ifndef GUARD_LIB_STR_SORT_COLLATE_TAILORING_ASM
%define GUARD_LIB_STR_SORT_COLLATE_TAILORING_ASM
; =============================================================================
; str/sort/collate_tailoring.asm
; Locale-specific collation overrides (German phonebook, Swedish end-of-alphabet).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

LOCALE_DEFAULT  equ 0
LOCALE_DE_PHONE equ 1       ; German phonebook (ä/ö/ü -> ae/oe/ue)
LOCALE_SV       equ 2       ; Swedish (z < å < ä < ö)

section .text

; -----------------------------------------------------------------------------
; _parse_collate_locale (internal)
; -----------------------------------------------------------------------------
_parse_collate_locale:
    test    rdi, rdi
    jz      .default
    movzx   eax, byte [rdi]
    test    al, al
    jz      .default

    cmp     al, 'd'
    je      .check_de
    cmp     al, 'D'
    je      .check_de

    cmp     al, 's'
    je      .check_sv
    cmp     al, 'S'
    je      .check_sv

.default:
    xor     eax, eax
    ret

.check_de:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 'e'
    je      .ret_de
    cmp     cl, 'E'
    je      .ret_de
    jmp     .default
.ret_de:
    mov     eax, LOCALE_DE_PHONE
    ret

.check_sv:
    movzx   ecx, byte [rdi + 1]
    cmp     cl, 'v'
    je      .ret_sv
    cmp     cl, 'V'
    je      .ret_sv
    jmp     .default
.ret_sv:
    mov     eax, LOCALE_SV
    ret

; -----------------------------------------------------------------------------
; str_collate_tailored
;
; Locale-aware string comparison with support for German/Swedish rules.
;
; Signature:
;   int64_t str_collate_tailored(const StrSlice *a, const StrSlice *b,
;                                 const char *locale, uint64_t strength)
; -----------------------------------------------------------------------------
STR_FUNC str_collate_tailored
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 32             ; stack space for out_advance

    mov     rbx, rdi            ; slice a
    mov     r12, rsi            ; slice b
    mov     r15, rcx            ; strength (1 = primary, 2 = secondary, 3 = tertiary)

    ; parse locale
    mov     rdi, rdx
    call    _parse_collate_locale
    mov     [rsp + 24], rax     ; save locale_id

    mov     r13, [rbx + StrSlice.ptr]   ; cursor a
    mov     r9,  [rbx + StrSlice.len]   ; len a
    mov     r14, r13
    add     r14, r9                     ; end a

    mov     r10, [r12 + StrSlice.ptr]   ; cursor b
    mov     r9,  [r12 + StrSlice.len]   ; len b
    mov     r12, r10
    add     r12, r9                     ; end b

.loop:
    ; check if either reached end
    cmp     r13, r14
    jae     .a_end
    cmp     r10, r12
    jae     .b_end

    ; decode next char from a
    mov     rdi, r13
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     r13, rcx
    mov     r8d, eax            ; cp a in R8D

    ; decode next char from b
    mov     rdi, r10
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     r10, rcx
    mov     r9d, eax            ; cp b in R9D

    ; apply locale weight adjustments
    mov     rax, [rsp + 24]     ; locale_id
    cmp     rax, LOCALE_DE_PHONE
    je      .de_phonebook
    cmp     rax, LOCALE_SV
    je      .sv_swedish

.compare:
    ; apply casing depending on strength
    cmp     r15, 3
    je      .cmp_case           ; tertiary / case-sensitive

    ; strength 1 or 2: fold case for ASCII
    cmp     r8d, 'A'
    jb      .b_fold
    cmp     r8d, 'Z'
    ja      .b_fold
    or      r8d, 0x20
.b_fold:
    cmp     r9d, 'A'
    jb      .cmp_case
    cmp     r9d, 'Z'
    ja      .cmp_case
    or      r9d, 0x20

.cmp_case:
    cmp     r8d, r9d
    jb      .a_less
    ja      .b_less
    jmp     .loop

.de_phonebook:
    ; ä -> ae, ö -> oe, ü -> ue
    cmp     r8d, 0x00E4         ; ä
    je      .de_a_ae
    cmp     r8d, 0x00C4         ; Ä
    je      .de_a_ae
    cmp     r8d, 0x00F6         ; ö
    je      .de_a_oe
    cmp     r8d, 0x00D6         ; Ö
    je      .de_a_oe
    cmp     r8d, 0x00FC         ; ü
    je      .de_a_ue
    cmp     r8d, 0x00DC         ; Ü
    je      .de_a_ue
.de_b:
    cmp     r9d, 0x00E4
    je      .de_b_ae
    cmp     r9d, 0x00C4
    je      .de_b_ae
    cmp     r9d, 0x00F6
    je      .de_b_oe
    cmp     r9d, 0x00D6
    je      .de_b_oe
    cmp     r9d, 0x00FC
    je      .de_b_ue
    cmp     r9d, 0x00DC
    je      .de_b_ue
    jmp     .compare

.de_a_ae:
    mov     r8d, 'a'            ; simplify comparison for German phonebook sorting
    jmp     .de_b
.de_a_oe:
    mov     r8d, 'o'
    jmp     .de_b
.de_a_ue:
    mov     r8d, 'u'
    jmp     .de_b

.de_b_ae:
    mov     r9d, 'a'
    jmp     .compare
.de_b_oe:
    mov     r9d, 'o'
    jmp     .compare
.de_b_ue:
    mov     r9d, 'u'
    jmp     .compare

.sv_swedish:
    ; Swedish placing å, ä, ö at end of alphabet after z (weight 122)
    cmp     r8d, 0x00E5         ; å
    je      .sv_a_ao
    cmp     r8d, 0x00C5         ; Å
    je      .sv_a_ao
    cmp     r8d, 0x00E4         ; ä
    je      .sv_a_ae
    cmp     r8d, 0x00C4         ; Ä
    je      .sv_a_ae
    cmp     r8d, 0x00F6         ; ö
    je      .sv_a_oe
    cmp     r8d, 0x00D6         ; Ö
    je      .sv_a_oe
.sv_b:
    cmp     r9d, 0x00E5
    je      .sv_b_ao
    cmp     r9d, 0x00C5
    je      .sv_b_ao
    cmp     r9d, 0x00E4
    je      .sv_b_ae
    cmp     r9d, 0x00C4
    je      .sv_b_ae
    cmp     r9d, 0x00F6
    je      .sv_b_oe
    cmp     r9d, 0x00D6
    je      .sv_b_oe
    jmp     .compare

.sv_a_ao: mov r8d, 200; jmp .sv_b
.sv_a_ae: mov r8d, 201; jmp .sv_b
.sv_a_oe: mov r8d, 202; jmp .sv_b

.sv_b_ao: mov r9d, 200; jmp .compare
.sv_b_ae: mov r9d, 201; jmp .compare
.sv_b_oe: mov r9d, 202; jmp .compare

.a_end:
    cmp     r10, r12
    jae     .equal
    jmp     .a_less             ; a is shorter, so a < b

.b_end:
    jmp     .b_less             ; b is shorter, so a > b

.equal:
    xor     eax, eax
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.a_less:
    mov     rax, -1
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.b_less:
    mov     rax, 1
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_collate_tailored

%endif ; GUARD_LIB_STR_SORT_COLLATE_TAILORING_ASM
