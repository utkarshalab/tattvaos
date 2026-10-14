; =============================================================================
; Tattva OS — bounded QEMU EDU MSI ownership proof
;
; This is deliberately a device-specific boot proof, not a general PCI driver.
; Prepare runs before AP release so its IDT and page-table writes are serialized.
; The live test later enables one MSI, observes it, and restores PCI state.
; =============================================================================

%ifndef KERNEL_ARCH_X86_64_PCI_EDU_ASM
%define KERNEL_ARCH_X86_64_PCI_EDU_ASM

[BITS 64]

KPCI_EDU_ID                    equ 0x11E81234
KPCI_EDU_BAR_BYTES             equ 0x100000
KPCI_EDU_BAR_SIZE_MASK         equ 0xFFF00000
KPCI_EDU_MMIO_PAGE_BYTES       equ 4096
KPCI_EDU_MMIO_SEARCH           equ 0x0000600000000000
KPCI_EDU_SIGNATURE             equ 0x010000ED
KPCI_EDU_IRQ_STATUS            equ 0x24
KPCI_EDU_IRQ_RAISE             equ 0x60
KPCI_EDU_IRQ_ACK               equ 0x64
KPCI_EDU_DMA_COMMAND           equ 0x98
KPCI_EDU_DMA_RUN               equ 1 << 0
KPCI_EDU_IRQ_TOKEN             equ 0x80000000
KPCI_EDU_WAIT_MS               equ 1000

KPCI_EDU_STATE_ABSENT          equ 0
KPCI_EDU_STATE_READY           equ 1
KPCI_EDU_STATE_REMAP_REQUIRED  equ 2
KPCI_EDU_STATE_DONE            equ 3

KPCI_COMMAND_IO                equ 1 << 0
KPCI_COMMAND_MEMORY            equ 1 << 1
KPCI_COMMAND_BUS_MASTER        equ 1 << 2
KPCI_COMMAND_INTX_DISABLE      equ 1 << 10

KPCI_EDU_CLEAN_COMMAND         equ 1 << 0
KPCI_EDU_CLEAN_MSI             equ 1 << 1
KPCI_EDU_CLEAN_PASS            equ 1 << 2
KPCI_EDU_CLEAN_QUIESCED        equ 1 << 3
KPCI_EDU_CLEAN_RESTORE_BAD     equ 1 << 4

section .text

; Find and validate the controlled EDU endpoint, install one permanent IDT gate,
; and map only its interrupt-register page UC. Absence and an unencodable direct
; MSI destination are supported skips. A present malformed device is fatal.
global kpci_edu_prepare
kpci_edu_prepare:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov byte [rel kpci_edu_state], KPCI_EDU_STATE_ABSENT
    mov qword [rel kpci_edu_mmio], 0
    mov qword [rel kpci_edu_vma], 0
    mov qword [rel kpci_edu_bar_phys], 0
    mov dword [rel kpci_edu_bdf], 0

    mov edi, KPCI_EDU_ID
    xor esi, esi                    ; ACPI root discovery is a later ceiling.
    call kpci_find_device
    jc .failed
    cmp eax, -1
    jne .found
    clc
    jmp .done

.found:
    mov r12d, eax
    mov edi, r12d
    lea rsi, [rel kpci_edu_snapshot]
    call kpci_cfg_snapshot
    jc .failed
    lea r14, [rel kpci_edu_snapshot]
    cmp dword [r14], KPCI_EDU_ID
    jne .failed
    movzx eax, byte [r14 + 0x0E]
    and eax, 0x7F
    jnz .failed

    mov edi, r12d
    mov esi, [r14 + 0x10]
    call kpci_edu_probe_bar0
    jc .failed
    mov r14, rax
    mov rax, r14
    add rax, KPCI_EDU_BAR_BYTES
    jc .failed
    cmp rax, [rel phys_state + phys_state_t.direct_map_limit]
    ja .failed

    ; Never alias a page the PMM considers online usable RAM as device MMIO.
    mov rdi, r14
    mov esi, 1
    call phys_range_is_online_usable
    test eax, eax
    jnz .failed

    ; Direct compatibility-format MSI has only an eight-bit physical APIC ID;
    ; 0xFF is broadcast, so it is not a valid unicast destination.
    mov eax, [rel smp_bsp_apic_id]
    cmp eax, 0xFE
    ja .remap_required

    mov edi, KPCI_EDU_MMIO_PAGE_BYTES
    mov rsi, KPCI_EDU_MMIO_SEARCH
    call virt_find_free_range
    test rax, rax
    jz .failed
    mov r15, rax
    mov rdi, r15
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jnz .failed
    mov rdi, r15
    mov esi, KPCI_EDU_MMIO_PAGE_BYTES
    mov edx, VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .failed
    mov [rel kpci_edu_vma], rax
    mov rdi, r15
    mov rsi, r14
    mov rdx, PAGE_WRITABLE | PAGE_PWT | PAGE_PCD | PAGE_NX
    call virt_map
    test rax, rax
    jz .rollback_mapping
    mov rdi, r15
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jz .rollback_mapping
    cmp edx, 4
    jb .rollback_mapping
    cmp edx, 5
    ja .rollback_mapping
    mov rcx, [rax]
    mov rdx, PAGE_ADDR_MASK_4K
    and rdx, rcx
    cmp rdx, r14
    jne .rollback_mapping
    mov edx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_PWT | PAGE_PCD
    and edx, ecx
    cmp edx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_PWT | PAGE_PCD
    jne .rollback_mapping
    test ecx, PAGE_USER
    jnz .rollback_mapping
    cmp byte [rel cpu_has_nx], 0
    je .mapping_verified
    bt rcx, 63
    jnc .rollback_mapping
