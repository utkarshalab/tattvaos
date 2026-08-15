; =============================================================================
; Tattva OS — lib/hw/unuma/detect.asm
; =============================================================================
; ACPI SRAT Processor Affinity parser: maps each logical processor's APIC /
; x2APIC ID to its NUMA proximity domain.
;
; lib/mem/numa/numa_detect.asm already parses SRAT Memory Affinity (Type 1)
; entries into node-to-physical-range data. It does not touch Type 0
; (Processor Local APIC Affinity) or Type 2 (Processor Local x2APIC
; Affinity) entries, so nothing in the tree currently knows which node a
; given CPU core belongs to from real firmware data — the closest existing
; thing, lib/mem/virt/rt_safe/sched_affinity.asm's cpu_to_node table, is a
; hardcoded placeholder (CPUs 0-7 -> node 0, 8-15 -> node 1; see its own
; "Initialize default CPU-to-Node mapping" comment). This file reuses the
; SRAT physical address numa_detect_init already located (numa_srat_phys_addr)
; instead of re-walking RSDP -> XSDT/RSDT itself, and must therefore run
; after numa_detect_init.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UNUMA_DETECT_ASM
%define LIB_HW_UNUMA_DETECT_ASM

[BITS 64]

UNUMA_MAX_CPUS equ 256

section .bss
global unuma_cpu_node_table
global unuma_cpu_node_count

; unuma_cpu_node_table[x2apic_id] = proximity domain (node id), 0xFFFFFFFF = unset
unuma_cpu_node_table: resd UNUMA_MAX_CPUS
unuma_cpu_node_count: resq 1         ; count of entries actually parsed from SRAT

section .text

; -----------------------------------------------------------------------------
; unuma_cpu_detect_init — parses SRAT Type 0 / Type 2 entries into
; unuma_cpu_node_table. Must run after numa_detect_init.
; Input:  none
; Output: RAX = number of processor-affinity entries recorded (0 if SRAT
;         was not found or carried none)
; -----------------------------------------------------------------------------
global unuma_cpu_detect_init
unuma_cpu_detect_init:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15

    ; Fill table with "unset" sentinel first
    lea rdi, [rel unuma_cpu_node_table]
    mov rcx, UNUMA_MAX_CPUS
    mov eax, 0xFFFFFFFF
    cld
    rep stosd

    mov qword [rel unuma_cpu_node_count], 0

    mov r14, [rel numa_srat_phys_addr]
    test r14, r14
    jz .done                        ; no SRAT located by numa_detect_init

    mov rdi, r14
    mov r10d, [rdi + 4]              ; SRAT Length
    cmp r10d, 48
    jbe .done

    lea r11, [rdi + 48]              ; current entry pointer
    lea r12, [rdi + r10]             ; end of table
    xor r13, r13                     ; recorded count = 0

.entry_loop:
    cmp r11, r12
    jae .done

    movzx eax, byte [r11]            ; entry Type
    movzx ecx, byte [r11 + 1]        ; entry Length
    cmp ecx, 2
    jb .done                         ; sanity check

    cmp eax, 0                       ; Type 0: Processor Local APIC Affinity
    je .type0
    cmp eax, 2                       ; Type 2: Processor Local x2APIC Affinity
    je .type2
    jmp .next_entry

.type0:
    cmp ecx, 16
    jne .next_entry

    mov edx, [r11 + 4]               ; Flags (offset 4, dword)
    test dl, 1                       ; Enabled?
    jz .next_entry

    movzx ebx, byte [r11 + 3]        ; APIC ID (offset 3)

    ; Proximity domain is split: low byte @ offset 2, bits[31:8] as three
    ; bytes @ offset 9-11. Read the 4-byte-aligned dword at offset 8 (Local
    ; SAPIC EID + the three domain bytes) and drop the EID byte.
    movzx eax, byte [r11 + 2]
    mov edx, [r11 + 8]
    shr edx, 8                       ; EDX = domain bytes[9..11] in bits[23:0]
    shl edx, 8                       ; reposition to bits[31:8]
    or eax, edx                      ; EAX = full 32-bit proximity domain

    mov rdi, rbx
    mov rsi, rax
    call .record
    jmp .next_entry

.type2:
    cmp ecx, 24
    jne .next_entry

    mov edx, [r11 + 12]              ; Flags (offset 12, dword)
    test dl, 1                       ; Enabled?
    jz .next_entry

    mov ebx, [r11 + 8]               ; x2APIC ID (offset 8, dword)
    mov eax, [r11 + 4]               ; Proximity Domain (offset 4, dword)

    mov rdi, rbx
    mov rsi, rax
    call .record

.next_entry:
    add r11, rcx
    jmp .entry_loop

.done:
    mov rax, [rel unuma_cpu_node_count]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; ---- internal: record (apic_id=RDI, node_id=RSI) into the table ----
; Clobbers: RAX, RCX only; not part of the public ABI.
.record:
    cmp rdi, UNUMA_MAX_CPUS
    jae .record_skip
    mov rax, rdi
    mov ecx, esi
    mov [rel unuma_cpu_node_table + rax * 4], ecx
    inc qword [rel unuma_cpu_node_count]
.record_skip:
    ret

; -----------------------------------------------------------------------------
; unuma_node_of_cpu — looks up the proximity domain for an APIC/x2APIC ID
; Input:
;   RDI = apic_id (x2APIC ID)
; Output:
;   RAX = 1 if known, 0 if out of range or never seen in SRAT
;   RSI = node_id (only meaningful if RAX = 1)
; -----------------------------------------------------------------------------
global unuma_node_of_cpu
unuma_node_of_cpu:
    cmp rdi, UNUMA_MAX_CPUS
    jae .unknown

    mov eax, [rel unuma_cpu_node_table + rdi * 4]
    cmp eax, 0xFFFFFFFF
    je .unknown

    mov esi, eax
    mov rax, 1
    ret

.unknown:
    xor rax, rax
    xor rsi, rsi
    ret

%endif ; LIB_HW_UNUMA_DETECT_ASM
