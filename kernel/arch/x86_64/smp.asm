%ifndef KERNEL_ARCH_X86_64_SMP_ASM
%define KERNEL_ARCH_X86_64_SMP_ASM
; =============================================================================
; Kernel-owned x86-64 SMP discovery, INIT/SIPI startup, and rendezvous.
; =============================================================================

[BITS 64]
%include "boot/boot_info.inc"
%include "lib/percpu.inc"
%include "kernel/arch/x86_64/madt.asm"
%include "kernel/arch/x86_64/dmar.asm"

SMP_MAX_CPUS                 equ PERCPU_MAX_CORES
SMP_MAILBOX_STRIDE           equ 64
SMP_TSS_STRIDE               equ 128
SMP_GDT_STRIDE               equ 64
SMP_GDTR_STRIDE              equ 16
SMP_IST_BYTES_PER_CPU        equ 3 * 4096
SMP_CPU_OFFLINE              equ 0
SMP_CPU_STARTING             equ 1
SMP_CPU_ENTERED              equ 2
SMP_CPU_ONLINE               equ 3
SMP_CPU_FAILED               equ 4
SMP_CPU_CANCELLED            equ 5
SMP_CPU_PARKED               equ 6
SMP_RELEASE_WAIT             equ 0
SMP_RELEASE_ACK              equ 1
SMP_RELEASE_ABORT            equ 2
SMP_RELEASE_RUN              equ 3
SMP_APIC_ID_OFF              equ 0
SMP_LOGICAL_ID_OFF           equ 4
SMP_STATE_OFF                equ 8
SMP_FLAGS_OFF                equ 12
SMP_STACK_TOP_OFF            equ 16
SMP_PERCPU_OFF               equ 24
SMP_GDTR_PTR_OFF             equ 32

SMP_LAPIC_TPR                equ 0x080
SMP_LAPIC_EOI                equ 0x0B0
SMP_LAPIC_SVR                equ 0x0F0
SMP_LAPIC_ICR_LOW            equ 0x300
SMP_LAPIC_ICR_HIGH           equ 0x310
SMP_LAPIC_LVT_TIMER          equ 0x320
SMP_LAPIC_LVT_LINT0          equ 0x350
SMP_LAPIC_LVT_LINT1          equ 0x360
SMP_LAPIC_LVT_ERROR          equ 0x370
SMP_X2APIC_TPR_MSR           equ 0x808
SMP_X2APIC_EOI_MSR           equ 0x80B
SMP_X2APIC_SVR_MSR           equ 0x80F
SMP_X2APIC_ICR_MSR           equ 0x830
SMP_X2APIC_LVT_TIMER_MSR     equ 0x832
SMP_X2APIC_LVT_LINT0_MSR     equ 0x835
SMP_X2APIC_LVT_LINT1_MSR     equ 0x836
SMP_X2APIC_LVT_ERROR_MSR     equ 0x837
SMP_APIC_INIT_ASSERT         equ 0x0000C500
SMP_APIC_INIT_DEASSERT       equ 0x00008500
SMP_APIC_STARTUP             equ 0x00004600
SMP_APIC_MASKED              equ 1 << 16
SMP_SPURIOUS_VECTOR          equ 0xFF
SMP_BSP_CR4_ALLOWED          equ (1 << 5) | (1 << 6) | (1 << 7) | (1 << 9) | (1 << 10) | (1 << 16) | (1 << 17) | (1 << 18) | (1 << 20) | (1 << 21) | (1 << 22) | (1 << 24)

SMP_RSDP_SIGNATURE           equ 0x2052545020445352
SMP_XSDT_SIGNATURE           equ 0x54445358
SMP_RSDT_SIGNATURE           equ 0x54445352
SMP_ACPI_MAX_TABLE_BYTES     equ 1024 * 1024
SMP_ACPI_MAX_ROOT_ENTRIES    equ 4096

struc smp_mailbox_t
    .apic_id        resd 1
    .logical_id     resd 1
    .state          resd 1
    .flags          resd 1
    .stack_top      resq 1
    .percpu         resq 1
    .gdtr_ptr       resq 1
    .reserved       resb SMP_MAILBOX_STRIDE - 40
endstruc
%if smp_mailbox_t_size != SMP_MAILBOX_STRIDE
    %error "SMP mailbox stride drift"
%endif

section .text

; RDI=BootInfo. CF=0 only for the complete versioned contract.
smp_bootinfo_validate:
    test rdi, rdi
    jz .invalid
    test rdi, 7
    jnz .invalid
    mov rax, 0x100000000 - BOOT_INFO_ABI_SIZE
    cmp rdi, rax
    ja .invalid
    cmp dword [rdi + BOOT_INFO_ABI_SIZE_OFF], BOOT_INFO_ABI_SIZE
    jne .invalid
    mov rax, BOOT_INFO_MAGIC
    cmp [rdi + BOOT_INFO_MAGIC_OFF], rax
    jne .invalid
    cmp dword [rdi + BOOT_INFO_SMP_CORES_OFF], 1
    jne .invalid
    cmp dword [rdi + BOOT_INFO_AP_TRAMPOLINE_SIZE_OFF], BOOT_AP_TRAMPOLINE_BYTES
    jne .invalid
    mov edx, [rdi + BOOT_INFO_BOOT_SOURCE_OFF]
    cmp edx, BOOT_SOURCE_BIOS
    je .bios_source
    cmp edx, BOOT_SOURCE_UEFI
    jne .invalid
    mov rax, [rdi + BOOT_INFO_AP_TRAMPOLINE_OFF]
    cmp rax, 0x10000
    jb .invalid
    jmp .source_ok
.bios_source:
    mov rax, [rdi + BOOT_INFO_AP_TRAMPOLINE_OFF]
    cmp rax, 0x4000
    jne .invalid
.source_ok:
    test rax, 0xFFF
    jnz .invalid
    add rax, BOOT_AP_TRAMPOLINE_BYTES
    jc .invalid
    cmp rax, 0xA0000
    ja .invalid
    clc
    ret
.invalid:
    stc
    ret

smp_current_apic_id:
    push rbx
    xor eax, eax
    cpuid
    mov r8d, eax
    cmp r8d, 0x1F
    jb .try_b
    mov eax, 0x1F
    xor ecx, ecx
    cpuid
    test ebx, ebx
    jz .try_b
    mov eax, edx
    pop rbx
    ret
.try_b:
    cmp r8d, 0x0B
    jb .legacy
    mov eax, 0x0B
    xor ecx, ecx
    cpuid
    test ebx, ebx
    jz .legacy
    mov eax, edx
    pop rbx
    ret
.legacy:
    mov eax, 1
    cpuid
    mov eax, ebx
    shr eax, 24
    pop rbx
    ret

smp_acpi_checksum:
    xor eax, eax
.loop:
    add al, [rdi]
    inc rdi
    dec rcx
    jnz .loop
    ret

; RDI=RSDP, RSI=exclusive accessible physical limit. CF=0/RAX=MADT.
smp_find_madt:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r14, rsi
    xor r15d, r15d
    mov byte [rel smp_dmar_seen], 0
    mov byte [rel smp_x2apic_veto], 0
    test r12, r12
    jz .invalid
    mov rax, r12
    add rax, 20
    jc .invalid
    cmp rax, r14
    ja .invalid
    mov rax, SMP_RSDP_SIGNATURE
    cmp [r12], rax
    jne .invalid
    mov rdi, r12
    mov ecx, 20
    call smp_acpi_checksum
    test al, al
    jnz .invalid
    movzx eax, byte [r12 + 15]
    cmp eax, 2
    jb .use_rsdt
    mov ecx, [r12 + 20]
    cmp ecx, 36
    jb .invalid
    cmp ecx, 4096
    ja .invalid
    mov rax, r12
    add rax, rcx
    jc .invalid
    cmp rax, r14
    ja .invalid
    mov rdi, r12
    call smp_acpi_checksum
    test al, al
    jnz .invalid
    mov r12, [r12 + 24]
    test r12, r12
    jz .invalid
    mov ebx, 8
    mov ebp, SMP_XSDT_SIGNATURE
    jmp .root
