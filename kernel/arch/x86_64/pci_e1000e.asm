; =============================================================================
; Tattva OS — QEMU e1000e one-shot MSI-X ownership proof
; =============================================================================
; This is a bounded boot-time proof for Intel 82574L/QEMU e1000e (8086:10d3),
; not a packet driver. It owns no rings and performs no DMA.

%ifndef KERNEL_ARCH_X86_64_PCI_E1000E_ASM
%define KERNEL_ARCH_X86_64_PCI_E1000E_ASM

[BITS 64]

KPCI_E1000E_ID                 equ 0x10D38086
KPCI_E1000E_BAR0_BYTES         equ 0x20000
KPCI_E1000E_BAR3_BYTES         equ 0x4000
KPCI_E1000E_BAR0_MASK          equ 0xFFFE0000
KPCI_E1000E_BAR3_MASK          equ 0xFFFFC000
KPCI_E1000E_MAP_BYTES          equ 0x5000
KPCI_E1000E_MAP_PAGES          equ KPCI_E1000E_MAP_BYTES / 4096
KPCI_E1000E_MMIO_SEARCH        equ 0x0000600000100000

KPCI_E1000E_ICR                equ 0x00C0
KPCI_E1000E_ICS                equ 0x00C8
KPCI_E1000E_IMS                equ 0x00D0
KPCI_E1000E_IMC                equ 0x00D8
KPCI_E1000E_IVAR               equ 0x00E4
KPCI_E1000E_STATUS             equ 0x0008
KPCI_E1000E_RXQ0_CAUSE         equ 1 << 20
KPCI_E1000E_ICR_ASSERTED       equ 1 << 31
KPCI_E1000E_IVAR_RXQ0_VECTOR0  equ 1 << 3
KPCI_E1000E_WAIT_MS            equ 1000

KPCI_E1000E_COMMAND_IO         equ 1 << 0
KPCI_E1000E_COMMAND_MEMORY     equ 1 << 1
KPCI_E1000E_COMMAND_BUS_MASTER equ 1 << 2
KPCI_E1000E_COMMAND_INTX_OFF   equ 1 << 10

KPCI_E1000E_STATE_ABSENT       equ 0
KPCI_E1000E_STATE_READY        equ 1
KPCI_E1000E_STATE_REMAP        equ 2
KPCI_E1000E_STATE_DONE         equ 3

KPCI_E1000E_CLEAN_COMMAND      equ 1 << 0
KPCI_E1000E_CLEAN_OWNER        equ 1 << 1
KPCI_E1000E_CLEAN_PASS         equ 1 << 2
KPCI_E1000E_CLEAN_SOURCE       equ 1 << 3
KPCI_E1000E_CLEAN_RESTORE_BAD  equ 1 << 4
KPCI_E1000E_CLEAN_REGS         equ 1 << 5

section .text

; EDI=BDF, RSI=configuration snapshot.
; Probe QEMU's two 32-bit non-prefetchable memory BARs while IO/MEM/BME are
; disabled. Exact BAR and Command restoration is verified before return.
; CF=0: RAX=BAR0 base, RDX=BAR3 base.
kpci_e1000e_probe_bars:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov ebx, edi
    mov r12, rsi
    xor ebp, ebp
    mov dword [rsp + 4], 0
    test r12, r12
    jz .failed
    movzx r13d, word [r12 + 0x04]
    mov r14d, [r12 + 0x10]
    mov r15d, [r12 + 0x1C]

    mov eax, r14d
    test eax, 0xF
    jnz .failed
    and eax, 0xFFFFFFF0
    jz .failed
    test eax, KPCI_E1000E_BAR0_BYTES - 1
    jnz .failed
    mov edx, eax
    add rdx, KPCI_E1000E_BAR0_BYTES
    mov rax, 1
    shl rax, 32
    cmp rdx, rax
    ja .failed

    mov eax, r15d
    test eax, 0xF
    jnz .failed
    and eax, 0xFFFFFFF0
    jz .failed
    test eax, KPCI_E1000E_BAR3_BYTES - 1
    jnz .failed
    mov ecx, eax
    add rcx, KPCI_E1000E_BAR3_BYTES
    mov rax, 1
    shl rax, 32
    cmp rcx, rax
    ja .failed

    mov eax, r14d
    and eax, 0xFFFFFFF0
    mov edx, r15d
    and edx, 0xFFFFFFF0
    lea rcx, [rax + KPCI_E1000E_BAR0_BYTES]
    cmp rcx, rdx
    jbe .ranges_ok
    lea rcx, [rdx + KPCI_E1000E_BAR3_BYTES]
    cmp rcx, rax
    ja .failed