.mapping_verified:

    mov [rel kpci_edu_bdf], r12d
    mov [rel kpci_edu_bar_phys], r14
    mov [rel kpci_edu_mmio], r15
    lea rdi, [rel kpci_edu_msi_owner]
    mov esi, r12d
    lea rdx, [rel kpci_edu_isr]
    mov ecx, [rel smp_bsp_apic_id]
    call kpci_msi_prepare
    jnc .msi_prepared
    cmp dword [rel kpci_edu_msi_owner + KPCI_MSI_OWNER_VECTOR], 0
    je .rollback_mapping
    lea rdi, [rel kpci_edu_msi_owner]
    call kpci_msi_restore
    jc .failed
    jmp .rollback_mapping
.msi_prepared:
    mov byte [rel kpci_edu_state], KPCI_EDU_STATE_READY
    clc
    jmp .done

.rollback_mapping:
    mov rdi, r15
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jz .destroy_vma
    mov rdi, r15
    call virt_unmap
    mov rdi, r15
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jnz .failed
.destroy_vma:
    mov rdi, [rel kpci_edu_vma]
    call vma_destroy
    mov qword [rel kpci_edu_vma], 0
    mov qword [rel kpci_edu_mmio], 0
    mov qword [rel kpci_edu_bar_phys], 0
    mov dword [rel kpci_edu_bdf], 0
    jmp .failed

.remap_required:
    mov byte [rel kpci_edu_state], KPCI_EDU_STATE_REMAP_REQUIRED
    clc
    jmp .done

.failed:
    lea rsi, [rel msg_kpci_edu_failed]
    call uart_print_str
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Probe BAR0 transactionally with decoding disabled. The original BAR and
; command word are restored and verified before success. If BAR restoration
; ever fails, memory/I/O decoding stays disabled rather than exposing a bogus
; aperture.
; EDI=BDF, ESI=snapshotted BAR0. CF=0/RAX=base; CF=1/RAX=0.
kpci_edu_probe_bar0:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor ebx, ebx
    mov r12d, edi
    mov r13d, esi

    cmp r13d, 0xFFFFFFFF
    je .fail
    test r13b, 1                   ; I/O BAR
    jnz .fail
    test r13d, 6                   ; only a 32-bit memory BAR in this proof
    jnz .fail

    mov edi, r12d
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .fail
    cmp eax, r13d
    jne .fail

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .fail
    mov r14d, eax

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, r14d
    and ecx, ~(KPCI_COMMAND_IO | KPCI_COMMAND_MEMORY)
    call kpci_cfg_write
    jc .rollback
    or ebx, 1
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .rollback
    test eax, KPCI_COMMAND_IO | KPCI_COMMAND_MEMORY
    jnz .rollback

    mov edi, r12d
    mov esi, 0x10
    mov edx, 4
    mov ecx, 0xFFFFFFFF
    call kpci_cfg_write
    jc .rollback
    or ebx, 2
    mov edi, r12d
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .rollback
    mov r15d, eax

    mov edi, r12d
    mov esi, 0x10
    mov edx, 4
    mov ecx, r13d
    call kpci_cfg_write
    jc .rollback
    mov edi, r12d
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .rollback
    cmp eax, r13d
    jne .rollback
    and ebx, ~2

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, r14d
    call kpci_cfg_write
    jc .rollback
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .rollback
    cmp eax, r14d
    jne .rollback
    and ebx, ~1

    and r15d, 0xFFFFFFF0
    cmp r15d, KPCI_EDU_BAR_SIZE_MASK
    jne .fail
    mov eax, r13d
    and eax, 0xFFFFFFF0
    jz .fail
    test eax, KPCI_EDU_BAR_BYTES - 1
    jnz .fail
    clc
    jmp .done

