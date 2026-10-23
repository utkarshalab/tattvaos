; Native hostile-input harness for kernel/arch/x86_64/madt.asm.
; Exit status 0 means every parser contract passed. Each nonzero status maps
; to one independently constructed case, keeping CI failures reproducible.

[BITS 64]
default rel

%include "kernel/arch/x86_64/madt.asm"

section .text
global _start
_start:
    ; Valid, unordered topology: firmware lists an AP before the BSP and mixes
    ; legacy Local APIC and x2APIC records. Disabled CPUs are ignored.
    call reset_table
    call parse_default
    jc .fail_1
    cmp eax, 3
    jne .fail_1
    cmp edx, 3
    jne .fail_1
    cmp dword [rel output_ids], 7
    jne .fail_1
    cmp dword [rel output_ids + 4], 2
    jne .fail_1
    cmp dword [rel output_ids + 8], 300
    jne .fail_1
    mov eax, 0xFEC00000
    cmp qword [rel lapic_output], rax
    jne .fail_1

    ; Corrupting any covered byte must be caught by the ACPI checksum.
    call reset_table
    xor byte [rel working_table + 20], 1
    call parse_default
    jnc .fail_2
    test eax, eax
    jnz .fail_2
    cmp edx, SMP_MADT_ERR_HEADER
    jne .fail_2

    ; A valid declared length outside the accessible mapping is a span error.
    call reset_table
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + MADT_BYTES - 1]
    mov edx, 7
    lea rcx, [rel output_ids]
    mov r8d, 8
    lea r9, [rel lapic_output]
    call smp_madt_parse
    jnc .fail_3
    cmp edx, SMP_MADT_ERR_SPAN
    jne .fail_3

    ; Entry length zero must not turn the iterator into an infinite loop.
    call reset_table
    mov byte [rel working_table + FIRST_ENTRY_OFF + 1], 0
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_4
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_4

    ; Duplicate enabled APIC IDs are ambiguous and rejected.
    call reset_table
    mov byte [rel working_table + SECOND_ENTRY_OFF + 3], 2
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_5
    cmp edx, SMP_MADT_ERR_DUPLICATE
    jne .fail_5

    ; Capacity is a hard boundary; the parser never silently truncates CPUs.
    call reset_table
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + MADT_BYTES]
    mov edx, 7
    lea rcx, [rel output_ids]
    mov r8d, 2
    lea r9, [rel lapic_output]
    call smp_madt_parse
    jnc .fail_6
    cmp edx, SMP_MADT_ERR_CAPACITY
    jne .fail_6

    ; The executing CPU must appear exactly once among enabled processors.
    call reset_table
    mov byte [rel working_table + SECOND_ENTRY_OFF + 3], 8
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_7
    cmp edx, SMP_MADT_ERR_BSP
    jne .fail_7

    ; Firmware input and caller outputs may not alias.
    call reset_table
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + MADT_BYTES]
    mov edx, 7
    mov rcx, rdi
    mov r8d, 8
    lea r9, [rel lapic_output]
    call smp_madt_parse
    jnc .fail_8
    cmp edx, SMP_MADT_ERR_SPAN
    jne .fail_8

    ; LAPIC overrides must remain page-aligned and below 4 GiB.
    call reset_table
    mov eax, 0xFEC00001
    mov qword [rel working_table + OVERRIDE_ADDR_OFF], rax
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_9
    cmp edx, SMP_MADT_ERR_LAPIC
    jne .fail_9

    ; Output capacity itself is bounded before any table bytes are emitted.
    call reset_table
    lea rdi, [rel working_table]
    lea rsi, [rel working_table + MADT_BYTES]
    mov edx, 7
    lea rcx, [rel output_ids]
    mov r8d, SMP_MADT_MAX_OUTPUT_IDS + 1
    lea r9, [rel lapic_output]
    call smp_madt_parse
    jnc .fail_10
    cmp edx, SMP_MADT_ERR_INPUT
    jne .fail_10

    ; The architectural x2APIC broadcast destination is never a CPU ID.
    call reset_table
    mov dword [rel working_table + X2APIC_ID_OFF], 0xFFFFFFFF
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_11
    cmp edx, SMP_MADT_ERR_APIC_ID
    jne .fail_11

    ; QEMU-style Local APIC NMI wildcard routes all enabled processors.
    call reset_table
    lea rsi, [rel route_type4_wild]
    mov ecx, ROUTE_TYPE4_WILD_BYTES
    call append_routes
    call parse_default
    jc .fail_12
    call find_default
    jc .fail_12
    test eax, eax
    jnz .fail_12
    cmp ecx, 0x400
    jne .fail_12

    ; Explicit active-low/level flags become LAPIC LVT polarity/trigger bits.
    call reset_table
    lea rsi, [rel route_type4_low_level]
    mov ecx, ROUTE_TYPE4_LOW_LEVEL_BYTES
    call append_routes
    call parse_default
    jc .fail_13
    call find_default
    jc .fail_13
    cmp eax, 0xA400
    jne .fail_13
    test ecx, ecx
    jnz .fail_13

    ; Wildcard and exact-UID records can describe independent pins. Identical
    ; duplicates are accepted because they describe the same wiring.
    call reset_table
    lea rsi, [rel routes_dual_lint]
    mov ecx, ROUTES_DUAL_LINT_BYTES
    call append_routes
    call parse_default
    jc .fail_14
    call find_default
    jc .fail_14
    cmp eax, 0xA400
    jne .fail_14
    cmp ecx, 0x400
    jne .fail_14

    ; Local x2APIC NMI uses a 32-bit UID and 0xffffffff as its wildcard.
    call reset_table
    lea rsi, [rel route_type10_wild]
    mov ecx, ROUTE_TYPE10_WILD_BYTES
    call append_routes
    call parse_default
    jc .fail_15
    call find_default
    jc .fail_15
    test eax, eax
    jnz .fail_15
    cmp ecx, 0x400
    jne .fail_15

    ; Reserved polarity and trigger encodings are rejected by the primary
    ; parser rather than deferred to LAPIC programming.
    call reset_table
    lea rsi, [rel route_bad_polarity]
    mov ecx, ROUTE_BAD_POLARITY_BYTES
    call append_routes
    call parse_default
    jnc .fail_16
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_16

    call reset_table
    lea rsi, [rel route_bad_trigger]
    mov ecx, ROUTE_BAD_TRIGGER_BYTES
    call append_routes
    call parse_default
    jnc .fail_17
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_17

    ; LINT pins outside 0/1 and nonzero x2APIC reserved bytes are malformed.
    call reset_table
    lea rsi, [rel route_bad_pin]
    mov ecx, ROUTE_BAD_PIN_BYTES
    call append_routes
    call parse_default
    jnc .fail_18
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_18

    call reset_table
    lea rsi, [rel route_bad_reserved]
    mov ecx, ROUTE_BAD_RESERVED_BYTES
    call append_routes
    call parse_default
    jnc .fail_19
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_19

    ; Conflicting configurations for the same pin are ambiguous.
    call reset_table
    lea rsi, [rel routes_wild_conflict]
    mov ecx, ROUTES_WILD_CONFLICT_BYTES
    call append_routes
    call parse_default
    jc .fail_20
    call find_default
    jnc .fail_20
    test eax, eax
    jnz .fail_20
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_20

    ; A valid route for another UID is not applicable to this processor.
    call reset_table
    lea rsi, [rel route_other_uid]
    mov ecx, ROUTE_OTHER_UID_BYTES
    call append_routes
    call parse_default
    jc .fail_21
    call find_default
    jc .fail_21
    test eax, eax
    jnz .fail_21
    test ecx, ecx
    jnz .fail_21

    ; Both NMI record formats have fixed architectural lengths.
    call reset_table
    lea rsi, [rel route_bad_type4_length]
    mov ecx, ROUTE_BAD_TYPE4_LENGTH_BYTES
    call append_routes
    call parse_default
    jnc .fail_22
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_22

    call reset_table
    lea rsi, [rel route_bad_type10_length]
    mov ecx, ROUTE_BAD_TYPE10_LENGTH_BYTES
    call append_routes
    call parse_default
    jnc .fail_23
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_23

    ; A type-10 exact UID route uses the ACPI UID, not the x2APIC ID.
    call reset_table
    lea rsi, [rel route_type10_exact]
    mov ecx, ROUTE_TYPE10_EXACT_BYTES
    call append_routes
    call parse_default
    jc .fail_24
    call find_ap_300
    jc .fail_24
    cmp eax, 0x400
    jne .fail_24
    test ecx, ecx
    jnz .fail_24

    ; Reserved processor flag bits and reserved fixed-structure fields fail
    ; closed even when the affected processor would otherwise be ignored.
    call reset_table
    or dword [rel working_table + FIRST_ENTRY_OFF + 4], 4
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_25
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_25

    call reset_table
    mov word [rel working_table + X2APIC_RESERVED_OFF], 1
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_26
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_26

    call reset_table
    mov word [rel working_table + OVERRIDE_RESERVED_OFF], 1
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_27
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_27

    call reset_table
    or dword [rel working_table + X2APIC_FLAGS_OFF], 4
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_28
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_28

    ; Online-capable is defined only for disabled processors. Once enabled,
    ; bit 1 is reserved in both processor record formats.
    call reset_table
    or dword [rel working_table + FIRST_ENTRY_OFF + 4], 2
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_29
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_29

    call reset_table
    or dword [rel working_table + X2APIC_FLAGS_OFF], 2
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_default
    jnc .fail_30
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_30

    ; External-interrupt topology is parsed by an independently bounded pass.
    call reset_table
    lea rsi, [rel irq_routes_valid]
    mov ecx, IRQ_ROUTES_VALID_BYTES
    call append_routes
    call parse_irqs_default
    jc .fail_31
    cmp eax, 1
    jne .fail_31
    cmp ecx, 1
    jne .fail_31
    cmp dword [rel irq_ioapics + SMP_MADT_IOAPIC_ID_OFF], 3
    jne .fail_31
    cmp dword [rel irq_ioapics + SMP_MADT_IOAPIC_ADDR_OFF], 0xFEC00000
    jne .fail_31
    cmp dword [rel irq_ioapics + SMP_MADT_IOAPIC_GSI_OFF], 0
    jne .fail_31
    cmp dword [rel irq_isos + SMP_MADT_ISO_SOURCE_OFF], 0
    jne .fail_31
    cmp dword [rel irq_isos + SMP_MADT_ISO_GSI_OFF], 2
    jne .fail_31

    ; Identical override duplicates are harmless and collapse to one route.
    call reset_table
    lea rsi, [rel irq_routes_duplicate_iso]
    mov ecx, IRQ_ROUTES_DUPLICATE_ISO_BYTES
    call append_routes
    call parse_irqs_default
    jc .fail_32
    cmp eax, 1
    jne .fail_32
    cmp ecx, 1
    jne .fail_32

    ; Conflicting definitions for one ISA source fail closed.
    call reset_table
    lea rsi, [rel irq_routes_conflicting_iso]
    mov ecx, IRQ_ROUTES_CONFLICTING_ISO_BYTES
    call append_routes
    call parse_irqs_default
    jnc .fail_33
    cmp edx, SMP_MADT_ERR_DUPLICATE
    jne .fail_33

    ; Controller IDs, MMIO pages, and GSI bases are unique ownership keys.
    call reset_table
    lea rsi, [rel irq_routes_duplicate_ioapic]
    mov ecx, IRQ_ROUTES_DUPLICATE_IOAPIC_BYTES
    call append_routes
    call parse_irqs_default
    jnc .fail_34
    cmp edx, SMP_MADT_ERR_DUPLICATE
    jne .fail_34

    ; Fixed-format reserved fields and override encodings are validated.
    call reset_table
    lea rsi, [rel irq_route_bad_reserved]
    mov ecx, IRQ_ROUTE_BAD_RESERVED_BYTES
    call append_routes
    call parse_irqs_default
    jnc .fail_35
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_35

    call reset_table
    lea rsi, [rel irq_route_bad_flags]
    mov ecx, IRQ_ROUTE_BAD_FLAGS_BYTES
    call append_routes
    call parse_irqs_default
    jnc .fail_36
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_36

    ; Capacity exhaustion is reported instead of truncating controllers.
    call reset_table
    lea rsi, [rel irq_routes_two_ioapics]
    mov ecx, IRQ_ROUTES_TWO_IOAPICS_BYTES
    call append_routes
    lea rdi, [rel working_table]
    mov eax, [rel working_table + 4]
    lea rsi, [rel working_table]
    add rsi, rax
    lea rdx, [rel irq_ioapics]
    mov ecx, 1
    lea r8, [rel irq_isos]
    mov r9d, 16
    call smp_madt_parse_irqs
    jnc .fail_37
    cmp edx, SMP_MADT_ERR_CAPACITY
    jne .fail_37

    ; Firmware bytes can never alias parser outputs.
    call reset_table
    lea rsi, [rel irq_routes_valid]
    mov ecx, IRQ_ROUTES_VALID_BYTES
    call append_routes
    lea rdi, [rel working_table]
    mov eax, [rel working_table + 4]
    lea rsi, [rel working_table]
    add rsi, rax
    mov rdx, rdi
    mov ecx, 4
    lea r8, [rel irq_isos]
    mov r9d, 16
    call smp_madt_parse_irqs
    jnc .fail_38
    cmp edx, SMP_MADT_ERR_SPAN
    jne .fail_38

    ; Declared bytes beyond the accessible map and zero-length entries reject.
    call reset_table
    lea rsi, [rel irq_routes_valid]
    mov ecx, IRQ_ROUTES_VALID_BYTES
    call append_routes
    lea rdi, [rel working_table]
    mov eax, [rel working_table + 4]
    lea rsi, [rel working_table]
    add rsi, rax
    dec rsi
    lea rdx, [rel irq_ioapics]
    mov ecx, 4
    lea r8, [rel irq_isos]
    mov r9d, 16
    call smp_madt_parse_irqs
    jnc .fail_39
    cmp edx, SMP_MADT_ERR_SPAN
    jne .fail_39

    call reset_table
    lea rsi, [rel irq_routes_valid]
    mov ecx, IRQ_ROUTES_VALID_BYTES
    call append_routes
    mov byte [rel working_table + MADT_BYTES + 1], 0
    lea rdi, [rel working_table]
    call fix_checksum
    call parse_irqs_default
    jnc .fail_40
    cmp edx, SMP_MADT_ERR_ENTRY
    jne .fail_40

    xor edi, edi
    jmp .exit

