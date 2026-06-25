; =============================================================================
; str/mem/align.asm
; Pointer and size alignment utilities.
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
; All alignment values must be powers of 2.
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_align_up
;
; Round value up to the next multiple of align.
; align must be a power of 2.
;
; Signature:
;   uint64_t str_align_up(uint64_t value, uint64_t align)
;
; Arguments:
;   RDI  — value
;   RSI  — alignment (power of 2)
;
; Returns:
;   RAX  — aligned value
; -----------------------------------------------------------------------------

STR_FUNC str_align_up

    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx                 ; align - 1
    add     rax, rcx            ; value + align - 1
    not     rcx                 ; ~(align - 1)
    and     rax, rcx            ; mask off low bits

    pop     rbp
    ret

STR_ENDFUNC str_align_up

; -----------------------------------------------------------------------------
; str_align_down
;
; Round value DOWN to the nearest multiple of align.
;
; Signature:
;   uint64_t str_align_down(uint64_t value, uint64_t align)
; -----------------------------------------------------------------------------

STR_FUNC str_align_down

    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    not     rcx
    and     rax, rcx

    pop     rbp
    ret

STR_ENDFUNC str_align_down

; -----------------------------------------------------------------------------
; str_is_aligned
;
; Check if value is aligned to align.
;
; Signature:
;   int64_t str_is_aligned(uint64_t value, uint64_t align)
;
; Returns:
;   RAX  = 1  aligned
;   RAX  = 0  not aligned
; -----------------------------------------------------------------------------

STR_FUNC str_is_aligned

    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    test    rax, rcx
    setz    al
    movzx   eax, al

    pop     rbp
    ret

STR_ENDFUNC str_is_aligned

; -----------------------------------------------------------------------------
; str_align_ptr_up / str_align_ptr_down
;
; Align a pointer up/down to align bytes.
; Same as align_up/down but semantically on pointer types.
; -----------------------------------------------------------------------------

STR_FUNC str_align_ptr_up
    pop     rbp
    jmp     str_align_up
STR_ENDFUNC str_align_ptr_up

STR_FUNC str_align_ptr_down
    pop     rbp
    jmp     str_align_down
STR_ENDFUNC str_align_ptr_down

; -----------------------------------------------------------------------------
; str_align_size
;
; Round a size up to the next multiple of alignment.
; Overflow-safe version.
;
; Signature:
;   int64_t str_align_size(uint64_t size, uint64_t align,
;                           uint64_t *out_aligned)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_OVERFLOW
;   RAX  = STR_ERR_NULL
; -----------------------------------------------------------------------------

STR_FUNC str_align_size

    guard_null rdx, STR_ERR_NULL

    ; check align is power of 2
    mov     rax, rsi
    dec     rax
    test    rdi, rax            ; if any bit in (align-1) mask is set in value:
    ; actually we want: check (size + align-1) doesn't overflow
    mov     rax, rdi            ; size
    add     rax, rsi
    dec     rax                 ; size + align - 1
    jc      .as_overflow        ; carry = overflow

    mov     rcx, rsi
    dec     rcx
    not     rcx
    and     rax, rcx

    mov     [rdx], rax
    xor     eax, eax
    pop     rbp
    ret

.as_overflow:
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

STR_ENDFUNC str_align_size

; -----------------------------------------------------------------------------
; str_padding_bytes
;
; Compute the number of padding bytes needed to align ptr to align.
;
; Signature:
;   uint64_t str_padding_bytes(uint64_t ptr_or_size, uint64_t align)
;
; Returns:
;   RAX  — padding bytes (0 if already aligned)
; -----------------------------------------------------------------------------

STR_FUNC str_padding_bytes

    mov     rax, rdi
    mov     rcx, rsi
    dec     rcx
    and     rax, rcx            ; remainder = value & (align-1)
    test    rax, rax
    jz      .pb_zero

    ; padding = align - remainder
    mov     rcx, rsi
    sub     rcx, rax
    mov     rax, rcx

    pop     rbp
    ret

.pb_zero:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_padding_bytes