.ranges_ok:
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, r13d
    jne .failed
    mov edi, ebx
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    cmp eax, r14d
    jne .failed
    mov edi, ebx
    mov esi, 0x1C
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    cmp eax, r15d
    jne .failed

    mov eax, r13d
    and eax, ~(KPCI_E1000E_COMMAND_IO | KPCI_E1000E_COMMAND_MEMORY | KPCI_E1000E_COMMAND_BUS_MASTER)
    mov [rsp], eax
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    mov ecx, eax
    call kpci_cfg_write
    jc .failed
    or ebp, 1
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, [rsp]
    jne .failed

    mov edi, ebx
    mov esi, 0x10
    mov edx, 4
    mov ecx, 0xFFFFFFFF
    call kpci_cfg_write
    jc .failed
    or ebp, 2
    mov edi, ebx
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    mov ecx, eax
    and ecx, 0xFFFFFFF0
    cmp ecx, KPCI_E1000E_BAR0_MASK
    jne .failed
    test eax, 0xF
    jnz .failed
    mov edi, ebx
    mov esi, 0x10
    mov edx, 4
    mov ecx, r14d
    call kpci_cfg_write
    jc .failed
    mov edi, ebx
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    cmp eax, r14d
    jne .failed
    and ebp, ~2

    mov edi, ebx
    mov esi, 0x1C
    mov edx, 4
    mov ecx, 0xFFFFFFFF
    call kpci_cfg_write
    jc .failed
    or ebp, 4
    mov edi, ebx
    mov esi, 0x1C
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    mov ecx, eax
    and ecx, 0xFFFFFFF0
    cmp ecx, KPCI_E1000E_BAR3_MASK
    jne .failed
    test eax, 0xF
    jnz .failed
    mov edi, ebx
    mov esi, 0x1C
    mov edx, 4
    mov ecx, r15d
    call kpci_cfg_write
    jc .failed
    mov edi, ebx
    mov esi, 0x1C
    mov edx, 4
    call kpci_cfg_read
    jc .failed
    cmp eax, r15d
    jne .failed
    and ebp, ~4

    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    mov ecx, r13d
    call kpci_cfg_write
    jc .failed
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .failed
    cmp eax, r13d
    jne .failed
    and ebp, ~1

    mov eax, r14d
    and eax, 0xFFFFFFF0
    mov edx, r15d
    and edx, 0xFFFFFFF0
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    clc
    ret

.failed:
    test ebp, 4
    jz .restore_bar0
    mov edi, ebx
    mov esi, 0x1C
    mov edx, 4
    mov ecx, r15d
    call kpci_cfg_write
    jc .bar3_bad
    mov edi, ebx
    mov esi, 0x1C
    mov edx, 4
    call kpci_cfg_read
    jc .bar3_bad
    cmp eax, r15d
    je .restore_bar0
.bar3_bad:
    mov dword [rsp + 4], 1
.restore_bar0:
    test ebp, 2
    jz .restore_command
    mov edi, ebx
    mov esi, 0x10
    mov edx, 4
    mov ecx, r14d
    call kpci_cfg_write
    jc .bar0_bad
    mov edi, ebx
    mov esi, 0x10
    mov edx, 4
    call kpci_cfg_read
    jc .bar0_bad
    cmp eax, r14d
    je .restore_command
.bar0_bad:
    mov dword [rsp + 4], 1