.fail_1:
    mov edi, 1
    jmp .exit
.fail_2:
    mov edi, 2
    jmp .exit
.fail_3:
    mov edi, 3
    jmp .exit
.fail_4:
    mov edi, 4
    jmp .exit
.fail_5:
    mov edi, 5
    jmp .exit
.fail_6:
    mov edi, 6
    jmp .exit
.fail_7:
    mov edi, 7
    jmp .exit
.fail_8:
    mov edi, 8
    jmp .exit
.fail_9:
    mov edi, 9
    jmp .exit
.fail_10:
    mov edi, 10
    jmp .exit
.fail_11:
    mov edi, 11
    jmp .exit
.fail_12:
    mov edi, 12
    jmp .exit
.fail_13:
    mov edi, 13
    jmp .exit
.fail_14:
    mov edi, 14
    jmp .exit
.fail_15:
    mov edi, 15
    jmp .exit
.fail_16:
    mov edi, 16
    jmp .exit
.fail_17:
    mov edi, 17
    jmp .exit
.fail_18:
    mov edi, 18
    jmp .exit
.fail_19:
    mov edi, 19
    jmp .exit
.fail_20:
    mov edi, 20
    jmp .exit
.fail_21:
    mov edi, 21
    jmp .exit
.fail_22:
    mov edi, 22
    jmp .exit
