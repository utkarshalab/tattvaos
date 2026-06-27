; =============================================================================
; str/unicode/emoji_sequences.asm
; Emoji sequence type detection (beyond single codepoint properties).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm                   (str_utf8_decode_unchecked)
;   unicode/emoji.asm                 (str_cp_is_emoji_modifier_base, etc.)
;
; -----------------------------------------------------------------------------
; Modern emoji rendering requires detecting multi-codepoint sequences.
; A single "emoji" on screen may be 2-7+ codepoints:
;
; 1. Keycap sequences:    base + VS16 + U+20E3 (Combining Enclosing Keycap)
;    Example: 1️⃣ = U+0031 + U+FE0F + U+20E3
;
; 2. Flag sequences:      Regional_Indicator + Regional_Indicator
;    Example: 🇺🇸 = U+1F1FA + U+1F1F8 (US flag)
;
; 3. Modifier sequences:  emoji_modifier_base + emoji_modifier (skin tone)
;    Example: 👋🏽 = U+1F44B + U+1F3FD (waving hand, medium skin)
;
; 4. Tag sequences:       🏴 + tag_chars + U+E007F (cancel tag)
;    Example: 🏴󠁧󠁢󠁳󠁣󠁴󠁿 = 🏴 + gbsct + cancel (Scotland flag)
;
; 5. ZWJ sequences:       emoji + ZWJ + emoji [+ ZWJ + emoji ...]
;    Example: 👨‍👩‍👧‍👦 = man + ZWJ + woman + ZWJ + girl + ZWJ + boy
;             👩‍💻 = woman + ZWJ + laptop (woman technologist)
;
; 6. Presentation sequences: emoji_base + VS15/VS16
;    Example: ☺️ = U+263A + U+FE0F (smiley, emoji presentation)
;
; Functions:
;   str_emoji_is_keycap_seq        — detect keycap sequence at offset
;   str_emoji_is_flag_seq          — detect flag sequence at offset
;   str_emoji_is_modifier_seq      — detect modifier sequence at offset
;   str_emoji_is_tag_seq           — detect tag sequence at offset
;   str_emoji_is_zwj_seq           — detect ZWJ sequence at offset
;   str_emoji_presentation_style   — text or emoji after VS?
;   str_emoji_sequence_type        — classify sequence type at offset
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked
extern str_cp_is_emoji
extern str_cp_is_emoji_modifier_base
extern str_cp_is_emoji_modifier

; Emoji sequence types
EMOJI_SEQ_NONE      equ 0   ; not an emoji sequence
EMOJI_SEQ_KEYCAP    equ 1   ; keycap: digit/# + VS16 + U+20E3
EMOJI_SEQ_FLAG      equ 2   ; flag: RI + RI
EMOJI_SEQ_MODIFIER  equ 3   ; modifier: base + skin tone
EMOJI_SEQ_TAG       equ 4   ; tag: 🏴 + tags + cancel
EMOJI_SEQ_ZWJ       equ 5   ; ZWJ: emoji + ZWJ + emoji
EMOJI_SEQ_PRESENT   equ 6   ; presentation: emoji + VS15/VS16

; Key codepoints
ZWJ             equ 0x200D
VS15            equ 0xFE0E      ; text presentation
VS16            equ 0xFE0F      ; emoji presentation
KEYCAP          equ 0x20E3      ; combining enclosing keycap
BLACK_FLAG      equ 0x1F3F4     ; 🏴
TAG_CANCEL      equ 0xE007F     ; cancel tag
TAG_SPACE       equ 0xE0020     ; tag space (first tag char)
TAG_TILDE       equ 0xE007E     ; tag tilde (last printable tag char)
RI_BASE         equ 0x1F1E6     ; Regional Indicator A
RI_LAST         equ 0x1F1FF     ; Regional Indicator Z

section .text

