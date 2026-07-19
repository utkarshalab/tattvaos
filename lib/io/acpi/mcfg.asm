; =============================================================================
; lib/io/acpi/mcfg.asm
; ACPI MCFG (Memory Mapped Configuration Space) table parser.
;
; Extracts the PCIe Enhanced Configuration Access Mechanism (ECAM) base
; address from the MCFG table found via the XSDT walk. The ECAM base is
; required for MMIO-based PCI config access to extended capabilities
; (offsets 0x100–0xFFF): AER, ACS, MSI-X, SR-IOV.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ACPI_MCFG_ASM
%define IO_ACPI_MCFG_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; MCFG table layout (after standard 36-byte ACPI header):
;   offset 36: 8 bytes reserved
;   offset 44: array of Configuration Space Base Address Allocation structures
; Each allocation entry (16 bytes):
;   offset  0: Base Address (u64) — ECAM physical base
;   offset  8: PCI Segment Group Number (u16)
;   offset 10: Start Bus Number (u8)
;   offset 11: End Bus Number (u8)
;   offset 12: Reserved (u32)
MCFG_ALLOC_OFFSET   equ 44          ; First allocation entry starts here
MCFG_ALLOC_SIZE     equ 16          ; Each allocation entry is 16 bytes
MCFG_SIG            equ 0x4746434D  ; "MCFG" as little-endian u32

section .data
global io_ecam_base
io_ecam_base:       dq 0            ; PCIe ECAM physical base address (0 = not available)
global io_ecam_virt
io_ecam_virt:       dq 0            ; ECAM mapped virtual base (0 = not mapped)
global io_ecam_start_bus
io_ecam_start_bus:  db 0            ; Start bus number covered by ECAM
global io_ecam_end_bus
io_ecam_end_bus:    db 0            ; End bus number covered by ECAM

section .text

; =============================================================================
; mcfg_parse — Parse an MCFG ACPI table and extract ECAM base address
; In : RDI = -> MCFG table (physical/virtual pointer, must be mapped)
; Out: RAX = 0 on success (ECAM base stored), or negative error code
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC mcfg_parse
    guard_null rdi
    push    rbx
    push    rcx
    push    rdx

    ; 1. Validate MCFG signature (first 4 bytes of ACPI header)
    mov     eax, [rdi + acpi_header_t.signature]
    cmp     eax, MCFG_SIG
    jne     .err_bad_table

    ; 2. Get table length to determine number of allocation entries
    mov     ecx, [rdi + acpi_header_t.length]
    cmp     ecx, MCFG_ALLOC_OFFSET + MCFG_ALLOC_SIZE
    jb      .err_bad_table          ; Table too small for even one entry

    ; 3. Read first allocation entry at offset 44
    lea     rbx, [rdi + MCFG_ALLOC_OFFSET]

    ; Extract ECAM base address (u64 at entry offset 0)
    mov     rax, [rbx + 0]
    test    rax, rax
    jz      .err_bad_table          ; Zero base = invalid

    mov     [rel io_ecam_base], rax

    ; Extract bus range (start at offset 10, end at offset 11)
    movzx   ecx, byte [rbx + 10]
    mov     [rel io_ecam_start_bus], cl
    movzx   ecx, byte [rbx + 11]
    mov     [rel io_ecam_end_bus], cl

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_bad_table:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC mcfg_parse

; =============================================================================
; mcfg_map_ecam — Map the ECAM region into kernel virtual address space
;
; Must be called after mcfg_parse has stored io_ecam_base. Maps enough space
; to cover the bus range: size = (end_bus - start_bus + 1) * 256 * 4096
; (each bus has 256 device-functions, each with 4096 bytes of config space).
;
; In : None
; Out: RAX = 0 on success (io_ecam_virt populated), or negative error code
; RSO: RAX owned-out
; =============================================================================
IO_FUNC mcfg_map_ecam
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; 1. Check that ECAM base was parsed
    mov     rdi, [rel io_ecam_base]
    test    rdi, rdi
    jz      .err_not_available

    ; 2. Calculate ECAM region size
    ;    size = (end_bus - start_bus + 1) * 32 * 8 * 4096
    ;         = (end_bus - start_bus + 1) << 20
    movzx   rax, byte [rel io_ecam_end_bus]
    movzx   rcx, byte [rel io_ecam_start_bus]
    sub     rax, rcx
    inc     rax                     ; RAX = number of buses
    shl     rax, 20                 ; Each bus = 256 devfns * 4KB = 1MB
    mov     rsi, rax                ; RSI = total ECAM region size

    ; 3. Map via dma_map_virtual (phys_addr, size, page_flags)
    ;    Flags: Present + Write + PCD (uncacheable MMIO)
    mov     rdx, PTE_PRESENT | PTE_WRITE | PTE_PCD
    call    dma_map_virtual
    ; Returns: RAX = phys base (passthrough), RBX = virtual base

    test    rbx, rbx
    jz      .err_map_fail

    mov     [rel io_ecam_virt], rbx

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_not_available:
    mov     rax, IO_ERR_NO_DEVICE
    jmp     .done

.err_map_fail:
    mov     rax, IO_ERR_NOMEM

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC mcfg_map_ecam

%endif ; IO_ACPI_MCFG_ASM