.fail_23:
    mov edi, 23
    jmp .exit
.fail_24:
    mov edi, 24
    jmp .exit
.fail_25:
    mov edi, 25
    jmp .exit
.fail_26:
    mov edi, 26
    jmp .exit
.fail_27:
    mov edi, 27
    jmp .exit
.fail_28:
    mov edi, 28
    jmp .exit
.fail_29:
    mov edi, 29
    jmp .exit
.fail_30:
    mov edi, 30
    jmp .exit
.fail_31:
    mov edi, 31
    jmp .exit
.fail_32:
    mov edi, 32
    jmp .exit
.fail_33:
    mov edi, 33
    jmp .exit
.fail_34:
    mov edi, 34
    jmp .exit
.fail_35:
    mov edi, 35
    jmp .exit
.fail_36:
    mov edi, 36
    jmp .exit
.fail_37:
    mov edi, 37
    jmp .exit
.fail_38:
    mov edi, 38
    jmp .exit
.fail_39:
    mov edi, 39
    jmp .exit
.fail_40:
    mov edi, 40

.exit:
    mov eax, 60
    syscall

; Restore the canonical table and regenerate its checksum.
reset_table:
    cld
    lea rsi, [rel madt_template]
    lea rdi, [rel working_table]
    mov ecx, MADT_BYTES
    rep movsb
    lea rdi, [rel working_table]
    call fix_checksum
    ret

