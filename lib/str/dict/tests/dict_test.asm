; =============================================================================
; Tattva OS — str/dict/tests/dict_test.asm
; =============================================================================
; Semantic test suite for the default English dictionary.
;
; The dictionary is static data plus pure functions — no clock, no entropy,
; no allocator to double out — so unlike security/usrauth this suite needs no
; separate harness.asm; the report routine lives here.
;
; Every non-error assertion below was cross-checked against the same
; wamerican-huge wordlist using an independent Python implementation of
; binary search and Levenshtein distance (see tools/gen_dict_table.py's
; sibling scratch work), not derived from this assembly, so a bug shared
; between the generator and the lookup code would not hide behind agreement
; between the two.
;
; The mask is written as four raw bytes on stdout rather than returned as an
; exit code — see security/usrauth/tests/harness.asm for why an exit code
; would silently lose every test past the eighth.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM), hosted test build
; =============================================================================

%include "dict/dict.inc"

section .data
align 8

; --- StrSlice literals: {ptr, len} pairs matching StrSlice's layout ---------

sl_hello:       dq s_hello, 5
s_hello:        db "hello"

sl_garbage:     dq s_garbage, 17
s_garbage:      db "zzzxxxqqqnotaword"

sl_zebra:       dq s_zebra, 5
s_zebra:        db "zebra"

sl_zebrawoods:  dq s_zebrawoods, 10
s_zebrawoods:   db "zebrawoods"

sl_wrld:        dq s_wrld, 4
s_wrld:         db "wrld"

sl_wald:        dq s_wald, 4
s_wald:         db "wald"

sl_world:       dq s_world, 5
s_world:        db "world"

sl_nomatch:     dq s_nomatch, 7
s_nomatch:      db "xqzzptv"

sl_empty:       dq 0, 0

sl_toolong:     dq s_toolong, 300
s_toolong:      times 300 db 'z'

got_match:      times DICTMATCH_SIZE db 0
suggestions:    times (5 * DICTMATCH_SIZE) db 0
out_count:      dq 0
out_lo:         dq 0
out_hi:         dq 0

dict_test_result: dd 0

section .text
global _start

; -----------------------------------------------------------------------------
; _dict_test_streq — compare a DictMatch/StrSlice-shaped {ptr,len} pair
; against a raw byte literal.
;
; RDI = ptr, RSI = len, RDX = expected_ptr, RCX = expected_len
; Returns RAX = 1 if equal, 0 otherwise.
; -----------------------------------------------------------------------------
_dict_test_streq:
    cmp     rsi, rcx
    jne     .false
    xor     r8, r8
.loop:
    cmp     r8, rsi
    jae     .true
    mov     al, [rdi + r8]
    mov     r9b, [rdx + r8]
    cmp     al, r9b
    jne     .false
    inc     r8
    jmp     .loop
.true:
    mov     eax, 1
    ret
.false:
    xor     eax, eax
    ret

_start:
    xor     r15d, r15d              ; failure mask