.restore_command:
    test ebp, 1
    jz .failed_done
    cmp dword [rsp + 4], 0
    jne .contain_command
    mov r12d, r13d
    jmp .write_command
.contain_command:
    mov r12d, [rsp]
.write_command:
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    mov ecx, r12d
    call kpci_cfg_write
    jc .retry_containment
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .retry_containment
    cmp eax, r12d
    je .failed_done
.retry_containment:
    mov r12d, [rsp]
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    mov ecx, r12d
    call kpci_cfg_write
    jc .failed_done
    mov edi, ebx
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .failed_done
    cmp eax, r12d
.failed_done:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    xor eax, eax
    xor edx, edx
    stc
    ret

; Unmap only a failed, unpublished preparation. Published gates keep their
; MMIO mapping for the boot lifetime because IDT unregister is not yet atomic.
kpci_e1000e_unmap:
    push rbx
    push r12
    push r13
    mov r12, [rel kpci_e1000e_map_base]
    mov r13d, [rel kpci_e1000e_mapped_pages]
    xor ebx, ebx
.unmap_loop:
    cmp ebx, r13d
    jae .verify
    mov rdi, r12
    mov eax, ebx
    shl rax, 12
    add rdi, rax
    call virt_unmap
    inc ebx
    jmp .unmap_loop
.verify:
    xor ebx, ebx
.verify_loop:
    cmp ebx, r13d
    jae .destroy
    mov rdi, r12
    mov eax, ebx
    shl rax, 12
    add rdi, rax
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jnz .failed
    inc ebx
    jmp .verify_loop
.destroy:
    mov rdi, [rel kpci_e1000e_vma]
    test rdi, rdi
    jz .clear
    call vma_destroy
.clear:
    mov qword [rel kpci_e1000e_vma], 0
    mov qword [rel kpci_e1000e_map_base], 0
    mov qword [rel kpci_e1000e_mmio], 0
    mov qword [rel kpci_e1000e_bar3_mmio], 0
    mov dword [rel kpci_e1000e_mapped_pages], 0
    pop r13
    pop r12
    pop rbx
    clc
    ret
.failed:
    pop r13
    pop r12
    pop rbx
    stc
    ret

; RDI=BAR0 physical base, RSI=BAR3 physical base.
kpci_e1000e_map_bars:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14, rdi
    mov r15, rsi
    mov edi, KPCI_E1000E_MAP_BYTES
    mov rsi, KPCI_E1000E_MMIO_SEARCH
    call virt_find_free_range
    test rax, rax
    jz .failed
    mov r12, rax
    mov [rel kpci_e1000e_map_base], r12
    mov rdi, r12
    mov esi, KPCI_E1000E_MAP_BYTES
    mov edx, VMA_READ | VMA_WRITE
    call vma_create
    test rax, rax
    jz .rollback
    mov [rel kpci_e1000e_vma], rax
    xor r13d, r13d
.map_loop:
    cmp r13d, KPCI_E1000E_MAP_PAGES
    jae .verify
    mov rdi, r12
    mov eax, r13d
    shl rax, 12
    add rdi, rax
    test r13d, r13d
    jz .bar0_page
    mov rsi, r15
    mov eax, r13d
    dec eax
    shl rax, 12
    add rsi, rax
    jmp .map_page
.bar0_page:
    mov rsi, r14
.map_page:
    mov rdx, PAGE_WRITABLE | PAGE_PWT | PAGE_PCD | PAGE_NX
    call virt_map
    test rax, rax
    jz .rollback
    inc r13d
    mov [rel kpci_e1000e_mapped_pages], r13d
    jmp .map_loop

.verify:
    xor r13d, r13d
.verify_loop:
    cmp r13d, KPCI_E1000E_MAP_PAGES
    jae .mapped
    mov rdi, r12
    mov eax, r13d
    shl rax, 12
    add rdi, rax
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jz .rollback
    cmp edx, 4
    jb .rollback
    cmp edx, 5
    ja .rollback
    mov rcx, [rax]
    mov rdx, PAGE_ADDR_MASK_4K
    and rdx, rcx
    test r13d, r13d
    jz .expect_bar0
    mov rbx, r15
    mov eax, r13d
    dec eax
    shl rax, 12
    add rbx, rax
    jmp .check_phys
