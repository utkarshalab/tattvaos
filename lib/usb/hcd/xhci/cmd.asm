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

; -----------------------------------------------------------------------------
; xhci_disable_slot — a device gone: its transfers forgotten, Disable Slot,
;                     then its rings, contexts and record given back
; Input:  RDI = hc, ESI = slot
; Output: EAX = 0 (the slot is released even when the command fails)
; -----------------------------------------------------------------------------
global xhci_disable_slot
xhci_disable_slot:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    xor eax, eax
    test r12d, r12d
    jz .out
    cmp r12d, 255
    ja .out
    mov r13, [rbx + xhci_hc.slots + r12 * 8]
    test r13, r13
    jz .out
    ; nothing completes into a driver from here on
    xor ecx, ecx
.forget:
    mov eax, ecx
    imul eax, eax, xhci_ep_size
    mov qword [r13 + xhci_slot.eps + rax + xhci_ep.xfer], 0
    inc ecx
    cmp ecx, 32
    jb .forget
    mov rdi, rbx
    xor esi, esi
    xor edx, edx
    mov ecx, r12d
    shl ecx, 24
    or ecx, TRB_DISABLE_SLOT << TRB_TYPE_SHIFT
    call xhci_command
    ; released whatever the command said: the slot is unusable either way
    mov rax, [rbx + xhci_hc.dcbaa]
    mov qword [rax + r12 * 8], 0
    mov qword [rbx + xhci_hc.slots + r12 * 8], 0
    mov r14d, 1
.ring:
    mov eax, r14d
    imul eax, eax, xhci_ep_size
    mov rdi, [r13 + xhci_slot.eps + rax + xhci_ep.ring]
    call xhci_ring_free
    inc r14d
    cmp r14d, 32
    jb .ring
    mov rdi, [r13 + xhci_slot.out_ctx]
    mov esi, [rbx + xhci_hc.ctx_size]
    shl esi, 5
    mov edx, 64
    call usb_free
    mov rdi, [r13 + xhci_slot.in_ctx]
    mov esi, [rbx + xhci_hc.ctx_size]
    imul esi, esi, 33
    mov edx, 64
    call usb_free
    mov rdi, r13
    mov esi, xhci_slot_size
    mov edx, 64
    call usb_free
    xor eax, eax
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_set_hub — the slot is a hub: Configure Endpoint will say so
; Input:  RDI = hc, ESI = slot, EDX = ports, ECX = TT think time (0-3),
;         R8D = 1 for a multi-TT hub
; -----------------------------------------------------------------------------
global xhci_set_hub
xhci_set_hub:
    mov esi, esi
    mov rax, [rdi + xhci_hc.slots + rsi * 8]
    test rax, rax
    jz .out
    mov [rax + xhci_slot.hub_ports], edx
    and ecx, 3
    shl r8d, 2
    or ecx, r8d
    or ecx, 1 << 3                      ; a hub
    mov [rax + xhci_slot.hub], ecx
.out:
    ret

; -----------------------------------------------------------------------------
; xhci_ep_interval — the endpoint context's interval (2^n × 125 µs)
; Input:  ECX = transfer type (USB_EP_*), EDX = speed, R8D = bInterval
; Output: EAX
; -----------------------------------------------------------------------------
xhci_ep_interval:
    xor eax, eax
    cmp ecx, USB_EP_BULK
    je .out
    cmp edx, USB_SPEED_HIGH
    jae .exponent
    cmp edx, USB_SPEED_FULL
    jne .frames                         ; low speed: interrupt only
    cmp ecx, USB_EP_ISOC
    je .fs_isoc
.frames:
    ; interrupt at full or low speed: bInterval in ms → microframes, log2
    mov eax, r8d
    test eax, eax
    jnz .ms
    mov eax, 1
.ms:
    shl eax, 3
    bsr eax, eax
    cmp eax, 3
    jae .ms_max
    mov eax, 3
.ms_max:
    cmp eax, 10
    jbe .out
    mov eax, 10
    ret
.fs_isoc:
    ; 2^(bInterval - 1) frames
    mov eax, r8d
    cmp eax, 1
    jae .fs_ok
    mov eax, 1
.fs_ok:
    cmp eax, 16
    jbe .fs_cap
    mov eax, 16
.fs_cap:
    add eax, 2
    ret
