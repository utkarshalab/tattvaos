; =============================================================================
; Utkarsha OS — lib/usb/class/hub/hub.asm — USB 2 and USB 3 hubs
; =============================================================================
;   usb_hub_attach(dev)     a hub (class 9): its configuration and hub
;                           descriptor, the controller told it is a hub
;                           (ports, TT think time, multi-TT), USB 3 hub
;                           depth, its status endpoint, its ports powered
;                           and marked for the service to look at
;   usb_hub_service()       from the fiber: ports the status endpoint said
;                           changed: connect (reset, speed, enumerate), go
;                           away (what was there removed), over-current
;
; Port work waits on control transfers, so it never runs in the status
; endpoint's completion: that only marks ports for the service.
; =============================================================================

%ifndef LIB_USB_CLASS_HUB_HUB_ASM
%define LIB_USB_CLASS_HUB_HUB_ASM

%define USB_HUB_MAX         16
%define USB_HUB_MAX_PORTS   31

; hub class requests
%define HUB_GET_STATUS      0x00
%define HUB_CLEAR_FEATURE   0x01
%define HUB_SET_FEATURE     0x03
%define HUB_SET_DEPTH       0x0C
; port features
%define PORT_F_ENABLE       1
%define PORT_F_RESET        4
%define PORT_F_POWER        8
%define PORT_F_C_CONNECTION 16
%define PORT_F_C_RESET      20
%define PORT_F_BH_RESET     28
; wPortStatus
%define HPS_CONNECTION      (1 << 0)
%define HPS_ENABLE          (1 << 1)
%define HPS_OVER_CURRENT    (1 << 3)
%define HPS_RESET           (1 << 4)
%define HPS_LOW_SPEED       (1 << 9)    ; USB 2 hubs
%define HPS_HIGH_SPEED      (1 << 10)
; wPortChange bit → the feature that clears it
; 0 connection 16, 1 enable 17, 2 suspend 18, 3 over-current 19,
; 4 reset 20, 5 BH reset 29, 6 link state 25, 7 config error 26

struc usb_hub
    .dev:           resq 1
    .ports:         resd 1
    .ss:            resd 1          ; a USB 3 hub
    .power_ms:      resd 1          ; power-on to power-good
    .pending:       resd 1          ; ports to look at (bit = port)
    .flags:         resd 1          ; 1: status endpoint needs recovery
    .over_current:  resd 1
    .xfer:          resb usb_xfer_size
    .buf:           resb 8
    .status:        resb 4          ; GET_STATUS answers
endstruc

section .bss
alignb 8
global usb_hubs
usb_hubs:           resq USB_HUB_MAX
global usb_hub_count
usb_hub_count:      resd 1

section .rodata
usb_hub_clear_bit:  db PORT_F_C_CONNECTION, 17, 18, 19, PORT_F_C_RESET, 29, 25, 26

section .text

; usb_hub_ctl — a class request to the hub RBX: EDI = bmRequestType |
; bRequest << 8 | wValue << 16, ESI = wIndex, EDX = length, RCX = buffer
; → EAX as xhci_control
usb_hub_ctl:
    sub rsp, 8
    mov eax, esi
    shl rax, 32
    mov r8d, edx
    mov edx, edi
    or rdx, rax
    mov eax, r8d
    shl rax, 48
    or rdx, rax
    mov rax, [rbx + usb_hub.dev]
    movzx esi, byte [rax + usb_device.slot]
    mov rdi, [rax + usb_device.hc]
    call xhci_control
    add rsp, 8
    ret

; usb_hub_feature — EDI = 1 clear, 3 set; ESI = feature; EDX = port
usb_hub_feature:
    shl esi, 16
    shl edi, 8
    or edi, esi
    or edi, 0x23                        ; class, other (a port)
    mov esi, edx
    xor edx, edx
    xor ecx, ecx
    jmp usb_hub_ctl

