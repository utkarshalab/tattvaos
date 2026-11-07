; =============================================================================
; Utkarsha OS — lib/usb/hcd/xhci/ring.asm — producer rings and the event ring
; =============================================================================
;   xhci_ring_new(trbs)                 a ring ending in a link TRB
;   xhci_ring_put(ring, param, status, control)  one TRB, cycle bit added
;   xhci_ring_deq(ring)                 RAX = where the next TRB goes, with
;                                       the cycle bit (for Set TR Dequeue)
;   xhci_poll(hc)                       handle every event waiting
; =============================================================================

%ifndef LIB_USB_HCD_XHCI_RING_ASM
%define LIB_USB_HCD_XHCI_RING_ASM

section .text

; -----------------------------------------------------------------------------
; xhci_ring_new — EDI = TRBs (the link one included) → RAX = xhci_ring*, or 0
; One page holds 256 TRBs and never crosses 64 KB, as the TRBs of a segment
; must not.
; -----------------------------------------------------------------------------
global xhci_ring_new
xhci_ring_new:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    mov edi, xhci_ring_size
    mov esi, 64
    call usb_alloc
    test rax, rax
    jz .out
    mov rbx, rax
    mov edi, r12d
    shl edi, 4
    mov esi, 4096
    call usb_alloc
    test rax, rax
    jz .out
    mov [rbx + xhci_ring.trbs], rax
    mov [rbx + xhci_ring.size], r12d
    mov dword [rbx + xhci_ring.cycle], 1
    ; the link TRB back to the start, toggling the cycle
    lea ecx, [r12d - 1]
    shl ecx, 4
    mov [rax + rcx], rax
    mov dword [rax + rcx + 12], (TRB_LINK << TRB_TYPE_SHIFT) | TRB_TC
    mov rax, rbx
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_ring_put — RDI = ring, RSI = parameter, EDX = status, ECX = control
;                 without the cycle bit
; Output: RAX = the TRB written
; At the link TRB: the link gets the cycle bit (and the chain bit, when this
; TRB chains on), and the ring starts over with the cycle toggled.
; -----------------------------------------------------------------------------
global xhci_ring_put
xhci_ring_put:
    push rbx
    mov r8, [rdi + xhci_ring.trbs]
    mov eax, [rdi + xhci_ring.enq]
    shl eax, 4
    lea rbx, [r8 + rax]
    mov [rbx], rsi
    mov [rbx + 8], edx
    or ecx, [rdi + xhci_ring.cycle]
    mov [rbx + 12], ecx                 ; the cycle bit last
    mov [rdi + xhci_ring.last], rbx
    mov eax, [rdi + xhci_ring.enq]
    inc eax
    mov r9d, [rdi + xhci_ring.size]
    dec r9d
    cmp eax, r9d
    jb .store
    ; reached the link TRB
    shl r9d, 4
    mov r10d, (TRB_LINK << TRB_TYPE_SHIFT) | TRB_TC
    and ecx, TRB_CH | TRB_CYCLE
    or r10d, ecx
    mov [r8 + r9 + 12], r10d
    xor dword [rdi + xhci_ring.cycle], 1
    xor eax, eax
.store:
    mov [rdi + xhci_ring.enq], eax
    mov rax, rbx
    pop rbx
    ret

; xhci_ring_free — RDI = ring (0: nothing): its TRBs and its record back
global xhci_ring_free
xhci_ring_free:
    test rdi, rdi
    jz .out
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + xhci_ring.trbs]
    mov esi, [rbx + xhci_ring.size]
    shl esi, 4
    mov edx, 4096
    call usb_free
    mov rdi, rbx
    mov esi, xhci_ring_size
    mov edx, 64
    call usb_free
    pop rbx
.out:
    ret

; xhci_ring_deq — RDI = ring → RAX = the enqueue TRB's address | cycle
global xhci_ring_deq
xhci_ring_deq:
    mov eax, [rdi + xhci_ring.enq]
    shl eax, 4
    add rax, [rdi + xhci_ring.trbs]
    mov ecx, [rdi + xhci_ring.cycle]
    or rax, rcx                         ; a 32-bit OR would cut the address
    ret

; -----------------------------------------------------------------------------
; xhci_poll — handle the events waiting on interrupter 0
; Input:  RDI = hc
; Output: EAX = events handled
; Each event is copied and the ring advanced before it is handled, so a
; handler may itself wait on the controller (and so poll again): a command
; from a completion callback sees the events after its own.
; -----------------------------------------------------------------------------
global xhci_poll
xhci_poll:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16                         ; the event being handled
    mov rbx, rdi
    xor r15d, r15d
