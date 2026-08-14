%ifndef GUARD_LIB_STR_PATTERN_REGEX_REPLACE_ASM
%define GUARD_LIB_STR_PATTERN_REGEX_REPLACE_ASM
; =============================================================================
; str/pattern/regex_replace.asm
; Regex find and replace.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   pattern/regex_compile.asm (str_regex_compile)
;   pattern/regex_exec.asm    (str_regex_exec)
;   mem/arena.asm             (str_arena_init)
;   core/copy.asm             (str_copy_bytes)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"




section .text

; -----------------------------------------------------------------------------
; str_regex_replace
;
; Find and replace using regular expressions.
;
; Signature:
;   int64_t str_regex_replace(const StrSlice *src, const StrSlice *pattern,
;                             const StrSlice *replacement, uint8_t *dst,
;                             uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — pattern (StrSlice*)
;   RDX  — replacement (StrSlice*)
;   RCX  — dst (uint8_t*)
;   R8   — cap (uint64_t)
;   R9   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_regex_replace
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    ; Local stack frame size:
    ;   [rsp + 0]    = RegexProgram (24 bytes)
    ;   [rsp + 24]   = StrArena (40 bytes)
    ;   [rsp + 64]   = backing buffer (4096 bytes)
    ;   [rsp + 4160] = match_start (8 bytes)
    ;   [rsp + 4168] = match_len (8 bytes)
    ;   [rsp + 4176] = temp_input.ptr (8 bytes)
    ;   [rsp + 4184] = temp_input.len (8 bytes)
    ;   [rsp + 4192] = dst_offset (8 bytes)
    ;   [rsp + 4200] = out_len ptr (8 bytes)
    ;   [rsp + 4208] = dst (8 bytes)
    ;   [rsp + 4216] = cap (8 bytes)
    ;   [rsp + 4224] = replacement (8 bytes)
    ; Total = 4232 bytes (keeps 16-byte alignment)
    sub     rsp, 4232

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; pattern
    mov     [rsp + 4224], rdx   ; replacement
    mov     [rsp + 4208], rcx   ; dst
    mov     [rsp + 4216], r8    ; cap
    mov     [rsp + 4200], r9    ; out_len ptr

    ; 1. Initialize StrArena on the stack
    lea     rdi, [rsp + 24]     ; arena pointer
    lea     rsi, [rsp + 64]     ; backing buffer
    mov     rdx, 4096           ; size
    call    str_arena_init
    test    rax, rax
    js      .compile_err

    ; 2. Compile RegexProgram
    mov     rdi, r12            ; pattern
    lea     rsi, [rsp + 24]     ; arena
    lea     rdx, [rsp + 0]      ; RegexProgram out
    call    str_regex_compile
    test    rax, rax
    jnz     .compile_err

    ; Initialize temp_input = *src
    mov     rax, [rbx + StrSlice.ptr]
    mov     [rsp + 4176], rax
    mov     rax, [rbx + StrSlice.len]
    mov     [rsp + 4184], rax

    mov     qword [rsp + 4192], 0 ; dst_offset = 0

.loop:
    mov     rax, [rsp + 4184]   ; temp_input.len
    test    rax, rax
    jz      .done

    ; Execute regex
    lea     rdi, [rsp + 0]      ; prog
    lea     rsi, [rsp + 4176]   ; temp_input
    lea     rdx, [rsp + 4160]   ; match_start
    lea     rcx, [rsp + 4168]   ; match_len
    call    str_regex_exec
    test    rax, rax
    jz      .no_match

    ; Match found
    mov     r12, [rsp + 4160]   ; start
    mov     r13, [rsp + 4168]   ; len

    ; copy prefix: temp_input.ptr (length start) to dst
    test    r12, r12
    jz      .prefix_done

    mov     rax, [rsp + 4192]   ; dst_offset
    add     rax, r12
    cmp     rax, [rsp + 4216]   ; cap check
    ja      .too_small

    mov     rdi, [rsp + 4208]   ; dst
    add     rdi, [rsp + 4192]
    mov     rsi, [rsp + 4176]   ; temp_input.ptr
    mov     rdx, r12
    call    str_copy_bytes
    add     [rsp + 4192], r12

.prefix_done:
    ; copy replacement with captures
    mov     r14, [rsp + 4224]   ; replacement StrSlice*
    mov     r15, [r14 + StrSlice.ptr]
    mov     r10, [r14 + StrSlice.len]
    xor     r11, r11            ; k = 0

.rep_loop:
    cmp     r11, r10
    je      .rep_done

    movzx   eax, byte [r15 + r11]
    cmp     al, '$'
    jne     .write_char

    ; check if next char exists
    lea     rcx, [r11 + 1]
    cmp     rcx, r10
    jae     .write_char

    movzx   edx, byte [r15 + rcx]
    cmp     dl, '0'
    je      .rep_match

    cmp     dl, '$'
    je      .rep_dollar

    cmp     dl, '1'
    jb      .write_char
    cmp     dl, '9'
    jbe     .rep_empty_cap

    jmp     .write_char

.rep_dollar:
    mov     rax, [rsp + 4192]
    cmp     rax, [rsp + 4216]
    jae     .too_small
    mov     rcx, [rsp + 4208]
    mov     byte [rcx + rax], '$'
    inc     qword [rsp + 4192]
    add     r11, 2
    jmp     .rep_loop

.rep_empty_cap:
    ; skip $1..$9 (acts as empty)
    add     r11, 2
    jmp     .rep_loop

.rep_match:
    ; copy full matched substring: temp_input.ptr + start (length len)
    test    r13, r13
    jz      .rep_match_done

    mov     rax, [rsp + 4192]
    add     rax, r13
    cmp     rax, [rsp + 4216]
    ja      .too_small

    mov     rdi, [rsp + 4208]
    add     rdi, [rsp + 4192]
    mov     rsi, [rsp + 4176]
    add     rsi, r12            ; temp_input.ptr + start
    mov     rdx, r13
    call    str_copy_bytes
    add     [rsp + 4192], r13

.rep_match_done:
    add     r11, 2
    jmp     .rep_loop

.write_char:
    mov     rax, [rsp + 4192]
    cmp     rax, [rsp + 4216]
    jae     .too_small
    mov     rcx, [rsp + 4208]
    mov     [rcx + rax], al
    inc     qword [rsp + 4192]
    inc     r11
    jmp     .rep_loop

.rep_done:
    ; advance temp_input
    test    r13, r13
    jz      .zero_len_advance

    mov     rax, r12
    add     rax, r13            ; start + len
    add     [rsp + 4176], rax   ; temp_input.ptr += start + len
    sub     [rsp + 4184], rax   ; temp_input.len -= start + len
    jmp     .loop

.zero_len_advance:
    ; zero length match: copy 1 skipped byte and advance by 1
    mov     rax, r12
    add     rax, 1
    cmp     rax, [rsp + 4184]
    ja      .zero_len_done

    mov     rsi, [rsp + 4176]
    movzx   edi, byte [rsi + r12]
    mov     rcx, [rsp + 4192]
    cmp     rcx, [rsp + 4216]
    jae     .too_small
    mov     rsi, [rsp + 4208]
    mov     [rsi + rcx], dil
    inc     qword [rsp + 4192]

.zero_len_done:
    mov     rax, r12
    inc     rax                 ; start + 1
    add     [rsp + 4176], rax
    sub     [rsp + 4184], rax
    jmp     .loop

.no_match:
    ; copy remaining temp_input to dst
    mov     rdx, [rsp + 4184]
    test    rdx, rdx
    jz      .done

    mov     rax, [rsp + 4192]
    add     rax, rdx
    cmp     rax, [rsp + 4216]
    ja      .too_small

    mov     rdi, [rsp + 4208]
    add     rdi, [rsp + 4192]
    mov     rsi, [rsp + 4176]
    call    str_copy_bytes
    add     [rsp + 4192], rdx

.done:
    mov     rax, [rsp + 4200]   ; out_len ptr
    mov     rcx, [rsp + 4192]   ; dst_offset
    mov     [rax], rcx

    add     rsp, 4232
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.compile_err:
    add     rsp, 4232
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID

.too_small:
    add     rsp, 4232
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_regex_replace

%endif ; GUARD_LIB_STR_PATTERN_REGEX_REPLACE_ASM
