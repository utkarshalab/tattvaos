%ifndef GUARD_LIB_UFILE_SIGNATURES_EXEC_SIGNATURES_ASM
%define GUARD_LIB_UFILE_SIGNATURES_EXEC_SIGNATURES_ASM
; =============================================================================
; Tattva OS — lib/ufile/signatures/exec_signatures.asm
; =============================================================================
; Executable Signature Matchers (ULF Unikernel Format, ELF64, PE/COFF).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/ufile/ufile.inc"

section .text

; -----------------------------------------------------------------------------
; match_ulf — Match and extract Unikernel Loader Format (ULF) metadata
; Input:  RDI = Buffer pointer, RSI = Output ufile_meta_t pointer
; Output: RAX = 1 if matched, 0 if not
; -----------------------------------------------------------------------------
match_ulf:
    ; ULF magic "ULF\0" (0x00464C55) at offset 0
    mov eax, [rdi]
    cmp eax, 0x00464C55             ; "ULF\0"
    jne .no_match

    mov dword [rsi + ufile_meta_t.type_id], UFILE_TYPE_ULF
    mov dword [rsi + ufile_meta_t.category], UFILE_CAT_EXEC
    mov qword [rsi + ufile_meta_t.mime_str], str_mime_ulf
    mov qword [rsi + ufile_meta_t.ext_str], str_ext_ulf

    ; Extract Payload Size at offset 4
    mov eax, [rdi + 4]
    mov [rsi + ufile_meta_t.size_bytes], rax

    ; Extract Entry RIP at offset 8
    mov rax, [rdi + 8]
    mov [rsi + ufile_meta_t.param1], rax

    ; Extract Checksum at offset 16
    mov rax, [rdi + 16]
    mov [rsi + ufile_meta_t.sha256_digest], rax

    mov rax, 1
    ret

.no_match:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; match_elf64 — Match and extract ELF64 metadata
; Input:  RDI = Buffer pointer, RSI = Output ufile_meta_t pointer
; Output: RAX = 1 if matched, 0 if not
; -----------------------------------------------------------------------------
match_elf64:
    ; ELF magic "\x7FELF" (0x464C457F) at offset 0
    mov eax, [rdi]
    cmp eax, 0x464C457F             ; "\x7FELF"
    jne .no_match

    mov dword [rsi + ufile_meta_t.type_id], UFILE_TYPE_ELF64
    mov dword [rsi + ufile_meta_t.category], UFILE_CAT_EXEC
    mov qword [rsi + ufile_meta_t.mime_str], str_mime_elf
    mov qword [rsi + ufile_meta_t.ext_str], str_ext_elf

    ; Extract Entry Point RIP at offset 24
    mov rax, [rdi + 24]
    mov [rsi + ufile_meta_t.param1], rax

    mov rax, 1
    ret

.no_match:
    xor rax, rax
    ret

section .data
str_mime_ulf: db 'application/x-ulf', 0
str_ext_ulf:  db '.ulf', 0
str_mime_elf: db 'application/x-elf64', 0
str_ext_elf:  db '.elf', 0

%endif ; GUARD_LIB_UFILE_SIGNATURES_EXEC_SIGNATURES_ASM
