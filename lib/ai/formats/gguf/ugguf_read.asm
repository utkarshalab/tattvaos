%ifndef GUARD_LIB_AI_FORMATS_UGGUF_READ_ASM
%define GUARD_LIB_AI_FORMATS_UGGUF_READ_ASM
; =============================================================================
; File     : lib/ai/formats/gguf/ugguf_read.asm
; Project  : Tattva OS — AI Inference Stack
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: GGUF format reader — header parsing, magic, version, tensor
;              count, metadata count. Zero-copy: returns pointers into the
;              memory-mapped GGUF file; no allocations, no copies.
; =============================================================================

bits 64

section .rodata
align 16
gguf_magic:     db "GGUF"           ; 0x46554747 little-endian
gguf_magic_len: equ 4

section .text

; -----------------------------------------------------------------------------
; ugguf_header — Parse GGUF header (first 24 bytes)
; Input:  rdi = pointer to GGUF file data (memory-mapped)
; Output: rax = 0 on success, non-zero on error
;         rbx = version
;         rcx = tensor_count
;         rdx = metadata_kv_count
;         rsi = pointer to first metadata KV pair (offset 24)
; Clobbers: rax, rbx, rcx, rdx, rsi
; -----------------------------------------------------------------------------
global ugguf_header
ugguf_header:
    push    rbx
    push    rcx
    push    rdx
    push    rsi

    ; Check magic "GGUF"
    mov     eax, [rdi]
    cmp     eax, 0x46554747          ; "GGUF" in little-endian
    jne     .bad_magic

    ; Read version (u32 at offset 4)
    mov     ebx, [rdi + 4]

    ; Read tensor_count (u64 at offset 8)
    mov     rcx, [rdi + 8]

    ; Read metadata_kv_count (u64 at offset 16)
    mov     rdx, [rdi + 16]

    ; rsi = pointer to first metadata KV pair (offset 24)
    mov     rsi, rdi
    add     rsi, 24

    xor     rax, rax                 ; success
    jmp     .done

.bad_magic:
    mov     eax, 1                   ; error: bad magic

.done:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; ugguf_meta_count — Return metadata KV count from header
; Input:  rdi = pointer to GGUF file data
; Output: rax = metadata_kv_count (u64)
; -----------------------------------------------------------------------------
global ugguf_meta_count
ugguf_meta_count:
    mov     rax, [rdi + 16]
    ret

; -----------------------------------------------------------------------------
; ugguf_tensor_count — Return tensor count from header
; Input:  rdi = pointer to GGUF file data
; Output: rax = tensor_count (u64)
; -----------------------------------------------------------------------------
global ugguf_tensor_count
ugguf_tensor_count:
    mov     rax, [rdi + 8]
    ret

; -----------------------------------------------------------------------------
; ugguf_meta_offset — Return offset of first metadata KV pair (always 24)
; Output: rax = 24
; -----------------------------------------------------------------------------
global ugguf_meta_offset
ugguf_meta_offset:
    mov     rax, 24
    ret

%endif ; GUARD_LIB_AI_FORMATS_UGGUF_READ_ASM