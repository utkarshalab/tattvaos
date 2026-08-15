%ifndef GUARD_LIB_STR_DICT_LOOKUP_ASM
%define GUARD_LIB_STR_DICT_LOOKUP_ASM
; =============================================================================
; str/dict/lookup.asm
; Exact membership lookup and indexed access into the default English
; dictionary.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   dict/dict.inc
;   dict/tables/dict_table.asm   (dict_word_count, dict_offsets, dict_lengths,
;                                  dict_blob — generated, %include'd by whoever
;                                  assembles this unit; no `extern` needed,
;                                  the whole kernel is one translation unit)
;
; -----------------------------------------------------------------------------
; The table is sorted ascending by the UTF-8 byte sequence of each word, so
; exact lookup is a plain binary search — O(log N) over ~348K entries is at
; most ~19 comparisons, each a short byte-wise compare. No allocation, no
; init step: dict_word_lookup_at (below) reads straight out of .rodata.
;
; Functions:
;   str_dict_word_count   — total number of words in the dictionary
;   str_dict_lookup       — exact membership test
;   str_dict_get          — fetch word bytes/length by sorted index
; =============================================================================

%include "lib/str/arch/common/types.inc"
%include "lib/str/arch/common/error.inc"
%include "lib/str/arch/common/macros.inc"
%include "lib/str/dict/dict.inc"

section .text

; -----------------------------------------------------------------------------
; _dict_cmp_at (internal)
;
; Compare dictionary word at a sorted index against an arbitrary key.
; Shared by lookup.asm's binary search and prefix.asm's range search.
;
; Inputs:
;   RDI = index          (0 <= index < dict_word_count, caller's responsibility)
;   RSI = key_ptr
;   RDX = key_len
;
; Returns:
;   RAX = -1  word[index] <  key
;   RAX =  0  word[index] == key
;   RAX =  1  word[index] >  key
;
; Clobbers: RAX, RCX, RDX, RSI only (no stack frame — this is a leaf helper).
; -----------------------------------------------------------------------------

_dict_cmp_at:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r13, rsi                        ; key_ptr
    mov     r14, rdx                        ; key_len

    mov     eax, [dict_offsets + rdi*4]     ; word offset (zero-extended)
    mov     rbx, rax
    movzx   r12, byte [dict_lengths + rdi]  ; word_len
    lea     rbx, [dict_blob + rbx]          ; word_ptr

    mov     rax, r12
    cmp     rax, r14
    jbe     .use_word_len
    mov     rax, r14
.use_word_len:
    ; RAX = min(word_len, key_len)

    xor     rcx, rcx
.byte_loop:
    cmp     rcx, rax
    jae     .prefix_equal

    movzx   edx, byte [rbx + rcx]
    movzx   esi, byte [r13 + rcx]
    cmp     edx, esi
    jl      .less
    jg      .greater
    inc     rcx
    jmp     .byte_loop

.prefix_equal:
    cmp     r12, r14
    jl      .less
    jg      .greater
    xor     eax, eax
    jmp     .done

.less:
    mov     eax, -1
    jmp     .done

.greater:
    mov     eax, 1

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; str_dict_word_count
;
; Signature:
;   uint64_t str_dict_word_count(void)
; -----------------------------------------------------------------------------

STR_FUNC str_dict_word_count
    mov     eax, [dict_word_count]
STR_ENDFUNC str_dict_word_count

; -----------------------------------------------------------------------------
; str_dict_lookup
;
; Exact membership test: is this UTF-8 word in the dictionary?
;
; Signature:
;   int64_t str_dict_lookup(const StrSlice *word)
;
; Returns:
;   RAX = STR_OK             found
;   RAX = STR_ERR_NOT_FOUND  not in the dictionary
;   RAX = STR_ERR_NULL       word is NULL
; -----------------------------------------------------------------------------

STR_FUNC str_dict_lookup
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     r12, [rdi + StrSlice.ptr]
    mov     r13, [rdi + StrSlice.len]

    xor     r14, r14                  ; lo = 0
    mov     r15d, [dict_word_count]   ; hi = count

.bs_loop:
    cmp     r14, r15
    jae     .bs_not_found

    mov     rbx, r14
    add     rbx, r15
    shr     rbx, 1                    ; mid = (lo + hi) / 2

    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    call    _dict_cmp_at

    cmp     eax, 0
    je      .bs_found
    jl      .bs_right                 ; word[mid] < key -> lo = mid + 1

    mov     r15, rbx                  ; word[mid] > key -> hi = mid
    jmp     .bs_loop

.bs_right:
    lea     r14, [rbx + 1]
    jmp     .bs_loop

.bs_found:
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.bs_not_found:
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_NOT_FOUND

STR_ENDFUNC str_dict_lookup

; -----------------------------------------------------------------------------
; str_dict_get
;
; Fetch the word at a sorted dictionary index. Combine with
; str_dict_prefix_range (prefix.asm) to enumerate autocomplete candidates,
; or with str_dict_word_count to walk the whole table.
;
; Signature:
;   int64_t str_dict_get(uint64_t index, DictMatch *out)
;
; Returns:
;   RAX = STR_OK                 out filled in (out->distance = 0)
;   RAX = STR_ERR_NULL           out is NULL
;   RAX = STR_ERR_OUT_OF_BOUNDS  index >= str_dict_word_count()
; -----------------------------------------------------------------------------

STR_FUNC str_dict_get
    guard_null rsi, STR_ERR_NULL

    mov     eax, [dict_word_count]
    cmp     rdi, rax
    jb      .get_in_bounds
    ret_err STR_ERR_OUT_OF_BOUNDS

.get_in_bounds:
    push    rbx

    mov     ebx, [dict_offsets + rdi*4]
    lea     rax, [dict_blob + rbx]
    mov     [rsi + DictMatch.ptr], rax

    movzx   ecx, byte [dict_lengths + rdi]
    mov     [rsi + DictMatch.len], rcx
    mov     qword [rsi + DictMatch.distance], 0

    pop     rbx
    ret_ok

STR_ENDFUNC str_dict_get

%endif ; GUARD_LIB_STR_DICT_LOOKUP_ASM
