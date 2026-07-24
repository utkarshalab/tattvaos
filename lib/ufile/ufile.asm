; =============================================================================
; Tattva OS — lib/ufile/ufile.asm
; =============================================================================
; Universal File Format Inspection Engine & Two-Phase SIMD Magic Matrix.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "ufile.inc"

section .text

; -----------------------------------------------------------------------------
; ufile_init — Initialize ufile inspection engine
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
ufile_init:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; ufile_detect_buffer — Zero-Copy Buffer Inspection & Deep Metadata Extraction
; Input:  RDI = Untrusted Buffer Pointer
;         RSI = Buffer Length in Bytes
;         RDX = Output ufile_meta_t Container Pointer (min 256 bytes)
; Output: RAX = Format Type ID (UFILE_TYPE_*), 0 if unknown
; -----------------------------------------------------------------------------
ufile_detect_buffer:
    push rbx
    push rcx
    push r8
    push r9
    push r12
    push r13
    push r14

    mov r12, rdi                    ; R12 = src buffer
    mov r13, rsi                    ; R13 = length
    mov r14, rdx                    ; R14 = meta pointer

    ; Zero-out ufile_meta_t container (256 bytes)
    mov rdi, r14
    mov rcx, 32                     ; 32 qwords = 256 bytes
    xor rax, rax
    rep stosq

    ; 1. Take TOCTOU Shadow Copy of first 512 bytes
    mov rdi, r12
    mov rsi, r13
    call ufile_shadow_copy
    mov r12, rax                    ; R12 now points to immutable shadow copy

    ; 2. Compute Shannon Entropy on header
    mov rdi, r12
    mov rsi, r13
    call ufile_compute_entropy
    mov [r14 + ufile_meta_t.entropy_q16], eax
    mov [r14 + ufile_meta_t.entropy_type], edx

    ; 3. Hash header checksum
    mov rdi, r12
    mov rsi, r13
    mov rdx, r14
    call ufile_hash_header

    ; 4. Phase 1 & 2 Signature Matchers
    ; Try ULF Unikernel Format
    mov rdi, r12
    mov rsi, r14
    call match_ulf
    test rax, rax
    jnz .matched

    ; Try GGUF AI Model
    mov rdi, r12
    mov rsi, r14
    call match_gguf
    test rax, rax
    jnz .matched

    ; Try FAT32 Filesystem
    mov rdi, r12
    mov rsi, r14
    call match_fat32
    test rax, rax
    jnz .matched

    ; Try GPT Partition Table
    mov rdi, r12
    mov rsi, r14
    call match_gpt
    test rax, rax
    jnz .matched

    ; Try ELF64 Executable
    mov rdi, r12
    mov rsi, r14
    call match_elf64
    test rax, rax
    jnz .matched

    ; Unknown format
    mov dword [r14 + ufile_meta_t.type_id], UFILE_TYPE_UNKNOWN
    mov dword [r14 + ufile_meta_t.category], UFILE_CAT_UNKNOWN
    mov qword [r14 + ufile_meta_t.mime_str], str_mime_unknown
    mov qword [r14 + ufile_meta_t.ext_str], str_ext_unknown
    xor rax, rax
    jmp .done

.matched:
    ; 5. Normalize metadata across versions via ufile_transpose_meta
    mov rdi, r14
    call ufile_transpose_meta
    mov eax, [r14 + ufile_meta_t.type_id]

.done:
    pop r14
    pop r13
    pop r12
    pop r9
    pop r8
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufile_detect_sector — Specialized 512-byte Disk Sector Inspector
; Input:  RDI = 512-byte Sector Buffer Pointer
;         RSI = Output ufile_meta_t Container Pointer
; Output: RAX = Format Type ID (UFILE_TYPE_*), 0 if unknown
; -----------------------------------------------------------------------------
ufile_detect_sector:
    mov rdx, rsi                    ; RDX = meta pointer
    mov rsi, 512                    ; RSI = length 512
    call ufile_detect_buffer
    ret

section .data
str_mime_unknown: db 'application/octet-stream', 0
str_ext_unknown:  db '.bin', 0