.exponent:
    ; high speed and SuperSpeed: 2^(bInterval - 1) microframes
    mov eax, r8d
    test eax, eax
    jz .out
    dec eax
    cmp eax, 15
    jbe .out
    mov eax, 15
.out:
    ret

; -----------------------------------------------------------------------------
; xhci_configure_iface — endpoint contexts and rings for one interface's
;                        endpoints (one alternate setting), Configure Endpoint
; Input:  RDI = hc, ESI = slot, RDX = usb_config*, ECX = index in its ifaces
; Output: EAX = 0 or a negative USB_E*
; -----------------------------------------------------------------------------
global xhci_configure_iface
xhci_configure_iface:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 40         ; [rsp] add flags, [+4] largest DCI, [+8] config,
                        ; [+16] next endpoint, [+20] endpoints left
    mov rbx, rdi
    mov r12d, esi
    mov [rsp + 8], rdx
    mov r13, [rbx + xhci_hc.slots + r12 * 8]
    mov eax, -USB_EHC
    test r13, r13
    jz .out
    mov eax, -USB_EINVAL
    cmp cl, [rdx + usb_config.iface_count]
    jae .out
    movzx eax, cl
    imul eax, eax, usb_iface_size
    lea rax, [rdx + usb_config.ifaces + rax]
    movzx ecx, byte [rax + usb_iface.first_ep]
    mov [rsp + 16], ecx
    movzx ecx, byte [rax + usb_iface.ep_count]
    mov [rsp + 20], ecx
    ; the input context: zero, then the slot context as it is now
    mov rdi, [r13 + xhci_slot.in_ctx]
    mov ecx, [rbx + xhci_hc.ctx_size]
    imul ecx, ecx, 33
    xor eax, eax
    rep stosb
    mov rdi, [r13 + xhci_slot.in_ctx]
    mov ecx, [rbx + xhci_hc.ctx_size]
    lea rdi, [rdi + rcx]
    mov rsi, [r13 + xhci_slot.out_ctx]
    rep movsb
    mov dword [rsp], 1                  ; A0: the slot context
    mov rax, [r13 + xhci_slot.out_ctx]
    mov eax, [rax]
    shr eax, 27
    mov [rsp + 4], eax

.endpoint:
    cmp dword [rsp + 20], 0
    je .command
    dec dword [rsp + 20]
    mov eax, [rsp + 16]
    inc dword [rsp + 16]
    shl eax, 4                          ; usb_ep_size
    mov r14, [rsp + 8]
    lea r14, [r14 + usb_config.eps + rax]
    movzx eax, byte [r14 + usb_ep.address]
    mov ebp, eax
    and ebp, USB_EP_NUM_MASK
    jz .endpoint                        ; endpoint 0 is not configured here
    shl ebp, 1
    test al, USB_EP_DIR_IN
    jz .dci
    inc ebp                             ; EBP = device context index
.dci:
    movzx r15d, byte [r14 + usb_ep.attributes]
    and r15d, USB_EP_TYPE_MASK
    jz .endpoint                        ; a second control endpoint: not used
    ; its ring
    mov edi, XHCI_RING_TRBS
    call xhci_ring_new
    test rax, rax
    jz .nomem
    mov ecx, ebp
    imul ecx, ecx, xhci_ep_size
    lea rdx, [r13 + xhci_slot.eps + rcx]
    mov [rdx + xhci_ep.ring], rax
    mov qword [rdx + xhci_ep.xfer], 0
    mov eax, r15d
    test byte [r14 + usb_ep.address], USB_EP_DIR_IN
    jz .type
    add eax, 4
.type:
    mov [rdx + xhci_ep.type], eax
    ; the context
    mov rdi, [r13 + xhci_slot.in_ctx]
    mov ecx, ebp
    inc ecx
    imul ecx, [rbx + xhci_hc.ctx_size]
    add rdi, rcx
    ; dword 1: error count, type, burst, packet size
    shl eax, 3
    cmp r15d, USB_EP_ISOC
    je .no_cerr
    or eax, 3 << 1
.no_cerr:
    movzx r9d, word [r14 + usb_ep.max_packet]
    mov r10d, r9d
    and r9d, 0x7FF                      ; packet size
    shr r10d, 11
    and r10d, 3                         ; high-speed extra transactions
    cmp dword [r13 + xhci_slot.speed], USB_SPEED_SUPER
    jb .burst
    movzx r10d, byte [r14 + usb_ep.ss_burst]
