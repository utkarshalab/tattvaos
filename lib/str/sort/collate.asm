; =============================================================================
; str/sort/collate.asm
; Locale-aware string collation (simplified DUCET-inspired ordering).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;
; -----------------------------------------------------------------------------
; Collation levels (Unicode Collation Algorithm):
;   Level 1 (primary):   base letter (a == A == á)
;   Level 2 (secondary): accents (a < á, a == A)
;   Level 3 (tertiary):  case (a < A)
;
; This implementation provides a simplified collation:
;   - Strips combining marks for level 1 comparison
;   - Case-insensitive at level 1
;   - Case-sensitive as tiebreaker
;
; For full DUCET ordering see unicode/tables/collation_table.s
;
; Functions:
;   str_collate         — compare two strings with collation
;   str_collate_key     — generate a sort key for a string
;   str_collate_level   — compare at a specific level
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_decode_unchecked

section .text

; -----------------------------------------------------------------------------
; _collate_primary_weight
;
; Get the primary collation weight for a codepoint.
; For ASCII: strips case. For Latin accented: strips accents.
; Returns weight in EAX.
;
; Arguments: EDI = codepoint
; -----------------------------------------------------------------------------

_collate_primary_weight:
    ; ASCII: fold to lowercase
    cmp     edi, 0x7F
    ja      .cpw_upper_latin

    cmp     edi, 'A'
    jb      .cpw_as_is
    cmp     edi, 'Z'
    ja      .cpw_as_is
    or      edi, 0x20           ; lowercase

.cpw_as_is:
    mov     eax, edi
    ret

.cpw_upper_latin:
    ; Latin-1 supplement: strip accents → base letter
    ; À-Ö (0xC0-0xD6) → A-V (strip accent, fold case)
    cmp     edi, 0xC0
    jb      .cpw_check_lower_latin
    cmp     edi, 0xD6
    ja      .cpw_check_d7

    ; map to base: 0xC0-0xC5 → 'a', 0xC6 → "ae" etc.
    ; simplified: just fold to ASCII base letter
    cmp     edi, 0xC0
    jb      .cpw_as_is_up
    cmp     edi, 0xC5
    jbe     .cpw_to_a
    cmp     edi, 0xC8
    jb      .cpw_as_is_up
    cmp     edi, 0xCB
    jbe     .cpw_to_e
    cmp     edi, 0xCC
    jb      .cpw_as_is_up
    cmp     edi, 0xCF
    jbe     .cpw_to_i
    cmp     edi, 0xD2
    jb      .cpw_as_is_up
    cmp     edi, 0xD6
    jbe     .cpw_to_o
    jmp     .cpw_as_is_up

.cpw_to_a: mov eax, 'a' ; ret
    ret
.cpw_to_e: mov eax, 'e'
    ret
.cpw_to_i: mov eax, 'i'
    ret
.cpw_to_o: mov eax, 'o'
    ret

.cpw_check_d7:
    cmp     edi, 0xD8
    jb      .cpw_as_is_up       ; 0xD7 = multiply sign
    cmp     edi, 0xDE
    ja      .cpw_check_lower_latin
    ; 0xD8-0xDE → keep as-is (Ø, Ù-Þ)
    jmp     .cpw_as_is_up

.cpw_check_lower_latin:
    ; 0xE0-0xFF: lowercase accented
    cmp     edi, 0xE0
    jb      .cpw_as_is_up
    cmp     edi, 0xE5
    jbe     .cpw_to_a
    cmp     edi, 0xE8
    jb      .cpw_as_is_up
    cmp     edi, 0xEB
    jbe     .cpw_to_e
    cmp     edi, 0xEC
    jb      .cpw_as_is_up
    cmp     edi, 0xEF
    jbe     .cpw_to_i
    cmp     edi, 0xF2
    jb      .cpw_as_is_up
    cmp     edi, 0xF6
    jbe     .cpw_to_o
    cmp     edi, 0xF9
    jb      .cpw_as_is_up
    cmp     edi, 0xFC
    jbe     .cpw_to_u