.event:
    mov eax, [rbx + xhci_hc.evt_deq]
    shl eax, 4
    mov r12, [rbx + xhci_hc.evt]
    add r12, rax                        ; the TRB
    mov r13d, [r12 + 12]                ; control
    mov eax, r13d
    and eax, 1
    cmp eax, [rbx + xhci_hc.evt_cycle]
    jne .caught_up
    inc r15d
    mov rax, [r12]
    mov [rsp], rax
    mov rax, [r12 + 8]
    mov [rsp + 8], rax
    ; past it, and the controller told, before anything else runs
    mov eax, [rbx + xhci_hc.evt_deq]
    inc eax
    cmp eax, XHCI_EVT_TRBS
    jb .store
    xor eax, eax
    xor dword [rbx + xhci_hc.evt_cycle], 1
.store:
    mov [rbx + xhci_hc.evt_deq], eax
    call .erdp
    mov eax, r13d
    shr eax, TRB_TYPE_SHIFT
    and eax, 63
    cmp eax, TRB_EV_TRANSFER
    je .transfer
    cmp eax, TRB_EV_COMMAND
    je .command
    cmp eax, TRB_EV_PORT
    je .port
    cmp eax, TRB_EV_HC
    jne .event
    inc dword [rbx + xhci_hc.hc_events]
    jmp .event

.command:
    mov rax, [rsp]
    cmp rax, [rbx + xhci_hc.cmd_last]
    jne .event                          ; not the one waited for (aborted)
    movzx eax, byte [rsp + 11]
    mov [rbx + xhci_hc.cmd_code], eax
    mov eax, r13d
    shr eax, 24
    mov [rbx + xhci_hc.cmd_slot], eax
    mov dword [rbx + xhci_hc.cmd_done], 1
    jmp .event

.port:
    movzx eax, byte [rsp + 3]           ; port ID, bits 24-31
    bts [rbx + xhci_hc.port_change], eax
    jmp .event

.transfer:
    mov eax, r13d
    shr eax, 24                         ; slot
    mov r14, [rbx + xhci_hc.slots + rax * 8]
    test r14, r14
    jz .event
    mov eax, r13d
    shr eax, 16
    and eax, 31                         ; device context index
    imul eax, eax, xhci_ep_size
    lea r14, [r14 + xhci_slot.eps + rax]
    movzx ecx, byte [rsp + 11]          ; completion code
    mov edx, [rsp + 8]
    and edx, 0xFFFFFF                   ; bytes not moved
    cmp ecx, CC_SHORT_PACKET
    jne .not_short
    add [r14 + xhci_ep.residual], edx
    mov rax, [rsp]
    cmp rax, [r14 + xhci_ep.last]
    jne .event                          ; more of the TD to come
    mov ecx, CC_SUCCESS
    jmp .td_done
.not_short:
    cmp ecx, CC_SUCCESS
    jne .td_done                        ; an error ends the TD where it is
    mov rax, [rsp]
    cmp rax, [r14 + xhci_ep.last]
    jne .event
.td_done:
    mov [r14 + xhci_ep.code], ecx
    mov dword [r14 + xhci_ep.done], 1
    mov rdi, [r14 + xhci_ep.xfer]
    test rdi, rdi
    jz .event
    mov qword [r14 + xhci_ep.xfer], 0
    mov rsi, r14
    call xhci_xfer_complete
    jmp .event

.caught_up:
    mov eax, r15d
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ERDP at the dequeue TRB, the handler-busy bit cleared; IMAN's pending bit
; cleared (called with one more return address on the stack: aligned)
.erdp:
    mov eax, [rbx + xhci_hc.evt_deq]
    shl eax, 4
    mov rsi, [rbx + xhci_hc.evt]
    add rsi, rax
    or rsi, ERDP_EHB
    mov rdi, [rbx + xhci_hc.rt]
    add rdi, XHCI_IR0 + IR_ERDP
    sub rsp, 8
    call usb_wr64
    mov rdi, [rbx + xhci_hc.rt]
    add rdi, XHCI_IR0 + IR_IMAN
    mov esi, IMAN_IP | IMAN_IE
    call usb_wr32
    add rsp, 8
    ret

%endif ; LIB_USB_HCD_XHCI_RING_ASM
