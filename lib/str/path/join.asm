%ifndef GUARD_LIB_STR_PATH_JOIN_ASM
%define GUARD_LIB_STR_PATH_JOIN_ASM
; =============================================================================
; str/path/join.asm
; Join path segments with the path separator '/'.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Path joining rules:
;   - If the right segment is absolute (starts with /), it replaces the left
;   - Otherwise: left + '/' + right (with dedup of trailing/leading slashes)
;   - Empty segments are skipped
;
; Functions:
;   str_path_join       — join two path segments
;   str_path_join_many  — join an array of segments
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

PATH_SEP    equ '/'

section .text

; -----------------------------------------------------------------------------
; str_path_join
;
; Join two path segments: left / right.
;
; Signature:
;   int64_t str_path_join(const StrSlice *left, const StrSlice *right,
;                          uint8_t *dst, uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — left segment
;   RSI  — right segment
;   RDX  — destination buffer
;   RCX  — capacity
;   R8   — out_len (may be null)
; -----------------------------------------------------------------------------

STR_FUNC str_path_join

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; left
    mov     r12, rsi            ; right
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out_len

    xor     r9, r9              ; dst offset

    ; check if right is absolute
    mov     rax, [r12 + StrSlice.len]
    test    rax, rax
    jz      .pj_left_only       ; right is empty → just copy left

    mov     rsi, [r12 + StrSlice.ptr]
    movzx   eax, byte [rsi]
    cmp     al, PATH_SEP
    je      .pj_right_only      ; right is absolute → replaces left

    ; check if left is empty
    mov     rax, [rbx + StrSlice.len]
    test    rax, rax
    jz      .pj_right_only      ; left empty → just copy right

    ; copy left
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]

.pj_copy_left:
    test    rcx, rcx
    jz      .pj_check_sep

    cmp     r9, r14
    jae     .pj_overflow

    movzx   eax, byte [rsi]
    mov     [r13 + r9], al
    inc     rsi
    inc     r9
    dec     rcx
    jmp     .pj_copy_left

.pj_check_sep:
    ; strip trailing slashes from left
.pj_strip_trailing:
    test    r9, r9
    jz      .pj_add_sep

    movzx   eax, byte [r13 + r9 - 1]
    cmp     al, PATH_SEP
    jne     .pj_add_sep
    dec     r9
    jmp     .pj_strip_trailing

.pj_add_sep:
    ; add separator (only if left was non-empty after stripping)
    test    r9, r9
    jz      .pj_copy_right      ; left was all slashes or empty

    cmp     r9, r14
    jae     .pj_overflow

    mov     byte [r13 + r9], PATH_SEP
    inc     r9

.pj_copy_right:
    ; skip leading slashes in right
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rcx, [r12 + StrSlice.len]

.pj_skip_leading:
    test    rcx, rcx
    jz      .pj_done

    movzx   eax, byte [rsi]
    cmp     al, PATH_SEP
    jne     .pj_copy_right_bytes
    inc     rsi
    dec     rcx
    jmp     .pj_skip_leading

.pj_copy_right_bytes:
    test    rcx, rcx
    jz      .pj_done

    cmp     r9, r14
    jae     .pj_overflow

    movzx   eax, byte [rsi]
    mov     [r13 + r9], al
    inc     rsi
    inc     r9
    dec     rcx
    jmp     .pj_copy_right_bytes

.pj_left_only:
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]
    jmp     .pj_copy_segment

.pj_right_only:
    mov     rsi, [r12 + StrSlice.ptr]
    mov     rcx, [r12 + StrSlice.len]

.pj_copy_segment:
    test    rcx, rcx
    jz      .pj_done

    cmp     r9, r14
    jae     .pj_overflow

    movzx   eax, byte [rsi]
    mov     [r13 + r9], al
    inc     rsi
    inc     r9
    dec     rcx
    jmp     .pj_copy_segment

.pj_done:
    test    r15, r15
    jz      .pj_ok
    mov     [r15], r9

.pj_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pj_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_path_join

; -----------------------------------------------------------------------------
; str_path_join_many
;
; Join an array of path segments sequentially.
;
; Signature:
;   int64_t str_path_join_many(const StrSlice *parts, uint64_t count,
;                               uint8_t *dst, uint64_t dst_cap,
;                               uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_path_join_many

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; parts array
    mov     r12, rsi            ; count
    mov     r13, rdx            ; dst
    mov     r14, rcx            ; cap
    mov     r15, r8             ; out_len

    ; start with empty result
    xor     r9, r9              ; result length = 0
    xor     r10, r10            ; part index

    ; if no parts: result is empty
    test    r12, r12
    jz      .pjm_done

    ; copy first part directly
    mov     rsi, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]

.pjm_first:
    test    rcx, rcx
    jz      .pjm_loop_start

    cmp     r9, r14
    jae     .pjm_overflow

    movzx   eax, byte [rsi]
    mov     [r13 + r9], al
    inc     rsi
    inc     r9
    dec     rcx
    jmp     .pjm_first

.pjm_loop_start:
    mov     r10, 1

.pjm_loop:
    cmp     r10, r12
    jae     .pjm_done

    ; join current result [r13, r9) with parts[r10]
    ; use a temp StrSlice for the current result
    sub     rsp, STRSLICE_SIZE * 2 + 16
    and     rsp, -16

    ; left = current result
    mov     [rsp + StrSlice.ptr], r13
    mov     [rsp + StrSlice.len], r9

    ; right = parts[r10]
    mov     rax, r10
    imul    rax, STRSLICE_SIZE
    mov     rcx, [rbx + rax + StrSlice.ptr]
    mov     rdx, [rbx + rax + StrSlice.len]
    mov     [rsp + STRSLICE_SIZE + StrSlice.ptr], rcx
    mov     [rsp + STRSLICE_SIZE + StrSlice.len], rdx

    ; we need a separate temp buffer to avoid overlap
    ; for simplicity: join in-place since left IS the dst
    ; this works because str_path_join reads left fully before writing
    lea     rdi, [rsp]
    lea     rsi, [rsp + STRSLICE_SIZE]
    mov     rdx, r13
    mov     rcx, r14
    lea     r8, [rsp + STRSLICE_SIZE * 2]
    push    r10
    push    r12
    call    str_path_join
    pop     r12
    pop     r10

    test    rax, rax
    jnz     .pjm_err

    mov     r9, [rsp + STRSLICE_SIZE * 2]   ; updated length
    mov     rsp, rbp

    inc     r10
    jmp     .pjm_loop

.pjm_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    pop     rbp
    ret

.pjm_done:
    test    r15, r15
    jz      .pjm_ok
    mov     [r15], r9

.pjm_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pjm_overflow:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_path_join_many
%endif ; GUARD_LIB_STR_PATH_JOIN_ASM
