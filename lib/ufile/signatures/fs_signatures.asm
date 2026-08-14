%ifndef GUARD_LIB_UFILE_SIGNATURES_FS_SIGNATURES_ASM
%define GUARD_LIB_UFILE_SIGNATURES_FS_SIGNATURES_ASM
; =============================================================================
; Tattva OS — lib/ufile/signatures/fs_signatures.asm
; =============================================================================
; Filesystem & Boot Sector Signature Matchers (FAT32, EXT2/3/4, GPT, MBR, UBF).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/ufile/ufile.inc"

section .text

; -----------------------------------------------------------------------------
; match_fat32 — Match and extract FAT32 metadata
; Input:  RDI = 512-byte Sector Buffer, RSI = Output ufile_meta_t pointer
; Output: RAX = 1 if matched, 0 if not
; -----------------------------------------------------------------------------
match_fat32:
    push rbx

    ; Check 0xAA55 signature at offset 510
    cmp word [rdi + 510], 0xAA55
    jne .no_match

    ; Check BS_FilSysType "FAT32   " at offset 82
    mov rax, [rdi + 82]
    mov rbx, 0x2020203233544146     ; "FAT32   " in little-endian
    cmp rax, rbx
    jne .no_match

    ; Matched FAT32! Fill metadata
    mov dword [rsi + ufile_meta_t.type_id], UFILE_TYPE_FAT32
    mov dword [rsi + ufile_meta_t.category], UFILE_CAT_FS
    mov qword [rsi + ufile_meta_t.mime_str], str_mime_fat32
    mov qword [rsi + ufile_meta_t.ext_str], str_ext_fat32

    ; Extract sector size & cluster size
    movzx eax, word [rdi + 11]      ; BPB_BytsPerSec
    movzx ebx, byte [rdi + 13]      ; BPB_SecPerClus
    imul rax, rbx                   ; Cluster size in bytes
    mov [rsi + ufile_meta_t.param1], rax

    ; Extract total sectors
    xor eax, eax
    mov ax, [rdi + 19]              ; BPB_TotSec16
    test ax, ax
    jnz .store_totsec
    mov eax, [rdi + 32]             ; BPB_TotSec32
.store_totsec:
    mov [rsi + ufile_meta_t.param2], rax

    mov rax, 1
    jmp .done

.no_match:
    xor rax, rax

.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; match_ext — Match and extract EXT2/EXT3/EXT4 metadata
; Input:  RDI = Superblock Buffer (offset 1024), RSI = Output ufile_meta_t pointer
; Output: RAX = 1 if matched, 0 if not
; -----------------------------------------------------------------------------
match_ext:
    ; Superblock magic 0xEF53 at offset 56
    cmp word [rdi + 56], 0xEF53
    jne .no_match

    mov dword [rsi + ufile_meta_t.type_id], UFILE_TYPE_EXT4
    mov dword [rsi + ufile_meta_t.category], UFILE_CAT_FS
    mov qword [rsi + ufile_meta_t.mime_str], str_mime_ext
    mov qword [rsi + ufile_meta_t.ext_str], str_ext_ext

    mov rax, 1
    ret

.no_match:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; match_gpt — Match and extract GPT Partition Header metadata
; Input:  RDI = LBA 1 Sector Buffer, RSI = Output ufile_meta_t pointer
; Output: RAX = 1 if matched, 0 if not
; -----------------------------------------------------------------------------
match_gpt:
    ; Signature "EFI PART" (0x5452415020494645) at offset 0
    mov rax, [rdi]
    mov rbx, 0x5452415020494645     ; "EFI PART"
    cmp rax, rbx
    jne .no_match

    mov dword [rsi + ufile_meta_t.type_id], UFILE_TYPE_GPT
    mov dword [rsi + ufile_meta_t.category], UFILE_CAT_FS
    mov qword [rsi + ufile_meta_t.mime_str], str_mime_gpt
    mov qword [rsi + ufile_meta_t.ext_str], str_ext_gpt

    mov rax, 1
    ret

.no_match:
    xor rax, rax
    ret

section .data
str_mime_fat32: db 'application/x-fat32', 0
str_ext_fat32:  db '.fat32', 0
str_mime_ext:   db 'application/x-ext4', 0
str_ext_ext:    db '.ext4', 0
str_mime_gpt:   db 'application/x-gpt', 0
str_ext_gpt:    db '.gpt', 0

%endif ; GUARD_LIB_UFILE_SIGNATURES_FS_SIGNATURES_ASM
