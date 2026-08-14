%ifndef GUARD_LIB_STR_UNICODE_EMOJI_MODIFIERS_ASM
%define GUARD_LIB_STR_UNICODE_EMOJI_MODIFIERS_ASM
; =============================================================================
; str/unicode/emoji_modifiers.asm
; UTS #51 emoji modifier sequence detection (skin tones, hair, gender).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


ZWJ             equ 0x200D
VS16            equ 0xFE0F

section .text

; -----------------------------------------------------------------------------
; str_emoji_has_modifier
;
; Check if a codepoint is a valid emoji modifier base (i.e. can accept skin tone/hair).
; Matches common face/body/people emoji ranges.
;
; Signature:
;   int64_t str_emoji_has_modifier(uint32_t cp)
; -----------------------------------------------------------------------------
STR_FUNC str_emoji_has_modifier
    ; face ranges: U+1F600..U+1F64F
    cmp     edi, 0x1F600
    jb      .check_body
    cmp     edi, 0x1F64F
    jbe     .yes

.check_body:
    ; hands/body: U+1F910..U+1F93F
    cmp     edi, 0x1F910
    jb      .check_people
    cmp     edi, 0x1F93F
    jbe     .yes

.check_people:
    ; people/occupations: U+1F9D0..U+1F9FF
    cmp     edi, 0x1F9D0
    jb      .check_legacy
    cmp     edi, 0x1F9FF
    jbe     .yes

.check_legacy:
    ; legacy human symbols: U+270A..U+270D
    cmp     edi, 0x270A
    jb      .no
    cmp     edi, 0x270D
    jbe     .yes

.no:
    xor     eax, eax
    pop     rbp
    ret

.yes:
    mov     eax, 1
    pop     rbp
    ret
STR_ENDFUNC str_emoji_has_modifier

; -----------------------------------------------------------------------------
; str_emoji_resolve_modifiers
;
; Checks if the next codepoint in a string is a skin tone or hair modifier.
;
; Signature:
;   int64_t str_emoji_resolve_modifiers(const StrSlice *src, uint64_t offset,
;                                        uint64_t *out_advance, uint32_t *out_mod)
; -----------------------------------------------------------------------------
STR_FUNC str_emoji_resolve_modifiers
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13
    sub     rsp, 24             ; pre-allocate 16 bytes for out_advance + 8 bytes padding

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]   ; end
    add     rbx, rsi                    ; cursor

    cmp     rbx, r12
    jae     .no_mod

    ; decode
    mov     rdi, rbx
    lea     rsi, [rsp]          ; out_advance at [rsp]
    call    str_utf8_decode_unchecked
    mov     r13, [rsp]          ; advance size

    ; check Fitzpatrick skin tone modifiers (U+1F3FB..U+1F3FF)
    cmp     eax, 0x1F3FB
    jb      .check_hair
    cmp     eax, 0x1F3FF
    jbe     .found_mod

.check_hair:
    ; check hair modifiers (U+1F9B0..U+1F9B3)
    cmp     eax, 0x1F9B0
    jb      .no_mod
    cmp     eax, 0x1F9B3
    jbe     .found_mod

.no_mod:
    add     rsp, 24
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.found_mod:
    ; save results
    mov     [rdx], r13          ; write advance
    mov     [rcx], eax          ; write modifier CP
    mov     eax, 1

    add     rsp, 24
    pop_regs r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_emoji_resolve_modifiers

; -----------------------------------------------------------------------------
; str_emoji_is_multi_person
;
; Checks if a ZWJ sequence represents a multi-person group (e.g. families, couples).
;
; Signature:
;   int64_t str_emoji_is_multi_person(const StrSlice *src, uint64_t offset)
; -----------------------------------------------------------------------------
STR_FUNC str_emoji_is_multi_person
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    sub     rsp, 24             ; pre-allocate 16 bytes for out_advance + 8 bytes padding

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    add     rbx, rsi            ; cursor

    ; must start with people emoji
    cmp     rbx, r12
    jae     .no_multi

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r13, [rsp]

    ; check if people emoji
    cmp     eax, 0x1F466         ; boy
    je      .check_zwj_loop
    cmp     eax, 0x1F467         ; girl
    je      .check_zwj_loop
    cmp     eax, 0x1F468         ; man
    je      .check_zwj_loop
    cmp     eax, 0x1F469         ; woman
    je      .check_zwj_loop
    cmp     eax, 0x1F9D1         ; adult/person
    je      .check_zwj_loop
    jmp     .no_multi

.check_zwj_loop:
    add     rbx, r13            ; advance past current emoji
    cmp     rbx, r12
    jae     .no_multi

    ; next must be ZWJ
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r13, [rsp]

    cmp     eax, ZWJ
    jne     .no_multi           ; must have ZWJ to join next person

    add     rbx, r13            ; past ZWJ
    cmp     rbx, r12
    jae     .no_multi

    ; next must be another person emoji
    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r13, [rsp]

    cmp     eax, 0x1F466
    je      .yes_multi
    cmp     eax, 0x1F467
    je      .yes_multi
    cmp     eax, 0x1F468
    je      .yes_multi
    cmp     eax, 0x1F469
    je      .yes_multi
    cmp     eax, 0x1F9D1
    je      .yes_multi
    jmp     .no_multi

.yes_multi:
    mov     eax, 1
    add     rsp, 24
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.no_multi:
    xor     eax, eax
    add     rsp, 24
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_emoji_is_multi_person

%endif ; GUARD_LIB_STR_UNICODE_EMOJI_MODIFIERS_ASM