; RDI = mutable ACPI table. Recalculate its standard byte checksum.
fix_checksum:
    mov byte [rdi + 9], 0
    mov ecx, [rdi + 4]
    mov rdx, rdi
    xor eax, eax
.sum:
    add al, [rdx]
    inc rdx
    dec ecx
    jnz .sum
    neg al
    mov [rdi + 9], al
    ret

; RSI = route bytes, ECX = byte count. Append to the canonical processor
; topology, update the declared length, and restore the checksum.
append_routes:
    mov eax, ecx
    lea rdi, [rel working_table + MADT_BYTES]
    cld
    rep movsb
    add eax, MADT_BYTES
    mov [rel working_table + 4], eax
    lea rdi, [rel working_table]
    call fix_checksum
    ret

parse_default:
    lea rdi, [rel working_table]
    mov eax, [rel working_table + 4]
    lea rsi, [rel working_table]
    add rsi, rax
    mov edx, 7
    lea rcx, [rel output_ids]
    mov r8d, 8
    lea r9, [rel lapic_output]
    call smp_madt_parse
    ret

find_default:
    lea rdi, [rel working_table]
    mov eax, [rel working_table + 4]
    lea rsi, [rel working_table]
    add rsi, rax
    mov edx, 7
    call smp_madt_find_nmi
    ret