.use_rsdt:
    mov r12d, [r12 + 16]
    test r12, r12
    jz .invalid
    mov ebx, 4
    mov ebp, SMP_RSDT_SIGNATURE
.root:
    mov rax, r12
    add rax, 36
    jc .invalid
    cmp rax, r14
    ja .invalid
    cmp [r12], ebp
    jne .invalid
    mov ecx, [r12 + 4]
    cmp ecx, 36
    jb .invalid
    cmp ecx, SMP_ACPI_MAX_TABLE_BYTES
    ja .invalid
    mov r13, r12
    add r13, rcx
    jc .invalid
    cmp r13, r14
    ja .invalid
    mov rdi, r12
    call smp_acpi_checksum
    test al, al
    jnz .invalid
    mov eax, [r12 + 4]
    sub eax, 36
    xor edx, edx
    div ebx
    test edx, edx
    jnz .invalid
    cmp eax, SMP_ACPI_MAX_ROOT_ENTRIES
    ja .invalid
    mov ebp, eax
    lea r12, [r12 + 36]
.root_loop:
    test ebp, ebp
    jz .root_done
    cmp ebx, 8
    jne .root32
    mov r13, [r12]
    jmp .have_table
.root32:
    mov r13d, [r12]
.have_table:
    add r12, rbx
    dec ebp
    test r13, r13
    jz .root_loop
    mov rax, r13
    add rax, 36
    jc .invalid
    cmp rax, r14
    ja .invalid
    cmp dword [r13], SMP_MADT_SIGNATURE
    je .found_madt
    cmp dword [r13], DMAR_SIGNATURE
    jne .root_loop
    cmp byte [rel smp_dmar_seen], 0
    jne .veto_x2apic
    mov byte [rel smp_dmar_seen], 1
    mov rdi, r13
    mov rsi, r14
    call smp_dmar_policy_parse
    jc .veto_x2apic
    test al, DMAR_FLAG_X2APIC_OPT_OUT
    jz .root_loop
.veto_x2apic:
    mov byte [rel smp_x2apic_veto], 1
    jmp .root_loop
.found_madt:
    test r15, r15
    jnz .invalid
    mov r15, r13
    jmp .root_loop
.root_done:
    test r15, r15
    jz .invalid
    mov rax, r15
    clc
    jmp .done
.invalid:
    xor eax, eax
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

smp_report_apic_mode:
    lea rsi, [rel msg_smp_xapic]
    cmp byte [rel smp_x2apic_mode], 0
    je .print
    lea rsi, [rel msg_smp_x2apic]
.print:
    call uart_print_str
    ret

global smp_discover
smp_discover:
    push rbx
    push r12
    push r13
    push r14
    mov dword [rel smp_discovered_cores], 1
    mov dword [rel smp_online_pending], 1
    mov dword [rel smp_discovery_error], 0
    mov byte [rel smp_x2apic_mode], 0
    mov qword [rel smp_madt_ptr], 0
    call smp_current_apic_id
    mov [rel smp_bsp_apic_id], eax
    mov [rel smp_apic_ids], eax
    mov [gs:percpu_t.lapic_id], eax

    ; Capture the firmware mode first. A new x2APIC transition is made only
    ; after validated ACPI policy has had a chance to veto it.
    mov ecx, 0x1B
    rdmsr
    test eax, 1 << 11
    jz .bad_apic
    mov r13d, eax
    and r13d, 0xFFFFF000
    mov r14d, edx
    test eax, 1 << 10
    jz .firmware_xapic
    mov eax, 1
    cpuid
    test ecx, 1 << 21
    jz .bad_apic
    mov byte [rel smp_x2apic_mode], 1
    jmp .apic_base_ready

.firmware_xapic:
    ; This kernel identity-maps xAPIC MMIO below 4 GiB only. IA32_APIC_BASE
    ; carries base bits 35:32 in EDX, so rejecting only the low dword would
    ; silently target the wrong page.
    test r14d, r14d
    jnz .bad_apic
    test r13d, r13d
    jz .bad_apic
.apic_base_ready:
    mov [rel smp_lapic_base], r13

    mov rbx, [rel boot_info_ptr]
    test rbx, rbx
    jz .no_topology
    mov rdi, rbx
    call smp_bootinfo_validate
    jc .no_topology
    mov rdi, [rbx + BOOT_INFO_ACPI_RSDP_OFF]
    test rdi, rdi
    jz .no_topology
    mov rsi, [rel phys_state + phys_state_t.direct_map_limit]
    call smp_find_madt
    jc .bad_root
    mov [rel smp_madt_ptr], rax

    ; Interrupts remain disabled here, so the xAPIC -> x2APIC transition
    ; cannot race local or device delivery. Once EXTD is set it is never
    ; cleared: architectural downgrade disables the APIC and loses state.
    cmp byte [rel smp_x2apic_mode], 0
    jne .firmware_x2apic
    cmp byte [rel smp_x2apic_veto], 0
    jne .apic_mode_ready
    mov eax, 1
    cpuid
    test ecx, 1 << 21
    jz .apic_mode_ready
    mov ecx, 0x1B
    rdmsr
    or eax, (1 << 11) | (1 << 10)
    wrmsr
    mov ecx, 0x1B
    rdmsr
    test eax, 1 << 11
    jz .bad_apic
    test eax, 1 << 10
    jz .bad_apic
    mov byte [rel smp_x2apic_mode], 1
    jmp .apic_mode_ready
.firmware_x2apic:
    cmp byte [rel smp_x2apic_veto], 0
    jne .fatal_x2apic_veto
.apic_mode_ready:
    mov rdi, [rel smp_madt_ptr]
    mov rsi, [rel phys_state + phys_state_t.direct_map_limit]
    mov edx, [rel smp_bsp_apic_id]
    lea rcx, [rel smp_apic_ids]
    mov r8d, SMP_MAX_CPUS
    lea r9, [rel smp_lapic_base]
    call smp_madt_parse
    jc .bad_madt
    cmp eax, 1
    jb .bad_madt
    mov r12d, eax
    cmp byte [rel smp_x2apic_mode], 0
    jne .ids_ready
    mov rax, [rel smp_lapic_base]
    mov rdx, rax
    shr rdx, 32
    jnz .bad_apic
    test eax, eax
    jz .bad_apic
    cmp eax, r13d
    jne .bad_apic
    xor ecx, ecx
.id_loop:
    cmp ecx, r12d
    jae .ids_ready
    lea rdx, [rel smp_apic_ids]
    cmp dword [rdx + rcx * 4], 255
    jae .bad_apic
    inc ecx
    jmp .id_loop
.ids_ready:
    mov [rel smp_discovered_cores], r12d
    lea rdi, [rel smp_mailboxes]
    xor eax, eax
    mov ecx, (SMP_MAX_CPUS * SMP_MAILBOX_STRIDE) / 8
    rep stosq
    xor ecx, ecx