; usb_hub_port_status — ESI = port → EAX = wPortStatus | wPortChange << 16,
;                       or a negative error
usb_hub_port_status:
    sub rsp, 8
    mov edi, 0xA3 | (HUB_GET_STATUS << 8)
    mov edx, 4
    lea rcx, [rbx + usb_hub.status]
    call usb_hub_ctl
    test eax, eax
    js .out
    mov eax, [rbx + usb_hub.status]
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; usb_hub_attach
; Input:  RDI = usb_device* (enumerated)
; Output: EAX = 1 when it is a hub and was taken, 0 when not a hub, or a
;         negative USB_E*
; -----------------------------------------------------------------------------
global usb_hub_attach
usb_hub_attach:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32                         ; the hub descriptor
    mov r12, rdi
    xor eax, eax
    mov r13, [r12 + usb_device.config]
    test r13, r13
    jz .out
    cmp byte [r12 + usb_device.desc + usb_device_desc.bDeviceClass], USB_CLASS_HUB
    je .hub
    cmp byte [r13 + usb_config.iface_count], 0
    je .out
    cmp byte [r13 + usb_config.ifaces + usb_iface.class], USB_CLASS_HUB
    jne .out
.hub:
    mov eax, -USB_ENOMEM
    cmp dword [rel usb_hub_count], USB_HUB_MAX
    jae .out
    mov eax, -USB_EINVAL
    cmp byte [r12 + usb_device.depth], 4
    ja .out                             ; a sixth tier of hubs is not allowed
    ; the configuration
    movzx eax, byte [r13 + usb_config.value]
    shl eax, 16
    or eax, USB_REQ_SET_CONFIG << 8
    mov rdx, rax
    mov rdi, [r12 + usb_device.hc]
    movzx esi, byte [r12 + usb_device.slot]
    xor ecx, ecx
    xor r8d, r8d
    call xhci_control
    test eax, eax
    js .out
    mov al, [r13 + usb_config.value]
    mov [r12 + usb_device.config_value], al
    mov byte [r12 + usb_device.state], USB_DEV_CONFIGURED
    or word [r12 + usb_device.flags], USB_DEVF_HUB
    ; its record
    mov edi, usb_hub_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov rbx, rax
    mov [rbx + usb_hub.dev], r12
    xor r15d, r15d                      ; USB 2
    cmp byte [r12 + usb_device.speed], USB_SPEED_SUPER
    jb .usb2
    mov r15d, 1
.usb2:
    mov [rbx + usb_hub.ss], r15d
    ; the hub descriptor: 0x29 (USB 2) or 0x2A (USB 3)
    mov edi, 0xA0 | (USB_REQ_GET_DESCRIPTOR << 8) | (0x2900 << 16)
    test r15d, r15d
    jz .desc
    mov edi, 0xA0 | (USB_REQ_GET_DESCRIPTOR << 8) | (0x2A00 << 16)
.desc:
    xor esi, esi
    mov edx, 12
    mov rcx, rsp
    call usb_hub_ctl
    test eax, eax
    js .drop
    cmp eax, 7
    jb .bad
    movzx eax, byte [rsp + 2]
    test eax, eax
    jz .bad
    cmp eax, USB_HUB_MAX_PORTS
    jbe .ports
    mov eax, USB_HUB_MAX_PORTS
.ports:
    mov [rbx + usb_hub.ports], eax
    movzx eax, byte [rsp + 5]
    add eax, eax                        ; 2 ms units
    cmp eax, 100
    jae .power
    mov eax, 100                        ; and never less than 100 ms
.power:
    mov [rbx + usb_hub.power_ms], eax
    ; tell the controller: ports, TT think time, multi-TT
    mov rdi, [r12 + usb_device.hc]
    movzx esi, byte [r12 + usb_device.slot]
    mov edx, [rbx + usb_hub.ports]
    movzx ecx, word [rsp + 3]
    shr ecx, 5                          ; TT think time, USB 2 hubs
    xor r8d, r8d
    cmp byte [r12 + usb_device.desc + usb_device_desc.bDeviceProtocol], 2
    jne .single
    mov r8d, 1
