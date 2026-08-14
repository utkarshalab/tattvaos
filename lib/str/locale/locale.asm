%ifndef GUARD_LIB_STR_LOCALE_LOCALE_ASM
%define GUARD_LIB_STR_LOCALE_LOCALE_ASM
; =============================================================================
; str/locale/locale.asm
; BCP 47 language tag parsing, canonicalization, and fallback matching.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

struc ParsedLocale
    .lang      resb STRSLICE_SIZE
    .script    resb STRSLICE_SIZE
    .region    resb STRSLICE_SIZE
    .variant   resb STRSLICE_SIZE
endstruc

section .text

; -----------------------------------------------------------------------------
; str_locale_parse
;
; Parse a BCP 47 language tag (e.g., zh-Hans-CN) into a ParsedLocale structure.
;
; Signature:
;   int64_t str_locale_parse(const StrSlice *tag, ParsedLocale *out)
; -----------------------------------------------------------------------------
STR_FUNC str_locale_parse
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    mov     rbx, rdi            ; tag
    mov     r12, rsi            ; out

    ; zero ParsedLocale (64 bytes)
    mov     rdi, r12
    xor     eax, eax
    mov     ecx, 8              ; 8 * 8 = 64 bytes
    rep stosq

    mov     r13, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]
    mov     r14, r13
    add     r14, rcx                    ; end

    xor     r8d, r8d                    ; subtag index
    mov     rdi, r13                    ; subtag start

.loop:
    cmp     r13, r14
    jae     .finalize_subtag

    movzx   eax, byte [r13]
    cmp     al, '-'
    je      .subtag_break
    cmp     al, '_'
    je      .subtag_break

    inc     r13
    jmp     .loop

.subtag_break:
    call    .save_subtag
    inc     r13                         ; past '-' or '_'
    mov     rdi, r13
    inc     r8d
    jmp     .loop

.finalize_subtag:
    call    .save_subtag

.done:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

; Helper to save subtag [rdi, r13) based on r8d index
.save_subtag:
    mov     rax, r13
    sub     rax, rdi            ; length
    test    rax, rax
    jz      .subtag_ret

    cmp     r8d, 0
    je      .save_lang

    cmp     r8d, 1
    je      .save_subtag_1

    cmp     r8d, 2
    je      .save_subtag_2

    ; variant for any subsequent subtags
    jmp     .save_variant

.save_lang:
    mov     [r12 + ParsedLocale.lang + StrSlice.ptr], rdi
    mov     [r12 + ParsedLocale.lang + StrSlice.len], rax
    ret

.save_subtag_1:
    ; if len == 4 -> script; if len == 2 or 3 -> region; else -> variant
    cmp     rax, 4
    je      .save_script
    cmp     rax, 2
    je      .save_region
    cmp     rax, 3
    je      .save_region
    jmp     .save_variant

.save_subtag_2:
    ; if we already have script and no region, check if region
    mov     rcx, [r12 + ParsedLocale.script + StrSlice.len]
    test    rcx, rcx
    jz      .save_variant       ; no script -> variant

    cmp     rax, 2
    je      .save_region
    cmp     rax, 3
    je      .save_region
    jmp     .save_variant

.save_script:
    mov     [r12 + ParsedLocale.script + StrSlice.ptr], rdi
    mov     [r12 + ParsedLocale.script + StrSlice.len], rax
    ret

.save_region:
    mov     [r12 + ParsedLocale.region + StrSlice.ptr], rdi
    mov     [r12 + ParsedLocale.region + StrSlice.len], rax
    ret

.save_variant:
    ; if already has variant, append or keep first one
    mov     rcx, [r12 + ParsedLocale.variant + StrSlice.len]
    test    rcx, rcx
    jnz     .subtag_ret
    mov     [r12 + ParsedLocale.variant + StrSlice.ptr], rdi
    mov     [r12 + ParsedLocale.variant + StrSlice.len], rax
.subtag_ret:
    ret
STR_ENDFUNC str_locale_parse