.mailbox_loop:
    cmp ecx, r12d
    jae .discovered
    mov eax, ecx
    shl rax, 6
    lea rdx, [rel smp_mailboxes]
    add rdx, rax
    lea rsi, [rel smp_apic_ids]
    mov eax, [rsi + rcx * 4]
    mov [rdx + SMP_APIC_ID_OFF], eax
    mov [rdx + SMP_LOGICAL_ID_OFF], ecx
    mov dword [rdx + SMP_STATE_OFF], SMP_CPU_OFFLINE
    inc ecx
    jmp .mailbox_loop
.discovered:
    mov dword [rel smp_mailboxes + SMP_STATE_OFF], SMP_CPU_ONLINE
    call smp_report_apic_mode
    lea rsi, [rel msg_smp_discovered]
    call uart_print_str
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_smp_processors]
    call uart_print_str
    clc
    jmp .done
.bad_root:
    mov dword [rel smp_discovery_error], 1
    jmp .fallback
.bad_madt:
    mov [rel smp_discovery_error], edx
    jmp .fallback
.bad_apic:
    mov dword [rel smp_discovery_error], 9
    jmp .fatal
.fatal_x2apic_veto:
    call smp_report_apic_mode
    lea rsi, [rel msg_smp_x2apic_veto]
    call uart_print_str
    mov dword [rel smp_discovery_error], 11
    jmp .fatal_return
.no_topology:
    mov dword [rel smp_discovery_error], 10
.fallback:
    call smp_report_apic_mode
    lea rsi, [rel msg_smp_disabled]
    call uart_print_str
    mov eax, [rel smp_discovery_error]
    call uart_print_dec
    lea rsi, [rel msg_crlf_smp]
    call uart_print_str
    clc
    jmp .done
.fatal:
    call smp_report_apic_mode
.fatal_return:
    lea rsi, [rel msg_smp_fatal]
    call uart_print_str
    stc
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Build one AP's per-CPU block, private TSS/GDT/IST. EDI=logical ID.
smp_prepare_context:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r12d, edi
    test r12d, r12d
    jz .invalid
    cmp r12d, [rel smp_discovered_cores]
    jae .invalid
    mov rax, r12
    shl rax, 6
    lea r13, [rel smp_mailboxes]
    add r13, rax
    lea rdx, [rel smp_cpu_stacks]
    mov rax, [rdx + r12 * 8]
    test rax, rax
    jz .invalid
    mov [r13 + SMP_STACK_TOP_OFF], rax
    mov rax, r12
    imul rax, percpu_t_size
    lea r14, [rel smp_percpu_table]
    add r14, rax
    mov rdi, r14
    xor eax, eax
    mov ecx, percpu_t_size / 8
    rep stosq
    mov [r14 + percpu_t.self], r14
    mov [r14 + percpu_t.cpu_id], r12d
    mov eax, [r13 + SMP_APIC_ID_OFF]
    mov [r14 + percpu_t.lapic_id], eax
    mov rax, [r13 + SMP_STACK_TOP_OFF]
    mov [r14 + percpu_t.stack_top], rax
    mov [r13 + SMP_PERCPU_OFF], r14

    mov rax, r12
    shl rax, 7
    lea r15, [rel smp_tss_table]
    add r15, rax
    mov rdi, r15
    xor eax, eax
    mov ecx, 104 / 8
    rep stosq
    mov rax, [r13 + SMP_STACK_TOP_OFF]
    mov [r15 + 4], rax
    mov rax, r12
    imul rax, SMP_IST_BYTES_PER_CPU
    lea rbx, [rel smp_ist_stacks]
    add rbx, rax
    lea rax, [rbx + 4096]
    mov [r15 + 36], rax
    lea rax, [rbx + 8192]
    mov [r15 + 44], rax
    lea rax, [rbx + 12288]
    mov [r15 + 52], rax
    mov word [r15 + 102], 104

    mov rax, r12
    shl rax, 6
    lea rbx, [rel smp_gdt_table]
    add rbx, rax
    mov rdi, rbx
    xor eax, eax
    mov ecx, SMP_GDT_STRIDE / 8
    rep stosq
    mov rax, 0x00209A0000000000
    mov [rbx + 8], rax
    mov rax, 0x0000920000000000
    mov [rbx + 16], rax
    mov rax, 0x0000F20000000000
    mov [rbx + 24], rax
    mov rax, 0x0020FA0000000000
    mov [rbx + 32], rax
    mov word [rbx + 40], 103
    mov rax, r15
    mov [rbx + 42], ax
    shr rax, 16
    mov [rbx + 44], al
    mov byte [rbx + 45], 0x89
    mov byte [rbx + 46], 0
    shr rax, 8
    mov [rbx + 47], al
    shr rax, 8
    mov [rbx + 48], eax
    mov dword [rbx + 52], 0

    mov rax, r12
    shl rax, 4
    lea rbp, [rel smp_gdtr_table]
    add rbp, rax
    mov word [rbp], 55
    mov [rbp + 2], rbx
    mov [r13 + SMP_GDTR_PTR_OFF], rbp
    clc
    jmp .done
.invalid:
    stc
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

smp_capture_bsp_state:
    push rbx
    mov rax, cr0
    and rax, ~((1 << 2) | (1 << 3))
    mov [rel smp_bsp_cr0], rax
    mov rax, cr4
    mov [rel smp_bsp_cr4], rax
    xor ecx, ecx
    xgetbv
    mov [rel smp_bsp_xcr0], eax
    mov [rel smp_bsp_xcr0 + 4], edx
    mov ecx, 0xC0000080
    rdmsr
    mov [rel smp_bsp_efer], eax
    mov [rel smp_bsp_efer + 4], edx
    mov ecx, 0x277
    rdmsr
    mov [rel smp_bsp_pat], eax
    mov [rel smp_bsp_pat + 4], edx
    mov byte [rel smp_bsp_has_spec_ctrl], 0
    mov eax, 7
    xor ecx, ecx
    cpuid
    test edx, (1 << 26) | (1 << 27)
    jz .done
    mov ecx, 0x48
    rdmsr
    mov [rel smp_bsp_spec_ctrl], eax
    mov [rel smp_bsp_spec_ctrl + 4], edx
    mov byte [rel smp_bsp_has_spec_ctrl], 1
.done:
    pop rbx
    ret

