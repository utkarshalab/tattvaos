; =============================================================================
; Utkarsha OS — lib/usb/hcd/xhci/xfer.asm — transfers
; =============================================================================
;   xhci_control(hc, slot, setup, buffer, length)
;       a control transfer on EP0, waited for: Setup, Data (when there is
;       data), Status. EAX = bytes moved, or a negative USB_E*; a stall or
;       transaction error leaves the endpoint recovered for the next one
;   xhci_xfer_complete(xfer, ep)
;       from xhci_poll, for transfers that were not waited for
; =============================================================================

%ifndef LIB_USB_HCD_XHCI_XFER_ASM
%define LIB_USB_HCD_XHCI_XFER_ASM

section .text

; -----------------------------------------------------------------------------
; xhci_cc_error — completion code ECX → EAX = negative USB_E*
; -----------------------------------------------------------------------------
xhci_cc_error:
    mov eax, -USB_ESTALL
    cmp ecx, CC_STALL
    je .out
    mov eax, -USB_EXACT
    cmp ecx, CC_TRANSACTION
    je .out
    cmp ecx, CC_BABBLE
    je .out
    cmp ecx, CC_DATA_BUFFER
    je .out
    mov eax, -USB_EHC
.out:
    ret

; -----------------------------------------------------------------------------
; xhci_control
; Input:  RDI = hc, ESI = slot, RDX = the setup packet (8 bytes, as a qword),
;         RCX = buffer, R8D = length (the setup's wLength or less)
; Output: EAX = bytes moved, or a negative USB_E*
; -----------------------------------------------------------------------------
global xhci_control
xhci_control:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, esi
    mov r14, rcx
    mov r15d, r8d
    mov rax, [rbx + xhci_hc.slots + r12 * 8]
    test rax, rax
    jz .no_slot
    lea r13, [rax + xhci_slot.eps + xhci_ep_size]   ; EP0, context index 1
    mov rdi, [r13 + xhci_ep.ring]
    test rdi, rdi
    jz .no_slot
    mov dword [r13 + xhci_ep.done], 0
    mov dword [r13 + xhci_ep.residual], 0
    mov dword [r13 + xhci_ep.code], 0
    ; Setup: the packet itself in the TRB (IDT), and which data stage follows
    mov rsi, rdx
    mov ecx, (TRB_SETUP << TRB_TYPE_SHIFT) | TRB_IDT
    test r15d, r15d
    jz .setup
    test dl, USB_DIR_IN
    jz .setup_out
    or ecx, TRT_IN << 16
    jmp .setup
.setup_out:
    or ecx, TRT_OUT << 16
.setup:
    push rdx
    sub rsp, 8
    mov edx, 8
    call xhci_ring_put
    add rsp, 8
    pop rdx
    ; Data
    test r15d, r15d
    jz .status
    mov rdi, [r13 + xhci_ep.ring]
    mov rsi, r14
    mov ecx, TRB_DATA << TRB_TYPE_SHIFT
    test dl, USB_DIR_IN
    jz .data_out
    or ecx, TRB_DIR_IN | TRB_ISP        ; a short IN is reported, not an error
.data_out:
    push rdx
    sub rsp, 8
    mov edx, r15d
    call xhci_ring_put
    add rsp, 8
    pop rdx
.status:
    ; Status: the other direction from the data (IN when there was none)
    mov rdi, [r13 + xhci_ep.ring]
    xor esi, esi
    mov ecx, (TRB_STATUS << TRB_TYPE_SHIFT) | TRB_IOC
    test r15d, r15d
    jz .status_in
    test dl, USB_DIR_IN
    jnz .status_put
.status_in:
    or ecx, TRB_DIR_IN
.status_put:
    xor edx, edx
    call xhci_ring_put
    mov [r13 + xhci_ep.last], rax
    ; doorbell: the slot's, target EP0
    mov rdi, [rbx + xhci_hc.db]
    lea rdi, [rdi + r12 * 4]
    mov esi, 1
    call usb_wr32
    mov r14d, XHCI_WAIT_TRIES * 10      ; a second: slow devices answer late
.wait:
    mov rdi, rbx
    call xhci_poll
    cmp dword [r13 + xhci_ep.done], 0
    jne .done
    dec r14d
    jz .timeout
    mov edi, 50
    call usb_delay
    jmp .wait
.done:
    mov ecx, [r13 + xhci_ep.code]
    cmp ecx, CC_SUCCESS
    jne .error
    mov eax, r15d
    sub eax, [r13 + xhci_ep.residual]
    jns .out
    xor eax, eax
    jmp .out
.error:
    call xhci_cc_error
    mov r15d, eax
    mov rdi, rbx
    mov esi, r12d
    mov edx, 1
    call xhci_ep_recover
    mov eax, r15d
    jmp .out
.timeout:
    mov eax, -USB_ETIMEOUT
    jmp .out
.no_slot:
    mov eax, -USB_ENODEV
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_xfer_complete — a transfer that was not waited for has finished
; Input:  RDI = usb_xfer*, RSI = its xhci_ep (code and residual set)
; -----------------------------------------------------------------------------
global xhci_xfer_complete
xhci_xfer_complete:
    push rbx
    mov rbx, rdi
    mov ecx, [rsi + xhci_ep.code]
    xor eax, eax
    cmp ecx, CC_SUCCESS
    je .status
    call xhci_cc_error
.status:
    mov [rbx + usb_xfer.status], eax
    mov eax, [rbx + usb_xfer.length]
    sub eax, [rsi + xhci_ep.residual]
    jns .actual
    xor eax, eax
.actual:
    mov [rbx + usb_xfer.actual], eax
    mov rax, [rbx + usb_xfer.done]
    test rax, rax
    jz .out
    mov rdi, rbx
    call rax
.out:
    pop rbx
    ret

%endif ; LIB_USB_HCD_XHCI_XFER_ASM
