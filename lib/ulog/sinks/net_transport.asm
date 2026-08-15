; =============================================================================
; Tattva OS — lib/ulog/sinks/net_transport.asm
; =============================================================================
; The sink_iface.inc contract over net_queue.asm. Doesn't touch a NIC, a
; socket, or unet/ at all — that's the whole point of the queue-based
; handoff. This always reports success; the actual transmit half of "did it
; reach the remote collector" is unet/services/syslog.asm's problem once it
; exists, not this sink's.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_NET_TRANSPORT_ASM
%define LIB_ULOG_SINKS_NET_TRANSPORT_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .text

; -----------------------------------------------------------------------------
; net_sink_write — sink_t.write_fn
; Input:  RDI = log_record_t* batch, RSI = count
; Output: RAX = count (queueing itself never fails — see net_queue.asm's
;         overwrite-oldest policy for what happens if the remote side is slow)
; -----------------------------------------------------------------------------
global net_sink_write
net_sink_write:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    xor r13, r13

.loop:
    cmp r13, r12
    jae .done

    mov rax, r13
    imul rax, rax, LOG_RECORD_SIZE
    add rax, rbx
    mov rdi, rax
    call net_queue_push

    inc r13
    jmp .loop

.done:
    mov rax, r12
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; net_sink_flush — no-op; the queue is the durability boundary on this side
; -----------------------------------------------------------------------------
global net_sink_flush
net_sink_flush:
    mov rax, 1
    ret

%endif ; LIB_ULOG_SINKS_NET_TRANSPORT_ASM