; Copy, patch, flush, and seal the exact SIPI page RO+X.
smp_prepare_trampoline:
    push rbx
    push r12
    push r13
    mov r12, [rel boot_info_ptr]
    test r12, r12
    jz .invalid
    mov rdi, r12
    call smp_bootinfo_validate
    jc .invalid
    mov rbx, [r12 + BOOT_INFO_AP_TRAMPOLINE_OFF]
    mov rdi, rbx
    xor esi, esi
    call virt_walk_table
    test rax, rax
    jz .invalid
    cmp rdx, 4
    jne .invalid
    mov r13, rax
    mov rax, [r13]
    test rax, 1
    jz .invalid
    test rax, 2
    jz .invalid
    mov rdx, rax
    mov rcx, 0x000FFFFFFFFFF000
    and rdx, rcx
    cmp rdx, rbx
    jne .invalid
    ; The whole page becomes executable. Remove any firmware/low-memory tail
    ; bytes before copying the bounded template so no stale bytes are gadgets.
    cld
    mov rdi, rbx
    xor eax, eax
    mov ecx, BOOT_AP_TRAMPOLINE_BYTES / 8
    rep stosq
    lea rsi, [rel smp_trampoline_template]
    mov rdi, rbx
    mov ecx, smp_trampoline_end - smp_trampoline_template
    rep movsb
    lea rax, [rbx + smp_trampoline_gdt - smp_trampoline_template]
    mov [rbx + smp_trampoline_gdtr_base - smp_trampoline_template], eax
    lea rax, [rbx + smp_trampoline_pm32 - smp_trampoline_template]
    mov [rbx + smp_trampoline_pm32_target - smp_trampoline_template], eax
    lea rax, [rbx + smp_trampoline_long64 - smp_trampoline_template]
    mov [rbx + smp_trampoline_long64_target - smp_trampoline_template], eax
    mov [rbx + smp_trampoline_base_imm - smp_trampoline_template], ebx
    mov rax, cr3
    and rax, -4096
    mov rdx, rax
    shr rdx, 32
    jnz .invalid
    mov [rbx + smp_trampoline_cr3 - smp_trampoline_template], eax
    mov rax, cr4
    and eax, 1 << 18
    or eax, (1 << 5) | (1 << 9) | (1 << 10)
    mov [rbx + smp_trampoline_cr4 - smp_trampoline_template], eax
    mov ecx, 0xC0000080
    rdmsr
    and eax, 1 << 11
    mov [rbx + smp_trampoline_efer - smp_trampoline_template], eax
    lea rax, [rel smp_mailboxes]
    mov [rbx + smp_trampoline_mailboxes - smp_trampoline_template], rax
    mov eax, [rel smp_discovered_cores]
    mov [rbx + smp_trampoline_mailbox_count - smp_trampoline_template], eax
    lea rax, [rel smp_ap_entry]
    mov [rbx + smp_trampoline_ap_entry - smp_trampoline_template], rax
    mfence
    mov rax, rbx
.flush_loop:
    clflush [rax]
    add rax, 64
    lea rdx, [rbx + BOOT_AP_TRAMPOLINE_BYTES]
    cmp rax, rdx
    jb .flush_loop
    mfence
    and qword [r13], ~2
    btr qword [r13], 63
    mfence
    invlpg [rbx]
    mov rax, [r13]
    test rax, 1
    jz .invalid
    test rax, 2
    jnz .invalid
    bt rax, 63
    jc .invalid
    mov rdx, rax
    mov rcx, 0x000FFFFFFFFFF000
    and rdx, rcx
    cmp rdx, rbx
    jne .invalid
    clc
    jmp .done
.invalid:
    stc
.done:
    pop r13
    pop r12
    pop rbx
    ret

smp_xapic_wait_idle:
    mov rax, [rel smp_lapic_base]
    mov ecx, 1000000
.wait:
    test dword [rax + SMP_LAPIC_ICR_LOW], 1 << 12
    jz .idle
    pause
    dec ecx
    jnz .wait
    stc
    ret
.idle:
    clc
    ret

; RDI=destination APIC ID, ESI=ICR low command.  Destination shorthand
; commands may pass zero because hardware ignores the destination field.
; CF reports completion failure; EAX=1 once the command was written, even if
; the post-write delivery-status wait timed out, and EAX=0 if it was rejected
; before reaching the ICR.
global smp_send_ipi
smp_send_ipi:
    cmp byte [rel smp_x2apic_mode], 0
    je .xapic
    cmp edi, -1                    ; x2APIC physical broadcast ID
    je .failed
    mov ecx, SMP_X2APIC_ICR_MSR
    mov eax, esi
    mov edx, edi
    wrmsr
    mov eax, 1
    clc
    ret
.xapic:
    cmp edi, 255
    jae .failed                    ; xAPIC broadcast ID is never targeted
    call smp_xapic_wait_idle
    jc .failed
    mov rax, [rel smp_lapic_base]
    mov edx, edi
    shl edx, 24
    mov [rax + SMP_LAPIC_ICR_HIGH], edx
    mov [rax + SMP_LAPIC_ICR_LOW], esi
    call smp_xapic_wait_idle
    mov eax, 1
    ret
.failed:
    xor eax, eax
    stc
    ret

; Send one fixed-vector command to every online processor except the caller.
; EDI=ICR low command, including the all-excluding-self shorthand.  The
; destination field is deliberately zero: xAPIC and x2APIC both ignore it
; when a destination shorthand is present.  CF=1 means the xAPIC delivery
; register remained busy and no new command was issued.
global smp_send_all_others
smp_send_all_others:
    cmp byte [rel smp_x2apic_mode], 0
    je .xapic
    mov eax, edi
    xor edx, edx
    mov ecx, SMP_X2APIC_ICR_MSR
    wrmsr
    clc
    ret
.xapic:
    call smp_xapic_wait_idle
    jc .failed
    mov rax, [rel smp_lapic_base]
    mov dword [rax + SMP_LAPIC_ICR_LOW], edi
    ; Serialize reuse of the shared ICR.  A timeout is reported to the caller,
    ; which may then fail closed while waiting for its rendezvous.
    call smp_xapic_wait_idle
    ret
.failed:
    stc
    ret

; Acknowledge a local-APIC interrupt in whichever APIC mode firmware selected.
; Clobbers RAX, RCX, and RDX only.
global smp_lapic_eoi
smp_lapic_eoi:
    cmp byte [rel smp_x2apic_mode], 0
    je .xapic
    mov ecx, SMP_X2APIC_EOI_MSR
    xor eax, eax
    xor edx, edx
    wrmsr
    ret
.xapic:
    mov rax, [rel smp_lapic_base]
    mov dword [rax + SMP_LAPIC_EOI], 0
    ret

; RDI=APIC ID, RSI=mailbox. Bounded 100ms rendezvous.
smp_start_one:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d                 ; no SIPI has reached the ICR yet
    mov dword [r12 + SMP_STATE_OFF], SMP_CPU_STARTING
    mfence
    mov rdi, rbx
    mov esi, SMP_APIC_INIT_ASSERT
    call smp_send_ipi
    jc .failed
    mov rdi, 10000
    call udelay
    mov rdi, rbx
    mov esi, SMP_APIC_INIT_DEASSERT
    call smp_send_ipi
    jc .failed
    mov rdi, 200
    call udelay
    mov rax, [rel boot_info_ptr]
    mov rax, [rax + BOOT_INFO_AP_TRAMPOLINE_OFF]
    shr eax, 12
    and eax, 0xFF
    or eax, SMP_APIC_STARTUP
    mov esi, eax
    mov rdi, rbx
    call smp_send_ipi
    jnc .first_sipi_sent
    test eax, eax
    jz .failed
    mov r13d, 1                    ; written, but delivery status timed out
    jmp .failed
.first_sipi_sent:
    mov r13d, 1
    mov rdi, 200
    call udelay
    mov rax, [rel boot_info_ptr]
    mov rax, [rax + BOOT_INFO_AP_TRAMPOLINE_OFF]
    shr eax, 12
    and eax, 0xFF
    or eax, SMP_APIC_STARTUP
    mov esi, eax
    mov rdi, rbx
    call smp_send_ipi
    jc .failed
    mov ebx, 100
.rendezvous:
    mov eax, [r12 + SMP_STATE_OFF]
    cmp eax, SMP_CPU_ONLINE
    je .online
    cmp eax, SMP_CPU_FAILED
    je .failed
    mov rdi, 1000
    call udelay
    dec ebx
    jnz .rendezvous
.failed:
.cancel:
    mov eax, [r12 + SMP_STATE_OFF]
    cmp eax, SMP_CPU_ONLINE
    je .online
    cmp eax, SMP_CPU_FAILED
    je .failed_done
    cmp eax, SMP_CPU_PARKED
    je .failed_done
    cmp eax, SMP_CPU_ENTERED
    je .cancel_entered
    cmp eax, SMP_CPU_CANCELLED
    je .wait_cancelled
