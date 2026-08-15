%ifndef GUARD_LIB_STR_DICT_SUGGEST_ASM
%define GUARD_LIB_STR_DICT_SUGGEST_ASM
; =============================================================================
; str/dict/suggest.asm
; "Did you mean" spellcheck suggestions: bounded Levenshtein distance against
; the default English dictionary.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   dict/dict.inc
;
; -----------------------------------------------------------------------------
; The dictionary table is sorted by content, not by length, so there is no
; index range to binary-search the way lookup/prefix do. Instead this scans
; every entry once, but two cheap checks reject almost all of them before the
; expensive part ever runs:
;
;   1. |word_len - query_len| > max_distance  — a word this different in
;      length cannot possibly be within max_distance edits, no DP needed.
;   2. word_len > DICT_SUGGEST_MAX_LEN        — bounds the fixed-size DP
;      row buffers; every real English word is far under this.
;
; Only words that survive both get a full Levenshtein DP (insert/delete/
; substitute, no transposition — plain Levenshtein, not Damerau-Levenshtein;
; that is a deliberate scope cut, not an oversight). Matches within
; max_distance are kept in a running top-`max_results` list, sorted ascending
; by distance, maintained by insertion as the scan goes — there are ~348K
; candidates but usually only a handful ever beat the current worst kept
; match, so this stays cheap in practice despite being O(max_results) per
; hit in the worst case.
;
; Functions:
;   str_dict_suggest   — ranked spellcheck suggestions for a word
; =============================================================================

%include "lib/str/arch/common/types.inc"
%include "lib/str/arch/common/error.inc"
%include "lib/str/arch/common/macros.inc"
%include "lib/str/dict/dict.inc"

; One DP row: (DICT_SUGGEST_MAX_LEN + 1) 32-bit cells, indices 0..max_len.
DICT_DP_ROW_BYTES   equ (DICT_SUGGEST_MAX_LEN + 1) * 4

section .text

; -----------------------------------------------------------------------------
; _dict_edit_distance (internal)
;
; Plain Levenshtein distance (insert/delete/substitute, unit cost) via a
; two-row rolling DP on the stack. No allocation.
;
; Inputs:
;   RDI = a_ptr, RSI = a_len   (caller guarantees a_len <= DICT_SUGGEST_MAX_LEN)
;   RDX = b_ptr, RCX = b_len   (caller guarantees b_len <= DICT_SUGGEST_MAX_LEN)
;
; Returns:
;   RAX = edit distance (>= 0)
; -----------------------------------------------------------------------------

_dict_edit_distance:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi              ; a_ptr
    mov     r13, rsi              ; a_len
    mov     r14, rdx              ; b_ptr
    mov     r15, rcx              ; b_len

    sub     rsp, DICT_DP_ROW_BYTES * 2
    ; prev row: [rsp .. rsp+DICT_DP_ROW_BYTES)
    ; curr row: [rsp+DICT_DP_ROW_BYTES .. rsp+2*DICT_DP_ROW_BYTES)

    xor     rcx, rcx
.init_loop:
    cmp     rcx, r15
    ja      .init_done
    mov     [rsp + rcx*4], ecx
    inc     rcx
    jmp     .init_loop
.init_done:

    mov     rbx, 1                ; i = 1..a_len
.row_loop:
    cmp     rbx, r13
    ja      .rows_done

    mov     eax, ebx
    mov     [rsp + DICT_DP_ROW_BYTES], eax   ; curr[0] = i

    mov     rax, rbx
    dec     rax
    movzx   r8d, byte [r12 + rax]             ; a_char = a[i-1]

    mov     rcx, 1                             ; j = 1..b_len
.col_loop:
    cmp     rcx, r15
    ja      .row_done

    mov     rax, rcx
    dec     rax
    movzx   r9d, byte [r14 + rax]              ; b_char = b[j-1]

    xor     edx, edx
    cmp     r8d, r9d
    sete    dl
    xor     edx, 1                              ; cost = (a_char != b_char)

    mov     r10, rcx
    dec     r10                                  ; r10 = j-1

    mov     esi, [rsp + r10*4]                   ; diag = prev[j-1]
    mov     edi, [rsp + rcx*4]                    ; up   = prev[j]
    mov     r11d, [rsp + DICT_DP_ROW_BYTES + r10*4] ; left = curr[j-1]

    add     esi, edx                              ; diag + cost
    lea     edi, [edi + 1]                          ; up + 1
    lea     r11d, [r11d + 1]                         ; left + 1

    mov     eax, esi
    cmp     edi, eax
    jae     .skip_up
    mov     eax, edi
.skip_up:
    cmp     r11d, eax
    jae     .skip_left
    mov     eax, r11d
.skip_left:
    mov     [rsp + DICT_DP_ROW_BYTES + rcx*4], eax  ; curr[j] = min(...)

    inc     rcx
    jmp     .col_loop

.row_done:
    ; prev <- curr, for the next i
    xor     rcx, rcx
.swap_loop:
    cmp     rcx, r15
    ja      .swap_done
    mov     eax, [rsp + DICT_DP_ROW_BYTES + rcx*4]
    mov     [rsp + rcx*4], eax
    inc     rcx
    jmp     .swap_loop
.swap_done:

    inc     rbx
    jmp     .row_loop