.expect_bar0:
    mov rbx, r14
.check_phys:
    cmp rdx, rbx
    jne .rollback
    mov edx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_PWT | PAGE_PCD
    and edx, ecx
    cmp edx, PAGE_PRESENT | PAGE_WRITABLE | PAGE_PWT | PAGE_PCD
    jne .rollback
    test ecx, PAGE_USER
    jnz .rollback
    cmp byte [rel cpu_has_nx], 0
    je .next_verify
    bt rcx, 63
    jnc .rollback
.next_verify:
    inc r13d
    jmp .verify_loop
.mapped:
    mov [rel kpci_e1000e_mmio], r12
    lea rax, [r12 + 0x1000]
    mov [rel kpci_e1000e_bar3_mmio], rax
    mov rax, r12
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    clc
    ret
.rollback:
    call kpci_e1000e_unmap
.failed:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    xor eax, eax
    stc
    ret

; Discover, size, map, and prepare one e1000e MSI-X entry while BSP-serialized.
global kpci_e1000e_prepare
kpci_e1000e_prepare:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov byte [rel kpci_e1000e_state], KPCI_E1000E_STATE_ABSENT
    mov qword [rel kpci_e1000e_vma], 0
    mov qword [rel kpci_e1000e_map_base], 0
    mov qword [rel kpci_e1000e_mmio], 0
    mov qword [rel kpci_e1000e_bar3_mmio], 0
    mov dword [rel kpci_e1000e_mapped_pages], 0
    mov dword [rel kpci_e1000e_bdf], 0

    mov edi, KPCI_E1000E_ID
    xor esi, esi
    call kpci_find_device
    jc .failed
    cmp eax, -1
    jne .found
    clc
    jmp .done
.found:
    mov r12d, eax
    mov edi, r12d
    lea rsi, [rel kpci_e1000e_snapshot]
    call kpci_cfg_snapshot
    jc .failed
    lea r13, [rel kpci_e1000e_snapshot]
    cmp dword [r13], KPCI_E1000E_ID
    jne .failed
    movzx eax, byte [r13 + 0x0E]
    and eax, 0x7F
    jnz .failed
    cmp word [r13 + 0x0A], 0x0200
    jne .failed

    mov rdi, r13
    lea rsi, [rel kpci_e1000e_msix_layout]
    call kpci_msix_snapshot_layout
    jc .failed
    cmp dword [rel kpci_e1000e_msix_layout + KPCI_MSIX_LAYOUT_TABLE_BIR], 3
    jne .failed
    lea rdi, [rel kpci_e1000e_msix_layout]
    mov esi, KPCI_E1000E_BAR3_BYTES
    call kpci_msix_validate_layout
    jc .failed

    mov edi, r12d
    mov rsi, r13
    call kpci_e1000e_probe_bars
    jc .failed
    mov r14, rax
    mov r15, rdx
    mov rax, r14
    add rax, KPCI_E1000E_BAR0_BYTES
    jc .failed
    cmp rax, [rel phys_state + phys_state_t.direct_map_limit]
    ja .failed
    mov rax, r15
    add rax, KPCI_E1000E_BAR3_BYTES
    jc .failed
    cmp rax, [rel phys_state + phys_state_t.direct_map_limit]
    ja .failed
    mov rdi, r14
    mov esi, KPCI_E1000E_BAR0_BYTES / 4096
    call phys_range_is_online_usable
    test eax, eax
    jnz .failed
    mov rdi, r15
    mov esi, KPCI_E1000E_BAR3_BYTES / 4096
    call phys_range_is_online_usable
    test eax, eax
    jnz .failed

    mov eax, [rel smp_bsp_apic_id]
    cmp eax, 0xFE
    ja .remap_required
    mov rdi, r14
    mov rsi, r15
    call kpci_e1000e_map_bars
    jc .failed

    mov [rel kpci_e1000e_bdf], r12d
    mov rdx, [rel kpci_e1000e_bar3_mmio]
    mov eax, [rel kpci_e1000e_msix_layout + KPCI_MSIX_LAYOUT_TABLE_OFFSET]
    add rdx, rax
    jc .mapping_failed
    mov rcx, [rel kpci_e1000e_bar3_mmio]
    mov eax, [rel kpci_e1000e_msix_layout + KPCI_MSIX_LAYOUT_PBA_OFFSET]
    add rcx, rax
    jc .mapping_failed
    lea rdi, [rel kpci_e1000e_msix_owner]
    mov esi, r12d
    lea r8, [rel kpci_e1000e_isr]
    mov r9d, [rel smp_bsp_apic_id]
    call kpci_msix_prepare
    jnc .prepared
    cmp dword [rel kpci_e1000e_msix_owner + KPCI_MSIX_OWNER_VECTOR], 0
    je .mapping_failed
    lea rdi, [rel kpci_e1000e_msix_owner]
    call kpci_msix_restore
    jc .failed
    jmp .mapping_failed
