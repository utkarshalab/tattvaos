%ifndef GUARD_LIB_STR_CORE_TRANSLATE_ASM
%define GUARD_LIB_STR_CORE_TRANSLATE_ASM
; =============================================================================
; str/core/translate.asm
; Unix tr-like character translation and deletion.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   core/remove.asm (str_remove_chars)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_translate
;
; Character-by-character translation (like tr).
;
; Signature:
;   int64_t str_translate(const StrSlice *src, const StrSlice *from,
;                         const StrSlice *to, uint8_t *dst,
;                         uint64_t cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — src (StrSlice*)
;   RSI  — from (StrSlice*)
;   RDX  — to (StrSlice*)
;   RCX  — dst (uint8_t*)
;   R8   — cap (uint64_t)
;   R9   — out_len (uint64_t*)
; -----------------------------------------------------------------------------
STR_FUNC str_translate
    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r9,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15
    sub     rsp, 520            ; 512 bytes lookup tables + 8 bytes padding (keeps 16-byte alignment)

    mov     rbx, rdi            ; src
    mov     r12, rsi            ; from
    mov     r13, rdx            ; to
    mov     r14, rcx            ; dst
    mov     r15, r8             ; cap

    ; Zero 256-byte action table [rsp] and 256-byte replacement table [rsp+256]
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, 64             ; 64 * 8 = 512 bytes
    rep stosq

    ; Populate translation tables
    mov     r8, [r12 + StrSlice.ptr]    ; from.ptr
    mov     r9, [r12 + StrSlice.len]    ; from.len
    mov     r10, [r13 + StrSlice.ptr]   ; to.ptr
    mov     r11, [r13 + StrSlice.len]   ; to.len
    xor     rcx, rcx                    ; i = 0

.pop_loop:
    cmp     rcx, r9
    je      .pop_done

    movzx   eax, byte [r8 + rcx]        ; byte_val = from.ptr[i]
    cmp     rcx, r11                    ; is i < to.len?
    jae     .pop_delete

    ; Action = 1 (replace), Value = to.ptr[i]
    mov     byte [rsp + rax], 1         ; action[byte_val] = 1
    movzx   edx, byte [r10 + rcx]
    mov     byte [rsp + 256 + rax], dl  ; replacement[byte_val] = to.ptr[i]
    jmp     .pop_next

.pop_delete:
    ; Action = 2 (delete)
    mov     byte [rsp + rax], 2         ; action[byte_val] = 2

.pop_next:
    inc     rcx
    jmp     .pop_loop

.pop_done:
    ; Loop through src and translate
    mov     rsi, [rbx + StrSlice.ptr]
    mov     r8,  [rbx + StrSlice.len]
    xor     rcx, rcx                    ; src_offset = 0
    xor     rdx, rdx                    ; dst_offset = 0

.translate_loop:
    cmp     rcx, r8
    je      .done

    movzx   eax, byte [rsi + rcx]       ; byte_val = src.ptr[src_offset]
    movzx   edi, byte [rsp + rax]       ; action[byte_val]

    cmp     dil, 0
    je      .keep

    cmp     dil, 1
    je      .replace

    ; Action = 2 (delete) -> skip
    jmp     .char_done

.keep:
    cmp     rdx, r15
    jae     .too_small
    mov     [r14 + rdx], al
    inc     rdx
    jmp     .char_done

.replace:
    cmp     rdx, r15
    jae     .too_small
    movzx   r10d, byte [rsp + 256 + rax]
    mov     [r14 + rdx], r10b
    inc     rdx

.char_done:
    inc     rcx
    jmp     .translate_loop

.done:
    mov     [r9], rdx
    add     rsp, 520
    pop_regs r15, r14, r13, r12, rbx
    ret_ok

.too_small:
    add     rsp, 520
    pop_regs r15, r14, r13, r12, rbx
    ret_err STR_ERR_BUF_TOO_SMALL
STR_ENDFUNC str_translate

; -----------------------------------------------------------------------------
; str_delete_chars
;
; Delete all bytes that appear in `chars`.
; Equivalent to str_remove_chars.
;
; Signature:
;   int64_t str_delete_chars(const StrSlice *src, const StrSlice *chars,
;                            uint8_t *dst, uint64_t cap, uint64_t *out_len)
; -----------------------------------------------------------------------------
STR_FUNC str_delete_chars
    ; Forward directly to str_remove_chars
    jmp     str_remove_chars
STR_ENDFUNC str_delete_chars

%endif ; GUARD_LIB_STR_CORE_TRANSLATE_ASM