.rows_done:
    mov     eax, [rsp + r15*4]        ; prev[b_len]

    add     rsp, DICT_DP_ROW_BYTES * 2
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; str_dict_suggest
;
; Ranked "did you mean" candidates for a misspelled word.
;
; Signature:
;   int64_t str_dict_suggest(const StrSlice *word, uint32_t max_distance,
;                             DictMatch *out_matches, uint64_t max_results,
;                             uint64_t *out_count)
;
; out_matches must have room for max_results entries. On return, the first
; *out_count of them hold the best matches found, sorted ascending by
; .distance (ties broken by dictionary order, i.e. earlier scan wins — an
; incidental but stable tie-break since the table is scanned index 0..N-1).
;
; Returns:
;   RAX = STR_OK                 out_count > 0
;   RAX = STR_ERR_NOT_FOUND      nothing within max_distance
;   RAX = STR_ERR_NULL           word, out_matches, or out_count is NULL
;   RAX = STR_ERR_INVALID_ARG    word.len is 0 or > DICT_SUGGEST_MAX_LEN,
;                                 max_distance > DICT_SUGGEST_MAX_DISTANCE,
;                                 or max_results is 0
; -----------------------------------------------------------------------------

STR_FUNC str_dict_suggest
    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    mov     rax, [rdi + StrSlice.len]
    test    rax, rax
    jz      .sg_bad_arg
    cmp     rax, DICT_SUGGEST_MAX_LEN
    ja      .sg_bad_arg
    cmp     esi, DICT_SUGGEST_MAX_DISTANCE
    ja      .sg_bad_arg
    test    rcx, rcx
    jz      .sg_bad_arg

    jmp     .sg_start

.sg_bad_arg:
    ret_err STR_ERR_INVALID_ARG

.sg_start:
    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; query_ptr
    mov     r12, rax                    ; query_len
    mov     r13d, esi                   ; max_distance (32-bit mov zero-extends)
    mov     r14, rdx                    ; out_matches base
    mov     r15, rcx                    ; max_results

    sub     rsp, 32
    ; [rsp+0]  = out_count_ptr
    ; [rsp+8]  = current_count
    ; [rsp+16] = loop_idx
    mov     [rsp + 0], r8
    mov     qword [rsp + 8], 0
    mov     qword [rsp + 16], 0
    mov     qword [r8], 0

.sg_loop:
    mov     rax, [rsp + 16]
    mov     ecx, [dict_word_count]
    cmp     rax, rcx
    jae     .sg_loop_done

    movzx   r9, byte [dict_lengths + rax]   ; wlen

    mov     r11, r12
    sub     r11, r9
    jns     .sg_abs_ok
    neg     r11
.sg_abs_ok:
    cmp     r11, r13
    ja      .sg_next

    cmp     r9, DICT_SUGGEST_MAX_LEN
    ja      .sg_next

    mov     r8d, [dict_offsets + rax*4]
    lea     r8, [dict_blob + r8]            ; word_ptr

    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r8
    mov     rcx, r9
    call    _dict_edit_distance

    cmp     rax, r13
    ja      .sg_next

    ; candidate accepted — reload word_ptr/word_len/idx (call clobbered them)
    mov     r10, rax                          ; distance
    mov     rax, [rsp + 16]                    ; idx
    movzx   r9, byte [dict_lengths + rax]       ; wlen
    mov     r8d, [dict_offsets + rax*4]
    lea     r8, [dict_blob + r8]                ; word_ptr

    mov     rax, [rsp + 8]                       ; current_count
    cmp     rax, r15
    jb      .sg_ins_room

    ; full: only replace if strictly better than current worst
    mov     rdx, r15
    dec     rdx
    imul    rdx, rdx, DICTMATCH_SIZE
    add     rdx, r14
    mov     rax, [rdx + DictMatch.distance]
    cmp     r10, rax
    jae     .sg_next

    mov     rcx, r15
    dec     rcx                                  ; p = max_results - 1
    jmp     .sg_ins_shift

.sg_ins_room:
    mov     rcx, rax                              ; p = current_count

.sg_ins_shift:
    test    rcx, rcx
    jz      .sg_ins_place

    mov     rdx, rcx
    dec     rdx
    imul    rdx, rdx, DICTMATCH_SIZE
    add     rdx, r14                              ; &out_matches[p-1]
    mov     rax, [rdx + DictMatch.distance]
    cmp     rax, r10
    jbe     .sg_ins_place                          ; already <= candidate: stop

    imul    rsi, rcx, DICTMATCH_SIZE
    add     rsi, r14                                ; &out_matches[p]
    mov     rax, [rdx + DictMatch.ptr]
    mov     [rsi + DictMatch.ptr], rax
    mov     rax, [rdx + DictMatch.len]
    mov     [rsi + DictMatch.len], rax
    mov     rax, [rdx + DictMatch.distance]
    mov     [rsi + DictMatch.distance], rax

    dec     rcx
    jmp     .sg_ins_shift

.sg_ins_place:
    imul    rsi, rcx, DICTMATCH_SIZE
    add     rsi, r14
    mov     [rsi + DictMatch.ptr], r8
    mov     [rsi + DictMatch.len], r9
    mov     [rsi + DictMatch.distance], r10

    mov     rax, [rsp + 8]
    cmp     rax, r15
    jae     .sg_next                                 ; was already full: count unchanged
    inc     qword [rsp + 8]

.sg_next:
    inc     qword [rsp + 16]
    jmp     .sg_loop

.sg_loop_done:
    mov     rax, [rsp + 0]
    mov     rcx, [rsp + 8]
    mov     [rax], rcx

    test    rcx, rcx
    jnz     .sg_found

    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_NOT_FOUND

.sg_found:
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

STR_ENDFUNC str_dict_suggest

%endif ; GUARD_LIB_STR_DICT_SUGGEST_ASM