.cancel_unclaimed:
    ; Once a SIPI reached the ICR, STARTING (or any other nonterminal state)
    ; cannot be declared quiescent by the BSP. Publish cancellation and wait
    ; until a delayed trampoline either PARKs or reports an AP-owned failure.
    test r13d, r13d
    jnz .cancel_pending
    mov edx, SMP_CPU_FAILED
    lock cmpxchg [r12 + SMP_STATE_OFF], edx
    jne .cancel
    jmp .failed_done
.cancel_pending:
    mov edx, SMP_CPU_CANCELLED
    lock cmpxchg [r12 + SMP_STATE_OFF], edx
    jne .cancel
    jmp .wait_cancelled
.cancel_entered:
    mov edx, SMP_CPU_CANCELLED
    lock cmpxchg [r12 + SMP_STATE_OFF], edx
    jne .cancel
.wait_cancelled:
    mov ebx, 100
.cancel_wait:
    mov eax, [r12 + SMP_STATE_OFF]
    cmp eax, SMP_CPU_PARKED
    je .failed_done
    ; A cancelled AP can still take its hardware-init failure path after its
    ; initial state check. FAILED is also quiescent: it is published only once
    ; that AP has finished touching shared startup state and is about to halt.
    cmp eax, SMP_CPU_FAILED
    je .failed_done
    mov rdi, 1000
    call udelay
    dec ebx
    jnz .cancel_wait
    cli
    lea rsi, [rel msg_smp_cancel_timeout]
    call uart_print_str
.cancel_fatal:
    hlt
    jmp .cancel_fatal
.failed_done:
    mfence
    stc
    jmp .done
.online:
    clc
.done:
    pop r13
    pop r12
    pop rbx
    ret

smp_local_apic_init:
    push r12
    push r13

    ; Resolve this processor's firmware-declared NMI input before replacing
    ; any LVT state. Each local interrupt pin is routed independently; an
    ; omitted route remains masked.
    xor r12d, r12d                 ; LINT0 configuration, zero means no route
    xor r13d, r13d                 ; LINT1 configuration, zero means no route
    mov rdi, [rel smp_madt_ptr]
    test rdi, rdi
    jz .route_ready
    mov rsi, [rel phys_state + phys_state_t.direct_map_limit]
    call smp_current_apic_id
    mov edx, eax
    call smp_madt_find_nmi
    jc .failed
    mov r12d, eax
    mov r13d, ecx
.route_ready:
    cmp byte [rel smp_x2apic_mode], 0
    je .xapic
    mov ecx, SMP_X2APIC_TPR_MSR
    xor eax, eax
    xor edx, edx
    wrmsr
    mov ecx, SMP_X2APIC_SVR_MSR
    mov eax, (1 << 8) | SMP_SPURIOUS_VECTOR
    xor edx, edx
    wrmsr
    mov eax, SMP_APIC_MASKED
    xor edx, edx
    mov ecx, SMP_X2APIC_LVT_TIMER_MSR
    wrmsr
    mov ecx, SMP_X2APIC_LVT_LINT0_MSR
    wrmsr
    mov ecx, SMP_X2APIC_LVT_LINT1_MSR
    wrmsr
    mov ecx, SMP_X2APIC_LVT_ERROR_MSR
    wrmsr
    test r12d, r12d
    jz .x2apic_lint1
    mov ecx, SMP_X2APIC_LVT_LINT0_MSR
    mov eax, r12d
    xor edx, edx
    wrmsr
.x2apic_lint1:
    test r13d, r13d
    jz .ready
    mov ecx, SMP_X2APIC_LVT_LINT1_MSR
    mov eax, r13d
    xor edx, edx
    wrmsr
    jmp .ready
.xapic:
    mov rax, [rel smp_lapic_base]
    mov dword [rax + SMP_LAPIC_TPR], 0
    mov dword [rax + SMP_LAPIC_SVR], (1 << 8) | SMP_SPURIOUS_VECTOR
    mov dword [rax + SMP_LAPIC_LVT_TIMER], SMP_APIC_MASKED
    mov dword [rax + SMP_LAPIC_LVT_LINT0], SMP_APIC_MASKED
    mov dword [rax + SMP_LAPIC_LVT_LINT1], SMP_APIC_MASKED
    mov dword [rax + SMP_LAPIC_LVT_ERROR], SMP_APIC_MASKED
    test r12d, r12d
    jz .xapic_lint1
    mov [rax + SMP_LAPIC_LVT_LINT0], r12d
.xapic_lint1:
    test r13d, r13d
    jz .ready
    mov [rax + SMP_LAPIC_LVT_LINT1], r13d
.ready:
    clc
    jmp .done
.failed:
    stc
.done:
    pop r13
    pop r12
    ret

; Verify mandatory vector state and reproduce per-core control/MSR state.
smp_ap_cpu_init:
    push rbx
    push r12
    xor eax, eax
    cpuid
    cmp eax, 0x0D
    jb .failed
    mov eax, 1
    cpuid
    mov r8d, ecx
    mov r9d, edx
    test edx, 1 << 5                ; MSR
    jz .failed
    test edx, 1 << 9                ; local APIC
    jz .failed
    test edx, 1 << 16               ; PAT
    jz .failed
    test edx, 1 << 24               ; FXSAVE/FXRSTOR
    jz .failed
    test edx, 1 << 25
    jz .failed
    test edx, 1 << 26
    jz .failed
    test ecx, 1 << 0
    jz .failed
    test ecx, 1 << 12
    jz .failed
    test ecx, 1 << 26
    jz .failed
    test ecx, 1 << 27
    jz .failed
    test ecx, 1 << 28
    jz .failed
    cmp byte [rel smp_x2apic_mode], 0
    je .basic_ready
    test ecx, 1 << 21               ; x2APIC
    jz .failed
.basic_ready:
    mov eax, 7
    xor ecx, ecx
    cpuid
    mov r10d, ebx
    mov r11d, ecx
    mov r12d, edx
    test ebx, 1 << 5
    jz .failed

    ; Never copy a BSP CR4 bit before the AP has enumerated its prerequisite.
    mov rdi, [rel smp_bsp_cr4]
    mov rax, rdi
    shr rax, 32
    jnz .failed
    mov eax, edi
    and eax, ~SMP_BSP_CR4_ALLOWED
    jnz .failed
    test edi, 1 << 6                ; MCE
    jz .check_pge
    test r9d, 1 << 7
    jz .failed
    test r9d, 1 << 14               ; MCA / IA32_MCG_CAP
    jz .failed
.check_pge:
    test edi, 1 << 7                ; PGE
    jz .check_fsgsbase
    test r9d, 1 << 13
    jz .failed
.check_fsgsbase:
    test edi, 1 << 16
    jz .check_pcid
    test r10d, 1 << 0
    jz .failed
.check_pcid:
    test edi, 1 << 17
    jz .check_osxsave
    test r8d, 1 << 17
    jz .failed
.check_osxsave:
    test edi, 1 << 18
    jz .check_smep
    test r8d, 1 << 26
    jz .failed
.check_smep:
    test edi, 1 << 20
    jz .check_smap
    test r10d, 1 << 7
    jz .failed
.check_smap:
    test edi, 1 << 21
    jz .check_pke
    test r10d, 1 << 20
    jz .failed
.check_pke:
    test edi, 1 << 22
    jz .check_pks
    test r11d, 1 << 3
    jz .failed
.check_pks:
    test edi, 1 << 24
    jz .check_spec_ctrl
    test r11d, 1 << 31
    jz .failed
