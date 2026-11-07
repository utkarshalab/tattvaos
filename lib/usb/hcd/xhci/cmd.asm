; =============================================================================
; Utkarsha OS — lib/usb/hcd/xhci/cmd.asm — commands, slots, contexts
; =============================================================================
;   xhci_command(hc, param, status, control)   one command, waited for
;   xhci_enable_slot(hc)                        a slot and its contexts
;   xhci_address_device(hc, slot, port, speed, route, tt)
;   xhci_set_mps0(hc, slot, size)               Evaluate Context for EP0
;   xhci_ep_recover(hc, slot, dci)              after a stall or error:
;                                               Reset Endpoint, then Set TR
;                                               Dequeue past what failed
; =============================================================================

%ifndef LIB_USB_HCD_XHCI_CMD_ASM
%define LIB_USB_HCD_XHCI_CMD_ASM

section .text

; -----------------------------------------------------------------------------
; xhci_command — put a command on the ring, ring doorbell 0, wait for it
; Input:  RDI = hc, RSI = parameter, EDX = status, ECX = control (type and
;         fields, no cycle bit)
; Output: EAX = completion code, or -USB_ETIMEOUT; EDX = slot ID it names
; -----------------------------------------------------------------------------
global xhci_command
xhci_command:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov dword [rbx + xhci_hc.cmd_done], 0
    mov rdi, [rbx + xhci_hc.cmd]
    call xhci_ring_put
    mov [rbx + xhci_hc.cmd_last], rax
    mov rdi, [rbx + xhci_hc.db]
    xor esi, esi
    call usb_wr32
    mov r12d, XHCI_WAIT_TRIES
.wait:
    mov rdi, rbx
    call xhci_poll
    cmp dword [rbx + xhci_hc.cmd_done], 0
    jne .done
    dec r12d
    jz .timeout
    mov edi, 50
    call usb_delay
    jmp .wait
.done:
    mov eax, [rbx + xhci_hc.cmd_code]
    mov edx, [rbx + xhci_hc.cmd_slot]
    jmp .out
.timeout:
    mov qword [rbx + xhci_hc.cmd_last], 0
    mov eax, -USB_ETIMEOUT
    xor edx, edx
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_enable_slot — Enable Slot, then the slot's records and contexts
; Input:  RDI = hc
; Output: EAX = slot ID, or a negative USB_E*
; -----------------------------------------------------------------------------
global xhci_enable_slot
xhci_enable_slot:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    xor esi, esi
    xor edx, edx
    mov ecx, TRB_ENABLE_SLOT << TRB_TYPE_SHIFT
    call xhci_command
    test eax, eax
    js .out
    cmp eax, CC_SUCCESS
    jne .refused
    mov r12d, edx
    test r12d, r12d
    jz .refused
    cmp r12d, [rbx + xhci_hc.max_slots]
    ja .refused
    mov edi, xhci_slot_size
    mov esi, 64
    call usb_alloc
    test rax, rax
    jz .nomem
    mov r13, rax
    mov edi, [rbx + xhci_hc.ctx_size]
    shl edi, 5                          ; slot + 31 endpoints
    mov esi, 64
    call usb_alloc
    test rax, rax
    jz .nomem
    mov [r13 + xhci_slot.out_ctx], rax
    mov edi, [rbx + xhci_hc.ctx_size]
    imul edi, edi, 33                   ; input control + the above
    mov esi, 64
    call usb_alloc
    test rax, rax
    jz .nomem
    mov [r13 + xhci_slot.in_ctx], rax
    mov [rbx + xhci_hc.slots + r12 * 8], r13
    mov rcx, [rbx + xhci_hc.dcbaa]
    mov rax, [r13 + xhci_slot.out_ctx]
    mov [rcx + r12 * 8], rax
    mov eax, r12d
    jmp .out
.refused:
    mov eax, -USB_EHC
    jmp .out
.nomem:
    mov eax, -USB_ENOMEM
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_address_device — the slot context and EP0, then Address Device
; Input:  RDI = hc, ESI = slot, EDX = root port, ECX = speed (USB_SPEED_*),
;         R8D = route string, R9D = TT: hub slot 0-7, hub port 8-15, MTT 16
;         (0 for a device not behind a high-speed hub)
; Output: EAX = 0 or a negative USB_E*; EDX = the bus address
; -----------------------------------------------------------------------------
global xhci_address_device
xhci_address_device:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, esi
    mov r14d, edx
    mov r15d, ecx
    mov r13, [rbx + xhci_hc.slots + r12 * 8]
    mov eax, -USB_EHC
    test r13, r13
    jz .out
    mov [r13 + xhci_slot.port], r14d
    mov [r13 + xhci_slot.speed], r15d
    push r8
    push r9
    ; EP0's ring
    mov edi, XHCI_RING_TRBS
    call xhci_ring_new
    pop r9
    pop r8
    test rax, rax
    jz .nomem
    mov [r13 + xhci_slot.eps + xhci_ep_size + xhci_ep.ring], rax
    mov dword [r13 + xhci_slot.eps + xhci_ep_size + xhci_ep.type], EP_TYPE_CONTROL
    ; the input context, from zero
    mov rdi, [r13 + xhci_slot.in_ctx]
    mov ecx, [rbx + xhci_hc.ctx_size]
    imul ecx, ecx, 33
    push rax
    push rdi
    xor eax, eax
    rep stosb
    pop rdi
    pop rax
    mov dword [rdi + 4], 3              ; add: slot and EP0
    mov ecx, [rbx + xhci_hc.ctx_size]
    lea rdx, [rdi + rcx]                ; slot context
    mov r10d, r8d
    and r10d, 0xFFFFF
    mov r11d, r15d
    shl r11d, 20
    or r10d, r11d
    or r10d, 1 << 27                    ; one context entry: EP0
    test r9d, 1 << 16
    jz .no_mtt
    or r10d, 1 << 25
