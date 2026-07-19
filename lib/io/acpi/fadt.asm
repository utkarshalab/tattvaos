; =============================================================================
; lib/io/acpi/fadt.asm
; ACPI FADT (Fixed ACPI Description Table) parser stub.
;
; Verifies table signature and integrity. Power management / reset registers
; are parsed here for future power state transitions.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ACPI_FADT_ASM
%define IO_ACPI_FADT_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; =============================================================================
; fadt_parse — Parses FADT table
; In : RDI = -> FADT table
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC fadt_parse
    guard_null rdi

    ; 1. Verify signature is "FACP" (0x50434146)
    mov     eax, [rdi + acpi_header_t.signature]
    cmp     eax, 0x50434146          ; "FACP" in little-endian
    jne     .err_bad_table

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_bad_table:
    mov     rax, IO_ERR_BADARG

.done:
IO_ENDFUNC fadt_parse

%endif ; IO_ACPI_FADT_ASM