.check_spec_ctrl:
    cmp byte [rel smp_bsp_has_spec_ctrl], 0
    je .check_xstate
    cmp dword [rel smp_bsp_spec_ctrl + 4], 0
    jne .failed
    mov eax, [rel smp_bsp_spec_ctrl]
    test eax, ~3
    jnz .failed
    test eax, 1
    jz .check_stibp_feature
    test r12d, 1 << 26              ; IBRS
    jz .failed
.check_stibp_feature:
    test eax, 2
    jz .check_xstate
    test r12d, 1 << 27              ; STIBP
    jz .failed

.check_xstate:
    mov eax, 0x0D
    xor ecx, ecx
    cpuid
    mov r10d, eax
    mov r8, rdx
    shl r8, 32
    or r8, r10
    mov r9, [rel smp_bsp_xcr0]
    mov r10, r8
    not r10
    and r10, r9
    jnz .failed
    mov eax, r9d
    and eax, 0x07
    cmp eax, 0x07
    jne .failed

    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .failed
    mov eax, 0x80000001
    cpuid
    mov r10d, [rel smp_bsp_efer]
    test r10d, 1 << 11              ; NXE
    jz .check_syscall
    test edx, 1 << 20
    jz .failed
.check_syscall:
    test r10d, 1 << 0               ; SCE
    jz .state_valid
    test edx, 1 << 11
    jz .failed

.state_valid:
    mov rax, [rel smp_bsp_cr0]
    mov cr0, rax
    ; Enable MCE only after this AP's own MCA banks have been configured.
    mov rax, rdi
    and rax, ~(1 << 6)
    mov cr4, rax
    xor ecx, ecx
    mov eax, [rel smp_bsp_xcr0]
    mov edx, [rel smp_bsp_xcr0 + 4]
    xsetbv
    mov ecx, 0xC0000080
    rdmsr
    mov r8d, [rel smp_bsp_efer]
    and r8d, (1 << 0) | (1 << 11)
    or eax, r8d
    wrmsr
    mov ecx, 0x277
    mov eax, [rel smp_bsp_pat]
    mov edx, [rel smp_bsp_pat + 4]
    wrmsr
    test edi, 1 << 6
    jz .mca_ready
    mov ecx, 0x179                  ; IA32_MCG_CAP
    rdmsr
    mov r8d, eax
    and r8d, 0xFF
    test eax, 1 << 8                ; MCG_CTL_P
    jz .mca_banks
    mov ecx, 0x17B                  ; IA32_MCG_CTL
    mov eax, 0xFFFFFFFF
    mov edx, 0xFFFFFFFF
    wrmsr
.mca_banks:
    xor r9d, r9d
.mca_loop:
    cmp r9d, r8d
    jae .mca_enable
    mov ecx, r9d
    shl ecx, 2
    add ecx, 0x401                  ; IA32_MCi_STATUS
    xor eax, eax
    xor edx, edx
    wrmsr
    dec ecx                         ; IA32_MCi_CTL
    mov eax, 0xFFFFFFFF
    mov edx, 0xFFFFFFFF
    wrmsr
    inc r9d
    jmp .mca_loop
.mca_enable:
    mov rax, cr4
    or rax, 1 << 6
    mov cr4, rax
.mca_ready:
    mov ecx, 0xC0000100
    xor eax, eax
    xor edx, edx
    wrmsr
    mov ecx, 0xC0000102
    wrmsr
    mov ecx, 0xC0000081
    xor eax, eax
    mov edx, 0x00130008
    wrmsr
    mov ecx, 0xC0000082
    lea rax, [rel sys_handler]
    mov rdx, rax
    shr rdx, 32
    wrmsr
    mov ecx, 0xC0000084
    mov eax, 0x200
    xor edx, edx
    wrmsr
    cmp byte [rel smp_bsp_has_spec_ctrl], 0
    je .spec_done
    mov ecx, 0x48
    mov eax, [rel smp_bsp_spec_ctrl]
    mov edx, [rel smp_bsp_spec_ctrl + 4]
    wrmsr
.spec_done:
    mov ecx, 0x1B
    rdmsr
    cmp byte [rel smp_x2apic_mode], 0
    je .require_xapic
    or eax, (1 << 11) | (1 << 10)
    wrmsr
    mov ecx, 0x1B
    rdmsr
    test eax, 1 << 11
    jz .failed
    test eax, 1 << 10
    jz .failed
    jmp .apic_ready
.require_xapic:
    test eax, 1 << 10
    jnz .failed
    test edx, edx
    jnz .failed
    or eax, 1 << 11
    wrmsr
    mov ecx, 0x1B
    rdmsr
    test eax, 1 << 11
    jz .failed
    test edx, edx
    jnz .failed
    and eax, 0xFFFFF000
    cmp eax, [rel smp_lapic_base]
    jne .failed
.apic_ready:
    fninit
    ldmxcsr [rel default_mxcsr]
    clc
    jmp .done
.failed:
    stc
.done:
    pop r12
    pop rbx
    ret

; Prepare scheduler contexts serially, seal trampoline, then start APs.
global smp_start
smp_start:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword [rel smp_release_flag], SMP_RELEASE_WAIT
    mov dword [rel smp_released_cores], 1
    mov byte [rel smp_startup_aborted], 0
    mov byte [rel smp_lapic_ready], 0
    mov r15d, [rel smp_discovered_cores]
    cmp dword [rel smp_discovery_error], 0
    jne .single
    mov edi, SMP_SPURIOUS_VECTOR
    lea rsi, [rel smp_spurious_isr]
    xor edx, edx
    call register_idt_handler
    call smp_local_apic_init
    jc .fatal_lapic
    mov byte [rel smp_lapic_ready], 1
    cmp r15d, 1
    jbe .single
    call smp_capture_bsp_state

    mov ecx, 0xC0000101
    rdmsr
    shl rdx, 32
    or rax, rdx
    mov r14, rax
    mov r12d, 1
.prepare_loop:
    cmp r12d, r15d
    jae .prepared
    mov edi, r12d
    call smp_prepare_context
    jc .prepare_failed
    mov rax, r12
    shl rax, 6
    lea r13, [rel smp_mailboxes]
    add r13, rax
    mov rax, [r13 + SMP_PERCPU_OFF]
    mov rdx, rax
    shr rdx, 32
    mov ecx, 0xC0000101
    wrmsr
    call sched_init_real
    test rax, rax
    jz .prepare_failed_restore
    jmp .next_prepare
.prepare_failed_restore:
    mov dword [r13 + SMP_STATE_OFF], SMP_CPU_FAILED
    jmp .abort_prepare
.prepare_failed:
    mov rax, r12
    shl rax, 6
    lea r13, [rel smp_mailboxes]
    add r13, rax
    mov dword [r13 + SMP_STATE_OFF], SMP_CPU_FAILED
.abort_prepare:
    mov rax, r14
    mov rdx, rax
    shr rdx, 32
    mov ecx, 0xC0000101
    wrmsr
    jmp .abort_startup
.next_prepare:
    inc r12d
    jmp .prepare_loop
.prepared:
    mov rax, r14
    mov rdx, rax
    shr rdx, 32
    mov ecx, 0xC0000101
    wrmsr
    call smp_prepare_trampoline
    jc .fatal_prepare
    mov dword [rel smp_online_pending], 1
    mov r12d, 1
.start_loop:
    cmp r12d, r15d
    jae .rendezvous_done
    mov rax, r12
    shl rax, 6
    lea r13, [rel smp_mailboxes]
    add r13, rax
    cmp dword [r13 + SMP_STATE_OFF], SMP_CPU_FAILED
    je .next_start
    mov edi, [r13 + SMP_APIC_ID_OFF]
    mov rsi, r13
    call smp_start_one
    jc .abort_startup
    inc dword [rel smp_online_pending]
