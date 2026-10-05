; =============================================================================
; Tattva OS — boot/uefi/entry.asm
; =============================================================================
; Main entry point for the UEFI PE32+ Bootloader path.
; Orchestrates Console, GOP, File loading, Memory maps, and Handoff.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_ENTRY_ASM
%define UEFI_ENTRY_ASM

[BITS 64]
default rel

%include "protocol.asm"
%include "console.asm"
%include "gop.asm"
%include "file.asm"
%include "memory.asm"
%include "handoff.asm"
%include "tpm/uefi_tpm.asm"
%include "nvram.asm"

section .text
global efi_main

; =============================================================================
; efi_main — UEFI Application entry point
; Input:  RCX = ImageHandle
;         RDX = SystemTable
; Output: EFI_STATUS status code (if boot fails)
; =============================================================================
efi_main:
    push rbp
    mov rbp, rsp
    sub rsp, 64                     ; shadow space + local variables

    ; Save inputs
    mov [uefi_image_handle], rcx
    mov [uefi_system_table], rdx

    ; 1. Print UEFI welcoming banner
    mov rcx, [uefi_system_table]
    lea rdx, [msg_uefi_banner]
    call uefi_print

    ; 2. Initialize GOP (Graphics Output Protocol)
    mov rcx, [uefi_system_table]
    call uefi_gop_init

    ; 3. Open the filesystem on the device that loaded this application.
    ; LocateProtocol alone can select an unrelated ESP on multi-disk systems.
    mov rcx, [rel uefi_system_table]
    mov rdx, [rel uefi_image_handle]
    call uefi_open_boot_volume
    test rax, rax
    jnz .load_failed
    mov [rel uefi_boot_root], rdx

    ; 4. Load the validated ULF into firmware-owned pages at its linked base.
    mov rcx, [rel uefi_system_table]
    mov rdx, [rel uefi_boot_root]
    lea r8, [rel msg_kernel_file]
    call uefi_load_kernel
    test rax, rax
    jnz .load_failed

    ; The initrd is optional only when it is absent.  Corruption, an I/O error,
    ; or an allocation failure is not silently converted into \"no initrd\".
    mov rcx, [rel uefi_system_table]
    mov rdx, [rel uefi_boot_root]
    lea r8, [rel msg_initrd_file]
    call uefi_load_initrd
    mov r10, EFI_NOT_FOUND
    cmp rax, r10
    je .initrd_ready
    test rax, rax
    jnz .load_failed

.initrd_ready:
    ; No file or volume handle may survive into the final memory-map window.
    mov rcx, [rel uefi_boot_root]
    mov qword [rel uefi_boot_root], 0
    mov rax, [rcx + FILE_CLOSE]
    call rax
    test rax, rax
    jnz .load_failed

    ; TPM measurement covers the exact initialized file bytes, not page
    ; padding or the zeroed BSS portion of the allocation.
    mov rcx, [rel uefi_system_table]
    call uefi_tpm_init
    test rax, rax
    jnz .skip_tpm_measure

    mov rcx, [rel uefi_system_table]
    mov rdx, [rel uefi_kernel_addr]
    mov r8, [rel uefi_kernel_size]
    mov r9d, 4                      ; PCR 4 (OS loader/kernel)
    call uefi_tpm_measure