.rollback:
    test ebx, 2
    jz .rollback_command
    mov edi, r12d
    mov esi, 0x10
    mov edx, 4
    mov ecx, r13d
    call kpci_cfg_write
    jc .contain_decode
    mov edi, r12d
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .contain_decode
    cmp eax, r13d
    jne .contain_decode
    and ebx, ~2
.rollback_command:
    test ebx, 1
    jz .fail
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, r14d
    call kpci_cfg_write
    jc .fail
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .fail
    cmp eax, r14d
    jne .fail
    jmp .fail

.contain_decode:
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, r14d
    and ecx, ~(KPCI_COMMAND_IO | KPCI_COMMAND_MEMORY)
    call kpci_cfg_write
.fail:
    xor eax, eax
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Prove one end-to-end MSI after LAPIC/interrupt delivery is live. The vector,
; gate, and UC mapping intentionally remain owned for the boot lifetime because
; this kernel has no atomic IDT unregister/quiesce primitive yet.
global kpci_edu_msi_selftest
kpci_edu_msi_selftest:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword [rel kpci_edu_diag_phase], 1
    mov dword [rel kpci_edu_diag_clean], 0
    movzx eax, byte [rel kpci_edu_state]
    cmp eax, KPCI_EDU_STATE_ABSENT
    je .skip_absent
    cmp eax, KPCI_EDU_STATE_REMAP_REQUIRED
    je .skip_remap
    cmp eax, KPCI_EDU_STATE_READY
    jne .failed_plain
    cmp byte [rel smp_lapic_ready], 1
    jne .failed_plain

    mov r12d, [rel kpci_edu_bdf]
    mov r14, [rel kpci_edu_mmio]
    cmp dword [rel kpci_edu_msi_owner + KPCI_MSI_OWNER_STATE], KPCI_MSI_STATE_PREPARED
    jne .failed_plain
    mov r15d, [rel kpci_edu_msi_owner + KPCI_MSI_OWNER_VECTOR]
    test r14, r14
    jz .failed_plain
    cmp r15d, 0x40
    jb .failed_plain
    cmp r15d, 0xEF
    ja .failed_plain
    mov dword [rel kpci_edu_diag_phase], 2

    pushfq
    pop rax
    test eax, 1 << 9
    jz .failed_plain
    mov [rel kpci_edu_saved_rflags], rax

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .failed_plain
    mov [rel kpci_edu_saved_command], eax
    mov dword [rel kpci_edu_diag_phase], 3

    mov dword [rel kpci_edu_irq_count], 0
    mov dword [rel kpci_edu_irq_seen], 0
    mov dword [rel kpci_edu_irq_bad], 0
    xor ebx, ebx
    cli

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, [rel kpci_edu_saved_command]
    or ecx, KPCI_COMMAND_MEMORY | KPCI_COMMAND_INTX_DISABLE
    and ecx, ~KPCI_COMMAND_BUS_MASTER
    call kpci_cfg_write
    jc .restore_flags_failed
    or ebx, KPCI_EDU_CLEAN_COMMAND
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .cleanup
    mov ecx, eax
    and ecx, KPCI_COMMAND_MEMORY | KPCI_COMMAND_INTX_DISABLE
    cmp ecx, KPCI_COMMAND_MEMORY | KPCI_COMMAND_INTX_DISABLE
    jne .cleanup
    test eax, KPCI_COMMAND_BUS_MASTER
    jnz .cleanup
    mov dword [rel kpci_edu_diag_phase], 4

    cmp dword [r14], KPCI_EDU_SIGNATURE
    jne .cleanup
    mov dword [r14 + KPCI_EDU_IRQ_ACK], -1
    mfence
    cmp dword [r14 + KPCI_EDU_IRQ_STATUS], 0
    jne .cleanup
    test dword [r14 + KPCI_EDU_DMA_COMMAND], KPCI_EDU_DMA_RUN
    jnz .cleanup
    or ebx, KPCI_EDU_CLEAN_QUIESCED
    mov dword [rel kpci_edu_diag_phase], 7

    ; MSI is itself a device-originated memory write. Keep bus mastering off
    ; through device validation, then enable it only for the proof window.
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, [rel kpci_edu_saved_command]
    or ecx, KPCI_COMMAND_MEMORY | KPCI_COMMAND_BUS_MASTER | KPCI_COMMAND_INTX_DISABLE
    call kpci_cfg_write
    jc .cleanup
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .cleanup
    mov ecx, eax
    and ecx, KPCI_COMMAND_MEMORY | KPCI_COMMAND_BUS_MASTER | KPCI_COMMAND_INTX_DISABLE
    cmp ecx, KPCI_COMMAND_MEMORY | KPCI_COMMAND_BUS_MASTER | KPCI_COMMAND_INTX_DISABLE
    jne .cleanup
    mov dword [rel kpci_edu_diag_phase], 8

    lea rdi, [rel kpci_edu_msi_owner]
    call kpci_msi_arm
    jc .cleanup
    or ebx, KPCI_EDU_CLEAN_MSI
    mov dword [rel kpci_edu_diag_phase], 9

    and ebx, ~KPCI_EDU_CLEAN_QUIESCED
    mov dword [rel kpci_edu_diag_phase], 10
    mfence
    mov dword [r14 + KPCI_EDU_IRQ_RAISE], KPCI_EDU_IRQ_TOKEN
    mfence
    push qword [rel kpci_edu_saved_rflags]
    popfq
    mov r13d, KPCI_EDU_WAIT_MS