; =============================================================================
; T1 — word count matches the generated table exactly (348454 for the
; wamerican-huge wordlist as of this table's generation).
; =============================================================================
    call    str_dict_word_count
    cmp     rax, 348454
    je      .t1
    or      r15d, 1
.t1:

; =============================================================================
; T2 — a common word is found.
; =============================================================================
    lea     rdi, [sl_hello]
    call    str_dict_lookup
    test    rax, rax
    jz      .t2
    or      r15d, 2
.t2:

; =============================================================================
; T3 — a string that is not a word is reported not found, not merely "some
; error". Asserting the specific code is what makes this worth anything: a
; lookup that always returned STR_ERR_NOT_FOUND regardless of input would
; pass T3 for the wrong reason if it also passed T2, which is why T2 and T3
; both exist.
; =============================================================================
    lea     rdi, [sl_garbage]
    call    str_dict_lookup
    cmp     rax, STR_ERR_NOT_FOUND
    je      .t3
    or      r15d, 4
.t3:

; =============================================================================
; T4 — index 0 of the sorted table is "A": the shortest, lowest-byte-value
; entry in the wordlist (uppercase sorts before lowercase in byte order).
; =============================================================================
    xor     rdi, rdi
    lea     rsi, [got_match]
    call    str_dict_get
    test    rax, rax
    jnz     .t4_fail

    mov     rdi, [got_match + DictMatch.ptr]
    mov     rsi, [got_match + DictMatch.len]
    cmp     rsi, 1
    jne     .t4_fail
    movzx   eax, byte [rdi]
    cmp     al, 'A'
    jne     .t4_fail
    jmp     .t4
.t4_fail:
    or      r15d, 8
.t4:

; =============================================================================
; T5 — prefix_count("zebra") is exactly 9: zebra, zebra's, zebraic, zebras,
; zebrass, zebrasses, zebrawood, zebrawood's, zebrawoods.
; =============================================================================
    lea     rdi, [sl_zebra]
    call    str_dict_prefix_count
    cmp     rax, 9
    je      .t5
    or      r15d, 16
.t5:

; =============================================================================
; T6 — prefix_range("zebra") brackets exactly that run: str_dict_get(lo)
; is "zebra" itself and str_dict_get(hi-1) is "zebrawoods", the last entry
; in byte order among the nine.
; =============================================================================
    lea     rdi, [sl_zebra]
    lea     rsi, [out_lo]
    lea     rdx, [out_hi]
    call    str_dict_prefix_range
    test    rax, rax
    jnz     .t6_fail

    mov     rdi, [out_lo]
    lea     rsi, [got_match]
    call    str_dict_get
    test    rax, rax
    jnz     .t6_fail
    mov     rdi, [got_match + DictMatch.ptr]
    mov     rsi, [got_match + DictMatch.len]
    lea     rdx, [s_zebra]
    mov     rcx, 5
    call    _dict_test_streq
    test    rax, rax
    jz      .t6_fail

    mov     rdi, [out_hi]
    dec     rdi
    lea     rsi, [got_match]
    call    str_dict_get
    test    rax, rax
    jnz     .t6_fail
    mov     rdi, [got_match + DictMatch.ptr]
    mov     rsi, [got_match + DictMatch.len]
    lea     rdx, [s_zebrawoods]
    mov     rcx, 10
    call    _dict_test_streq
    test    rax, rax
    jz      .t6_fail
    jmp     .t6
.t6_fail:
    or      r15d, 32
.t6:

; =============================================================================
; T7 — suggest("wrld", max_distance=2, max_results=5) returns exactly the
; five distance-1 neighbors of "wrld" in dictionary order: wald, weld, wild,
; wold, world. All five tie at distance 1, so this also exercises the
; insertion sort's stable ordering, not just the distance computation.
; =============================================================================
    lea     rdi, [sl_wrld]
    mov     esi, 2
    lea     rdx, [suggestions]
    mov     rcx, 5
    lea     r8, [out_count]
    call    str_dict_suggest
    test    rax, rax
    jnz     .t7_fail

    cmp     qword [out_count], 5
    jne     .t7_fail

    mov     rax, [suggestions + 0*DICTMATCH_SIZE + DictMatch.distance]
    cmp     rax, 1
    jne     .t7_fail
    mov     rdi, [suggestions + 0*DICTMATCH_SIZE + DictMatch.ptr]
    mov     rsi, [suggestions + 0*DICTMATCH_SIZE + DictMatch.len]
    lea     rdx, [s_wald]
    mov     rcx, 4
    call    _dict_test_streq
    test    rax, rax
    jz      .t7_fail

    mov     rax, [suggestions + 4*DICTMATCH_SIZE + DictMatch.distance]
    cmp     rax, 1
    jne     .t7_fail
    mov     rdi, [suggestions + 4*DICTMATCH_SIZE + DictMatch.ptr]
    mov     rsi, [suggestions + 4*DICTMATCH_SIZE + DictMatch.len]
    lea     rdx, [s_world]
    mov     rcx, 5
    call    _dict_test_streq
    test    rax, rax
    jz      .t7_fail
    jmp     .t7
.t7_fail:
    or      r15d, 64
.t7:

; =============================================================================
; T8 — nothing within distance 2 of "xqzzptv" reports NOT_FOUND with
; out_count left at 0, not a stale value from a previous call.
; =============================================================================
    mov     qword [out_count], 0x7EADBEEF
    lea     rdi, [sl_nomatch]
    mov     esi, 2
    lea     rdx, [suggestions]
    mov     rcx, 5
    lea     r8, [out_count]
    call    str_dict_suggest
    cmp     rax, STR_ERR_NOT_FOUND
    jne     .t8_fail
    cmp     qword [out_count], 0
    jne     .t8_fail
    jmp     .t8
.t8_fail:
    or      r15d, 128
.t8:

; =============================================================================
; T9 — argument validation: a NULL slice, an empty query, and a zero
; max_results are all rejected before the scan runs, not treated as
; "no suggestions found".
; =============================================================================
    xor     rdi, rdi
    call    str_dict_lookup
    cmp     rax, STR_ERR_NULL
    jne     .t9_fail

    lea     rdi, [sl_empty]
    mov     esi, 1
    lea     rdx, [suggestions]
    mov     rcx, 5
    lea     r8, [out_count]
    call    str_dict_suggest
    cmp     rax, STR_ERR_INVALID_ARG
    jne     .t9_fail

    lea     rdi, [sl_hello]
    mov     esi, 1
    lea     rdx, [suggestions]
    xor     rcx, rcx                 ; max_results = 0
    lea     r8, [out_count]
    call    str_dict_suggest
    cmp     rax, STR_ERR_INVALID_ARG
    jne     .t9_fail
    jmp     .t9
.t9_fail:
    or      r15d, 256
.t9:

; =============================================================================
; T10 — an empty prefix matches the whole dictionary: prefix_count("") is
; str_dict_word_count(), exercising _dict_prefix_bounds's key_len == 0 path,
; which prefix_range never reaches on its own (STR_ERR_NULL rejects a NULL
; StrSlice before the empty-length case is ever considered).
; =============================================================================
    lea     rdi, [sl_empty]
    call    str_dict_prefix_count
    cmp     rax, 348454
    je      .t10
    or      r15d, 512
.t10:

; =============================================================================
; T11 — a prefix longer than any dictionary entry (DICT_MAX_WORD_LEN = 255)
; matches nothing, without touching the successor-key stack buffer that
; longer prefixes would overflow if this short-circuit were missing.
; =============================================================================
    lea     rdi, [sl_toolong]
    call    str_dict_prefix_count
    test    rax, rax
    jz      .t11
    or      r15d, 1024
.t11:

    mov     edi, r15d
    call    dict_test_report

; -----------------------------------------------------------------------------
; dict_test_report — emit the failure bitmask on stdout and exit 0.
; See security/usrauth/tests/harness.asm for why the mask is not the exit
; code.
;
; EDI = failure bitmask
; -----------------------------------------------------------------------------
dict_test_report:
    mov     [dict_test_result], edi

    mov     eax, 1                   ; write
    mov     edi, 1                   ; stdout
    lea     rsi, [dict_test_result]
    mov     edx, 4
    syscall

    xor     edi, edi
    mov     eax, 60                  ; exit
    syscall
