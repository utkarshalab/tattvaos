; =============================================================================
; Utkarsha OS — lib/usb/hcd/xhci/port.asm — root hub ports
; =============================================================================
;   xhci_portsc(hc, port)           PORTSC (ports count from 1)
;   xhci_port_ack(hc, port)         clear its change bits
;   xhci_port_reset(hc, port)       reset and enable; EAX = speed
;
; A USB 3 port enables itself once its link trains; one that did not gets a
; warm reset. A USB 2 port is reset (PR) and enabled by the reset.
; Writing PORTSC writes back only the bits in PORT_PRESERVE plus the one
; being set: the change bits clear when written as 1, and PED disables.
; =============================================================================

%ifndef LIB_USB_HCD_XHCI_PORT_ASM
%define LIB_USB_HCD_XHCI_PORT_ASM

section .text

; xhci_portsc_addr — RDI = hc, ESI = port → RDI = the register
xhci_portsc_addr:
    lea eax, [rsi - 1]
    shl eax, 4
    mov rdi, [rdi + xhci_hc.op]
    lea rdi, [rdi + rax + XHCI_PORTSC]
    ret

; -----------------------------------------------------------------------------
; xhci_portsc — RDI = hc, ESI = port → EAX = PORTSC (0 for no such port)
; -----------------------------------------------------------------------------
global xhci_portsc
xhci_portsc:
    xor eax, eax
    test esi, esi
    jz .out
    cmp esi, [rdi + xhci_hc.max_ports]
    ja .out
    sub rsp, 8
    call xhci_portsc_addr
    call usb_rd32
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; xhci_port_ack — RDI = hc, ESI = port: write its change bits back as 1
; -----------------------------------------------------------------------------
global xhci_port_ack
xhci_port_ack:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    call xhci_portsc
    test eax, eax
    jz .out
    btr [rbx + xhci_hc.port_change], r12d
    mov rdi, rbx
    mov esi, r12d
    mov r8d, eax
    call xhci_portsc_addr
    mov eax, r8d
    mov ecx, eax
    and eax, PORT_PRESERVE
    and ecx, PORT_CHANGES
    or eax, ecx
    mov esi, eax
    call usb_wr32
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_port_reset — reset a connected port until it is enabled
; Input:  RDI = hc, ESI = port
; Output: EAX = speed (USB_SPEED_*), or -USB_ENODEV
; -----------------------------------------------------------------------------
global xhci_port_reset
xhci_port_reset:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    call xhci_portsc
    test eax, PORT_CCS
    jz .gone
    movzx ecx, byte [rbx + xhci_hc.port_major + r12]
    mov r14d, PORT_PR
    cmp ecx, 3
    jne .reset
    test eax, PORT_PED
    jnz .enabled                        ; a USB 3 link that trained
    mov r14d, PORT_WPR
.reset:
    mov rdi, rbx
    mov esi, r12d
    mov r8d, eax
    call xhci_portsc_addr
    mov r13, rdi
    mov eax, r8d
    and eax, PORT_PRESERVE
    or eax, r14d
    mov esi, eax
    call usb_wr32
    ; wait for the reset to finish: PRC (WRC after a warm reset)
    mov r14d, 100                       ; 100 ms
.wait:
    mov edi, 1000
    call usb_delay
    mov rdi, r13
    call usb_rd32
    test eax, PORT_PRC | PORT_WRC
    jnz .reset_done
    dec r14d
    jnz .wait
    jmp .gone
.reset_done:
    mov rdi, r13
    mov ecx, eax
    and eax, PORT_PRESERVE
    and ecx, PORT_PRC | PORT_WRC | PORT_CSC | PORT_PEC
    or eax, ecx
    mov esi, eax
    call usb_wr32
    mov edi, 10000                      ; reset recovery: 10 ms
    call usb_delay
    mov rdi, r13
    call usb_rd32
    test eax, PORT_CCS
    jz .gone
    test eax, PORT_PED
    jz .gone
.enabled:
    shr eax, PORT_SPEED_SHIFT
    and eax, 15
    jmp .out
.gone:
    mov eax, -USB_ENODEV
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_USB_HCD_XHCI_PORT_ASM