.next_start:
    inc r12d
    jmp .start_loop
.rendezvous_done:
    lea rsi, [rel msg_smp_rendezvous]
    call uart_print_str
    mov eax, [rel smp_online_pending]
    call uart_print_dec
    mov al, '/'
    call uart_putc
    mov eax, [rel smp_discovered_cores]
    call uart_print_dec
    lea rsi, [rel msg_crlf_smp]
    call uart_print_str
    jmp .done
.abort_startup:
    ; ponytail: all-or-nothing boot keeps logical IDs dense; add an online-ID
    ; map only when partial CPU hotplug is actually supported.
    mov byte [rel smp_startup_aborted], 1
    mov dword [rel smp_online_pending], 1
    mov dword [rel smp_release_flag], SMP_RELEASE_ABORT
    mfence
    ; Every AP that reached ONLINE is polling the release flag with IF=0.
    ; Do not resume BSP-only boot until each has acknowledged its park.
    mov ebx, 100
.abort_poll:
    mov r12d, 1
.abort_scan:
    cmp r12d, r15d
    jae .abort_quiesced
    mov rax, r12
    shl rax, 6
    lea r13, [rel smp_mailboxes]
    add r13, rax
    mov eax, [r13 + SMP_STATE_OFF]
    cmp eax, SMP_CPU_OFFLINE
    je .abort_next
    cmp eax, SMP_CPU_FAILED
    je .abort_next
    cmp eax, SMP_CPU_PARKED
    je .abort_next
    mov edi, 1000
    call udelay
    dec ebx
    jnz .abort_poll
    cli
    lea rsi, [rel msg_smp_abort_timeout]
    call uart_print_str
.abort_fatal:
    hlt
    jmp .abort_fatal
.abort_next:
    inc r12d
    jmp .abort_scan
.abort_quiesced:
    lea rsi, [rel msg_smp_startup_abort]
    call uart_print_str
    jmp .done
.fatal_prepare:
    lea rsi, [rel msg_smp_trampoline_fail]
    call uart_print_str
    cli
.fatal_halt:
    hlt
    jmp .fatal_halt
.fatal_lapic:
    lea rsi, [rel msg_smp_lapic_fail]
    call uart_print_str
    cli
    jmp .fatal_halt
.single:
    mov dword [rel smp_online_pending], 1
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; Called only after BSP shared initialization and initial fiber creation.
global smp_release
smp_release:
    push rbx
    push r12
    mov eax, 1
    cmp byte [rel smp_startup_aborted], 0
    jne .count_ok
    mov eax, [rel smp_online_pending]
    test eax, eax
    jnz .count_ok
    mov eax, 1
.count_ok:
    mov r12d, eax
    mov [rel smp_active_cores], eax
    mov dword [rel smp_released_cores], 1
    mov rdx, [rel boot_info_ptr]
    test rdx, rdx
    jz .publish
    mov [rdx + BOOT_INFO_SMP_CORES_OFF], eax
.publish:
    lea rsi, [rel msg_smp_online]
    call uart_print_str
    mov eax, [rel smp_active_cores]
    call uart_print_dec
    lea rsi, [rel msg_smp_processors]
    call uart_print_str
    cmp byte [rel smp_startup_aborted], 0
    jne .released
    mov dword [rel smp_release_flag], SMP_RELEASE_ACK
    mfence
    cmp r12d, 1
    jbe .released
    mov ebx, 100
.release_wait:
    mov eax, [rel smp_released_cores]
    cmp eax, r12d
    je .released
    mov edi, 1000
    call udelay
    dec ebx
    jnz .release_wait
    cli
    lea rsi, [rel msg_smp_release_timeout]
    call uart_print_str
.release_fatal:
    hlt
    jmp .release_fatal
.released:
    lea rsi, [rel msg_smp_released]
    call uart_print_str
    mov eax, [rel smp_released_cores]
    call uart_print_dec
    mov al, '/'
    call uart_putc
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_smp_processors]
    call uart_print_str
    cmp byte [rel smp_startup_aborted], 0
    jne .release_published
    mov dword [rel smp_release_flag], SMP_RELEASE_RUN
.release_published:
    mfence
    cmp byte [rel smp_lapic_ready], 0
    je .done
    sti
.done:
    pop r12
    pop rbx
    ret

smp_spurious_isr:
    iretq

; RDI=mailbox from the copied trampoline; private stack already loaded.
smp_ap_entry:
    cli
    cld
    mov r12, rdi
    cmp dword [r12 + SMP_STATE_OFF], SMP_CPU_ENTERED
    jne .abort_park
    mov rax, [r12 + SMP_GDTR_PTR_OFF]
    test rax, rax
    jz .failed
    lgdt [rax]
    push qword 0x08
    lea rax, [rel .cs_ready]
    push rax
    retfq
.cs_ready:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov ax, 0x28
    ltr ax
    lidt [rel idt_ptr]
    mov rax, [r12 + SMP_PERCPU_OFF]
    test rax, rax
    jz .failed
    mov rdx, rax
    shr rdx, 32
    mov ecx, 0xC0000101
    wrmsr
    mov rax, [gs:percpu_t.self]
    cmp rax, [r12 + SMP_PERCPU_OFF]
    jne .failed
    call smp_ap_cpu_init
    jc .failed
    call smp_local_apic_init
    jc .failed
    call ucpu_topology_decode_current
    ; Cache topology storage is global and was populated by the BSP. Running
    ; the scanner concurrently here would race every AP over that one table.
    mfence
    mov eax, SMP_CPU_ENTERED
    mov edx, SMP_CPU_ONLINE
    lock cmpxchg [r12 + SMP_STATE_OFF], edx
    jne .abort_park
.release_wait:
    pause
    mov eax, [rel smp_release_flag]
    cmp eax, SMP_RELEASE_WAIT
    je .release_wait
    cmp eax, SMP_RELEASE_ACK
    jne .abort_park
    lock inc dword [rel smp_released_cores]
    mfence
.run_wait:
    pause
    mov eax, [rel smp_release_flag]
    cmp eax, SMP_RELEASE_ACK
    je .run_wait
    cmp eax, SMP_RELEASE_RUN
    jne .abort_park
    lfence
    sti
    jmp sched_core_loop
.failed:
    mov dword [r12 + SMP_STATE_OFF], SMP_CPU_FAILED
    mfence
    cli
.failed_park:
    hlt
    jmp .failed_park
.abort_park:
    mov dword [r12 + SMP_STATE_OFF], SMP_CPU_PARKED
    mfence
    cli
.abort_halt:
    hlt
    jmp .abort_halt

; Position-independent SIPI template. No stack is touched until mailbox match.
align 16
smp_trampoline_template:
[BITS 16]
    cli
    cld
    mov ax, cs
    mov ds, ax
    mov es, ax
    mov ss, ax
    xor esp, esp
    lgdt [cs:smp_trampoline_gdtr - smp_trampoline_template]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    db 0x66, 0xEA
smp_trampoline_pm32_target:
    dd 0
    dw 0x08