.burst:
    cmp r15d, USB_EP_BULK
    jne .burst_set
    cmp dword [r13 + xhci_slot.speed], USB_SPEED_SUPER
    jae .burst_set
    xor r10d, r10d                      ; bulk below SuperSpeed: no burst
.burst_set:
    mov ecx, r10d
    shl ecx, 8
    or eax, ecx
    mov ecx, r9d
    shl ecx, 16
    or eax, ecx
    mov [rdi + 4], eax
    ; dword 0: interval, and Mult for SuperSpeed isochronous
    push rdi
    mov ecx, r15d
    mov edx, [r13 + xhci_slot.speed]
    movzx r8d, byte [r14 + usb_ep.interval]
    call xhci_ep_interval
    pop rdi
    shl eax, 16
    cmp r15d, USB_EP_ISOC
    jne .dword0
    cmp dword [r13 + xhci_slot.speed], USB_SPEED_SUPER
    jb .dword0
    movzx ecx, byte [r14 + usb_ep.ss_attr]
    and ecx, 3
    shl ecx, 8
    or eax, ecx
.dword0:
    ; the payload per service interval, for periodic endpoints
    xor ecx, ecx
    cmp r15d, USB_EP_BULK
    je .esit_done
    mov ecx, [r14 + usb_ep.ss_bpi]
    test ecx, ecx
    jnz .esit_done
    lea ecx, [r10d + 1]
    imul ecx, r9d
.esit_done:
    mov edx, ecx
    shr edx, 16
    shl edx, 24
    or eax, edx                         ; Max ESIT Payload high
    mov [rdi], eax
    ; dwords 2-3: the ring, cycle 1
    mov edx, ebp
    imul edx, edx, xhci_ep_size
    mov rax, [r13 + xhci_slot.eps + rdx + xhci_ep.ring]
    mov rax, [rax + xhci_ring.trbs]
    or rax, 1
    mov [rdi + 8], rax
    ; dword 4: average TRB length, Max ESIT Payload low
    mov eax, 1024
    cmp r15d, USB_EP_INTERRUPT
    je .avg
    mov eax, 3072
.avg:
    and ecx, 0xFFFF
    shl ecx, 16
    or eax, ecx
    mov [rdi + 16], eax
    bts dword [rsp], ebp
    cmp ebp, [rsp + 4]
    jbe .endpoint
    mov [rsp + 4], ebp
    jmp .endpoint

.command:
    mov rdi, [r13 + xhci_slot.in_ctx]
    mov eax, [rsp]
    mov [rdi + 4], eax                  ; add flags
    mov ecx, [rbx + xhci_hc.ctx_size]
    mov eax, [rdi + rcx]
    and eax, 0x07FFFFFF
    mov edx, [rsp + 4]
    shl edx, 27
    or eax, edx                         ; context entries: the largest DCI
    mov [rdi + rcx], eax
    ; a hub: the Hub and Multi-TT bits, its ports, the TT think time
    mov edx, [r13 + xhci_slot.hub]
    test edx, 1 << 3
    jz .not_hub
    or eax, 1 << 26
    test edx, 1 << 2
    jz .single_tt
    or eax, 1 << 25
.single_tt:
    mov [rdi + rcx], eax
    mov eax, [rdi + rcx + 4]
    and eax, 0x00FFFFFF
    mov r8d, [r13 + xhci_slot.hub_ports]
    shl r8d, 24
    or eax, r8d
    mov [rdi + rcx + 4], eax
    mov eax, [rdi + rcx + 8]
    and eax, ~(3 << 16)
    and edx, 3
    shl edx, 16
    or eax, edx
    mov [rdi + rcx + 8], eax
.not_hub:
    mov rdi, rbx
    mov rsi, [r13 + xhci_slot.in_ctx]
    xor edx, edx
    mov ecx, r12d
    shl ecx, 24
    or ecx, TRB_CONFIGURE_EP << TRB_TYPE_SHIFT
    call xhci_command
    test eax, eax
    js .out
    cmp eax, CC_SUCCESS
    mov eax, 0
    je .out
    mov eax, -USB_EHC
    jmp .out
.nomem:
    mov eax, -USB_ENOMEM
.out:
    add rsp, 40
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_USB_HCD_XHCI_CMD_ASM
