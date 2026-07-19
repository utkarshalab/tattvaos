; =============================================================================
; lib/io/intr/timer.asm
; Dynamic Local APIC Timer Calibration & Delay routines.
;
; Calibrates the Local APIC timer frequency dynamically against the legacy PIT
; (Programmable Interval Timer) to enable precise time-based delays (milliseconds).
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_TIMER_ASM
%define IO_INTR_TIMER_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .data
global lapic_ticks_per_ms
lapic_ticks_per_ms: dq 0            ; Calibrated frequency (ticks per ms)

section .text

extern io_lapic_base

; =============================================================================
; lapic_timer_calibrate — Calibrate LAPIC timer tick rate against PIT
; Out: RAX = 0 on success, or negative error code (IO_ERR_NO_DEVICE)
; =============================================================================
IO_FUNC lapic_timer_calibrate
    push    rbx
    push    rcx
    push    rdx

    mov     rax, [rel io_lapic_base]
    test    rax, rax
    jz      .err_no_lapic

    ; 1. Setup PIT Channel 2 in one-shot mode (Interrupt on Terminal Count)
    ;    Mode command: Channel 2, LOBYTE/HIBYTE, Mode 0, Binary (0xB0)
    mov     al, 0xB0
    out     0x43, al

    ; 2. Load count 11932 (approx. 10 milliseconds at 1.193182 MHz frequency)
    ;    LOBYTE = 0x9C, HIBYTE = 0x2E (11932 = 0x2E9C)
    mov     al, 0x9C
    out     0x42, al
    mov     al, 0x2E
    out     0x42, al

    ; 3. Enable PIT Channel 2 gate and mask speaker output
    in      al, 0x61
    and     al, 0xFD                ; Clear bit 1 (speaker disabled)
    or      al, 0x01                ; Set bit 0 (gate enabled)
    out     0x61, al

    ; 4. Initialize LAPIC Timer with Divisor 16 (code 0x03)
    ;    Divisor config register is at offset 0x3E0
    mov     dword [rax + 0x3E0], 0x03

    ; Set Initial Count to 0xFFFFFFFF (offset 0x380) to start decrementing
    mov     dword [rax + 0x380], 0xFFFFFFFF

    ; 5. Spin-wait until PIT Channel 2 Output (bit 5 of port 0x61) goes high (1)
.wait_pit:
    in      al, 0x61
    test    al, 0x20
    jz      .wait_pit

    ; 6. Read LAPIC Current Count (offset 0x390) and calculate ticks elapsed
    mov     ecx, [rax + 0x390]
    mov     edx, 0xFFFFFFFF
    sub     edx, ecx                ; EDX = ticks elapsed in 10ms

    ; Disable PIT Channel 2 gate
    in      al, 0x61
    and     al, 0xFE                ; Clear bit 0
    out     0x61, al

    ; Calculate ticks per millisecond: ticks / 10
    mov     eax, edx
    xor     edx, edx
    mov     ecx, 10
    div     ecx                     ; EAX = ticks per ms

    ; Prevent division-by-zero later if timer emulation is static
    test    eax, eax
    jnz     .store
    mov     eax, 1                  ; Default fallback tick rate

.store:
    mov     [rel lapic_ticks_per_ms], rax
    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_no_lapic:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC lapic_timer_calibrate

; =============================================================================
; lapic_delay — Spin-wait for a requested number of milliseconds
; In : RDI = Number of milliseconds to delay
; =============================================================================
IO_FUNC lapic_delay
    push    rax
    push    rcx
    push    rdx

    test    rdi, rdi
    jz      .done

    mov     rax, [rel io_lapic_base]
    test    rax, rax
    jz      .fallback_spin          ; LAPIC unavailable, use raw pause loop

    mov     rcx, [rel lapic_ticks_per_ms]
    test    rcx, rcx
    jz      .fallback_spin          ; Calibrate not executed, use raw loop

    ; Calculate ticks: ms * ticks_per_ms
    mov     rax, rdi
    imul    rax, rcx                ; RAX = total ticks count

    mov     rcx, [rel io_lapic_base]

    ; Start LAPIC timer countdown (write to offset 0x380)
    mov     [rcx + 0x380], eax

    ; Spin until Current Count (offset 0x390) becomes 0
.wait_timer:
    mov     edx, [rcx + 0x390]
    test    edx, edx
    jnz     .wait_timer
    jmp     .done

.fallback_spin:
    ; Fallback pause loop: approx. 1,000,000 cycles per ms
    imul    rdi, 1000000
.spin:
    pause
    dec     rdi
    jnz     .spin

.done:
    pop     rdx
    pop     rcx
    pop     rax
    ret
IO_ENDFUNC lapic_delay

%endif ; IO_INTR_TIMER_ASM
