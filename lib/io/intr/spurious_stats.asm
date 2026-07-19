; =============================================================================
; lib/io/intr/spurious_stats.asm
; Spurious interrupt telemetry and warning tracker.
;
; Maintains running counts of spurious interrupt occurrences (vector 0xFF) and
; logs a milestone alert to COM1 on detecting potential hardware storms.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_INTR_SPURIOUS_STATS_ASM
%define IO_INTR_SPURIOUS_STATS_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .data
global global_spurious_count
global_spurious_count: dq 0         ; Running spurious ticks counter
msg_spurious_alert:   db "IO:INTR_SPURIOUS_STORM", 0

section .text

global spurious_telemetry_tick
extern console_milestone

; =============================================================================
; spurious_telemetry_tick — Telemetry counter increment and warning trigger
; =============================================================================
IO_FUNC spurious_telemetry_tick
    push    rax
    push    rcx
    push    rdx
    push    rdi

    lock inc qword [rel global_spurious_count]

    ; Check if count is a multiple of 128 to alert of high storm rates
    mov     rax, [rel global_spurious_count]
    xor     rdx, rdx
    mov     rcx, 128
    div     rcx                     ; RDX = count % 128
    test    rdx, rdx
    jnz     .done

    ; Broadcast alert over COM1 serial line
    lea     rdi, [rel msg_spurious_alert]
    call    console_milestone

.done:
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rax
    ret
IO_ENDFUNC spurious_telemetry_tick

%endif ; IO_INTR_SPURIOUS_STATS_ASM
