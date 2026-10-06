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
; The context page has 0xF60 bytes after the E820 offset and before the stack.
; 160 packed 24-byte entries consume 0xF00, leaving a 96-byte guard.
UEFI_CANONICAL_MAX_ENTRIES   equ 160
UEFI_BOOTSTRAP_MAP_LIMIT     equ 0x0000000100000000

section .text

; =============================================================================
; uefi_handoff — ExitBootServices and jump to kernel
; Input:  RCX = pointer to System Table
;         RDX = ImageHandle
;         R8  = MapKey value from GetMemoryMap
;         R9  = validated ULF kernel entry address
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

    mov dword [rel uefi_handoff_stage], 1
    mov dword [rel uefi_handoff_detail], 0
    cmp byte [rel uefi_transition_ready], 1
    jne .prepare_failed
    call uefi_transition_verify_ready
    jc .prepare_failed
    mov rax, [rel uefi_kernel_entry]
    cmp [rbp - 32], rax
    jne .prepare_failed

    mov r12, [rel uefi_transition_state]
    test r12, r12
    jz .prepare_failed

    mov dword [rel uefi_handoff_stage], 2
    ; Normalize native EFI descriptors before publishing anything to the
    ; kernel. DescriptorVersion is part of the firmware ABI.
    cmp dword [rel uefi_desc_version], EFI_MEMORY_DESCRIPTOR_VERSION
    jne .prepare_failed
    mov rdi, [rel uefi_mem_map_buf]
    test rdi, rdi
    jz .prepare_failed
    mov rsi, [rel uefi_map_size]
    test rsi, rsi
    jz .prepare_failed
    cmp rsi, [rel uefi_mem_map_capacity]
    ja .prepare_failed
    mov rdx, [rel uefi_desc_size]
    mov rcx, r12
    add rcx, UEFI_TRANSITION_E820_OFF
    mov r8d, UEFI_CANONICAL_MAX_ENTRIES
    call uefi_normalize_memory_map
    jnc .map_normalized
    mov [rel uefi_handoff_detail], edx
    jmp .prepare_failed
.map_normalized:
    mov dword [rel uefi_handoff_detail], 0
    mov [rbp - 72], eax             ; canonical entry count

    mov dword [rel uefi_handoff_stage], 3
    ; BootInfo and its canonical map live in the allocated transition-state
    ; pages, not in the PE image.  Their identity addresses remain stable even
    ; when the linked kernel virtual window is backed by different frames.
    add r12, UEFI_TRANSITION_BOOT_INFO_OFF
    mov rax, r12
    add rax, UEFI_BOOT_INFO_SIZE
    jc .prepare_failed
    mov rdx, UEFI_BOOTSTRAP_MAP_LIMIT
    cmp rax, rdx
    ja .prepare_failed

    mov rax, [rel uefi_transition_state]
    add rax, UEFI_TRANSITION_E820_OFF
    mov ecx, [rbp - 72]
    imul rcx, UEFI_CANONICAL_ENTRY_SIZE
    add rcx, rax
    jc .prepare_failed
    cmp rcx, rdx
    ja .prepare_failed

    mov dword [rel uefi_handoff_stage], 4
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
    test rdi, rdi
    jz .acpi_ready
    mov rax, rdi
    mov edx, 36                    ; complete ACPI 2.0 RSDP; ACPI 1.0 fits
    call .identity_span_accessible
    jnc .acpi_ready
    xor edi, edi                   ; unavailable under the bootstrap mapping
.acpi_ready:
    mov [rbp - 40], rdi             ; save found ACPI RSDP pointer

    mov dword [rel uefi_handoff_stage], 5
    ; 2. Zero the loader-owned 88-byte BootInfo structure (11 quadwords).
    cld                             ; Clear direction flag for rep stosq
    mov rdi, r12
    mov rcx, 11                     ; 11 * 8 = 88 bytes (covers through SMP_CORES at offset 0x50)
    xor rax, rax
    rep stosq

    ; 3. Populate BootInfo fields
    mov rax, [rel uefi_transition_state]
    add rax, UEFI_TRANSITION_E820_OFF
    mov [r12 + UEFI_BOOT_INFO_E820_PTR], rax

    ; BOOT_INFO_INITRD_ADDR and SIZE describe the pages returned by firmware;
    ; there is no fixed-address initrd placement on the UEFI path.
    mov rax, [rel uefi_initrd_size]
    test rax, rax
    jz .no_uefi_initrd
    mov rdx, [rel uefi_initrd_addr]
    test rdx, rdx
    jz .prepare_failed
    mov r10, rax
    mov rax, rdx
    mov rdx, r10
    call .identity_span_accessible
    jc .prepare_failed
    mov rdx, [rel uefi_initrd_addr]
    mov rax, [rel uefi_initrd_size]
    mov [r12 + UEFI_BOOT_INFO_INITRD_ADDR], rdx
    mov [r12 + UEFI_BOOT_INFO_INITRD_SIZE], rax
    jmp .uefi_initrd_done