; -----------------------------------------------------------------------------
; str_locale_canonicalize
;
; Canonicalizes a locale tag (e.g. zh-CN -> zh-Hans-CN, iw -> he).
;
; Signature:
;   int64_t str_locale_canonicalize(const StrSlice *tag, uint8_t *dst,
;                                    uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_locale_canonicalize
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14
    mov     rbx, rdi            ; tag
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len

    mov     rsi, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]

    ; 1. Check iw -> he
    cmp     rcx, 2
    jne     .check_zh_cn
    cmp     byte [rsi], 'i'
    jne     .check_zh_cn
    cmp     byte [rsi + 1], 'w'
    je      .map_he

    ; check in -> id
    cmp     byte [rsi], 'i'
    jne     .check_zh_cn
    cmp     byte [rsi + 1], 'n'
    je      .map_id

    ; check ji -> yi
    cmp     byte [rsi], 'j'
    jne     .check_zh_cn
    cmp     byte [rsi + 1], 'i'
    je      .map_yi

.check_zh_cn:
    cmp     rcx, 5
    jne     .as_is
    cmp     dword [rsi], 0x432D687A     ; "zh-C" in hex (little-endian byte order: 'z','h','-','C')
    jne     .check_zh_tw
    cmp     byte [rsi + 4], 'N'
    je      .map_zh_hans_cn

.check_zh_tw:
    cmp     dword [rsi], 0x542D687A     ; "zh-T" in hex
    jne     .check_zh_hk
    cmp     byte [rsi + 4], 'W'
    je      .map_zh_hant_tw

.check_zh_hk:
    cmp     dword [rsi], 0x482D687A     ; "zh-H" in hex
    jne     .as_is
    cmp     byte [rsi + 4], 'K'
    je      .map_zh_hant_hk

.as_is:
    cmp     rcx, r13
    ja      .canon_overflow
    mov     rdi, r12
    mov     rdx, rcx
    call    str_copy_bytes
    mov     [r14], rcx
    jmp     .canon_ok

.map_he:
    mov     rax, 2
    cmp     rax, r13
    ja      .canon_overflow
    mov     byte [r12], 'h'
    mov     byte [r12 + 1], 'e'
    mov     qword [r14], 2
    jmp     .canon_ok

.map_id:
    mov     rax, 2
    cmp     rax, r13
    ja      .canon_overflow
    mov     byte [r12], 'i'
    mov     byte [r12 + 1], 'd'
    mov     qword [r14], 2
    jmp     .canon_ok

.map_yi:
    mov     rax, 2
    cmp     rax, r13
    ja      .canon_overflow
    mov     byte [r12], 'y'
    mov     byte [r12 + 1], 'i'
    mov     qword [r14], 2
    jmp     .canon_ok

.map_zh_hans_cn:
    mov     rax, 10
    cmp     rax, r13
    ja      .canon_overflow
    ; copy "zh-Hans-CN"
    mov     dword [r12], 0x482d687a     ; "zh-H"
    mov     dword [r12 + 4], 0x736e6161 ; "aans" (Hans offset)
    mov     word [r12 + 8], 0x4e43         ; "-CN"
    mov     byte [r12 + 8], '-'
    mov     byte [r12 + 9], 'C'
    mov     byte [r12 + 10], 'N'
    ; Wait, Hans is 4 bytes, so "zh-Hans-CN" length is:
    ; zh-Hans-CN -> 10 bytes:
    ; 'z','h','-','H','a','n','s','-','C','N'
    mov     byte [r12], 'z'
    mov     byte [r12 + 1], 'h'
    mov     byte [r12 + 2], '-'
    mov     byte [r12 + 3], 'H'
    mov     byte [r12 + 4], 'a'
    mov     byte [r12 + 5], 'n'
    mov     byte [r12 + 6], 's'
    mov     byte [r12 + 7], '-'
    mov     byte [r12 + 8], 'C'
    mov     byte [r12 + 9], 'N'
    mov     qword [r14], 10
    jmp     .canon_ok