; -----------------------------------------------------------------------------
; str_emoji_is_keycap_seq
;
; Detect a keycap sequence starting at the given offset in a string.
; Pattern: keycap_base + VS16 + U+20E3
; Keycap bases: '#' (0x23), '*' (0x2A), '0'-'9' (0x30-0x39)
;
; Signature:
;   int64_t str_emoji_is_keycap_seq(const StrSlice *src, uint64_t offset,
;                                    uint64_t *out_end)
;
; Arguments:
;   RDI  — source string
;   RSI  — byte offset to check from
;   RDX  — pointer to receive end offset (may be NULL)
;
; Returns:
;   RAX  = 1 if keycap sequence found, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_emoji_is_keycap_seq

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     r12, [rdi + StrSlice.ptr]
    mov     r13, r12
    add     r13, [rdi + StrSlice.len]   ; end
    add     r12, rsi                     ; current pos
    mov     r14, rdx                     ; out_end

    ; need at least 3 codepoints remaining
    cmp     r12, r13
    jae     .ks_no

    ; decode first: must be keycap base (#, *, 0-9)
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, r12
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax            ; cp1
    mov     rbx, [rsp]          ; advance1
    mov     rsp, rbp

    ; check keycap base
    cmp     r8d, '#'
    je      .ks_base_ok
    cmp     r8d, '*'
    je      .ks_base_ok
    cmp     r8d, '0'
    jb      .ks_no
    cmp     r8d, '9'
    ja      .ks_no

.ks_base_ok:
    ; decode second: must be VS16 (U+FE0F)
    lea     rdi, [r12 + rbx]
    cmp     rdi, r13
    jae     .ks_no

    sub     rsp, 16
    and     rsp, -16
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r9d, eax            ; cp2
    mov     rcx, [rsp]          ; advance2
    mov     rsp, rbp

    cmp     r9d, VS16
    jne     .ks_no

    ; decode third: must be U+20E3 (keycap)
    lea     rdi, [r12 + rbx]
    add     rdi, rcx
    cmp     rdi, r13
    jae     .ks_no

    push    rcx
    push    rbx
    sub     rsp, 16
    and     rsp, -16
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r10d, eax           ; cp3
    mov     rdx, [rsp]          ; advance3
    mov     rsp, rbp
    pop     rbx
    pop     rcx

    cmp     r10d, KEYCAP
    jne     .ks_no

    ; keycap sequence found!
    test    r14, r14
    jz      .ks_yes
    ; calculate end offset
    lea     rax, [rbx + rcx]
    add     rax, rdx
    add     rax, rsi            ; original offset + total advance
    mov     [r14], rax

.ks_yes:
    pop_regs r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.ks_no:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_emoji_is_keycap_seq

; -----------------------------------------------------------------------------
; str_emoji_is_flag_seq
;
; Detect a flag sequence (two Regional Indicators) at offset.
; Pattern: RI + RI (e.g., 🇺🇸 = U+1F1FA + U+1F1F8)
;
; Signature:
;   int64_t str_emoji_is_flag_seq(const StrSlice *src, uint64_t offset,
;                                  uint64_t *out_end)
;
; Arguments:
;   RDI  — source string
;   RSI  — byte offset
;   RDX  — out_end (may be NULL)
;
; Returns:
;   RAX  = 1 if flag sequence, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_emoji_is_flag_seq

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     r12, [rdi + StrSlice.ptr]
    mov     r13, r12
    add     r13, [rdi + StrSlice.len]
    add     r12, rsi
    mov     r14, rdx

    cmp     r12, r13
    jae     .fs_no

    ; decode first: must be Regional Indicator
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, r12
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     rbx, [rsp]
    mov     rsp, rbp

    cmp     r8d, RI_BASE
    jb      .fs_no
    cmp     r8d, RI_LAST
    ja      .fs_no

    ; decode second: must also be Regional Indicator
    lea     rdi, [r12 + rbx]
    cmp     rdi, r13
    jae     .fs_no

    sub     rsp, 16
    and     rsp, -16
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r9d, eax
    mov     rcx, [rsp]
    mov     rsp, rbp

    cmp     r9d, RI_BASE
    jb      .fs_no
    cmp     r9d, RI_LAST
    ja      .fs_no

    ; flag sequence found
    test    r14, r14
    jz      .fs_yes
    lea     rax, [rbx + rcx]
    add     rax, rsi
    mov     [r14], rax

.fs_yes:
    pop_regs r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.fs_no:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_emoji_is_flag_seq

; -----------------------------------------------------------------------------
; str_emoji_is_modifier_seq
;
; Detect a skin-tone modifier sequence at offset.
; Pattern: emoji_modifier_base + emoji_modifier (U+1F3FB-U+1F3FF)
;
; Signature:
;   int64_t str_emoji_is_modifier_seq(const StrSlice *src, uint64_t offset,
;                                      uint64_t *out_end)
;
; Arguments:
;   RDI  — source string
;   RSI  — byte offset
;   RDX  — out_end (may be NULL)
;
; Returns:
;   RAX  = 1 if modifier sequence, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_emoji_is_modifier_seq

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     r12, [rdi + StrSlice.ptr]
    mov     r13, r12
    add     r13, [rdi + StrSlice.len]
    add     r12, rsi
    mov     r14, rdx

    cmp     r12, r13
    jae     .ms_no

    ; decode first: must be emoji modifier base
    sub     rsp, 16
    and     rsp, -16
    mov     rdi, r12
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     rbx, [rsp]
    mov     rsp, rbp

    ; check if modifier base
    mov     edi, r8d
    push    rbx
    call    str_cp_is_emoji_modifier_base
    pop     rbx
    test    eax, eax
    jz      .ms_no

    ; decode second: must be emoji modifier (skin tone)
    lea     rdi, [r12 + rbx]
    cmp     rdi, r13
    jae     .ms_no

    sub     rsp, 16
    and     rsp, -16
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r9d, eax
    mov     rcx, [rsp]
    mov     rsp, rbp

    mov     edi, r9d
    push    rcx
    push    rbx
    call    str_cp_is_emoji_modifier
    pop     rbx
    pop     rcx
    test    eax, eax
    jz      .ms_no

    ; modifier sequence found
    test    r14, r14
    jz      .ms_yes
    lea     rax, [rbx + rcx]
    add     rax, rsi
    mov     [r14], rax

.ms_yes:
    pop_regs r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.ms_no:
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_emoji_is_modifier_seq

; -----------------------------------------------------------------------------
; str_emoji_is_tag_seq
;
; Detect a tag sequence at offset.
; Pattern: 🏴 (U+1F3F4) + tag_chars (U+E0020-U+E007E)+ + cancel (U+E007F)
; Used for subdivision flags (e.g., 🏴󠁧󠁢󠁳󠁣󠁴󠁿 = Scotland)
;
; Signature:
;   int64_t str_emoji_is_tag_seq(const StrSlice *src, uint64_t offset,
;                                 uint64_t *out_end)
;
; Arguments:
;   RDI  — source string
;   RSI  — byte offset
;   RDX  — out_end (may be NULL)
;
; Returns:
;   RAX  = 1 if tag sequence, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_emoji_is_tag_seq

    guard_null rdi, STR_ERR_NULL

    mov     r11, [rdi + StrSlice.ptr]
    push_regs rbx, r12, r13, r14, r15
    push    r11                 ; stack is now 16-byte aligned
    sub     rsp, 16             ; pre-allocate 16 bytes for out_advance

    mov     r12, r11
    mov     r13, r12
    add     r13, [rdi + StrSlice.len]
    add     r12, rsi
    mov     r14, rdx            ; out_end
    xor     r15d, r15d          ; tag count

    cmp     r12, r13
    jae     .ts_no

    ; decode first: must be BLACK_FLAG (U+1F3F4)
    mov     rdi, r12
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     r12, [rsp]

    cmp     r8d, BLACK_FLAG
    jne     .ts_no

    ; consume tag characters (U+E0020-U+E007E)
.ts_tag_loop:
    cmp     r12, r13
    jae     .ts_no              ; ran out of input without cancel tag

    mov     rdi, r12
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     rbx, [rsp]

    ; check for cancel tag
    cmp     r8d, TAG_CANCEL
    je      .ts_check_valid

    ; check for tag character
    cmp     r8d, TAG_SPACE
    jb      .ts_no
    cmp     r8d, TAG_TILDE
    ja      .ts_no

    ; valid tag character
    add     r12, rbx
    inc     r15d
    jmp     .ts_tag_loop

.ts_check_valid:
    ; must have at least 1 tag character before cancel
    test    r15d, r15d
    jz      .ts_no

    ; tag sequence found
    add     r12, rbx            ; advance past cancel tag
    test    r14, r14
    jz      .ts_yes
    ; compute end offset: r12 - original src->ptr
    mov     rax, r12
    sub     rax, [rsp + 16]     ; original src->ptr was pushed before allocating 16 bytes, so it's at [rsp + 16]
    mov     [r14], rax

.ts_yes:
    add     rsp, 16             ; deallocate local
    pop     r11                 ; discard original src->ptr
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.ts_no:
    add     rsp, 16             ; deallocate local
    pop     r11                 ; discard original src->ptr
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_emoji_is_tag_seq

; -----------------------------------------------------------------------------
; str_emoji_is_zwj_seq
;
; Detect a ZWJ (Zero-Width Joiner) sequence at offset.
; Pattern: emoji + ZWJ + emoji [+ ZWJ + emoji ...]
;
; This detects sequences of 2+ emoji joined by ZWJ (U+200D).
; The function returns true only if at least one ZWJ join is present.
;
; Signature:
;   int64_t str_emoji_is_zwj_seq(const StrSlice *src, uint64_t offset,
;                                 uint64_t *out_end)
;
; Arguments:
;   RDI  — source string
;   RSI  — byte offset
;   RDX  — out_end (may be NULL)
;
; Returns:
;   RAX  = 1 if ZWJ sequence, 0 otherwise
; -----------------------------------------------------------------------------

STR_FUNC str_emoji_is_zwj_seq

    guard_null rdi, STR_ERR_NULL

    mov     r11, [rdi + StrSlice.ptr]
    push_regs rbx, r12, r13, r14, r15
    push    r11                 ; stack is now 16-byte aligned
    sub     rsp, 16             ; pre-allocate 16 bytes for out_advance

    mov     r12, r11
    mov     r13, r12
    add     r13, [rdi + StrSlice.len]
    add     r12, rsi
    mov     r14, rdx            ; out_end
    xor     r15d, r15d          ; ZWJ count

    cmp     r12, r13
    jae     .zs_no

    ; decode first: must be emoji
    mov     rdi, r12
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     r12, [rsp]

    ; check if emoji
    push    rax                 ; dummy push for alignment (4 registers pushed = 32 bytes)
    push    rcx
    push    rdx
    push    rsi
    mov     edi, r8d
    call    str_cp_is_emoji
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    test    eax, eax
    jz      .zs_no

    ; skip any modifier / VS following the emoji
.zs_skip_mod:
    cmp     r12, r13
    jae     .zs_check_zwj_count

    mov     rdi, r12
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    mov     rbx, [rsp]

    ; skip skin tone modifiers
    cmp     r8d, 0x1F3FB
    jb      .zs_chk_vs
    cmp     r8d, 0x1F3FF
    jbe     .zs_advance_skip

.zs_chk_vs:
    ; skip VS16
    cmp     r8d, VS16
    je      .zs_advance_skip

    ; check for ZWJ
    cmp     r8d, ZWJ
    jne     .zs_check_zwj_count

    ; found ZWJ — advance past it
    add     r12, rbx
    inc     r15d

    ; next must be emoji
    cmp     r12, r13
    jae     .zs_check_zwj_count

    mov     rdi, r12
    lea     rsi, [rsp]          ; out_advance is at [rsp]
    call    str_utf8_decode_unchecked
    mov     r8d, eax
    add     r12, [rsp]

    push    rax                 ; dummy push for alignment
    push    rcx
    push    rdx
    push    rsi
    mov     edi, r8d
    call    str_cp_is_emoji
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rax
    test    eax, eax
    jz      .zs_check_zwj_count

    jmp     .zs_skip_mod        ; continue for more ZWJ joins

.zs_advance_skip:
    add     r12, rbx
    jmp     .zs_skip_mod

.zs_check_zwj_count:
    ; at least 1 ZWJ needed for this to be a ZWJ sequence
    test    r15d, r15d
    jz      .zs_no

    test    r14, r14
    jz      .zs_yes
    ; compute end offset: r12 - original src->ptr
    mov     rax, r12
    sub     rax, [rsp + 16]     ; original src->ptr is at [rsp + 16]
    mov     [r14], rax

.zs_yes:
    add     rsp, 16             ; deallocate local
    pop     r11                 ; discard original src->ptr
    pop_regs r15, r14, r13, r12, rbx
    mov     eax, 1
    pop     rbp
    ret

.zs_no:
    add     rsp, 16             ; deallocate local
    pop     r11                 ; discard original src->ptr
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_emoji_is_zwj_seq

; -----------------------------------------------------------------------------
; str_emoji_presentation_style
;
; Determine the presentation style of an emoji base + optional VS.
;
; Signature:
;   uint8_t str_emoji_presentation_style(uint32_t base_cp, uint32_t next_cp)
;
; Arguments:
;   EDI  — base codepoint
;   ESI  — next codepoint (may be 0 if no following codepoint)
;
; Returns:
;   AL   — 0 = text presentation, 1 = emoji presentation
; -----------------------------------------------------------------------------

STR_FUNC str_emoji_presentation_style

    ; explicit VS15 → text
    cmp     esi, VS15
    je      .eps_text

    ; explicit VS16 → emoji
    cmp     esi, VS16
    je      .eps_emoji

    ; no VS: use default presentation
    ; most SMP emoji (U+1F300+) default to emoji presentation
    cmp     edi, 0x1F300
    jb      .eps_chk_default_text
    cmp     edi, 0x1FAFF
    jbe     .eps_emoji

.eps_chk_default_text:
    ; BMP emoji default to text presentation (need VS16 for emoji)
    ; keycap bases, arrows, etc.
    xor     eax, eax            ; text
    pop     rbp
    ret

.eps_text:
    xor     eax, eax
    pop     rbp
    ret

.eps_emoji:
    mov     eax, 1
    pop     rbp
    ret

STR_ENDFUNC str_emoji_presentation_style

; -----------------------------------------------------------------------------
; str_emoji_sequence_type
;
; Classify the emoji sequence starting at the given offset.
;
; Signature:
;   uint8_t str_emoji_sequence_type(const StrSlice *src, uint64_t offset)
;
; Arguments:
;   RDI  — source string
;   RSI  — byte offset
;
; Returns:
;   AL   — EMOJI_SEQ_* enum value
; -----------------------------------------------------------------------------

STR_FUNC str_emoji_sequence_type

    guard_null rdi, STR_ERR_NULL

    push_regs rbx

    mov     rbx, rdi            ; save src

    ; try keycap first (most specific)
    xor     edx, edx
    call    str_emoji_is_keycap_seq
    test    eax, eax
    jnz     .est_keycap

    ; try flag
    mov     rdi, rbx
    ; rsi still has offset
    xor     edx, edx
    call    str_emoji_is_flag_seq
    test    eax, eax
    jnz     .est_flag

    ; try tag
    mov     rdi, rbx
    xor     edx, edx
    call    str_emoji_is_tag_seq
    test    eax, eax
    jnz     .est_tag

    ; try modifier
    mov     rdi, rbx
    xor     edx, edx
    call    str_emoji_is_modifier_seq
    test    eax, eax
    jnz     .est_modifier

    ; try ZWJ
    mov     rdi, rbx
    xor     edx, edx
    call    str_emoji_is_zwj_seq
    test    eax, eax
    jnz     .est_zwj

    ; none matched
    pop_regs rbx
    mov     al, EMOJI_SEQ_NONE
    pop     rbp
    ret

.est_keycap:
    pop_regs rbx
    mov     al, EMOJI_SEQ_KEYCAP
    pop     rbp
    ret

.est_flag:
    pop_regs rbx
    mov     al, EMOJI_SEQ_FLAG
    pop     rbp
    ret

.est_tag:
    pop_regs rbx
    mov     al, EMOJI_SEQ_TAG
    pop     rbp
    ret

.est_modifier:
    pop_regs rbx
    mov     al, EMOJI_SEQ_MODIFIER
    pop     rbp
    ret

.est_zwj:
    pop_regs rbx
    mov     al, EMOJI_SEQ_ZWJ
    pop     rbp
    ret

STR_ENDFUNC str_emoji_sequence_type