.prepared:
    mov byte [rel kpci_e1000e_state], KPCI_E1000E_STATE_READY
    clc
    jmp .done
.mapping_failed:
    call kpci_e1000e_unmap
    jmp .failed
.remap_required:
    mov byte [rel kpci_e1000e_state], KPCI_E1000E_STATE_REMAP
    clc
    jmp .done
.failed:
    lea rsi, [rel msg_kpci_e1000e_prepare_failed]
    call uart_print_str
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Prove one device-originated MSI-X without configuring DMA rings.
global kpci_e1000e_msix_selftest
kpci_e1000e_msix_selftest:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    movzx eax, byte [rel kpci_e1000e_state]
    cmp eax, KPCI_E1000E_STATE_ABSENT
    je .skip_absent
    cmp eax, KPCI_E1000E_STATE_REMAP
    je .skip_remap
    cmp eax, KPCI_E1000E_STATE_READY
    jne .failed_plain
    lea rax, [rel kpci_e1000e_msix_owner]
    cmp dword [rax + KPCI_MSIX_OWNER_STATE], KPCI_MSIX_STATE_PREPARED
    jne .failed_plain

    pushfq
    pop qword [rel kpci_e1000e_saved_rflags]
    mov r12d, [rel kpci_e1000e_bdf]
    mov r13, [rel kpci_e1000e_mmio]
    test r13, r13
    jz .failed_plain
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .failed_plain
    mov r14d, eax
    mov [rel kpci_e1000e_saved_command], eax
    xor r15d, r15d
    mov dword [rel kpci_e1000e_irq_count], 0
    mov dword [rel kpci_e1000e_irq_seen], 0
    mov dword [rel kpci_e1000e_irq_bad], 0
    cli

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, r14d
    or ecx, KPCI_E1000E_COMMAND_MEMORY | KPCI_E1000E_COMMAND_INTX_OFF
    and ecx, ~KPCI_E1000E_COMMAND_BUS_MASTER
    call kpci_cfg_write
    jc .restore_flags_failed
    or r15d, KPCI_E1000E_CLEAN_COMMAND
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .restore_owner
    mov ecx, eax
    and ecx, KPCI_E1000E_COMMAND_MEMORY | KPCI_E1000E_COMMAND_BUS_MASTER | KPCI_E1000E_COMMAND_INTX_OFF
    cmp ecx, KPCI_E1000E_COMMAND_MEMORY | KPCI_E1000E_COMMAND_INTX_OFF
    jne .restore_owner

    cmp dword [r13 + KPCI_E1000E_STATUS], 0xFFFFFFFF
    je .restore_owner
    mov eax, [r13 + KPCI_E1000E_IMS]
    mov [rel kpci_e1000e_saved_ims], eax
    test eax, eax
    jnz .restore_owner
    mov eax, [r13 + KPCI_E1000E_IVAR]
    mov [rel kpci_e1000e_saved_ivar], eax
    or r15d, KPCI_E1000E_CLEAN_REGS
    mov dword [r13 + KPCI_E1000E_IMC], 0xFFFFFFFF
    mfence
    cmp dword [r13 + KPCI_E1000E_IMS], 0
    jne .cleanup
    mov eax, [r13 + KPCI_E1000E_ICR]
    mfence
    cmp dword [r13 + KPCI_E1000E_ICR], 0
    jne .cleanup
    mov dword [r13 + KPCI_E1000E_IVAR], KPCI_E1000E_IVAR_RXQ0_VECTOR0
    mfence
    cmp dword [r13 + KPCI_E1000E_IVAR], KPCI_E1000E_IVAR_RXQ0_VECTOR0
    jne .cleanup
    or r15d, KPCI_E1000E_CLEAN_SOURCE

    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    mov ecx, r14d
    or ecx, KPCI_E1000E_COMMAND_MEMORY | KPCI_E1000E_COMMAND_BUS_MASTER | KPCI_E1000E_COMMAND_INTX_OFF
    call kpci_cfg_write
    jc .cleanup
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .cleanup
    mov ecx, eax
    and ecx, KPCI_E1000E_COMMAND_MEMORY | KPCI_E1000E_COMMAND_BUS_MASTER | KPCI_E1000E_COMMAND_INTX_OFF
    cmp ecx, KPCI_E1000E_COMMAND_MEMORY | KPCI_E1000E_COMMAND_BUS_MASTER | KPCI_E1000E_COMMAND_INTX_OFF
    jne .cleanup

    lea rdi, [rel kpci_e1000e_msix_owner]
    call kpci_msix_arm
    jc .cleanup
    or r15d, KPCI_E1000E_CLEAN_OWNER
    mov dword [r13 + KPCI_E1000E_IMS], KPCI_E1000E_RXQ0_CAUSE
    mfence
    test dword [r13 + KPCI_E1000E_IMS], KPCI_E1000E_RXQ0_CAUSE
    jz .cleanup
    and r15d, ~KPCI_E1000E_CLEAN_SOURCE
    mov dword [r13 + KPCI_E1000E_ICS], KPCI_E1000E_RXQ0_CAUSE
    mfence
    push qword [rel kpci_e1000e_saved_rflags]
    popfq
    mov ebp, KPCI_E1000E_WAIT_MS