.no_mtt:
    mov [rdx], r10d
    mov r10d, r14d
    shl r10d, 16
    mov [rdx + 4], r10d
    mov r10d, r9d
    and r10d, 0xFFFF
    mov [rdx + 8], r10d
    lea rdx, [rdx + rcx]                ; EP0 context
    mov edi, r15d
    call xhci_default_mps0
    shl eax, 16
    or eax, (3 << 1) | (EP_TYPE_CONTROL << 3)
    mov [rdx + 4], eax
    mov rdi, [r13 + xhci_slot.eps + xhci_ep_size + xhci_ep.ring]
    mov rax, [rdi + xhci_ring.trbs]
    or rax, 1                           ; dequeue cycle state
    mov [rdx + 8], rax
    mov dword [rdx + 16], 8             ; average TRB length
    ; Address Device
    mov rdi, rbx
    mov rsi, [r13 + xhci_slot.in_ctx]
    xor edx, edx
    mov ecx, r12d
    shl ecx, 24
    or ecx, TRB_ADDRESS_DEVICE << TRB_TYPE_SHIFT
    call xhci_command
    test eax, eax
    js .out
    cmp eax, CC_SUCCESS
    jne .failed
    mov rax, [r13 + xhci_slot.out_ctx]
    movzx edx, byte [rax + 12]          ; slot context dword 3: address
    xor eax, eax
    jmp .out
.failed:
    mov eax, -USB_EXACT
    xor edx, edx
    jmp .out
.nomem:
    mov eax, -USB_ENOMEM
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; xhci_default_mps0 — EDI = speed → EAX = EP0's packet size to start with
; (full speed starts at 8 and is corrected from the device descriptor)
xhci_default_mps0:
    mov eax, 8
    cmp edi, USB_SPEED_HIGH
    jne .ss
    mov eax, 64
.ss:
    cmp edi, USB_SPEED_SUPER
    jb .out
    mov eax, 512
.out:
    ret

; -----------------------------------------------------------------------------
; xhci_set_mps0 — EP0's packet size, through Evaluate Context
; Input:  RDI = hc, ESI = slot, EDX = size
; Output: EAX = 0 or a negative USB_E*
; -----------------------------------------------------------------------------
global xhci_set_mps0
xhci_set_mps0:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13, [rbx + xhci_hc.slots + r12 * 8]
    mov eax, -USB_EHC
    test r13, r13
    jz .out
    mov rdi, [r13 + xhci_slot.in_ctx]
    mov dword [rdi], 0                  ; drop nothing
    mov dword [rdi + 4], 2              ; evaluate EP0
    mov ecx, [rbx + xhci_hc.ctx_size]
    lea rax, [rdi + rcx * 2]            ; EP0 context
    mov ecx, [rax + 4]
    and ecx, 0xFFFF
    shl edx, 16
    or ecx, edx
    mov [rax + 4], ecx
    mov rdi, rbx
    mov rsi, [r13 + xhci_slot.in_ctx]
    xor edx, edx
    mov ecx, r12d
    shl ecx, 24
    or ecx, TRB_EVALUATE_CTX << TRB_TYPE_SHIFT
    call xhci_command
    test eax, eax
    js .out
    cmp eax, CC_SUCCESS
    mov eax, 0
    je .out
    mov eax, -USB_EHC
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_ep_recover — a halted endpoint back in use, past the failed TD
; Input:  RDI = hc, ESI = slot, EDX = device context index
; Output: EAX = 0 or a negative USB_E*
; -----------------------------------------------------------------------------
global xhci_ep_recover
xhci_ep_recover:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    mov ecx, r12d
    shl ecx, 24
    mov eax, r13d
    shl eax, 16
    or ecx, eax
    or ecx, TRB_RESET_EP << TRB_TYPE_SHIFT
    call xhci_command
    test eax, eax
    js .out
    ; Set TR Dequeue Pointer to the next free TRB: what failed is skipped
    mov rax, [rbx + xhci_hc.slots + r12 * 8]
    mov ecx, r13d
    imul ecx, ecx, xhci_ep_size
    mov rdi, [rax + xhci_slot.eps + rcx + xhci_ep.ring]
    call xhci_ring_deq
    mov rsi, rax
    mov rdi, rbx
    xor edx, edx
    mov ecx, r12d
    shl ecx, 24
    mov eax, r13d
    shl eax, 16
    or ecx, eax
    or ecx, TRB_SET_TR_DEQ << TRB_TYPE_SHIFT
    call xhci_command
    test eax, eax
    js .out
    cmp eax, CC_SUCCESS
    mov eax, 0
    je .out
    mov eax, -USB_EHC
.out:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_USB_HCD_XHCI_CMD_ASM