find_ap_300:
    lea rdi, [rel working_table]
    mov eax, [rel working_table + 4]
    lea rsi, [rel working_table]
    add rsi, rax
    mov edx, 300
    call smp_madt_find_nmi
    ret

parse_irqs_default:
    lea rdi, [rel working_table]
    mov eax, [rel working_table + 4]
    lea rsi, [rel working_table]
    add rsi, rax
    lea rdx, [rel irq_ioapics]
    mov ecx, 4
    lea r8, [rel irq_isos]
    mov r9d, 16
    call smp_madt_parse_irqs
    ret

section .data
align 8
madt_template:
    dd SMP_MADT_SIGNATURE
    dd MADT_BYTES
    db 1, 0                         ; revision, checksum (fixed at runtime)
    db "UTOS  "                    ; OEM ID
    db "SMPTABLE"                  ; OEM table ID
    dd 1                            ; OEM revision
    db "UTOS"                      ; creator ID
    dd 1                            ; creator revision
    dd 0xFEE00000                   ; architectural LAPIC base
    dd 1                            ; PC-AT compatibility flags

.first_entry:
    db 0, 8, 1, 2                   ; enabled Local APIC ID 2 (AP)
    dd 1
.second_entry:
    db 0, 8, 2, 7                   ; enabled Local APIC ID 7 (BSP)
    dd 1
