; =============================================================================
; Tattva OS — boot/uefi/ulf.asm
; =============================================================================
; Firmware-independent ULF v2 validation.  The metadata-only entry point is
; used before AllocatePages so no untrusted size can escape the loader policy;
; the full entry point repeats those checks and integrity-checks every file
; byte with the ULF additive checksum before control-flow metadata is published.
; =============================================================================

%ifndef UEFI_ULF_ASM
%define UEFI_ULF_ASM

%include "config.asm"

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; uefi_ulf_validate_header
; Input (internal/native ABI):
;   RDI = address of a ULF header
;   RSI = number of accessible bytes at RDI
;   RDX = exact file size reported by EFI_FILE_INFO
;   RCX = required linked virtual load base
; Output:
;   CF=0: RAX = complete in-memory footprint, R8 = validated entry address
;   CF=1: RAX = 0, R8 = 0
;
; RDI and RSI are deliberately left untouched, making the same routine usable
; from the PE loader and the native unit harness.
; -----------------------------------------------------------------------------
global uefi_ulf_validate_header
uefi_ulf_validate_header:
    test rdi, rdi
    jz .invalid
    cmp rsi, ULF_HEADER_SIZE
    jb .invalid
    cmp rdx, ULF_HEADER_SIZE
    jb .invalid
    cmp rdx, ULF_MAX_IMAGE_BYTES
    ja .invalid
    test rdx, 7                    ; checksum is defined over whole qwords
    jnz .invalid
    test rcx, 0xFFF                ; kernel mapping starts on a whole page
    jnz .invalid

    cmp dword [rdi + ULF_MAGIC_OFF], ULF_MAGIC
    jne .invalid
    mov eax, [rdi + ULF_IMAGE_SIZE_OFF]
    cmp rax, rdx                   ; header must describe the whole file
    jne .invalid
    cmp dword [rdi + ULF_VERSION_OFF], ULF_VERSION
    jne .invalid

    mov r9d, [rdi + ULF_EXEC_SIZE_OFF]
    cmp r9, ULF_HEADER_SIZE
    jb .invalid
    test r9, ULF_EXEC_ALIGN - 1
    jnz .invalid
    cmp r9, rdx
    ja .invalid
    cmp r9, ULF_MAX_EXEC_BYTES
    ja .invalid

    mov rax, [rdi + ULF_MEMORY_SIZE_OFF]
    cmp rax, rdx                   ; BSS cannot end before initialized data
    jb .invalid
    cmp rax, ULF_MAX_MEMORY_BYTES
    ja .invalid
    test rax, 7                    ; footprint/stamper contract is qword exact
    jnz .invalid

    mov r10, rcx
    add r10, rax                   ; complete footprint end, exclusive
    jc .invalid
    mov r11, 0x0000000100000000
    cmp r10, r11                   ; current bootstrap maps only low 4 GiB
    ja .invalid

    mov r8, [rdi + ULF_ENTRY_OFF]
    mov r10, rcx
    add r10, ULF_HEADER_SIZE
    jc .invalid
    cmp r8, r10
    jb .invalid
    mov r10, rcx
    add r10, r9
    jc .invalid
    cmp r8, r10                    ; entry must be inside executable prefix
    jae .invalid

    clc
    ret

.invalid:
    xor eax, eax
    xor r8d, r8d
    stc
    ret

; -----------------------------------------------------------------------------
; uefi_ulf_validate_image
; Input (internal/native ABI):
;   RDI = complete loaded image
;   RSI = exact image size
;   RDX = required linked virtual load base
; Output is identical to uefi_ulf_validate_header.
; -----------------------------------------------------------------------------
global uefi_ulf_validate_image
uefi_ulf_validate_image:
    push rbx
    mov rbx, rdx                   ; preserve base across validation passes

    mov rcx, rbx
    mov rdx, rsi
    call uefi_ulf_validate_header
    jc .bad

    xor r10d, r10d                 ; additive checksum, modulo 2^64
    xor r11d, r11d                 ; current byte offset
.checksum_loop:
    cmp r11, 16
    je .skip_checksum_field
    add r10, [rdi + r11]
.skip_checksum_field:
    add r11, 8
    cmp r11, rsi
    jb .checksum_loop

    cmp r10, [rdi + ULF_CHECKSUM_OFF]
    jne .bad

    ; Re-run the bounded metadata checks to return their canonical outputs.
    mov rcx, rbx
    mov rdx, rsi
    call uefi_ulf_validate_header
    pop rbx
    ret

.bad:
    xor eax, eax
    xor r8d, r8d
    stc
    pop rbx
    ret

%endif ; UEFI_ULF_ASM
