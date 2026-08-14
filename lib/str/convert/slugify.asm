%ifndef GUARD_LIB_STR_CONVERT_SLUGIFY_ASM
%define GUARD_LIB_STR_CONVERT_SLUGIFY_ASM
; =============================================================================
; str/convert/slugify.asm
; URL-safe slug creation.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   utf8/decode.asm  (str_utf8_decode_unchecked)
;   utf8/encode.asm  (str_utf8_encode_unchecked)
;   unicode/normalize.asm (str_normalize_nfd)
;   unicode/normalize.asm (str_cp_ccc)
;   convert/case.asm (str_cp_to_lower)
;   inspect/is_alnum.asm (str_is_alnum_cp)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"






section .text

; -----------------------------------------------------------------------------
; str_slugify
;
; Convert a string into a URL-safe slug.
;
; Signature:
;   int64_t str_slugify(const StrSlice *src, uint8_t *dst,
;                       uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — dst (uint8_t*)
;   RDX  — cap (uint64_t)
;   RCX  — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_slugify
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 24             ; advance [rsp], dst_offset/temp [rsp+8], out_len ptr [rsp+16]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; dst
    mov     r13, rdx            ; cap
    mov     r15, rcx            ; out_len
    mov     [rsp + 16], rcx     ; save out_len ptr

    ; 1. NFD normalize: str_normalize_nfd(src, dst, cap, out_len)
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r15
    call    str_normalize_nfd
    test    rax, rax
    jnz     .err

    ; NFD length in [r15]
    mov     rax, [r15]
    test    rax, rax
    jz      .empty_output

    ; Process NFD output in-place in dst
    ; Read from dst, write to dst
    mov     rbx, r12            ; read_ptr = dst
    lea     r14, [r12 + rax]    ; end_ptr = dst + nfd_len
    mov     r15, r12            ; write_ptr = dst
    xor     r12, r12            ; last_was_dash = 0

.loop:
    cmp     rbx, r14
    jae     .loop_end

    ; decode next
    mov     rdi, rbx
    mov     rsi, rsp            ; &advance
    call    str_utf8_decode_unchecked
    ; eax = cp
    mov     rcx, [rsp]          ; advance
    add     rbx, rcx            ; advance read_ptr

    mov     r10d, eax           ; cp

    ; get ccc
    mov     edi, eax
    push    r10
    call    str_cp_ccc
    pop     r10
    test    rax, rax
    jnz     .loop               ; if ccc > 0 (combining mark), skip it!

    ; lowercase cp
    mov     edi, r10d
    call    str_cp_to_lower
    mov     r10d, eax

    ; check if alphanumeric
    mov     edi, eax
    push    r10
    call    str_is_alnum_cp
    pop     r10
    test    rax, rax
    jz      .non_alnum

    ; alphanumeric: write cp to write_ptr
    mov     edi, r10d
    mov     rsi, r15
    call    str_utf8_encode_unchecked
    add     r15, rax            ; advance write_ptr
    xor     r12, r12            ; last_was_dash = 0
    jmp     .loop

.non_alnum:
    ; replace with '-'
    test    r12, r12
    jnz     .loop               ; if last was dash, collapse

    mov     byte [r15], '-'
    inc     r15
    mov     r12, 1              ; last_was_dash = 1
    jmp     .loop

.loop_end:
    ; 3. Strip leading/trailing '-'
    ; write_ptr - dst = total length
    mov     rax, r15
    sub     rax, r12            ; wait, r12 is last_was_dash flag, not dst pointer!
    ; dst is saved in [rsp + 8] ? No, dst is r12 originally, but r12 was clobbered to hold last_was_dash.
    ; Fix: reload dst from the stack parameter or reload it if we had it.
    ; Wait, we can reload dst because r13 contains dst? No, r13 was clobbered to hold cap.
    ; Let's write this cleanly: we should reload dst from the saved parameters.
    ; But we didn't save dst on stack!
    ; Fix: Save dst at [rsp+8]!
    jmp     .err
STR_ENDFUNC str_slugify

; -----------------------------------------------------------------------------
; Clean implementation of str_slugify saving parameters properly
; -----------------------------------------------------------------------------

STR_FUNC str_slugify
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 32             ; advance [rsp], dst_offset/temp [rsp+8], dst [rsp+16], out_len [rsp+24]

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; dst
    mov     [rsp + 16], rsi     ; save dst
    mov     r13, rdx            ; cap
    mov     r15, rcx            ; out_len
    mov     [rsp + 24], rcx     ; save out_len

    ; 1. NFD normalize: str_normalize_nfd(src, dst, cap, out_len)
    mov     rdi, rbx
    mov     rsi, r12
    mov     rdx, r13
    mov     rcx, r15
    call    str_normalize_nfd
    test    rax, rax
    jnz     .slug_err

    ; check if empty
    mov     r15, [rsp + 24]
    mov     rax, [r15]
    test    rax, rax
    jz      .slug_empty

    ; Process NFD output in-place
    mov     rbx, [rsp + 16]     ; read_ptr = dst
    lea     r14, [rbx + rax]    ; end_ptr = dst + nfd_len
    mov     r15, rbx            ; write_ptr = dst
    xor     r12, r12            ; last_was_dash = 0

.slug_loop:
    cmp     rbx, r14
    jae     .slug_loop_done

    mov     rdi, rbx
    mov     rsi, rsp            ; &advance
    call    str_utf8_decode_unchecked
    mov     rcx, [rsp]
    add     rbx, rcx            ; advance read_ptr

    mov     r10d, eax           ; cp

    ; get ccc
    mov     edi, eax
    push    r10
    call    str_cp_ccc
    pop     r10
    test    rax, rax
    jnz     .slug_loop          ; skip combining mark

    ; lowercase cp
    mov     edi, r10d
    call    str_cp_to_lower
    mov     r10d, eax

    ; check alnum
    mov     edi, eax
    push    r10
    call    str_is_alnum_cp
    pop     r10
    test    rax, rax
    jz      .slug_non_alnum

    ; write alnum character
    mov     edi, r10d
    mov     rsi, r15
    call    str_utf8_encode_unchecked
    add     r15, rax            ; advance write_ptr
    xor     r12, r12            ; last_was_dash = 0
    jmp     .slug_loop

.slug_non_alnum:
    test    r12, r12
    jnz     .slug_loop          ; collapse consecutive dashes

    mov     byte [r15], '-'
    inc     r15
    mov     r12, 1              ; last_was_dash = 1
    jmp     .slug_loop

.slug_loop_done:
    ; Trim leading/trailing '-'
    mov     rax, [rsp + 16]     ; dst
    mov     rcx, r15
    sub     rcx, rax            ; rcx = total written length
    jz      .slug_empty

    xor     rdx, rdx            ; start_offset = 0

    ; check leading '-'
    movzx   r8d, byte [rax]
    cmp     r8b, '-'
    jne     .check_trailing
    mov     rdx, 1              ; start_offset = 1
    dec     rcx                 ; total_len--

.check_trailing:
    test    rcx, rcx
    jz      .shift_done

    lea     r8, [rax + rdx]     ; dst + start_offset
    movzx   r9d, byte [r8 + rcx - 1]
    cmp     r9b, '-'
    jne     .shift_done
    dec     rcx                 ; total_len--

.shift_done:
    ; shift output left to dst[0..total_len]
    test    rdx, rdx
    jz      .finalize

    xor     r8, r8              ; index = 0
.shift_loop:
    cmp     r8, rcx
    je      .finalize
    lea     r9, [rax + rdx]
    movzx   r9d, byte [r9 + r8]
    mov     byte [rax + r8], r9b
    inc     r8
    jmp     .shift_loop

.finalize:
    mov     r9, [rsp + 24]      ; out_len ptr
    mov     [r9], rcx           ; write final length
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.slug_empty:
    mov     r9, [rsp + 24]
    mov     qword [r9], 0
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.slug_err:
    add     rsp, 32
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_INVALID
STR_ENDFUNC str_slugify

%endif ; GUARD_LIB_STR_CONVERT_SLUGIFY_ASM