.wait:
    cmp dword [rel kpci_e1000e_irq_bad], 0
    jne .cleanup
    cmp dword [rel kpci_e1000e_irq_count], 1
    je .delivered
    ja .cleanup
    mov edi, 1000
    call udelay
    dec ebp
    jnz .wait
    jmp .cleanup
.delivered:
    test dword [rel kpci_e1000e_irq_seen], KPCI_E1000E_RXQ0_CAUSE
    jz .cleanup
    or r15d, KPCI_E1000E_CLEAN_PASS

.cleanup:
    cli
    mov r13, [rel kpci_e1000e_mmio]
    and r15d, ~KPCI_E1000E_CLEAN_SOURCE
    mov dword [r13 + KPCI_E1000E_IMC], 0xFFFFFFFF
    mfence
    cmp dword [r13 + KPCI_E1000E_IMS], 0
    jne .source_bad
    mov eax, [r13 + KPCI_E1000E_ICR]
    mfence
    cmp dword [r13 + KPCI_E1000E_ICR], 0
    jne .source_bad
    or r15d, KPCI_E1000E_CLEAN_SOURCE
    test r15d, KPCI_E1000E_CLEAN_PASS
    jz .quiesce_owner
    cmp dword [rel kpci_e1000e_irq_bad], 0
    jne .proof_bad
    cmp dword [rel kpci_e1000e_irq_count], 1
    jne .proof_bad
    mov eax, [rel kpci_e1000e_irq_seen]
    test eax, KPCI_E1000E_RXQ0_CAUSE
    jz .proof_bad
    and eax, ~(KPCI_E1000E_RXQ0_CAUSE | KPCI_E1000E_ICR_ASSERTED)
    jnz .proof_bad
    jmp .quiesce_owner
