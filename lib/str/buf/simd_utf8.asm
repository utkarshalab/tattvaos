; =============================================================================
; str/buf/simd_utf8.asm
; SIMD-accelerated UTF-8 validation and fast ASCII scans.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_utf8_charlen

section .text

; -----------------------------------------------------------------------------
; str_simd_utf8_validate
;
; Fast SSE2-based scan validating UTF-8 structure.
; Processes 16-byte blocks in parallel for the ASCII fast-path.
;
; Signature:
;   int64_t str_simd_utf8_validate(const StrSlice *src)
; -----------------------------------------------------------------------------
STR_FUNC str_simd_utf8_validate
    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12, r13
    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rbx
    add     r13, r12                    ; end ptr

.simd_loop:
    mov     rax, r13
    sub     rax, rbx
    cmp     rax, 16
    jb      .scalar_loop

    ; load 16 bytes unaligned
    movdqu  xmm0, [rbx]
    ; extract sign bits of all 16 bytes
    pmovmskb eax, xmm0
    test    eax, eax
    jnz     .scalar_loop                ; non-ASCII byte detected, exit SIMD fast-path

    ; all 16 bytes are ASCII, advance
    add     rbx, 16
    jmp     .simd_loop

.scalar_loop:
    cmp     rbx, r13
    jae     .ok

    movzx   edi, byte [rbx]
    cmp     dil, 0x80
    jb      .scalar_ascii

    ; multi-byte sequence validation
    call    str_utf8_charlen
    test    rax, rax
    js      .invalid
    jz      .invalid

    mov     rcx, rax                    ; charlen (2..4)
    mov     rdx, r13
    sub     rdx, rbx
    cmp     rdx, rcx
    jb      .invalid                    ; incomplete sequence

    ; validate continuation bytes (bit 7 and 6 must be 10 -> U+80..U+BF)
    inc     rbx
    dec     rcx
.cont_loop:
    test    rcx, rcx
    jz      .simd_loop                  ; return to SIMD check after sequence

    movzx   eax, byte [rbx]
    and     al, 0xC0
    cmp     al, 0x80
    jne     .invalid

    inc     rbx
    dec     rcx
    jmp     .cont_loop

.scalar_ascii:
    inc     rbx
    jmp     .scalar_loop

.ok:
    xor     eax, eax                    ; STR_OK
    pop_regs r13, r12, rbx
    pop     rbp
    ret

.invalid:
    mov     rax, STR_ERR_INVALID
    pop_regs r13, r12, rbx
    pop     rbp
    ret
STR_ENDFUNC str_simd_utf8_validate
