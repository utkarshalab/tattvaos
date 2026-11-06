; =============================================================================
; Utkarsha OS — lib/input/core/hooks.asm
; =============================================================================
; The few things lib/input needs from its surroundings, as replaceable
; function pointers: the clock and port I/O. The kernel fills in the clock;
; host tests replace port I/O with a simulated controller.
; =============================================================================

%ifndef LIB_INPUT_CORE_HOOKS_ASM
%define LIB_INPUT_CORE_HOOKS_ASM

section .data
align 8
; RAX = monotonic nanoseconds. 0 (no clock): events go out with time 0, and
; the receiver stamps them on arrival.
global input_clock_fn
input_clock_fn:     dq 0
; DI = port; AL = byte read
global input_port_in8_fn
input_port_in8_fn:  dq input_native_in8
; DI = port, SIL = byte
global input_port_out8_fn
input_port_out8_fn: dq input_native_out8

section .text

; -----------------------------------------------------------------------------
; input_native_in8, input_native_out8 — the real port instructions
; -----------------------------------------------------------------------------
input_native_in8:
    mov edx, edi
    xor eax, eax
    in al, dx
    ret

input_native_out8:
    mov edx, edi
    mov eax, esi
    out dx, al
    ret

; -----------------------------------------------------------------------------
; input_inb — read a port through the hook
; Input:  EDI = port
; Output: EAX = the byte (zero-extended)
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_inb
input_inb:
    mov rax, [rel input_port_in8_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    movzx eax, al
    ret

; -----------------------------------------------------------------------------
; input_outb — write a port through the hook
; Input:  EDI = port, ESI = the byte
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_outb
input_outb:
    mov rax, [rel input_port_out8_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; input_now — the time for an event
; Output: RAX = monotonic nanoseconds, or 0 without a clock
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_now
input_now:
    mov rax, [rel input_clock_fn]
    test rax, rax
    jz .none
    sub rsp, 8
    call rax
    add rsp, 8
    ret
.none:
    xor eax, eax
    ret

%endif ; LIB_INPUT_CORE_HOOKS_ASM