.no_uefi_initrd:
    mov qword [r12 + UEFI_BOOT_INFO_INITRD_ADDR], 0
    mov qword [r12 + UEFI_BOOT_INFO_INITRD_SIZE], 0
.uefi_initrd_done:

    mov eax, [rbp - 72]
    mov [r12 + UEFI_BOOT_INFO_E820_COUNT], eax

    mov dword [r12 + UEFI_BOOT_INFO_DRIVE], 0

    ; Advertise only state that transition_prepare validated and the final
    ; stub will actually enable in CR4/XCR0.
    mov eax, [rel uefi_transition_features]
    mov [r12 + UEFI_BOOT_INFO_FEATURES], eax

    ; Publish the ACPI RSDP physical address.
    mov rax, [rbp - 40]
    mov [r12 + UEFI_BOOT_INFO_ACPI_RSDP], rax

    ; Publish GOP only when its complete span survives the remapped low virtual
    ; window and the removed physical-backing alias.
    mov rax, [rel uefi_fb_base]
    test rax, rax
    jz .framebuffer_done
    mov rdx, [rel uefi_fb_size]
    test rdx, rdx
    jz .framebuffer_done
    call .identity_span_accessible
    jc .framebuffer_done

    mov rax, [rel uefi_fb_base]
    mov [r12 + UEFI_BOOT_INFO_FB_ADDR], rax

    ; Publish framebuffer geometry only with the validated framebuffer.
    mov eax, [rel uefi_fb_width]
    mov [r12 + UEFI_BOOT_INFO_FB_WIDTH], eax

    mov eax, [rel uefi_fb_height]
    mov [r12 + UEFI_BOOT_INFO_FB_HEIGHT], eax

    mov eax, [rel uefi_fb_pitch]
    mov [r12 + UEFI_BOOT_INFO_FB_PITCH], eax

    mov eax, [rel uefi_fb_format]
    mov [r12 + UEFI_BOOT_INFO_FB_FORMAT], eax
.framebuffer_done:

    mov dword [rel uefi_handoff_stage], 6
    ; 4. Call ExitBootServices(ImageHandle, MapKey)
    mov rcx, [rbp - 8]              ; RCX = System Table
    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES] ; RAX = BootServices
    
    mov rcx, [rbp - 16]             ; RCX = ImageHandle
    mov rdx, [rbp - 24]             ; RDX = MapKey
    
    mov rax, [rax + BS_EXIT_BOOT_SERVICES]
    call rax                        ; execute ExitBootServices
    test rax, rax
    jnz .failed                     ; failed to exit boot services

    ; Enter the self-contained RX transition page while firmware mappings are
    ; still active.  It installs the owned stack/GDT/IDT/CR3 and deterministic
    ; CPU state before jumping to the validated linked kernel entry.
    cli
    mov rax, [rel uefi_transition_tables]
    mov rbx, [rel uefi_transition_state]
    add rbx, UEFI_TRANSITION_GDTR_OFF
    mov rcx, [rel uefi_transition_state]
    add rcx, UEFI_TRANSITION_IDTR_OFF
    mov rdx, [rel uefi_transition_state]
    add rdx, UEFI_TRANSITION_STACK_TOP_OFF
    mov rsi, [rbp - 32]
    mov rdi, r12
    mov r8d, [rel uefi_transition_features]
    lea r10, [rel uefi_transition_stub]
    jmp r10

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

; RAX = physical identity address, RDX = byte length.
; CF=0 only when the full span is below 4 GiB and is not shadowed by either
; the linked kernel virtual window or its deliberately unmapped backing alias.
.identity_span_accessible:
    test rdx, rdx
    jz .identity_bad
    mov r10, rax
    add r10, rdx
    jc .identity_bad
    mov r11, UEFI_BOOTSTRAP_MAP_LIMIT
    cmp r10, r11
    ja .identity_bad

    mov r11, [rel uefi_kernel_pages]
    test r11, r11
    jz .identity_bad
    cmp r11, ULF_MAX_MEMORY_BYTES / 4096
    ja .identity_bad
    shl r11, 12
    add r11, KERNEL_LOAD
    jc .identity_bad
    cmp rax, r11
    jae .check_backing_alias
    cmp r10, KERNEL_LOAD
    ja .identity_bad

.check_backing_alias:
    mov r11, [rel uefi_kernel_addr]
    cmp r11, KERNEL_LOAD
    je .identity_good
    cmp rax, r11
    jb .span_may_precede_backing
    mov rdx, [rel uefi_kernel_pages]
    shl rdx, 12
    add r11, rdx
    jc .identity_bad
    cmp rax, r11
    jb .identity_bad
    jmp .identity_good
.span_may_precede_backing:
    cmp r10, r11
    ja .identity_bad

.identity_good:
    clc
    ret
.identity_bad:
    stc
    ret

%endif ; UEFI_HANDOFF_ASM