.single:
    test r15d, r15d
    jz .tell
    xor ecx, ecx                        ; USB 3 hubs have no TT
    xor r8d, r8d
.tell:
    call xhci_set_hub
    ; a USB 3 hub needs its depth for routing
    test r15d, r15d
    jz .endpoint
    movzx eax, byte [r12 + usb_device.depth]
    shl eax, 16
    or eax, 0x20 | (HUB_SET_DEPTH << 8)
    mov edi, eax
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call usb_hub_ctl
    test eax, eax
    js .drop
.endpoint:
    mov rdi, [r12 + usb_device.hc]
    movzx esi, byte [r12 + usb_device.slot]
    mov rdx, r13
    xor ecx, ecx
    call xhci_configure_iface
    test eax, eax
    js .drop
    ; listed, and the device's driver
    mov eax, [rel usb_hub_count]
    lea rcx, [rel usb_hubs]
    mov [rcx + rax * 8], rbx
    inc dword [rel usb_hub_count]
    lea rax, [rel usb_hub_detach]
    mov [r12 + usb_device.driver], rax
    ; power every port, wait for it
    mov r14d, 1
.power_on:
    cmp r14d, [rbx + usb_hub.ports]
    ja .powered
    mov edi, HUB_SET_FEATURE
    mov esi, PORT_F_POWER
    mov edx, r14d
    call usb_hub_feature
    inc r14d
    jmp .power_on
.powered:
    mov edi, [rbx + usb_hub.power_ms]
    imul edi, edi, 1000
    call usb_delay
    ; every port looked at once, then the status endpoint says what changes
    mov ecx, [rbx + usb_hub.ports]
    mov eax, 2
    shl eax, cl
    sub eax, 2                          ; bits 1 .. ports
    mov [rbx + usb_hub.pending], eax
    ; its status change endpoint: the interrupt IN of interface 0
    lea rdi, [rbx + usb_hub.xfer]
    mov [rdi + usb_xfer.dev], r12
    movzx ecx, byte [r13 + usb_config.ifaces + usb_iface.first_ep]
    shl ecx, 4
    mov al, [r13 + usb_config.eps + rcx + usb_ep.address]
    mov [rdi + usb_xfer.endpoint], al
    mov byte [rdi + usb_xfer.type], USB_EP_INTERRUPT
    mov eax, [rbx + usb_hub.ports]
    shr eax, 3
    inc eax                             ; one bit per port and the hub's
    mov [rdi + usb_xfer.length], eax
    lea rax, [rbx + usb_hub.buf]
    mov [rdi + usb_xfer.buffer], rax
    lea rax, [rel usb_hub_done]
    mov [rdi + usb_xfer.done], rax
    mov [rdi + usb_xfer.context], rbx
    mov rsi, rdi
    mov rdi, [r12 + usb_device.hc]
    call xhci_submit
    test eax, eax
    jz .taken
    or dword [rbx + usb_hub.flags], 1
.taken:
    mov eax, 1                          ; its ports wait for usb_hub_service
    jmp .out
.bad:
    mov eax, -USB_EDESC
.drop:
    mov r14d, eax
    mov rdi, rbx
    mov esi, usb_hub_size
    mov edx, 8
    call usb_free
    and word [r12 + usb_device.flags], ~USB_DEVF_HUB
    mov eax, r14d
    jmp .out
.nomem:
    mov eax, -USB_ENOMEM
.out:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_hub_done — the status endpoint: ports that changed (bit 0: the hub)
; Input:  RDI = usb_xfer*
; -----------------------------------------------------------------------------
usb_hub_done:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    mov rbx, [r12 + usb_xfer.context]
    cmp dword [r12 + usb_xfer.status], 0
    jne .failed
    mov eax, [rbx + usb_hub.buf]
    mov ecx, [r12 + usb_xfer.actual]
    cmp ecx, 4
    jae .bits
    shl ecx, 3
    mov edx, 1
    shl edx, cl
    dec edx
    and eax, edx                        ; only the bytes that came
