%ifndef GUARD_LIB_UFILE_UFILE_TRANSPOSE_ASM
%define GUARD_LIB_UFILE_UFILE_TRANSPOSE_ASM
; =============================================================================
; Tattva OS — lib/ufile/ufile_transpose.asm
; =============================================================================
; Format Version Transposition & Header Normalization Layer.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/ufile/ufile.inc"

section .text

; -----------------------------------------------------------------------------
; ufile_transpose_meta — Normalize metadata across format versions
; Input:  RDI = Pointer to ufile_meta_t container
; Output: RAX = 1 (transposed)
; -----------------------------------------------------------------------------
ufile_transpose_meta:
    push rbx

    mov eax, [rdi + ufile_meta_t.type_id]

    ; 1. Normalize FAT12/FAT16 to FAT32 standard parameters
    cmp eax, UFILE_TYPE_FAT32
    je .normalize_fat

    ; 2. Normalize GGUF versions (v1, v2, v3)
    cmp eax, UFILE_TYPE_GGUF
    je .normalize_gguf

    jmp .done

.normalize_fat:
    ; Ensure cluster size param1 is non-zero
    cmp qword [rdi + ufile_meta_t.param1], 0
    jnz .done
    mov qword [rdi + ufile_meta_t.param1], 4096 ; Default 4KB cluster size fallback
    jmp .done

.normalize_gguf:
    ; Ensure version is set (default v3)
    cmp dword [rdi + ufile_meta_t.version], 0
    jnz .done
    mov dword [rdi + ufile_meta_t.version], 3

.done:
    mov rax, 1
    pop rbx
    ret

%endif ; GUARD_LIB_UFILE_UFILE_TRANSPOSE_ASM
