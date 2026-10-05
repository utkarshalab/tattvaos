; =============================================================================
; Tattva OS — boot/uefi/handoff.asm
; =============================================================================
; UEFI handoff to kernel. Shuts down boot services and jumps to kernel entry.
; Populates a loader-owned BootInfo structure and canonical memory map.
;
; Author:  Utkarsha Labs
; Target:  x86-64, UEFI PE32+
; =============================================================================

%ifndef UEFI_HANDOFF_ASM
%define UEFI_HANDOFF_ASM

%include "protocol.asm"
%include "memory_map.asm"

[BITS 64]

UEFI_BOOT_INFO_SIZE          equ 88
UEFI_BOOT_INFO_E820_PTR      equ 0
UEFI_BOOT_INFO_E820_COUNT    equ 8
UEFI_BOOT_INFO_DRIVE         equ 12
UEFI_BOOT_INFO_FEATURES      equ 16
UEFI_BOOT_INFO_ACPI_RSDP     equ 24
UEFI_BOOT_INFO_FB_ADDR       equ 32
UEFI_BOOT_INFO_FB_WIDTH      equ 40
UEFI_BOOT_INFO_FB_HEIGHT     equ 44
UEFI_BOOT_INFO_FB_PITCH      equ 48
UEFI_BOOT_INFO_FB_FORMAT     equ 52
UEFI_BOOT_INFO_INITRD_ADDR   equ 56
UEFI_BOOT_INFO_INITRD_SIZE   equ 64
UEFI_CANONICAL_MAX_ENTRIES   equ 128
UEFI_BOOTSTRAP_MAP_LIMIT     equ 0x0000000100000000

section .text

; =============================================================================
; uefi_handoff — ExitBootServices and jump to kernel
; Input:  RCX = pointer to System Table
;         RDX = ImageHandle
;         R8  = MapKey value from GetMemoryMap
;         R9  = kernel entry address (0x100000)
; Output: RAX = EFI status if local validation or ExitBootServices fails
; =============================================================================
uefi_handoff:
    push rbp
    mov rbp, rsp
    ; The lowest 32 bytes are dedicated Microsoft-x64 call home space. Local
    ; saves live above it and cannot be overwritten by firmware.
    sub rsp, 112

    ; Save inputs
    mov [rbp - 8], rcx              ; System Table pointer
    mov [rbp - 16], rdx             ; ImageHandle
    mov [rbp - 24], r8              ; MapKey
    mov [rbp - 32], r9              ; Kernel Entry Address

    ; Preserve non-volatile registers in the stack frame
    mov [rbp - 48], rbx
    mov [rbp - 56], rsi
    mov [rbp - 64], rdi
    mov [rbp - 80], r12

    ; Normalize native EFI descriptors before publishing anything to the
    ; kernel. DescriptorVersion is part of the firmware ABI.
    cmp dword [rel uefi_desc_version], EFI_MEMORY_DESCRIPTOR_VERSION
    jne .prepare_failed
    lea rdi, [rel uefi_mem_map_buf]
    mov rsi, [rel uefi_map_size]
    mov rdx, [rel uefi_desc_size]
    lea rcx, [rel uefi_e820_map_buf]
    mov r8d, UEFI_CANONICAL_MAX_ENTRIES
    call uefi_normalize_memory_map
    jc .prepare_failed
    mov [rbp - 72], eax             ; canonical entry count

    ; The current kernel bootstrap CR3 maps [0, 4 GiB). The loader image is
    ; retained as reserved memory, but these objects must be dereferenceable.
    lea r12, [rel uefi_boot_info]
    mov rax, r12
    add rax, UEFI_BOOT_INFO_SIZE
    jc .prepare_failed
    mov rdx, UEFI_BOOTSTRAP_MAP_LIMIT
    cmp rax, rdx
    ja .prepare_failed

    lea rax, [rel uefi_e820_map_buf]
    mov ecx, [rbp - 72]
    imul rcx, UEFI_CANONICAL_ENTRY_SIZE
    add rcx, rax
    jc .prepare_failed
    cmp rcx, rdx
    ja .prepare_failed

    ; 1. Walk ConfigurationTable to find ACPI RSDP pointer
    mov rcx, [rbp - 8]              ; RCX = System Table
    mov rdx, [rcx + SYS_TABLE_TABLE_COUNT]
    mov rsi, [rcx + SYS_TABLE_CONFIG_TABLE]
    xor rdi, rdi                    ; RDI = found RSDP address (default 0)

.config_loop:
    test rdx, rdx
    jz .config_loop_end

    mov rax, [rsi]                  ; first 8 bytes of GUID
    mov r10, [rsi + 8]              ; next 8 bytes of GUID

    ; ACPI 2.0 check:
    mov r11, 0x11D3E4F18868E871
    cmp rax, r11
    jne .check_acpi10
    mov r11, 0x81883CC7800022BC
    cmp r10, r11
    je .found_acpi20

.check_acpi10:
    ; ACPI 1.0 check:
    mov r11, 0x11D32D88EB9D2D30
    cmp rax, r11
    jne .next_entry
    mov r11, 0x4DC13F279000169A
    cmp r10, r11
    je .found_acpi10

.next_entry:
    add rsi, 24                     ; next entry (24 bytes)
    dec rdx
    jmp .config_loop

.found_acpi10:
    mov rdi, [rsi + 16]             ; Store ACPI 1.0 RSDP
    jmp .next_entry

.found_acpi20:
    mov rdi, [rsi + 16]             ; Store ACPI 2.0 RSDP (preferred)
    ; We found ACPI 2.0, we can stop scanning
    jmp .config_loop_end