.skip_tpm_measure:

    ; NVRAM can change the firmware memory map. It must run before the final
    ; GetMemoryMap -> local conversion -> ExitBootServices sequence.
    mov rcx, [rel uefi_system_table]
    lea rdx, [rel msg_uefi_banner]
    mov r8, 48
    call uefi_write_boot_log

    ; 5. Query GetMemoryMap to obtain size and MapKey. The static buffer is a
    ; hard capacity: EFI_BUFFER_TOO_SMALL is a clean boot failure.
    mov qword [rel uefi_map_size], 16384
    mov rcx, [uefi_system_table]
    lea rdx, [rel uefi_mem_map_buf]
    lea r8, [rel uefi_map_size]
    call uefi_get_memory_map
    test rax, rax
    jnz .mem_map_failed             ; if non-zero status, query failed

    ; 6. Handoff to kernel (Exit Boot Services + validated ULF entry).
    mov r8, [rel uefi_map_key]
    mov rcx, [rel uefi_system_table]
    mov rdx, [rel uefi_image_handle]
    mov r9, [rel uefi_kernel_entry]
    call uefi_handoff

    ; EFI_LOAD_ERROR is local validation failure before ExitBootServices, so
    ; console output remains legal.
    mov r10, EFI_LOAD_ERROR
    cmp rax, r10
    je .mem_map_failed

    ; The one retry permitted by the UEFI contract is for a stale MapKey.
    ; Any other firmware status fails silently: after the first exit attempt
    ; no console, filesystem, TPM, GOP, or NVRAM operation is safe.
    mov r10, EFI_INVALID_PARAMETER
    cmp rax, r10
    jne .halt

    ; Refresh the map and retry ExitBootServices with the new key.
    mov qword [rel uefi_map_size], 16384
    mov rcx, [uefi_system_table]
    lea rdx, [rel uefi_mem_map_buf]
    lea r8, [rel uefi_map_size]
    call uefi_get_memory_map
    test rax, rax
    jnz .halt                       ; no console/protocol calls after EBS failure

    ; Retry Handoff with updated MapKey
    mov r8, [rel uefi_map_key]
    mov rcx, [rel uefi_system_table]
    mov rdx, [rel uefi_image_handle]
    mov r9, [rel uefi_kernel_entry]
    call uefi_handoff

    ; If handoff returned again, fail silently: after an EBS failure firmware
    ; permits only the memory-map/allocation subset used by the retry.
    jmp .halt

.mem_map_failed:
    lea rdx, [rel msg_mem_map_failed]
    jmp .preboot_error

.load_failed:
    lea rdx, [rel msg_load_failed]

.preboot_error:
    ; Preserve the message across cleanup calls in a nonvolatile register slot.
    mov [rbp - 8], rdx
    mov rcx, [rel uefi_boot_root]
    test rcx, rcx
    jz .release_payloads
    mov qword [rel uefi_boot_root], 0
    mov rax, [rcx + FILE_CLOSE]
    call rax
.release_payloads:
    mov rcx, [rel uefi_system_table]
    call uefi_release_payloads
    mov rcx, [rel uefi_system_table]
    mov rdx, [rbp - 8]
    call uefi_print

.halt:
    cli
    hlt
    jmp .halt

; =============================================================================
; Data and Strings (UTF-16LE / 16-bit null-terminated words)
; =============================================================================
section .data
align 8
uefi_image_handle:  dq 0
uefi_system_table:  dq 0
uefi_map_size:      dq 0
uefi_boot_root:     dq 0

; UTF-16LE welcoming strings
msg_uefi_banner:
    dw 'T', 'a', 't', 't', 'v', 'a', ' ', 'O', 'S', ' ', '|', ' ', 'U', 'E', 'F', 'I', ' ', 'P', 'a', 't', 'h', ' ', 'O', 'K', 0x0D, 0x0A, 0

msg_kernel_file:
    dw 'k', 'e', 'r', 'n', 'e', 'l', '.', 'u', 'l', 'f', 0

msg_initrd_file:
    dw 'i', 'n', 'i', 't', 'r', 'd', '.', 'i', 'm', 'g', 0

msg_load_failed:
    dw 'E', 'R', 'R', 'O', 'R', ':', ' ', 'F', 'a', 'i', 'l', 'e', 'd', ' ', 't', 'o', ' ', 'l', 'o', 'a', 'd', ' ', 'k', 'e', 'r', 'n', 'e', 'l', '.', 'u', 'l', 'f', 0x0D, 0x0A, 0

msg_handoff_failed:
    dw 'E', 'R', 'R', 'O', 'R', ':', ' ', 'E', 'x', 'i', 't', 'B', 'o', 'o', 't', 'S', 'e', 'r', 'v', 'i', 'c', 'e', 's', ' ', 'f', 'a', 'i', 'l', 'e', 'd', 0x0D, 0x0A, 0

msg_mem_map_failed:
    dw 'E', 'R', 'R', 'O', 'R', ':', ' ', 'F', 'a', 'i', 'l', 'e', 'd', ' ', 't', 'o', ' ', 'g', 'e', 't', ' ', 'm', 'e', 'm', 'o', 'r', 'y', ' ', 'm', 'a', 'p', 0x0D, 0x0A, 0

section .bss align=16
uefi_mem_map_buf:   resb 16384
uefi_boot_info:     resb UEFI_BOOT_INFO_SIZE
                    resb 8          ; restore 16-byte alignment after 88-byte BootInfo
uefi_e820_map_buf:  resb UEFI_CANONICAL_MAX_ENTRIES * UEFI_CANONICAL_ENTRY_SIZE

%endif ; UEFI_ENTRY_ASM
