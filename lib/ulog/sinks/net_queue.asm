; =============================================================================
; Tattva OS — lib/ulog/sinks/net_queue.asm
; =============================================================================
; The ring buffer unet/services/syslog.asm's own doc comment already expects
; ("Ring Buffer Log Collector"). lib/ can't import from unet/ (layer rule),
; so the dependency points the other way: this queue lives here, and unet
; drains it once it exists — net_queue_pop is exported for exactly that,
; and nothing in lib/ulog itself calls it.
;
; Same overwrite-oldest policy as record/ring_wrap.asm, for the same reason:
; a full queue can't block the drain fiber that's the only thing feeding it.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_NET_QUEUE_ASM
%define LIB_ULOG_SINKS_NET_QUEUE_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

%define NET_QUEUE_SLOTS  256
%define NET_QUEUE_MASK   (NET_QUEUE_SLOTS - 1)

section .bss
alignb 8
global ulog_net_queue_head
ulog_net_queue_head: resq 1
global ulog_net_queue_tail
ulog_net_queue_tail: resq 1
global ulog_net_queue_dropped
ulog_net_queue_dropped: resq 1
global ulog_net_queue_slots
ulog_net_queue_slots: resb (LOG_RECORD_SIZE * NET_QUEUE_SLOTS)

section .text

; -----------------------------------------------------------------------------
; net_queue_push — single producer (drain/dispatch.asm)
; Input:  RDI = log_record_t* (64-byte source)
; Output: none
; -----------------------------------------------------------------------------
global net_queue_push
net_queue_push:
    push rsi
    push rax
    push rcx

    mov rax, [ulog_net_queue_head]
    mov rcx, [ulog_net_queue_tail]
    sub rax, rcx
    cmp rax, NET_QUEUE_SLOTS
    jl .has_room

    inc qword [ulog_net_queue_tail]
    inc qword [ulog_net_queue_dropped]

.has_room:
    mov rax, [ulog_net_queue_head]
    and rax, NET_QUEUE_MASK
    imul rax, rax, LOG_RECORD_SIZE
    lea rax, [ulog_net_queue_slots + rax]

    mov rsi, rdi
    mov rdi, rax
    push rcx
    mov rcx, LOG_RECORD_SIZE / 8
    cld
    rep movsq
    pop rcx

    inc qword [ulog_net_queue_head]

    pop rcx
    pop rax
    pop rsi
    ret

; -----------------------------------------------------------------------------
; net_queue_pop — single consumer (unet/services/syslog.asm, once it exists)
; Input:  RDI = log_record_t* destination
; Output: RAX = 1 popped, 0 empty
; -----------------------------------------------------------------------------
global net_queue_pop
net_queue_pop:
    push rsi
    push rcx
    push rdx

    mov rax, [ulog_net_queue_head]
    mov rdx, [ulog_net_queue_tail]
    cmp rax, rdx
    jne .not_empty
    xor rax, rax
    jmp .done

.not_empty:
    mov rax, rdx
    and rax, NET_QUEUE_MASK
    imul rax, rax, LOG_RECORD_SIZE
    lea rsi, [ulog_net_queue_slots + rax]

    mov rcx, LOG_RECORD_SIZE / 8
    cld
    rep movsq

    inc qword [ulog_net_queue_tail]
    mov rax, 1

.done:
    pop rdx
    pop rcx
    pop rsi
    ret

%endif ; LIB_ULOG_SINKS_NET_QUEUE_ASM