.bits:
    and eax, ~1
    or [rbx + usb_hub.pending], eax
    mov rax, [r12 + usb_xfer.dev]
    mov rdi, [rax + usb_device.hc]
    mov rsi, r12
    call xhci_submit
    test eax, eax
    jz .out
.failed:
    or dword [rbx + usb_hub.flags], 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_hub_child — the device on port ESI of hub RBX → RAX, or 0
; -----------------------------------------------------------------------------
usb_hub_child:
    mov rdx, [rbx + usb_hub.dev]
    xor ecx, ecx
.next:
    cmp ecx, [rel usb_device_total]
    jae .none
    lea rax, [rel usb_devices]
    mov rax, [rax + rcx * 8]
    inc ecx
    cmp [rax + usb_device.parent], rdx
    jne .next
    movzx r8d, byte [rax + usb_device.port]
    cmp r8d, esi
    jne .next
    ret
.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usb_hub_ports — look at every pending port of hub RDI
; -----------------------------------------------------------------------------
usb_hub_ports:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, 1
.port:
    cmp r12d, [rbx + usb_hub.ports]
    ja .out
    btr dword [rbx + usb_hub.pending], r12d
    jnc .next
    mov esi, r12d
    call usb_hub_port_status
    test eax, eax
    js .next
    mov r13d, eax                       ; status | change << 16
    ; clear every change it reports
    mov r14d, eax
    shr r14d, 16
    xor r15d, r15d
.clear:
    cmp r15d, 8
    jae .cleared
    bt r14d, r15d
    jnc .clear_next
    lea rax, [rel usb_hub_clear_bit]
    movzx esi, byte [rax + r15]
    mov edi, HUB_CLEAR_FEATURE
    mov edx, r12d
    call usb_hub_feature
.clear_next:
    inc r15d
    jmp .clear
.cleared:
    test r13d, HPS_OVER_CURRENT
    jz .no_oc
    inc dword [rbx + usb_hub.over_current]
.no_oc:
    mov esi, r12d
    call usb_hub_child
    mov r15, rax
    test r13d, HPS_CONNECTION
    jz .gone
    ; connected: a device that was there and stayed needs nothing
    test r15, r15
    jz .new
    test r13d, 1 << 16                  ; it reconnected: what was there went
    jz .next
    mov rdi, r15
    call usb_device_remove
.new:
    mov esi, r12d
    call usb_hub_reset
    test eax, eax
    js .next
    mov rdi, [rbx + usb_hub.dev]
    mov rdi, [rdi + usb_device.hc]
    mov rsi, [rbx + usb_hub.dev]
    mov edx, r12d
    mov ecx, eax
    call usb_enumerate_at
    test eax, eax
    jnz .next
    mov rdi, rdx
    call usb_device_found
    jmp .next
.gone:
    test r15, r15
    jz .next
    mov rdi, r15
    call usb_device_remove
.next:
    inc r12d
    jmp .port
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_hub_reset — reset port ESI of hub RBX until it is enabled
; Output: EAX = the speed, or a negative USB_E*
; USB 2 hubs say low, full or high speed; a USB 3 hub's ports are
; SuperSpeed. A USB 3 port whose link did not come up gets a warm reset.
; -----------------------------------------------------------------------------
usb_hub_reset:
    push r12
    push r13
    push r14
    mov r12d, esi
    mov r13d, PORT_F_RESET
    mov r14d, 1 << (16 + 4)             ; C_PORT_RESET
    cmp dword [rbx + usb_hub.ss], 0
    je .reset
    mov esi, r12d
    call usb_hub_port_status
    test eax, eax
    js .out
    test eax, HPS_ENABLE
    jnz .enabled                        ; the link trained by itself
    mov r13d, PORT_F_BH_RESET
    mov r14d, 1 << (16 + 5)             ; C_BH_PORT_RESET
.reset:
    mov edi, HUB_SET_FEATURE
    mov esi, r13d
    mov edx, r12d
    call usb_hub_feature
    test eax, eax
    js .out
    mov r13d, 50                        ; 50 × 10 ms
