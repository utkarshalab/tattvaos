; =============================================================================
; lib/io/acpi/acpi.asm
; ACPI Root Table Scanner.
;
; Validates the RSDP (Root System Description Pointer) and walks the
; XSDT (Extended System Description Table) entries to locate and parse
; the MADT (APIC), MCFG, and FADT tables.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ACPI_ACPI_ASM
%define IO_ACPI_ACPI_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; ACPI Table Signatures
RSDP_SIG            equ 0x2052545020445352  ; "RSD PTR " (8 bytes)
XSDT_SIG            equ 0x54445358          ; "XSDT" (4 bytes)
MADT_SIG            equ 0x43495041          ; "APIC" (4 bytes)
MCFG_SIG            equ 0x4746434D          ; "MCFG" (4 bytes)
FADT_SIG            equ 0x50434146          ; "FACP" (4 bytes)

section .text



; =============================================================================
; acpi_scan — Validate RSDP, walk XSDT entries and parse required tables
; In : RDI = physical pointer to RSDP structure
; Out: RAX = 0 on success, or a negative error code (IO_ERR_BADARG / IO_ERR_NO_DEVICE)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC acpi_scan
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi                ; RBX = -> RSDP

    ; 1. Validate RSDP Signature
    mov     rax, [rbx]
    mov     rcx, RSDP_SIG
    cmp     rax, rcx
    jne     .err_bad_signature

    ; 2. Validate RSDP Revision (must be ACPI 2.0+ to support XSDT, Revision >= 2)
    movzx   eax, byte [rbx + rsdp_t.revision]
    cmp     al, 2
    jb      .err_legacy_acpi

    ; 3. Fetch XSDT physical address (offset 24 in RSDP structure)
    mov     r12, [rbx + rsdp_t.xsdt_addr]
    test    r12, r12
    jz      .err_no_table

    ; 4. Validate XSDT Signature
    mov     eax, [r12 + acpi_header_t.signature]
    cmp     eax, XSDT_SIG
    jne     .err_bad_xsdt

    ; 5. Walk XSDT entries
    ;    Count of 64-bit entry pointers = (Length - 36) / 8
    mov     ecx, [r12 + acpi_header_t.length]
    sub     ecx, 36                 ; Subtract header size
    shr     ecx, 3                  ; Divide by 8
    test    ecx, ecx
    jz      .done                   ; Empty XSDT table

    mov     r13, rcx                ; R13 = entry count
    xor     r14, r14                ; R14 = entry index iterator

.scan_loop:
    cmp     r14, r13
    jae     .done

    ; Calculate pointer to entry: XSDT base + 36 + index * 8
    mov     rax, r14
    shl     rax, 3                  ; index * 8
    add     rax, r12
    add     rax, 36                 ; offset to entry array
    mov     rdi, [rax]              ; RDI = physical address of ACPI table
    test    rdi, rdi
    jz      .next_entry

    ; Read signature from table header
    mov     edx, [rdi + acpi_header_t.signature]

    ; Check for MADT (APIC)
    cmp     edx, MADT_SIG
    je      .call_madt

    ; Check for MCFG
    cmp     edx, MCFG_SIG
    je      .call_mcfg

    ; Check for FADT (FACP)
    cmp     edx, FADT_SIG
    je      .call_fadt

    jmp     .next_entry

.call_madt:
    call    madt_parse
    jmp     .next_entry

.call_mcfg:
    call    mcfg_parse
    jmp     .next_entry

.call_fadt:
    call    fadt_parse

.next_entry:
    inc     r14
    jmp     .scan_loop

.done:
    xor     rax, rax                ; Return 0 (Success)
    jmp     .exit

.err_bad_signature:
.err_bad_xsdt:
    mov     rax, IO_ERR_BADARG
    jmp     .exit

.err_legacy_acpi:
.err_no_table:
    mov     rax, IO_ERR_NO_DEVICE

.exit:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC acpi_scan

%endif ; IO_ACPI_ACPI_ASM
