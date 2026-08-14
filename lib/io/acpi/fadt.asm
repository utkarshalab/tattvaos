; =============================================================================
; lib/io/acpi/fadt.asm
; ACPI FADT (Fixed ACPI Description Table) parser and power controller.
;
; Parses hardware power ports (SMI_CMD, PM1a, PM1b) from the FADT table,
; switches the CPU to ACPI mode, and executes hypervisor shutdown commands.
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

section .data
global fadt_smi_cmd
fadt_smi_cmd:       dd 0            ; SMI Command Port register
global fadt_acpi_enable
fadt_acpi_enable:   db 0            ; Value to write to enable ACPI
global fadt_pm1a_cnt
fadt_pm1a_cnt:      dd 0            ; PM1a Control Block register
global fadt_pm1b_cnt
fadt_pm1b_cnt:      dd 0            ; PM1b Control Block register

section .text

global fadt_parse
global acpi_enable_smi
global acpi_shutdown



; =============================================================================
; fadt_parse — Parse FADT ports and configure power variables
; In : RDI = -> FADT table structure
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; =============================================================================
IO_FUNC fadt_parse
    guard_null rdi

    ; 1. Verify signature is "FACP" (0x50434146)
    mov     eax, [rdi + acpi_header_t.signature]
    cmp     eax, 0x50434146          ; "FACP" in little-endian
    jne     .err_bad_table

    ; 2. Extract hardware register offsets from FADT structure
    ;    SMI_CMD is at offset 48 (dword)
    mov     eax, [rdi + 48]
    mov     [rel fadt_smi_cmd], eax

    ;    ACPI_ENABLE command byte is at offset 52 (byte)
    mov     al, [rdi + 52]
    mov     [rel fadt_acpi_enable], al

    ;    PM1a_CNT_BLK is at offset 64 (dword)
    mov     eax, [rdi + 64]
    mov     [rel fadt_pm1a_cnt], eax

    ;    PM1b_CNT_BLK is at offset 68 (dword)
    mov     eax, [rdi + 68]
    mov     [rel fadt_pm1b_cnt], eax

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_bad_table:
    mov     rax, IO_ERR_BADARG

.done:
    ret
IO_ENDFUNC fadt_parse

; =============================================================================
; acpi_enable_smi — Switch motherboard from legacy mode to ACPI mode
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC acpi_enable_smi
    push    rbx
    push    rcx
    push    rdx

    mov     edi, [rel fadt_smi_cmd]
    test    edi, edi
    jz      .err_no_smi

    ; Write ACPI_ENABLE byte to SMI_CMD port to trigger firmware switch
    movzx   rsi, byte [rel fadt_acpi_enable]
    call    port_out8

    ; Wait for SCI_EN (bit 0) of PM1a Control Block to be set by hardware
    mov     edi, [rel fadt_pm1a_cnt]
    test    edi, edi
    jz      .done_ok                ; No PM1a Block, skip wait

    mov     ecx, 100000             ; Retry loop timeout to prevent hang
.wait_loop:
    call    port_in16               ; Read current PM1a status (16-bit)
    test    ax, 0x0001              ; SCI_EN is bit 0
    jnz     .done_ok

    dec     ecx
    jz      .done_ok                ; Timeout, proceed anyway
    pause
    jmp     .wait_loop

.done_ok:
    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_no_smi:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC acpi_enable_smi

; =============================================================================
; acpi_shutdown — System shutdown power off trigger (self-healing fallbacks)
; =============================================================================
IO_FUNC acpi_shutdown
    ; 1. Try ACPI Shutdown via PM1a Control Block
    mov     edi, [rel fadt_pm1a_cnt]
    test    edi, edi
    jz      .fallback_bochs

    ; Try S5 Sleep Type 5: SLP_EN (bit 13 = 0x2000) | (5 << 10) = 0x3400
    mov     rsi, 0x3400
    call    port_out16

    ; Try S5 Sleep Type 0: SLP_EN (bit 13 = 0x2000) | (0 << 10) = 0x2000
    mov     rsi, 0x2000
    call    port_out16

    ; 2. Try ACPI Shutdown via PM1b Control Block (if mapped)
    mov     edi, [rel fadt_pm1b_cnt]
    test    edi, edi
    jz      .fallback_bochs

    mov     rsi, 0x3400
    call    port_out16
    mov     rsi, 0x2000
    call    port_out16

.fallback_bochs:
    ; 3. Fallback: Try Bochs/QEMU legacy shutdown port (0xB004)
    mov     rdi, 0xB004
    mov     rsi, 0x2000
    call    port_out16

    ; 4. Fallback: Try QEMU debug exit port (0xF4)
    mov     rdi, 0xF4
    mov     rsi, 0x00
    call    port_out8

    ; If still running, halt the processor
    cli
.halt:
    hlt
    jmp     .halt
IO_ENDFUNC acpi_shutdown

%endif ; IO_ACPI_FADT_ASM