.wait:
    mov edi, 10000
    call usb_delay
    mov esi, r12d
    call usb_hub_port_status
    test eax, eax
    js .out
    test eax, r14d
    jnz .done
    dec r13d
    jnz .wait
    mov eax, -USB_ETIMEOUT
    jmp .out
.done:
    push rax
    sub rsp, 8
    mov edi, HUB_CLEAR_FEATURE
    mov esi, PORT_F_C_RESET
    cmp r14d, 1 << (16 + 4)
    je .clear
    mov esi, 29                         ; C_BH_PORT_RESET
.clear:
    mov edx, r12d
    call usb_hub_feature
    mov edi, 10000                      ; reset recovery
    call usb_delay
    add rsp, 8
    pop rax
.enabled:
    test eax, HPS_CONNECTION
    jz .gone
    test eax, HPS_ENABLE
    jz .gone
    mov ecx, eax
    mov eax, USB_SPEED_SUPER
    cmp dword [rbx + usb_hub.ss], 0
    jne .out
    mov eax, USB_SPEED_LOW
    test ecx, HPS_LOW_SPEED
    jnz .out
    mov eax, USB_SPEED_HIGH
    test ecx, HPS_HIGH_SPEED
    jnz .out
    mov eax, USB_SPEED_FULL
    jmp .out
.gone:
    mov eax, -USB_ENODEV
.out:
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; usb_hub_service — every hub's pending ports, and a status endpoint that
;                   failed put back (the input fiber)
; Output: EAX = hubs that had work
; -----------------------------------------------------------------------------
global usb_hub_service
usb_hub_service:
    push rbx
    push r12
    push r13
    xor r12d, r12d
    xor r13d, r13d
.hub:
    cmp r12d, [rel usb_hub_count]
    jae .out
    lea rax, [rel usb_hubs]
    mov rbx, [rax + r12 * 8]
    inc r12d
    btr dword [rbx + usb_hub.flags], 0
    jnc .ports
    inc r13d
    mov rax, [rbx + usb_hub.dev]
    mov rdi, [rax + usb_device.hc]
    movzx esi, byte [rax + usb_device.slot]
    lea rcx, [rbx + usb_hub.xfer]
    movzx edx, byte [rcx + usb_xfer.endpoint]
    and edx, USB_EP_NUM_MASK
    shl edx, 1
    inc edx
    call xhci_ep_recover
    mov rax, [rbx + usb_hub.dev]
    mov rdi, [rax + usb_device.hc]
    lea rsi, [rbx + usb_hub.xfer]
    call xhci_submit
.ports:
    cmp dword [rbx + usb_hub.pending], 0
    je .hub
    inc r13d
    mov rdi, rbx
    call usb_hub_ports
    ; a port's work may have removed hubs below this one and moved the
    ; list up: one could be passed over this time, and is seen next time
    jmp .hub
.out:
    mov eax, r13d
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_hub_detach — usb_device.driver: the hub went (what was behind it is
;                  already removed)
; Input:  RDI = usb_device*
; -----------------------------------------------------------------------------
usb_hub_detach:
    push rbx
    xor ecx, ecx
    lea rdx, [rel usb_hubs]
.find:
    cmp ecx, [rel usb_hub_count]
    jae .out
    mov rbx, [rdx + rcx * 8]
    cmp [rbx + usb_hub.dev], rdi
    je .unlist
    inc ecx
    jmp .find
.unlist:
    dec dword [rel usb_hub_count]
.shift:
    cmp ecx, [rel usb_hub_count]
    jae .free
    mov rax, [rdx + rcx * 8 + 8]
    mov [rdx + rcx * 8], rax
    inc ecx
    jmp .shift
.free:
    mov rdi, rbx
    mov esi, usb_hub_size
    mov edx, 8
    call usb_free
.out:
    pop rbx
    ret

%endif ; LIB_USB_CLASS_HUB_HUB_ASM