.config_loop_end:
    mov [rbp - 40], rdi             ; save found ACPI RSDP pointer

    ; 2. Zero the loader-owned 88-byte BootInfo structure (11 quadwords).
    cld                             ; Clear direction flag for rep stosq
    mov rdi, r12
    mov rcx, 11                     ; 11 * 8 = 88 bytes (covers through SMP_CORES at offset 0x50)
    xor rax, rax
    rep stosq

    ; 3. Populate BootInfo fields
    lea rax, [rel uefi_e820_map_buf]
    mov [r12 + UEFI_BOOT_INFO_E820_PTR], rax

    ; BOOT_INFO_INITRD_ADDR (0x7038) and BOOT_INFO_INITRD_SIZE (0x7040)
    mov rax, [rel uefi_initrd_size]
    test rax, rax
    jz .no_uefi_initrd
    mov qword [r12 + UEFI_BOOT_INFO_INITRD_ADDR], 0x2000000
    mov [r12 + UEFI_BOOT_INFO_INITRD_SIZE], rax
    jmp .uefi_initrd_done
.no_uefi_initrd:
    mov qword [r12 + UEFI_BOOT_INFO_INITRD_ADDR], 0
    mov qword [r12 + UEFI_BOOT_INFO_INITRD_SIZE], 0
.uefi_initrd_done:

    mov eax, [rbp - 72]
    mov [r12 + UEFI_BOOT_INFO_E820_COUNT], eax

    mov dword [r12 + UEFI_BOOT_INFO_DRIVE], 0

    ; BOOT_INFO_FEATURES (0x7010) -> CPU features bitmask
    mov r9d, 1                      ; Bit 0: Long Mode is always supported in 64-bit UEFI
    
    ; Check SSE, SSE2, AVX
    mov eax, 1
    cpuid
    test edx, 1 << 25               ; SSE?
    jz .no_sse
    or r9d, 1 << 2
.no_sse:
    test edx, 1 << 26               ; SSE2?
    jz .no_sse2
    or r9d, 1 << 3
.no_sse2:
    test ecx, 1 << 28               ; AVX?
    jz .no_avx
    or r9d, 1 << 4
.no_avx:

    ; Check AVX2, AVX-512, AMX
    mov eax, 0
    cpuid
    cmp eax, 7
    jl .no_leaf7
    
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, 1 << 5                ; AVX2?
    jz .no_avx2
    or r9d, 1 << 5
.no_avx2:
    test ebx, 1 << 16               ; AVX-512F?
    jz .no_avx512
    or r9d, 1 << 6
.no_avx512:
    test edx, 1 << 24               ; AMX-TILE?
    jz .no_amx
    or r9d, 1 << 7
.no_amx:
.no_leaf7:

    ; Check NX bit
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jl .no_ext_features
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 20               ; NX/XD bit?
    jz .no_nx
    or r9d, 1 << 1
.no_nx:
.no_ext_features:
    mov [r12 + UEFI_BOOT_INFO_FEATURES], r9d

    ; BOOT_INFO_ACPI_RSDP (0x7018) -> ACPI RSDP physical address
    mov rax, [rbp - 40]
    mov [r12 + UEFI_BOOT_INFO_ACPI_RSDP], rax

    ; BOOT_INFO_FB_ADDR (0x7020) -> framebuffer base
    mov rax, [uefi_fb_base]
    mov [r12 + UEFI_BOOT_INFO_FB_ADDR], rax

    ; BOOT_INFO_FB_WIDTH (0x7028) -> width
    mov eax, [uefi_fb_width]
    mov [r12 + UEFI_BOOT_INFO_FB_WIDTH], eax

    ; BOOT_INFO_FB_HEIGHT (0x702C) -> height
    mov eax, [uefi_fb_height]
    mov [r12 + UEFI_BOOT_INFO_FB_HEIGHT], eax

    ; BOOT_INFO_FB_PITCH (0x7030) -> pitch
    mov eax, [uefi_fb_pitch]
    mov [r12 + UEFI_BOOT_INFO_FB_PITCH], eax

    ; BOOT_INFO_FB_FORMAT (0x7034) -> BPP format
    mov eax, [uefi_fb_format]
    mov [r12 + UEFI_BOOT_INFO_FB_FORMAT], eax

    ; 4. Call ExitBootServices(ImageHandle, MapKey)
    mov rcx, [rbp - 8]              ; RCX = System Table
    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES] ; RAX = BootServices
    
    mov rcx, [rbp - 16]             ; RCX = ImageHandle
    mov rdx, [rbp - 24]             ; RDX = MapKey
    
    mov rax, [rax + BS_EXIT_BOOT_SERVICES]
    call rax                        ; execute ExitBootServices
    test rax, rax
    jnz .failed                     ; failed to exit boot services

    ; Disable interrupts (critical before jumping to kernel)
    cli

    ; Pass BootInfo pointer in RDI (System V ABI)
    mov rdi, r12

    ; Jump directly to the kernel entry point
    mov rax, [rbp - 32]
    jmp rax

.failed:
    ; ExitBootServices failed; preserve its EFI_STATUS for the bounded retry.
    jmp .restore_return

.prepare_failed:
    mov rax, EFI_LOAD_ERROR

.restore_return:
    ; Restore non-volatile registers and return failure status in RAX.
    mov r12, [rbp - 80]
    mov rdi, [rbp - 64]
    mov rsi, [rbp - 56]
    mov rbx, [rbp - 48]
    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_HANDOFF_ASM
