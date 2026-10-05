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

    ; 3. Load kernel.ulf from simple filesystem to KERNEL_LOAD (0x100000)
    mov rcx, [uefi_system_table]
    lea rdx, [msg_kernel_file]
    mov r8, 0x100000                ; KERNEL_LOAD (1MB mark)
    call uefi_file_load
    test rax, rax
    jz .load_failed                 ; zero read size = failed to load kernel

    ; TPM measurement of loaded kernel
    mov rbx, rax                    ; save kernel size
    mov rcx, [uefi_system_table]
    call uefi_tpm_init
    test rax, rax
    jnz .skip_tpm_measure

    mov rcx, [uefi_system_table]
    mov rdx, 0x100000               ; kernel data address
    mov r8, rbx                     ; kernel size
    mov r9d, 4                      ; PCR 4 (OS loader/kernel)
    call uefi_tpm_measure

.skip_tpm_measure:
    ; Load initrd.img from Simple File System to 0x2000000 (32MB)
    mov rcx, [uefi_system_table]
    lea rdx, [rel msg_initrd_file]
    mov r8, 0x2000000               ; 32MB mark
    call uefi_file_load
    mov [rel uefi_initrd_size], rax ; save initrd size (0 if not found)

    ; NVRAM can change the firmware memory map. It must run before the final
    ; GetMemoryMap -> local conversion -> ExitBootServices sequence.
    mov rcx, [rel uefi_system_table]
    lea rdx, [rel msg_uefi_banner]
    mov r8, 48
    call uefi_write_boot_log

    ; 4. Query GetMemoryMap to obtain size and MapKey. The static buffer is a
    ; hard capacity: EFI_BUFFER_TOO_SMALL is a clean boot failure.
    mov qword [rel uefi_map_size], 16384
    mov rcx, [uefi_system_table]
    lea rdx, [rel uefi_mem_map_buf]
    lea r8, [rel uefi_map_size]
    call uefi_get_memory_map
    test rax, rax
    jnz .mem_map_failed             ; if non-zero status, query failed

    ; 5. Handoff to kernel (Exit Boot Services + Jump)
    mov r8, [rel uefi_map_key]
    mov rcx, [uefi_system_table]
    mov rdx, [uefi_image_handle]
    mov r9, 0x100000                ; KERNEL_LOAD entry point
    call uefi_handoff

    ; EFI_LOAD_ERROR is local validation failure before ExitBootServices, so
    ; console output remains legal. Firmware failures use the restricted retry.
    mov r10, EFI_LOAD_ERROR
    cmp rax, r10
    je .mem_map_failed

    ; If we returned here, the first handoff failed (possibly due to changed memory map).
    ; Refresh memory map size and query memory map again.
    mov qword [rel uefi_map_size], 16384
    mov rcx, [uefi_system_table]
    lea rdx, [rel uefi_mem_map_buf]
    lea r8, [rel uefi_map_size]
    call uefi_get_memory_map
    test rax, rax
    jnz .halt                       ; no console/protocol calls after EBS failure

    ; Retry Handoff with updated MapKey
    mov r8, [rel uefi_map_key]
    mov rcx, [uefi_system_table]
    mov rdx, [uefi_image_handle]
    mov r9, 0x100000
    call uefi_handoff

    ; If handoff returned again, fail silently: after an EBS failure firmware
    ; permits only the memory-map/allocation subset used by the retry.
    jmp .halt

.mem_map_failed:
    lea rdx, [msg_mem_map_failed]
    jmp .error_out

.load_failed:
    lea rdx, [msg_load_failed]

.error_out:
    mov rcx, [uefi_system_table]
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

; UTF-16LE welcoming strings
msg_uefi_banner:
    dw 'T', 'a', 't', 't', 'v', 'a', ' ', 'O', 'S', ' ', '|', ' ', 'U', 'E', 'F', 'I', ' ', 'P', 'a', 't', 'h', ' ', 'O', 'K', 0x0D, 0x0A, 0

msg_kernel_file:
    dw 'k', 'e', 'r', 'n', 'e', 'l', '.', 'u', 'l', 'f', 0

msg_initrd_file:
    dw 'i', 'n', 'i', 't', 'r', 'd', '.', 'i', 'm', 'g', 0

align 8
uefi_initrd_size:   dq 0

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