[BITS 32]
smp_trampoline_pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    db 0xBD
smp_trampoline_base_imm:
    dd 0
    mov eax, 1
    cpuid
    mov esi, edx
    and esi, (1 << 25) | (1 << 26)
    cmp esi, (1 << 25) | (1 << 26)
    jne .park32
    mov esi, ecx
    and esi, (1 << 0) | (1 << 12) | (1 << 26) | (1 << 28)
    cmp esi, (1 << 0) | (1 << 12) | (1 << 26) | (1 << 28)
    jne .park32
    mov eax, [ebp + smp_trampoline_cr4 - smp_trampoline_template]
    mov cr4, eax
    mov eax, [ebp + smp_trampoline_cr3 - smp_trampoline_template]
    mov cr3, eax
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .park32
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29               ; long mode
    jz .park32
    mov esi, [ebp + smp_trampoline_efer - smp_trampoline_template]
    test esi, 1 << 11
    jz .efer_supported
    test edx, 1 << 20               ; NX
    jz .park32
.efer_supported:
    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    or eax, [ebp + smp_trampoline_efer - smp_trampoline_template]
    wrmsr
    mov eax, cr0
    and eax, ~((1 << 2) | (1 << 29) | (1 << 30))
    or eax, (1 << 31) | (1 << 16) | (1 << 5) | (1 << 1) | 1
    mov cr0, eax
    jmp far [ebp + smp_trampoline_long64_ptr - smp_trampoline_template]
.park32:
    cli
    hlt
    jmp .park32

[BITS 64]
smp_trampoline_long64:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    xor eax, eax
    cpuid
    mov r13d, eax
    cmp r13d, 0x1F
    jb .try_b
    mov eax, 0x1F
    xor ecx, ecx
    cpuid
    test ebx, ebx
    jz .try_b
    mov r12d, edx
    jmp .id_ready
.try_b:
    cmp r13d, 0x0B
    jb .legacy_id
    mov eax, 0x0B
    xor ecx, ecx
    cpuid
    test ebx, ebx
    jz .legacy_id
    mov r12d, edx
    jmp .id_ready
.legacy_id:
    mov eax, 1
    cpuid
    mov r12d, ebx
    shr r12d, 24
.id_ready:
    mov rbx, [rbp + smp_trampoline_mailboxes - smp_trampoline_template]
    mov ecx, [rbp + smp_trampoline_mailbox_count - smp_trampoline_template]
.scan:
    test ecx, ecx
    jz .park
    cmp [rbx + SMP_APIC_ID_OFF], r12d
    jne .next
    mov eax, SMP_CPU_STARTING
    mov edx, SMP_CPU_ENTERED
    lock cmpxchg [rbx + SMP_STATE_OFF], edx
    jne .claim_rejected
    mov rsp, [rbx + SMP_STACK_TOP_OFF]
    test rsp, rsp
    jz .claim_failed
    and rsp, -16
    mov rdi, rbx
    jmp qword [rbp + smp_trampoline_ap_entry - smp_trampoline_template]
.claim_rejected:
    cmp eax, SMP_CPU_FAILED
    je .claim_parked
    cmp eax, SMP_CPU_CANCELLED
    jne .park
.claim_parked:
    mov dword [rbx + SMP_STATE_OFF], SMP_CPU_PARKED
    mfence
    jmp .park
.claim_failed:
    mov dword [rbx + SMP_STATE_OFF], SMP_CPU_FAILED
    mfence
    jmp .park
.next:
    add rbx, SMP_MAILBOX_STRIDE
    dec ecx
    jmp .scan
.park:
    cli
    hlt
    jmp .park

align 8
smp_trampoline_gdt:
    dq 0
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
    dq 0x00AF9A000000FFFF
smp_trampoline_gdt_end:
smp_trampoline_gdtr:
    dw smp_trampoline_gdt_end - smp_trampoline_gdt - 1
smp_trampoline_gdtr_base:
    dd 0
smp_trampoline_long64_ptr:
smp_trampoline_long64_target:
    dd 0
    dw 0x18
align 8
smp_trampoline_cr3:           dd 0
smp_trampoline_cr4:           dd 0
smp_trampoline_efer:          dd 0
                              dd 0
smp_trampoline_mailboxes:     dq 0
smp_trampoline_mailbox_count: dd 0
                              dd 0
smp_trampoline_ap_entry:      dq 0
smp_trampoline_end:
[BITS 64]

%if smp_trampoline_end - smp_trampoline_template > BOOT_AP_TRAMPOLINE_BYTES
    %error "AP trampoline exceeds its firmware-owned page"
%endif

section .data
align 8
global smp_lapic_base
smp_lapic_base:             dq 0xFEE00000
smp_madt_ptr:               dq 0
smp_bsp_cr0:                dq 0
smp_bsp_cr4:                dq 0
smp_bsp_xcr0:               dq 0
smp_bsp_efer:               dq 0
smp_bsp_pat:                dq 0
smp_bsp_spec_ctrl:          dq 0
smp_discovered_cores:       dd 1
smp_online_pending:         dd 1
smp_release_flag:           dd 0
smp_released_cores:         dd 1
smp_discovery_error:        dd 0
smp_bsp_apic_id:            dd 0
smp_x2apic_mode:            db 0
smp_dmar_seen:               db 0
smp_x2apic_veto:             db 0
smp_bsp_has_spec_ctrl:      db 0
smp_startup_aborted:        db 0
smp_lapic_ready:            db 0
msg_smp_discovered:         db "SMP: discovered ", 0
msg_smp_xapic:              db "SMP: APIC mode xAPIC", 0x0D, 0x0A, 0
msg_smp_x2apic:             db "SMP: APIC mode x2APIC", 0x0D, 0x0A, 0
msg_smp_x2apic_veto:        db "SMP: firmware DMAR veto contradicts active x2APIC", 0x0D, 0x0A, 0
msg_smp_fatal:               db "SMP: fatal APIC policy failure", 0x0D, 0x0A, 0
msg_smp_rendezvous:         db "SMP: rendezvous ", 0
msg_smp_online:             db "SMP: online ", 0
msg_smp_released:           db "SMP: released ", 0
msg_smp_processors:         db " processors", 0x0D, 0x0A, 0
msg_smp_disabled:           db "SMP: disabled by validation code ", 0
msg_smp_startup_abort:      db "SMP: AP startup failed; using BSP only", 0x0D, 0x0A, 0
msg_smp_trampoline_fail:    db "KERNEL PANIC: AP trampoline ownership/sealing failed", 0x0D, 0x0A, 0
msg_smp_lapic_fail:         db "KERNEL PANIC: invalid MADT local NMI routing", 0x0D, 0x0A, 0
msg_smp_release_timeout:    db "KERNEL PANIC: AP release acknowledgment timed out", 0x0D, 0x0A, 0
msg_smp_cancel_timeout:     db "KERNEL PANIC: timed-out AP did not quiesce", 0x0D, 0x0A, 0
msg_smp_abort_timeout:      db "KERNEL PANIC: AP abort barrier timed out", 0x0D, 0x0A, 0
msg_crlf_smp:               db 0x0D, 0x0A, 0

section .bss
alignb 64
smp_mailboxes:              resb SMP_MAX_CPUS * SMP_MAILBOX_STRIDE
alignb 16
smp_apic_ids:               resd SMP_MAX_CPUS
alignb 64
smp_percpu_table:           resb SMP_MAX_CPUS * percpu_t_size
alignb 64
smp_gdt_table:              resb SMP_MAX_CPUS * SMP_GDT_STRIDE
alignb 16
smp_gdtr_table:             resb SMP_MAX_CPUS * SMP_GDTR_STRIDE
alignb 128
smp_tss_table:              resb SMP_MAX_CPUS * SMP_TSS_STRIDE
alignb 4096
smp_ist_stacks:             resb SMP_MAX_CPUS * SMP_IST_BYTES_PER_CPU

section .text
%endif ; KERNEL_ARCH_X86_64_SMP_ASM