.map_zh_hant_tw:
    mov     rax, 10
    cmp     rax, r13
    ja      .canon_overflow
    mov     byte [r12], 'z'
    mov     byte [r12 + 1], 'h'
    mov     byte [r12 + 2], '-'
    mov     byte [r12 + 3], 'H'
    mov     byte [r12 + 4], 'a'
    mov     byte [r12 + 5], 'n'
    mov     byte [r12 + 6], 't'
    mov     byte [r12 + 7], '-'
    mov     byte [r12 + 8], 'T'
    mov     byte [r12 + 9], 'W'
    mov     qword [r14], 10
    jmp     .canon_ok

.map_zh_hant_hk:
    mov     rax, 10
    cmp     rax, r13
    ja      .canon_overflow
    mov     byte [r12], 'z'
    mov     byte [r12 + 1], 'h'
    mov     byte [r12 + 2], '-'
    mov     byte [r12 + 3], 'H'
    mov     byte [r12 + 4], 'a'
    mov     byte [r12 + 5], 'n'
    mov     byte [r12 + 6], 't'
    mov     byte [r12 + 7], '-'
    mov     byte [r12 + 8], 'H'
    mov     byte [r12 + 9], 'K'
    mov     qword [r14], 10
    jmp     .canon_ok

.canon_ok:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.canon_overflow:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret
STR_ENDFUNC str_locale_canonicalize

; -----------------------------------------------------------------------------
; str_locale_match_fallback
;
; Resolves a requested locale tag against supported targets using CLDR inheritance rules.
;
; Signature:
;   int64_t str_locale_match_fallback(const StrSlice *locale,
;                                      const StrSlice *target_list,
;                                      uint64_t target_count,
;                                      uint64_t *out_index)
; -----------------------------------------------------------------------------
STR_FUNC str_locale_match_fallback
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 16             ; save active/mutated locale slice copy here

    mov     rbx, rsi            ; target_list
    mov     r12, rdx            ; target_count
    mov     r13, rcx            ; out_index

    ; copy initial locale slice to local space
    mov     rax, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]
    mov     [rsp + StrSlice.ptr], rax
    mov     [rsp + StrSlice.len], rcx

.match_loop:
    mov     rax, [rsp + StrSlice.len]
    test    rax, rax
    jz      .match_fail

    ; search in target_list
    xor     r14, r14            ; target loop index
.target_loop:
    cmp     r14, r12
    jae     .strip_subtag

    ; compare [rsp] with target_list[r14]
    lea     rax, [r14 * 2]
    shl     rax, 3              ; r14 * 16 (each StrSlice is 16 bytes)
    lea     rsi, [rbx + rax]    ; target_slice

    mov     rdi, [rsp + StrSlice.ptr]
    mov     r9,  [rsp + StrSlice.len]
    cmp     r9,  [rsi + StrSlice.len]
    jne     .next_target

    ; byte-by-byte compare
    mov     r10, [rsi + StrSlice.ptr]
    xor     r11, r11
.byte_cmp:
    cmp     r11, r9
    jae     .matched

    movzx   edx, byte [rdi + r11]
    movzx   eax, byte [r10 + r11]
    cmp     dl, al
    jne     .next_target
    inc     r11
    jmp     .byte_cmp

.next_target:
    inc     r14
    jmp     .target_loop

.strip_subtag:
    ; strip the last subtag (look from right for '-' or '_')
    mov     rdi, [rsp + StrSlice.ptr]
    mov     rcx, [rsp + StrSlice.len]
.strip_loop:
    test    rcx, rcx
    jz      .strip_done
    dec     rcx
    movzx   eax, byte [rdi + rcx]
    cmp     al, '-'
    je      .strip_found
    cmp     al, '_'
    je      .strip_found
    jmp     .strip_loop

.strip_found:
    mov     [rsp + StrSlice.len], rcx
    jmp     .match_loop

.strip_done:
    mov     qword [rsp + StrSlice.len], 0
    jmp     .match_loop

.matched:
    mov     [r13], r14
    xor     eax, eax
    add     rsp, 16
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.match_fail:
    mov     rax, STR_ERR_NOT_FOUND
    add     rsp, 16
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_locale_match_fallback

%endif ; GUARD_LIB_STR_LOCALE_LOCALE_ASM
