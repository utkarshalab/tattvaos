; =============================================================================
; lib/io/acpi/madt.asm
; ACPI MADT (Multiple APIC Description Table) parser.
;
; Parses the MADT (signature "APIC") to dynamically extract the physical base
; address of the Local APIC and I/O APIC, replacing default hardcoded values.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ACPI_MADT_ASM
%define IO_ACPI_MADT_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text


; =============================================================================
; madt_parse — Parse MADT table to locate LAPIC and I/O APIC physical bases
; In : RDI = -> MADT table
; Out: RAX = 0 on success, or a negative error code (IO_ERR_BADARG)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC madt_parse
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; 1. Verify signature is "APIC" (0x43495041)
    mov     eax, [rdi + acpi_header_t.signature]
    cmp     eax, 0x43495041          ; "APIC" in little-endian
    jne     .err_bad_table

    ; 2. Extract LAPIC physical address (u32 at offset 36)
    mov     eax, [rdi + 36]
    test    rax, rax
    jz      .err_bad_table
    mov     [rel io_lapic_base], rax ; Promote to u64

    ; 3. Loop over Interrupt Controller structures starting at offset 44
    mov     ecx, [rdi + acpi_header_t.length]
    lea     rsi, [rdi + 44]         ; RSI = current entry pointer
    add     rdi, rcx                ; RDI = end pointer of MADT table

.entry_loop:
    cmp     rsi, rdi
    jae     .done                   ; Reached end of the table entries

    movzx   eax, byte [rsi]         ; EAX = Entry type
    movzx   edx, byte [rsi + 1]     ; EDX = Entry length
    test    edx, edx
    jz      .done                   ; Guard against infinite loop if len = 0

    ; Type 1 is I/O APIC
    cmp     al, 1
    jne     .next

    ; Extract I/O APIC physical base address (u32 at offset 4 in I/O APIC entry)
    mov     eax, [rsi + 4]
    test    rax, rax
    jz      .next
    mov     [rel io_ioapic_base], rax ; Promote to u64 and store

.next:
    add     rsi, rdx                ; Advance by entry length bytes
    jmp     .entry_loop

.done:
    xor     rax, rax                ; Return 0 (Success)
    jmp     .exit

.err_bad_table:
    mov     rax, IO_ERR_BADARG

.exit:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC madt_parse

%endif ; IO_ACPI_MADT_ASM