.wait:
    cmp dword [rel kpci_edu_irq_bad], 0
    jne .cleanup
    cmp dword [rel kpci_edu_irq_count], 1
    je .delivered
    ja .cleanup
    mov edi, 1000
    call udelay
    dec r13d
    jnz .wait
    jmp .cleanup

.delivered:
    cmp dword [rel kpci_edu_irq_seen], KPCI_EDU_IRQ_TOKEN
    jne .cleanup
    or ebx, KPCI_EDU_CLEAN_PASS
    mov dword [rel kpci_edu_diag_phase], 11

.cleanup:
    cli
    test ebx, KPCI_EDU_CLEAN_MSI
    jz .msi_disabled
    lea rdi, [rel kpci_edu_msi_owner]
    call kpci_msi_quiesce
    jnc .msi_disabled
    or ebx, KPCI_EDU_CLEAN_RESTORE_BAD
    and ebx, ~KPCI_EDU_CLEAN_PASS
.msi_disabled:

    mov r14, [rel kpci_edu_mmio]
    and ebx, ~KPCI_EDU_CLEAN_QUIESCED
    mov dword [r14 + KPCI_EDU_IRQ_ACK], -1
    mfence
    cmp dword [r14 + KPCI_EDU_IRQ_STATUS], 0
    jne .irq_not_quiesced
    or ebx, KPCI_EDU_CLEAN_QUIESCED
    jmp .restore_message
.irq_not_quiesced:
    and ebx, ~KPCI_EDU_CLEAN_PASS
.restore_message:
    lea rdi, [rel kpci_edu_msi_owner]
    call kpci_msi_restore
    jnc .restore_command
    or ebx, KPCI_EDU_CLEAN_RESTORE_BAD
    and ebx, ~KPCI_EDU_CLEAN_PASS

.restore_command:
    test ebx, KPCI_EDU_CLEAN_COMMAND
    jz .restore_flags
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, [rel kpci_edu_saved_command]
    test ebx, KPCI_EDU_CLEAN_QUIESCED
    jz .contain_command
    test ebx, KPCI_EDU_CLEAN_RESTORE_BAD
    jz .command_value_ready
.contain_command:
    or ecx, KPCI_COMMAND_INTX_DISABLE
    and ecx, ~KPCI_COMMAND_BUS_MASTER
.command_value_ready:
    call kpci_cfg_write
    jc .cleanup_bad

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .cleanup_bad
    mov ecx, [rel kpci_edu_saved_command]
    test ebx, KPCI_EDU_CLEAN_QUIESCED
    jz .contain_expected
    test ebx, KPCI_EDU_CLEAN_RESTORE_BAD
    jz .command_expected_ready
.contain_expected:
    or ecx, KPCI_COMMAND_INTX_DISABLE
    and ecx, ~KPCI_COMMAND_BUS_MASTER
.command_expected_ready:
    cmp eax, ecx
    jne .cleanup_bad
    jmp .restore_flags

.cleanup_bad:
    or ebx, KPCI_EDU_CLEAN_RESTORE_BAD
    and ebx, ~KPCI_EDU_CLEAN_PASS
