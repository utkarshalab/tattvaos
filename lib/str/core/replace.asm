%ifndef GUARD_LIB_STR_CORE_REPLACE_ASM
%define GUARD_LIB_STR_CORE_REPLACE_ASM
; =============================================================================
; str/core/replace.asm
; String replacement functions.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   search/find.asm (str_find_from)
;   core/copy.asm   (str_copy_bytes)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"


section .text

; -----------------------------------------------------------------------------
; str_replace
;
; Replace the first occurrence of `old` with `new` in `src`.
;
; Signature:
;   int64_t str_replace(const StrSlice *src, const StrSlice *old_s,
;                       const StrSlice *new_s, uint8_t *dst,
;                       uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_replace
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    ; Forward to str_replace_n with max_count = 1
    ; Need to adjust arguments for str_replace_n:
    ; RDI = src
    ; RSI = old_s
    ; RDX = new_s
    ; RCX = max_count (1)
    ; R8  = dst
    ; R9  = cap
    ; stack[0] = out_len
    push    r9                  ; out_len (6th arg in str_replace, becomes 7th in str_replace_n)
    mov     r9, r8              ; cap
    mov     r8, rcx              ; dst
    mov     rcx, 1              ; max_count = 1
    call    str_replace_n
    add     rsp, 8              ; clean up stack parameter
    ret
STR_ENDFUNC str_replace

; -----------------------------------------------------------------------------
; str_replace_all
;
; Replace all occurrences of `old` with `new` in `src`.
;
; Signature:
;   int64_t str_replace_all(const StrSlice *src, const StrSlice *old_s,
;                           const StrSlice *new_s, uint8_t *dst,
;                           uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_replace_all
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    ; Forward to str_replace_n with max_count = -1 (unlimited)
    push    r9                  ; out_len
    mov     r9, r8              ; cap
    mov     r8, rcx              ; dst
    mov     rcx, -1             ; max_count = unlimited
    call    str_replace_n
    add     rsp, 8
    ret
STR_ENDFUNC str_replace_all

; -----------------------------------------------------------------------------
; str_replace_n
;
; Replace up to `max_count` occurrences of `old` with `new` in `src`.
;
; Signature:
;   int64_t str_replace_n(const StrSlice *src, const StrSlice *old_s,
;                         const StrSlice *new_s, uint64_t max_count,
;                         uint8_t *dst, uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_replace_n
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    ; Retrieve out_len from stack
    mov     rax, [rsp + 8]      ; Return address is at [rsp], stack param at [rsp+8]
    guard_null rax, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 40             ; keep 16-byte stack alignment

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; old
    mov     r13, rdx            ; new
    mov     r14, rcx            ; max_count
    mov     r15, r8             ; dst

    ; Save cap and out_len in stack slots
    mov     [rsp + 32], r9      ; cap
    mov     rax, [rbp + 16]     ; retrieve stack parameter out_len (above pushed RBP + return address)
    mov     [rsp + 24], rax     ; out_len

    ; Initialize loop states
    mov     qword [rsp + 16], 0 ; current_src_offset = 0
    mov     qword [rsp + 8], 0  ; current_dst_offset = 0
    mov     qword [rsp + 0], 0  ; replacements_done = 0

    ; Guard: if old.len == 0, return STR_ERR_INVALID to prevent infinite loops
    mov     rax, [r12 + StrSlice.len]
    test    rax, rax
    jz      .invalid_arg

.loop:
    ; 1. check if current_src_offset >= src.len
    mov     rax, [rsp + 16]     ; current_src_offset
    cmp     rax, [rbx + StrSlice.len]
    jae     .done

    ; 2. check if replacements_done == max_count
    mov     rax, [rsp + 0]      ; replacements_done
    cmp     rax, r14
    je      .done

    ; 3. find next match: str_find_from(src, old, current_src_offset)
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, [rsp + 16]     ; current_src_offset
    call    str_find_from
    ; rax = match_offset or STR_ERR_NOT_FOUND (negative)
    test    rax, rax
    js      .done

    ; Found match at match_offset (rax)
    mov     rcx, rax            ; match_offset
    mov     rdx, [rsp + 16]     ; current_src_offset
    sub     rcx, rdx            ; prefix_len = match_offset - current_src_offset

    ; Check if prefix fits in dst
    mov     rdi, [rsp + 8]      ; current_dst_offset
    add     rdi, rcx            ; projected_dst_len
    cmp     rdi, [rsp + 32]     ; cap
    ja      .too_small

    ; Copy prefix to dst
    test    rcx, rcx
    jz      .prefix_copied
    mov     rdi, r15
    add     rdi, [rsp + 8]      ; dst + current_dst_offset
    mov     rsi, [rbx + StrSlice.ptr]
    add     rsi, [rsp + 16]     ; src + current_src_offset
    mov     rdx, rcx            ; prefix_len
    call    str_copy_bytes
    test    rax, rax
    js      .err

.prefix_copied:
    ; Advance offsets by prefix_len
    add     [rsp + 16], rcx     ; current_src_offset += prefix_len
    add     [rsp + 8], rcx      ; current_dst_offset += prefix_len

    ; Check if new fits in dst
    mov     rcx, [r13 + StrSlice.len] ; new.len
    mov     rdi, [rsp + 8]
    add     rdi, rcx
    cmp     rdi, [rsp + 32]     ; cap
    ja      .too_small

    ; Copy new to dst
    test    rcx, rcx
    jz      .new_copied
    mov     rdi, r15
    add     rdi, [rsp + 8]      ; dst + current_dst_offset
    mov     rsi, [r13 + StrSlice.ptr]
    mov     rdx, rcx            ; new.len
    call    str_copy_bytes
    test    rax, rax
    js      .err

.new_copied:
    ; Advance offsets
    add     [rsp + 8], rcx      ; current_dst_offset += new.len
    mov     rax, [r12 + StrSlice.len] ; old.len
    add     [rsp + 16], rax     ; current_src_offset += old.len

    inc     qword [rsp + 0]     ; replacements_done++
    jmp     .loop

.done:
    ; Copy remaining suffix: src[current_src_offset..src.len]
    mov     rcx, [rbx + StrSlice.len]
    sub     rcx, [rsp + 16]     ; suffix_len = src.len - current_src_offset

    mov     rdi, [rsp + 8]      ; current_dst_offset
    add     rdi, rcx            ; projected_dst_len
    cmp     rdi, [rsp + 32]     ; cap
    ja      .too_small

    test    rcx, rcx
    jz      .suffix_copied
    mov     rdi, r15
    add     rdi, [rsp + 8]
    mov     rsi, [rbx + StrSlice.ptr]
    add     rsi, [rsp + 16]
    mov     rdx, rcx
    call    str_copy_bytes
    test    rax, rax
    js      .err

.suffix_copied:
    add     [rsp + 8], rcx      ; current_dst_offset += suffix_len

    ; Write out_len
    mov     rax, [rsp + 24]     ; out_len ptr
    mov     rcx, [rsp + 8]      ; current_dst_offset
    mov     [rax], rcx

    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.invalid_arg:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID

.too_small:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL

.err:
    add     rsp, 40
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_replace_n

%endif ; GUARD_LIB_STR_CORE_REPLACE_ASM