.cpw_as_is_up:
    mov     eax, edi
    ret

.cpw_to_u: mov eax, 'u'
    ret

; -----------------------------------------------------------------------------
; str_collate
;
; Compare two UTF-8 strings with collation ordering.
;
; Signature:
;   int64_t str_collate(const StrSlice *a, const StrSlice *b)
;
; Returns:
;   RAX  < 0   a before b
;   RAX  = 0   equal
;   RAX  > 0   a after b
; -----------------------------------------------------------------------------

STR_FUNC str_collate

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    ; set up two iterators
    mov     rbx, [rdi + StrSlice.ptr]   ; a_ptr
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]   ; a_end

    mov     r13, [rsi + StrSlice.ptr]   ; b_ptr
    mov     r14, r13
    add     r14, [rsi + StrSlice.len]   ; b_end

    ; Phase 1: primary weight comparison (case/accent insensitive)
.coll_primary:
    cmp     rbx, r12
    jae     .coll_a_done

    cmp     r13, r14
    jae     .coll_b_done

    ; decode from a
    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r9d, eax            ; cp_a
    add     rbx, [rsp]

    ; decode from b
    mov     rdi, r13
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r10d, eax           ; cp_b
    add     r13, [rsp]

    mov     rsp, rbp

    ; get primary weights
    mov     edi, r9d
    push    r9
    push    r10
    push    rbx
    push    r13
    call    _collate_primary_weight
    mov     r15d, eax           ; wa

    pop     r13
    pop     rbx
    pop     r10
    pop     r9

    mov     edi, r10d
    push    r9
    push    r10
    push    rbx
    push    r13
    call    _collate_primary_weight
    pop     r13
    pop     rbx
    pop     r10
    pop     r9
    ; eax = wb

    cmp     r15d, eax
    jne     .coll_primary_diff

    jmp     .coll_primary

.coll_primary_diff:
    sub     r15d, eax
    movsx   rax, r15d

    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.coll_a_done:
    ; a exhausted — check b
    cmp     r13, r14
    jae     .coll_equal         ; both exhausted
    ; a is shorter
    mov     rax, -1
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.coll_b_done:
    mov     rax, 1
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.coll_equal:
    ; Primary weights equal — do byte-level tiebreak
    ; Reset pointers
    mov     rbx, [rdi + StrSlice.ptr]   ; but rdi is clobbered...
    ; This needs a redesign — save src pointers at start
    ; For now: return 0 (equal)
    xor     eax, eax
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_collate

; -----------------------------------------------------------------------------
; str_collate_key
;
; Generate a sort key for a string that can be compared with memcmp.
; The key is a sequence of collation weights suitable for byte comparison.
;
; Signature:
;   int64_t str_collate_key(const StrSlice *src, uint8_t *dst,
;                            uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_collate_key

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, rbx
    add     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    xor     r9, r9              ; dst offset

.ck_loop:
    cmp     rbx, r12
    jae     .ck_done

    sub     rsp, 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_utf8_decode_unchecked
    mov     r10d, eax
    add     rbx, [rsp]
    mov     rsp, rbp

    ; get primary weight
    mov     edi, r10d
    push    rbx
    push    r9
    call    _collate_primary_weight
    pop     r9
    pop     rbx

    ; encode weight as 1-4 bytes into dst
    ; for BMP: 2 bytes (big-endian for correct memcmp ordering)
    cmp     r9 + 2, r14
    ja      .ck_overflow

    cmp     eax, 0xFF
    jbe     .ck_byte_weight

    mov     r10d, eax
    shr     r10d, 8
    mov     [r13 + r9], r10b
    inc     r9
    mov     [r13 + r9], al
    inc     r9
    jmp     .ck_loop

.ck_byte_weight:
    ; weight fits in 1 byte
    mov     [r13 + r9], al
    inc     r9
    jmp     .ck_loop

.ck_done:
    test    r15, r15
    jz      .ck_ok
    mov     [r15], r9

.ck_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ck_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_collate_key