.restore_flags:
    mov [rel kpci_edu_diag_clean], ebx
    mov byte [rel kpci_edu_state], KPCI_EDU_STATE_DONE
    push qword [rel kpci_edu_saved_rflags]
    popfq
    test ebx, KPCI_EDU_CLEAN_PASS
    jz .failed_plain
    lea rsi, [rel msg_kpci_edu_pass]
    call uart_print_str
    clc
    jmp .done

.restore_flags_failed:
    mov [rel kpci_edu_diag_clean], ebx
    push qword [rel kpci_edu_saved_rflags]
    popfq
.failed_plain:
    lea rdi, [rel kpci_edu_msi_owner]
    call kpci_msi_restore
    jnc .failure_report
    or dword [rel kpci_edu_diag_clean], KPCI_EDU_CLEAN_RESTORE_BAD
.failure_report:
    mov byte [rel kpci_edu_state], KPCI_EDU_STATE_DONE
    lea rsi, [rel msg_kpci_edu_diag_phase]
    call uart_print_str
    mov eax, [rel kpci_edu_diag_phase]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_edu_diag_count]
    call uart_print_str
    mov eax, [rel kpci_edu_irq_count]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_edu_diag_seen]
    call uart_print_str
    mov eax, [rel kpci_edu_irq_seen]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_edu_diag_bad]
    call uart_print_str
    mov eax, [rel kpci_edu_irq_bad]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_edu_diag_clean]
    call uart_print_str
    mov eax, [rel kpci_edu_diag_clean]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_edu_diag_end]
    call uart_print_str
    lea rsi, [rel msg_kpci_edu_failed]
    call uart_print_str
    stc
    jmp .done

.skip_absent:
    lea rsi, [rel msg_kpci_edu_absent]
    call uart_print_str
    clc
    jmp .done
.skip_remap:
    lea rsi, [rel msg_kpci_edu_remap]
    call uart_print_str
    clc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

kpci_edu_isr:
    push rax
    push rcx
    push rdx
    mov rax, [rel kpci_edu_mmio]
    test rax, rax
    jz .bad
    mov edx, [rax + KPCI_EDU_IRQ_STATUS]
    cmp edx, KPCI_EDU_IRQ_TOKEN
    jne .unexpected
    mov [rax + KPCI_EDU_IRQ_ACK], edx
    mov [rel kpci_edu_irq_seen], edx
    lock inc dword [rel kpci_edu_irq_count]
    jmp .eoi
.unexpected:
    test edx, edx
    jz .bad
    mov [rax + KPCI_EDU_IRQ_ACK], edx
    mov [rel kpci_edu_irq_seen], edx
.bad:
    lock inc dword [rel kpci_edu_irq_bad]
.eoi:
    call smp_lapic_eoi
    pop rdx
    pop rcx
    pop rax
    iretq

section .data
msg_kpci_edu_pass:   db "PCI MSI: EDU one-shot PASS", 0x0D, 0x0A, 0
msg_kpci_edu_failed: db "PCI MSI: EDU one-shot FAILED", 0x0D, 0x0A, 0
msg_kpci_edu_absent: db "PCI MSI: EDU device absent; SKIP", 0x0D, 0x0A, 0
msg_kpci_edu_remap:  db "PCI MSI: EDU destination requires interrupt remapping; SKIP", 0x0D, 0x0A, 0
msg_kpci_edu_diag_phase: db "PCI MSI: EDU diag phase=", 0
msg_kpci_edu_diag_count: db " count=", 0
msg_kpci_edu_diag_seen:  db " seen=", 0
msg_kpci_edu_diag_bad:   db " bad=", 0
msg_kpci_edu_diag_clean: db " clean=", 0
msg_kpci_edu_diag_end:   db 0x0D, 0x0A, 0

section .bss
alignb 16
kpci_edu_snapshot:           resb KPCI_CONFIG_SPACE_BYTES
kpci_edu_msi_owner:          resb KPCI_MSI_OWNER_SIZE
alignb 8
kpci_edu_mmio:               resq 1
kpci_edu_vma:                resq 1
kpci_edu_bar_phys:           resq 1
kpci_edu_saved_rflags:       resq 1
alignb 4
kpci_edu_bdf:                resd 1
kpci_edu_saved_command:      resd 1
kpci_edu_irq_count:          resd 1
kpci_edu_irq_seen:           resd 1
kpci_edu_irq_bad:            resd 1
kpci_edu_diag_phase:         resd 1
kpci_edu_diag_clean:         resd 1
kpci_edu_state:              resb 1

%endif ; KERNEL_ARCH_X86_64_PCI_EDU_ASM