.x2_entry:
    db 9, 16
    dw 0
    dd 300                          ; enabled x2APIC ID 300 (AP)
    dd 1
    dd 3
    db 0, 8, 4, 4                   ; disabled processor
    dd 0
    db 5, 12
    dw 0
.override_address:
    dq 0xFEC00000
.end:

route_type4_wild:
    db 4, 6, 0xFF
    dw 0
    db 1
route_type4_wild_end:

route_type4_low_level:
    db 4, 6, 0xFF
    dw 0x000F
    db 0
route_type4_low_level_end:

routes_dual_lint:
    db 4, 6, 0xFF
    dw 0
    db 1
    db 4, 6, 2
    dw 0x000F
    db 0
    db 4, 6, 2
    dw 0x000F
    db 0
routes_dual_lint_end:

route_type10_wild:
    db 10, 12
    dw 0
    dd 0xFFFFFFFF
    db 1, 0, 0, 0
route_type10_wild_end:

route_type10_exact:
    db 10, 12
    dw 0
    dd 3
    db 0, 0, 0, 0
route_type10_exact_end:

route_bad_polarity:
    db 4, 6, 0xFF
    dw 0x0002
    db 1
route_bad_polarity_end:

route_bad_trigger:
    db 4, 6, 0xFF
    dw 0x0008
    db 1
route_bad_trigger_end:

route_bad_pin:
    db 10, 12
    dw 0
    dd 0xFFFFFFFF
    db 2, 0, 0, 0
route_bad_pin_end:

route_bad_reserved:
    db 10, 12
    dw 0
    dd 0xFFFFFFFF
    db 1, 1, 0, 0
route_bad_reserved_end:

routes_wild_conflict:
    db 4, 6, 0xFF
    dw 0
    db 0
    db 4, 6, 0xFF
    dw 0x000F
    db 0
routes_wild_conflict_end:

route_other_uid:
    db 4, 6, 99
    dw 0
    db 1
route_other_uid_end:

route_bad_type4_length:
    db 4, 7, 0xFF
    dw 0
    db 1, 0
route_bad_type4_length_end:

route_bad_type10_length:
    db 10, 11
    dw 0
    dd 0xFFFFFFFF
    db 1, 0, 0
route_bad_type10_length_end:

irq_routes_valid:
    db 1, 12, 3, 0
    dd 0xFEC00000
    dd 0
    db 2, 10, 0, 0
    dd 2
    dw 0
irq_routes_valid_end:

irq_routes_duplicate_iso:
    db 1, 12, 3, 0
    dd 0xFEC00000
    dd 0
    db 2, 10, 0, 0
    dd 2
    dw 0
    db 2, 10, 0, 0
    dd 2
    dw 0
irq_routes_duplicate_iso_end:

irq_routes_conflicting_iso:
    db 1, 12, 3, 0
    dd 0xFEC00000
    dd 0
    db 2, 10, 0, 0
    dd 2
    dw 0
    db 2, 10, 0, 0
    dd 3
    dw 0
irq_routes_conflicting_iso_end:

irq_routes_duplicate_ioapic:
    db 1, 12, 3, 0
    dd 0xFEC00000
    dd 0
    db 1, 12, 3, 0
    dd 0xFEC01000
    dd 24
irq_routes_duplicate_ioapic_end:

irq_route_bad_reserved:
    db 1, 12, 3, 1
    dd 0xFEC00000
    dd 0
irq_route_bad_reserved_end:

irq_route_bad_flags:
    db 2, 10, 0, 0
    dd 2
    dw 2
irq_route_bad_flags_end:

irq_routes_two_ioapics:
    db 1, 12, 3, 0
    dd 0xFEC00000
    dd 0
    db 1, 12, 4, 0
    dd 0xFEC01000
    dd 24
irq_routes_two_ioapics_end:

MADT_BYTES          equ madt_template.end - madt_template
FIRST_ENTRY_OFF     equ madt_template.first_entry - madt_template
SECOND_ENTRY_OFF    equ madt_template.second_entry - madt_template
X2APIC_ID_OFF       equ madt_template.x2_entry - madt_template + 4
X2APIC_RESERVED_OFF equ madt_template.x2_entry - madt_template + 2
X2APIC_FLAGS_OFF    equ madt_template.x2_entry - madt_template + 8
OVERRIDE_ADDR_OFF   equ madt_template.override_address - madt_template
OVERRIDE_RESERVED_OFF equ madt_template.override_address - madt_template - 2
ROUTE_TYPE4_WILD_BYTES       equ route_type4_wild_end - route_type4_wild
ROUTE_TYPE4_LOW_LEVEL_BYTES  equ route_type4_low_level_end - route_type4_low_level
ROUTES_DUAL_LINT_BYTES       equ routes_dual_lint_end - routes_dual_lint
ROUTE_TYPE10_WILD_BYTES      equ route_type10_wild_end - route_type10_wild
ROUTE_TYPE10_EXACT_BYTES     equ route_type10_exact_end - route_type10_exact
ROUTE_BAD_POLARITY_BYTES     equ route_bad_polarity_end - route_bad_polarity
ROUTE_BAD_TRIGGER_BYTES      equ route_bad_trigger_end - route_bad_trigger
ROUTE_BAD_PIN_BYTES          equ route_bad_pin_end - route_bad_pin
ROUTE_BAD_RESERVED_BYTES     equ route_bad_reserved_end - route_bad_reserved
ROUTES_WILD_CONFLICT_BYTES   equ routes_wild_conflict_end - routes_wild_conflict
ROUTE_OTHER_UID_BYTES        equ route_other_uid_end - route_other_uid
ROUTE_BAD_TYPE4_LENGTH_BYTES equ route_bad_type4_length_end - route_bad_type4_length
ROUTE_BAD_TYPE10_LENGTH_BYTES equ route_bad_type10_length_end - route_bad_type10_length
IRQ_ROUTES_VALID_BYTES          equ irq_routes_valid_end - irq_routes_valid
IRQ_ROUTES_DUPLICATE_ISO_BYTES  equ irq_routes_duplicate_iso_end - irq_routes_duplicate_iso
IRQ_ROUTES_CONFLICTING_ISO_BYTES equ irq_routes_conflicting_iso_end - irq_routes_conflicting_iso
IRQ_ROUTES_DUPLICATE_IOAPIC_BYTES equ irq_routes_duplicate_ioapic_end - irq_routes_duplicate_ioapic
IRQ_ROUTE_BAD_RESERVED_BYTES    equ irq_route_bad_reserved_end - irq_route_bad_reserved
IRQ_ROUTE_BAD_FLAGS_BYTES       equ irq_route_bad_flags_end - irq_route_bad_flags
IRQ_ROUTES_TWO_IOAPICS_BYTES    equ irq_routes_two_ioapics_end - irq_routes_two_ioapics
NMI_ROUTE_CAPACITY           equ 32

section .bss
align 8
working_table: resb MADT_BYTES + NMI_ROUTE_CAPACITY
output_ids:    resd 8
lapic_output:  resq 1
irq_ioapics:   resb 4 * SMP_MADT_IOAPIC_BYTES
irq_isos:      resb 16 * SMP_MADT_ISO_BYTES