.source_bad:
    and r15d, ~KPCI_E1000E_CLEAN_PASS
    jmp .quiesce_owner
.proof_bad:
    and r15d, ~KPCI_E1000E_CLEAN_PASS
.quiesce_owner:
    test r15d, KPCI_E1000E_CLEAN_OWNER
    jz .restore_owner
    lea rdi, [rel kpci_e1000e_msix_owner]
    call kpci_msix_quiesce
    jnc .restore_owner
    or r15d, KPCI_E1000E_CLEAN_RESTORE_BAD
    and r15d, ~KPCI_E1000E_CLEAN_PASS
.restore_owner:
    lea rdi, [rel kpci_e1000e_msix_owner]
    call kpci_msix_restore
    jnc .restore_regs
    or r15d, KPCI_E1000E_CLEAN_RESTORE_BAD
    and r15d, ~KPCI_E1000E_CLEAN_PASS
.restore_regs:
    test r15d, KPCI_E1000E_CLEAN_REGS
    jz .restore_command
    mov eax, [rel kpci_e1000e_saved_ivar]
    mov [r13 + KPCI_E1000E_IVAR], eax
    mfence
    cmp eax, [r13 + KPCI_E1000E_IVAR]
    jne .regs_bad
    cmp dword [r13 + KPCI_E1000E_IMS], 0
    jne .regs_bad
    jmp .restore_command
.regs_bad:
    or r15d, KPCI_E1000E_CLEAN_RESTORE_BAD
    and r15d, ~KPCI_E1000E_CLEAN_PASS

.restore_command:
    test r15d, KPCI_E1000E_CLEAN_COMMAND
    jz .restore_flags
    mov ecx, [rel kpci_e1000e_saved_command]
    test r15d, KPCI_E1000E_CLEAN_RESTORE_BAD
    jnz .contain_command
    test r15d, KPCI_E1000E_CLEAN_REGS
    jz .command_ready
    test r15d, KPCI_E1000E_CLEAN_SOURCE
    jz .contain_command
    jmp .command_ready
.contain_command:
    or ecx, KPCI_E1000E_COMMAND_INTX_OFF
    and ecx, ~KPCI_E1000E_COMMAND_BUS_MASTER
.command_ready:
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_write
    jc .cleanup_bad
    mov edi, r12d
    mov esi, 0x04
    mov edx, 2
    call kpci_cfg_read
    jc .cleanup_bad
    mov ecx, [rel kpci_e1000e_saved_command]
    test r15d, KPCI_E1000E_CLEAN_SOURCE
    jz .contained_expected
    test r15d, KPCI_E1000E_CLEAN_RESTORE_BAD
    jz .expected_ready
.contained_expected:
    or ecx, KPCI_E1000E_COMMAND_INTX_OFF
    and ecx, ~KPCI_E1000E_COMMAND_BUS_MASTER
.expected_ready:
    cmp eax, ecx
    jne .cleanup_bad
    jmp .restore_flags
.cleanup_bad:
    or r15d, KPCI_E1000E_CLEAN_RESTORE_BAD
    and r15d, ~KPCI_E1000E_CLEAN_PASS
.restore_flags:
    mov [rel kpci_e1000e_diag_clean], r15d
    mov byte [rel kpci_e1000e_state], KPCI_E1000E_STATE_DONE
    push qword [rel kpci_e1000e_saved_rflags]
    popfq
    test r15d, KPCI_E1000E_CLEAN_PASS
    jz .failure_report
    lea rsi, [rel msg_kpci_e1000e_pass]
    call uart_print_str
    clc
    jmp .done

.restore_flags_failed:
    mov [rel kpci_e1000e_diag_clean], r15d
    push qword [rel kpci_e1000e_saved_rflags]
    popfq
.failed_plain:
    lea rdi, [rel kpci_e1000e_msix_owner]
    call kpci_msix_restore
