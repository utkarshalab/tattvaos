; =============================================================================
; str/pattern/regex.asm
; High-level regex API — compile once, execute many times.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   pattern/regex_compile.asm  (str_regex_compile)
;   pattern/regex_exec.asm     (str_regex_exec, str_regex_find)
;   mem/arena.asm              (str_arena_alloc, str_arena_init)
;   core/copy.asm              (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; High-level API:
;
;   Regex *regex = str_regex_new(pattern, arena)
;   if regex == null: pattern invalid
;
;   int match = str_regex_test(regex, input)  → 1 or 0
;   int found = str_regex_find_first(regex, input, *match_start, *match_len)
;   int count = str_regex_count(regex, input) → number of matches
;   int n     = str_regex_split(regex, input, out_slices, max_parts)
;   str       = str_regex_replace(regex, input, replacement, dst, cap)
;
; Regex struct (opaque, arena-allocated):
;   program   RegexProgram   — compiled NFA
;   pattern   StrSlice       — original pattern (for display)
;   flags     uint64_t       — match flags
;
; Functions:
;   str_regex_new             — compile pattern
;   str_regex_test            — test match (bool)
;   str_regex_find_first      — find first match position
;   str_regex_count           — count all non-overlapping matches
;   str_regex_split           — split string on pattern
;   str_regex_replace_first   — replace first match
;   str_regex_replace_all     — replace all matches
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_regex_compile
extern str_regex_exec
extern str_arena_alloc
extern str_copy_bytes

; Regex struct layout
struc Regex
    .code       resq 1      ; bytecode pointer
    .code_len   resq 1
    .nsave      resq 1
    .pattern    resq 2      ; StrSlice (ptr + len)
    .flags      resq 1
endstruc

REGEX_SIZE  equ 48

; Regex flags
REGEX_ICASE equ 0x01        ; case-insensitive
REGEX_MULTI equ 0x02        ; multiline (^ and $ match line breaks)

section .text

; -----------------------------------------------------------------------------
; str_regex_new
;
; Compile a regex pattern. Returns pointer to allocated Regex struct,
; or null on failure.
;
; Signature:
;   Regex *str_regex_new(const StrSlice *pattern, StrArena *arena,
;                         uint64_t flags)
;
; Arguments:
;   RDI  — pattern StrSlice
;   RSI  — arena for all allocations
;   RDX  — flags (REGEX_ICASE, REGEX_MULTI)
;
; Returns:
;   RAX  — pointer to Regex, or null on error
; -----------------------------------------------------------------------------

STR_FUNC str_regex_new

    test    rdi, rdi
    jz      .rn_null
    test    rsi, rsi
    jz      .rn_null

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi            ; pattern
    mov     r12, rsi            ; arena
    mov     r13, rdx            ; flags

    ; allocate Regex struct
    mov     rdi, r12
    mov     rsi, REGEX_SIZE
    mov     rdx, 8
    call    str_arena_alloc
    test    rax, rax
    jz      .rn_oom

    mov     r14, rax            ; regex struct

    ; compile pattern into struct
    mov     rdi, rbx
    mov     rsi, r12

    ; compile into a temp RegexProgram, then copy fields
    sub     rsp, REGEXPROG_SIZE + 16
    and     rsp, -16

    lea     rdx, [rsp]
    call    str_regex_compile
    test    rax, rax
    jnz     .rn_compile_err

    ; copy RegexProgram fields into Regex struct
    mov     rax, [rsp + RegexProgram.code]
    mov     [r14 + Regex.code], rax

    mov     rax, [rsp + RegexProgram.code_len]
    mov     [r14 + Regex.code_len], rax

    mov     rax, [rsp + RegexProgram.nsave]
    mov     [r14 + Regex.nsave], rax

    ; store pattern slice
    mov     rax, [rbx + StrSlice.ptr]
    mov     [r14 + Regex.pattern], rax
    mov     rax, [rbx + StrSlice.len]
    mov     [r14 + Regex.pattern + 8], rax

    ; store flags
    mov     [r14 + Regex.flags], r13

    mov     rsp, rbp
    mov     rax, r14

    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.rn_compile_err:
    mov     rsp, rbp
    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.rn_oom:
    pop_regs r14, r13, r12, rbx
.rn_null:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_regex_new

; -----------------------------------------------------------------------------
; str_regex_test
;
; Test if a pattern matches (anywhere in) the input.
;
; Signature:
;   int64_t str_regex_test(const Regex *regex, const StrSlice *input)
;
; Returns:
;   RAX  = 1  match
;   RAX  = 0  no match
; -----------------------------------------------------------------------------

STR_FUNC str_regex_test

    test    rdi, rdi
    jz      .rt_no_match
    test    rsi, rsi
    jz      .rt_no_match

    push_regs rbx, r12

    mov     rbx, rdi            ; regex
    mov     r12, rsi            ; input

    ; build a fake RegexProgram on stack from Regex struct
    sub     rsp, REGEXPROG_SIZE + 16
    and     rsp, -16

    mov     rax, [rbx + Regex.code]
    mov     [rsp + RegexProgram.code], rax
    mov     rax, [rbx + Regex.code_len]
    mov     [rsp + RegexProgram.code_len], rax
    mov     rax, [rbx + Regex.nsave]
    mov     [rsp + RegexProgram.nsave], rax

    lea     rdi, [rsp]
    mov     rsi, r12
    xor     edx, edx            ; no out_start
    xor     ecx, ecx            ; no out_len
    call    str_regex_exec

    mov     rsp, rbp
    pop_regs r12, rbx
    pop     rbp
    ret

.rt_no_match:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_regex_test

; -----------------------------------------------------------------------------
; str_regex_find_first
;
; Find first match of compiled regex in input.
;
; Signature:
;   int64_t str_regex_find_first(const Regex *regex, const StrSlice *input,
;                                 uint64_t *out_start, uint64_t *out_len)
;
; Returns:
;   RAX  = 1  match found (positions written)
;   RAX  = 0  no match
; -----------------------------------------------------------------------------

STR_FUNC str_regex_find_first

    test    rdi, rdi
    jz      .rff_no

    push_regs rbx, r12, r13, r14

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx            ; out_start
    mov     r14, rcx            ; out_len

    sub     rsp, REGEXPROG_SIZE + 16
    and     rsp, -16

    mov     rax, [rbx + Regex.code]
    mov     [rsp + RegexProgram.code], rax
    mov     rax, [rbx + Regex.code_len]
    mov     [rsp + RegexProgram.code_len], rax
    mov     rax, [rbx + Regex.nsave]
    mov     [rsp + RegexProgram.nsave], rax

    lea     rdi, [rsp]
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r14
    call    str_regex_exec

    mov     rsp, rbp
    pop_regs r14, r13, r12, rbx
    pop     rbp
    ret

.rff_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_regex_find_first

; -----------------------------------------------------------------------------
; str_regex_count
;
; Count non-overlapping matches in input.
;
; Signature:
;   uint64_t str_regex_count(const Regex *regex, const StrSlice *input)
; -----------------------------------------------------------------------------

STR_FUNC str_regex_count

    test    rdi, rdi
    jz      .rcount_zero
    test    rsi, rsi
    jz      .rcount_zero

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; regex
    mov     r12, [rsi + StrSlice.ptr]   ; input ptr
    mov     r13, [rsi + StrSlice.len]   ; input len

    xor     r14, r14            ; count
    xor     r15, r15            ; current position

.rc_count_loop:
    cmp     r15, r13
    jae     .rc_count_done

    ; build sub-slice from r15
    sub     rsp, STRSLICE_SIZE + REGEXPROG_SIZE + 16
    and     rsp, -16

    lea     rax, [r12 + r15]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r13
    sub     rax, r15
    mov     [rsp + StrSlice.len], rax

    ; build RegexProgram
    lea     rdx, [rsp + STRSLICE_SIZE]
    mov     rax, [rbx + Regex.code]
    mov     [rdx + RegexProgram.code], rax
    mov     rax, [rbx + Regex.code_len]
    mov     [rdx + RegexProgram.code_len], rax
    mov     rax, [rbx + Regex.nsave]
    mov     [rdx + RegexProgram.nsave], rax

    lea     rdi, [rsp + STRSLICE_SIZE]  ; prog
    lea     rsi, [rsp]                  ; input slice
    lea     rdx, [rsp + STRSLICE_SIZE + REGEXPROG_SIZE]      ; start
    lea     rcx, [rsp + STRSLICE_SIZE + REGEXPROG_SIZE + 8]  ; len
    call    str_regex_exec
    ; rax = 1 if match

    test    rax, rax
    jz      .rc_no_match_here

    ; got a match
    mov     rax, [rsp + STRSLICE_SIZE + REGEXPROG_SIZE + 8]  ; match len
    inc     r14                 ; count++
    add     r15, rax            ; advance past match
    test    rax, rax
    jz      .rc_advance_one     ; zero-length match: advance by 1
    jmp     .rc_next

.rc_no_match_here:
    ; no match at this position — advance
    add     r15, 1

.rc_advance_one:
.rc_next:
    mov     rsp, rbp
    sub     rsp, 0              ; restore frame
    ; actually rsp is restored via rbp via mov rsp,rbp
    jmp     .rc_count_loop

.rc_count_done:
    mov     rax, r14
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.rcount_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_regex_count

; -----------------------------------------------------------------------------
; str_regex_split
;
; Split input on regex matches. Returns array of StrSlice pieces.
;
; Signature:
;   int64_t str_regex_split(const Regex *regex, const StrSlice *input,
;                            StrSlice *out_parts, uint64_t max_parts,
;                            uint64_t *out_count)
; -----------------------------------------------------------------------------

STR_FUNC str_regex_split

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; regex
    mov     r12, rsi            ; input
    mov     r13, rdx            ; out_parts
    mov     r14, rcx            ; max_parts
    mov     r15, r8             ; out_count

    xor     r9, r9              ; part count
    xor     r10, r10            ; current input position

    mov     r11, [r12 + StrSlice.ptr]   ; input base
    mov     rax, [r12 + StrSlice.len]   ; input len

.rs_split_loop:
    cmp     r9, r14
    jae     .rs_split_done

    cmp     r10, rax
    jae     .rs_split_flush

    ; find next match from r10
    sub     rsp, STRSLICE_SIZE + REGEXPROG_SIZE + 24
    and     rsp, -16

    lea     rcx, [r11 + r10]
    mov     [rsp + StrSlice.ptr], rcx
    mov     rcx, rax
    sub     rcx, r10
    mov     [rsp + StrSlice.len], rcx

    lea     rcx, [rsp + STRSLICE_SIZE]
    mov     rdx, [rbx + Regex.code]
    mov     [rcx + RegexProgram.code], rdx
    mov     rdx, [rbx + Regex.code_len]
    mov     [rcx + RegexProgram.code_len], rdx
    mov     rdx, [rbx + Regex.nsave]
    mov     [rcx + RegexProgram.nsave], rdx

    lea     rdi, [rsp + STRSLICE_SIZE]
    lea     rsi, [rsp]
    lea     rdx, [rsp + STRSLICE_SIZE + REGEXPROG_SIZE]
    lea     rcx, [rsp + STRSLICE_SIZE + REGEXPROG_SIZE + 8]
    call    str_regex_exec

    test    rax, rax
    jz      .rs_no_more_matches

    ; match found
    mov     rdx, [rsp + STRSLICE_SIZE + REGEXPROG_SIZE]     ; match_start (relative)
    mov     rcx, [rsp + STRSLICE_SIZE + REGEXPROG_SIZE + 8] ; match_len

    mov     rsp, rbp
    sub     rsp, 0

    ; emit segment before match
    lea     rax, [r11 + r10]
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.ptr], rax
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.len], rdx
    inc     r9

    ; advance past match
    add     r10, rdx
    add     r10, rcx
    test    rcx, rcx
    jnz     .rs_split_loop
    inc     r10                 ; avoid infinite loop on zero-length match
    jmp     .rs_split_loop

.rs_no_more_matches:
    mov     rsp, rbp
    sub     rsp, 0

.rs_split_flush:
    ; emit remainder
    cmp     r9, r14
    jae     .rs_split_done

    lea     rax, [r11 + r10]
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.ptr], rax
    mov     rax, [r12 + StrSlice.len]
    sub     rax, r10
    mov     [r13 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9

.rs_split_done:
    test    r15, r15
    jz      .rs_ok
    mov     [r15], r9

.rs_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_regex_split