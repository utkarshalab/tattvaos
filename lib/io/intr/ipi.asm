; =============================================================================
; lib/io/intr/ipi.asm
; Local APIC Inter-Processor Interrupts (IPIs).
;
; Implements multi-core signaling for lock-free rescheduling, allowing a
; core to wake up scheduler loops on other cores upon async I/O completion.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_IPI_ASM
%define IO_INTR_IPI_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .text


; =============================================================================
; lapic_send_ipi — Issue an IPI to a target CPU core via LAPIC ICR
; In : RDI = Target APIC ID (physical core ID)
;      RSI = Vector index (0-255)
; Out: RAX = 0 on success, or negative error code (IO_ERR_NO_DEVICE)
; =============================================================================
IO_FUNC lapic_send_ipi
    push    rbx
    push    rcx
    push    rdx

    mov     rax, [rel io_lapic_base]
    test    rax, rax
    jz      .err_no_lapic           ; LAPIC not initialized

    ; 1. Spin-wait until ICR Delivery Status (bit 12) is clear (0 = Idle)
    ;    ICR Low register is at offset 0x300
.wait_idle:
    test    dword [rax + 0x300], 0x1000
    jnz     .wait_idle

    ; 2. Program target APIC ID in ICR High register (offset 0x310)
    ;    High register target ID is in bits [31:24]
    mov     rcx, rdi
    shl     rcx, 24                 ; Shift ID to target destination field
    mov     [rax + 0x310], ecx

    ; 3. Program vector and flags in ICR Low register (offset 0x300)
    ;    Flags: Level Assert (bit 14 = 0x4000), Delivery Mode Fixed (0x000), Destination Physical (0x000)
    and     rsi, 0xFF               ; Vector mask
    or      rsi, 0x4000             ; Assert flag
    mov     [rax + 0x300], esi      ; Writing low register triggers IPI

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_no_lapic:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC lapic_send_ipi

%endif ; IO_INTR_IPI_ASM