.failure_report:
    mov byte [rel kpci_e1000e_state], KPCI_E1000E_STATE_DONE
    lea rsi, [rel msg_kpci_e1000e_diag]
    call uart_print_str
    mov eax, [rel kpci_e1000e_irq_count]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_e1000e_diag_seen]
    call uart_print_str
    mov eax, [rel kpci_e1000e_irq_seen]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_e1000e_diag_bad]
    call uart_print_str
    mov eax, [rel kpci_e1000e_irq_bad]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_e1000e_diag_clean]
    call uart_print_str
    mov eax, [rel kpci_e1000e_diag_clean]
    call uart_print_hex64
    lea rsi, [rel msg_kpci_e1000e_diag_end]
    call uart_print_str
    lea rsi, [rel msg_kpci_e1000e_failed]
    call uart_print_str
    stc
    jmp .done
.skip_absent:
    lea rsi, [rel msg_kpci_e1000e_absent]
    call uart_print_str
    clc
    jmp .done
.skip_remap:
    lea rsi, [rel msg_kpci_e1000e_remap]
    call uart_print_str
    clc
.done:
    lea rsp, [rsp + 8]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

kpci_e1000e_isr:
    push rax
    push rcx
    push rdx
    mov rax, [rel kpci_e1000e_mmio]
    test rax, rax
    jz .bad
    mov edx, [rax + KPCI_E1000E_ICR]
    mov [rel kpci_e1000e_irq_seen], edx
    test edx, KPCI_E1000E_RXQ0_CAUSE
    jz .bad
    mov ecx, edx
    and ecx, ~(KPCI_E1000E_RXQ0_CAUSE | KPCI_E1000E_ICR_ASSERTED)
    jnz .bad
    lock inc dword [rel kpci_e1000e_irq_count]
    jmp .eoi
.bad:
    lock inc dword [rel kpci_e1000e_irq_bad]
.eoi:
    call smp_lapic_eoi
    pop rdx
    pop rcx
    pop rax
    iretq

section .data
msg_kpci_e1000e_pass: db "PCI MSI-X: e1000e one-shot PASS", 0x0D, 0x0A, 0
msg_kpci_e1000e_failed: db "PCI MSI-X: e1000e one-shot FAILED", 0x0D, 0x0A, 0
msg_kpci_e1000e_absent: db "PCI MSI-X: e1000e device absent; SKIP", 0x0D, 0x0A, 0
msg_kpci_e1000e_remap: db "PCI MSI-X: e1000e destination requires interrupt remapping; SKIP", 0x0D, 0x0A, 0
msg_kpci_e1000e_prepare_failed: db "PCI MSI-X: e1000e preparation FAILED", 0x0D, 0x0A, 0
msg_kpci_e1000e_diag: db "PCI MSI-X: e1000e diag count=", 0
msg_kpci_e1000e_diag_seen: db " seen=", 0
msg_kpci_e1000e_diag_bad: db " bad=", 0
msg_kpci_e1000e_diag_clean: db " clean=", 0
msg_kpci_e1000e_diag_end: db 0x0D, 0x0A, 0

section .bss
alignb 16
kpci_e1000e_snapshot:       resb KPCI_CONFIG_SPACE_BYTES
kpci_e1000e_msix_layout:    resb KPCI_MSIX_LAYOUT_SIZE
alignb 8
kpci_e1000e_msix_owner:     resb KPCI_MSIX_OWNER_SIZE
kpci_e1000e_vma:            resq 1
kpci_e1000e_map_base:       resq 1
kpci_e1000e_mmio:           resq 1
kpci_e1000e_bar3_mmio:      resq 1
kpci_e1000e_saved_rflags:   resq 1
alignb 4
kpci_e1000e_bdf:            resd 1
kpci_e1000e_mapped_pages:   resd 1
kpci_e1000e_saved_command:  resd 1
kpci_e1000e_saved_ims:      resd 1
kpci_e1000e_saved_ivar:     resd 1
kpci_e1000e_irq_count:      resd 1
kpci_e1000e_irq_seen:       resd 1
kpci_e1000e_irq_bad:        resd 1
kpci_e1000e_diag_clean:     resd 1
kpci_e1000e_state:          resb 1

%endif ; KERNEL_ARCH_X86_64_PCI_E1000E_ASM
