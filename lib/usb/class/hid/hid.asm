; =============================================================================
; Utkarsha OS — lib/usb/class/hid/hid.asm — USB keyboards and mice
; =============================================================================
; The USB transport for HID; what a report means is lib/input/hid's.
;
;   usb_hid_attach(dev)     claim the boot keyboard and mouse interfaces of
;                           an enumerated device: set its configuration,
;                           the boot protocol and no idle repeat, configure
;                           the interrupt endpoint, add the input device and
;                           start reading reports. EAX = interfaces claimed
;   usb_hid_service()       from the input fiber: keyboard LEDs after a lock
;                           key, and recovery of endpoints that failed
;
; Reports arrive through xhci_poll: each is turned into events at once and
; the transfer put back. Nothing in the completion waits on the controller;
; what has to (LEDs, recovery) is left for usb_hid_service.
;
; Report protocol (media keys, high-resolution wheels, touch) comes with the
; HID parser's input mapping; the new-keyboard check (decision U3) with the
; authorisation work in Phase 9.
; =============================================================================

%ifndef LIB_USB_CLASS_HID_HID_ASM
%define LIB_USB_CLASS_HID_HID_ASM

%define USB_HID_MAX         8
%define USB_HID_MAX_ERRORS  8       ; failed reports before giving up
%define USB_HID_KEYBOARD    1
%define USB_HID_MOUSE       2
%define USB_HID_REPORT_MAX  64

%define USB_HID_RECOVER     (1 << 0)
%define USB_HID_LEDS        (1 << 1)
%define USB_HID_DEAD        (1 << 2)

; class requests
%define HID_REQ_SET_REPORT  0x09
%define HID_REQ_SET_IDLE    0x0A
%define HID_REQ_SET_PROTOCOL 0x0B

struc usb_hid
    .dev:           resq 1
    .kind:          resd 1
    .iface:         resd 1          ; bInterfaceNumber
    .dci:           resd 1          ; its endpoint's device context index
    .flags:         resd 1          ; USB_HID_*
    .errors:        resd 1
    .reports:       resd 1
    .xfer:          resb usb_xfer_size
    .boot:          resb hid_boot_size
    .buf:           resb USB_HID_REPORT_MAX
    .led:           resb 8
endstruc

section .bss
alignb 8
global usb_hids
usb_hids:           resq USB_HID_MAX
global usb_hid_count
usb_hid_count:      resd 1

section .rodata
usb_hid_name_kbd:   db "USB keyboard", 0
usb_hid_name_mouse: db "USB mouse", 0

section .text

; -----------------------------------------------------------------------------
; usb_hid_ctl — a control request to the interface of RBX (usb_hid*)
; Input:  EDI = bmRequestType | bRequest << 8 | wValue << 16, ESI = length,
;         RCX = buffer
; Output: EAX as xhci_control
; -----------------------------------------------------------------------------
usb_hid_ctl:
    sub rsp, 8
    mov edx, edi
    mov eax, [rbx + usb_hid.iface]
    shl rax, 32
    or rdx, rax
    mov eax, esi
    shl rax, 48
    or rdx, rax
    mov r8d, esi
    mov rax, [rbx + usb_hid.dev]
    movzx esi, byte [rax + usb_device.slot]
    mov rdi, [rax + usb_device.hc]
    call xhci_control
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; usb_hid_attach
; Input:  RDI = usb_device* (enumerated)
; Output: EAX = interfaces claimed, or a negative USB_E*
; -----------------------------------------------------------------------------
global usb_hid_attach
usb_hid_attach:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov r12, rdi
    mov r13, [r12 + usb_device.config]
    mov eax, -USB_EINVAL
    test r13, r13
    jz .out
    xor r14d, r14d                      ; interface index
    xor r15d, r15d                      ; claimed
.iface:
    cmp r14b, [r13 + usb_config.iface_count]
    jae .done
    mov eax, r14d
    imul eax, eax, usb_iface_size
    lea rbp, [r13 + usb_config.ifaces + rax]
    cmp byte [rbp + usb_iface.alt], 0
    jne .next
    cmp byte [rbp + usb_iface.class], USB_CLASS_HID
    jne .next
    cmp byte [rbp + usb_iface.subclass], 1     ; boot interface
    jne .next
    movzx eax, byte [rbp + usb_iface.protocol]
    cmp eax, USB_HID_KEYBOARD
    je .kind_ok
    cmp eax, USB_HID_MOUSE
    jne .next
.kind_ok:
    ; its interrupt IN endpoint
    movzx ecx, byte [rbp + usb_iface.first_ep]
    movzx edx, byte [rbp + usb_iface.ep_count]
.find_ep:
    test edx, edx
    jz .next
    mov eax, ecx
    shl eax, 4
    lea r8, [r13 + usb_config.eps + rax]
    mov al, [r8 + usb_ep.attributes]
    and al, USB_EP_TYPE_MASK
    cmp al, USB_EP_INTERRUPT
    jne .find_next
    test byte [r8 + usb_ep.address], USB_EP_DIR_IN
    jnz .found_ep
.find_next:
    inc ecx
    dec edx
    jmp .find_ep
.found_ep:
    mov [rsp], r8
    cmp dword [rel usb_hid_count], USB_HID_MAX
    jae .done
    ; the configuration, once per device
    cmp byte [r12 + usb_device.config_value], 0
    jne .configured
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
.configured:
    mov edi, usb_hid_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov rbx, rax
    mov [rbx + usb_hid.dev], r12
    movzx eax, byte [rbp + usb_iface.protocol]
    mov [rbx + usb_hid.kind], eax
    movzx eax, byte [rbp + usb_iface.number]
    mov [rbx + usb_hid.iface], eax
    ; boot protocol; no repeats while nothing changes (both may stall:
    ; a boot interface works without them)
    mov edi, 0x21 | (HID_REQ_SET_PROTOCOL << 8)
    xor esi, esi
    xor ecx, ecx
    call usb_hid_ctl
    mov edi, 0x21 | (HID_REQ_SET_IDLE << 8)
    xor esi, esi
    xor ecx, ecx
    call usb_hid_ctl
    ; the endpoint
    mov rdi, [r12 + usb_device.hc]
    movzx esi, byte [r12 + usb_device.slot]
    mov rdx, r13
    mov ecx, r14d
    call xhci_configure_iface
    test eax, eax
    js .out
    ; the input device
    lea rdi, [rel usb_hid_name_kbd]
    mov edx, INPUT_CAP_KEYBOARD
    cmp dword [rbx + usb_hid.kind], USB_HID_KEYBOARD
    je .add
    lea rdi, [rel usb_hid_name_mouse]
    mov edx, INPUT_CAP_POINTER
.add:
    mov esi, INPUT_BUS_USB
    movzx ecx, word [r12 + usb_device.desc + usb_device_desc.idVendor]
    shl ecx, 16
    mov cx, [r12 + usb_device.desc + usb_device_desc.idProduct]
    call input_dev_add
    test eax, eax
    js .nomem
    mov [rbx + usb_hid.boot + hid_boot.dev], eax
    ; the transfer, and the first read
    mov r8, [rsp]
    lea rdi, [rbx + usb_hid.xfer]
    mov [rdi + usb_xfer.dev], r12
    mov al, [r8 + usb_ep.address]
    mov [rdi + usb_xfer.endpoint], al
    movzx ecx, al
    and ecx, USB_EP_NUM_MASK
    shl ecx, 1
    inc ecx
    mov [rbx + usb_hid.dci], ecx
    mov byte [rdi + usb_xfer.type], USB_EP_INTERRUPT
    mov word [rdi + usb_xfer.flags], USB_XF_SHORT_OK
    movzx eax, word [r8 + usb_ep.max_packet]
    and eax, 0x7FF
    cmp eax, USB_HID_REPORT_MAX
    jbe .len
    mov eax, USB_HID_REPORT_MAX
.len:
    mov [rdi + usb_xfer.length], eax
    lea rax, [rbx + usb_hid.buf]
    mov [rdi + usb_xfer.buffer], rax
    lea rax, [rel usb_hid_done]
    mov [rdi + usb_xfer.done], rax
    mov [rdi + usb_xfer.context], rbx
    mov eax, [rel usb_hid_count]
    lea rcx, [rel usb_hids]
    mov [rcx + rax * 8], rbx
    inc dword [rel usb_hid_count]
    inc r15d
    mov rsi, rdi
    mov rdi, [r12 + usb_device.hc]
    call xhci_submit
    test eax, eax
    jz .next
    or dword [rbx + usb_hid.flags], USB_HID_RECOVER
.next:
    inc r14d
    jmp .iface
.done:
    mov eax, r15d
    jmp .out
.nomem:
    mov eax, -USB_ENOMEM
.out:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_hid_done — a report came (or the read failed): from xhci_poll
; Input:  RDI = usb_xfer*
; -----------------------------------------------------------------------------
usb_hid_done:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    mov rbx, [r12 + usb_xfer.context]
    cmp dword [r12 + usb_xfer.status], 0
    jne .failed
    inc dword [rbx + usb_hid.reports]
    lea rdi, [rbx + usb_hid.boot]
    lea rsi, [rbx + usb_hid.buf]
    mov edx, [r12 + usb_xfer.actual]
    cmp dword [rbx + usb_hid.kind], USB_HID_KEYBOARD
    jne .mouse
    call hid_boot_keyboard
    test eax, eax
    jz .again
    or dword [rbx + usb_hid.flags], USB_HID_LEDS
    jmp .again
.mouse:
    call hid_boot_mouse
.again:
    mov rax, [r12 + usb_xfer.dev]
    mov rdi, [rax + usb_device.hc]
    mov rsi, r12
    call xhci_submit
    test eax, eax
    jz .out
.failed:
    inc dword [rbx + usb_hid.errors]
    or dword [rbx + usb_hid.flags], USB_HID_RECOVER
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_hid_service — LEDs and recovery, outside the completion path
; Output: EAX = devices that needed something
; -----------------------------------------------------------------------------
global usb_hid_service
usb_hid_service:
    push rbx
    push r12
    push r13
    xor r12d, r12d
    xor r13d, r13d
.hid:
    cmp r12d, [rel usb_hid_count]
    jae .out
    lea rax, [rel usb_hids]
    mov rbx, [rax + r12 * 8]
    inc r12d
    mov eax, [rbx + usb_hid.flags]
    test eax, USB_HID_DEAD
    jnz .hid
    test eax, USB_HID_RECOVER | USB_HID_LEDS
    jz .hid
    inc r13d
    btr dword [rbx + usb_hid.flags], 1  ; USB_HID_LEDS
    jnc .recover
    mov eax, [rbx + usb_hid.boot + hid_boot.locks]
    mov [rbx + usb_hid.led], al
    mov edi, 0x21 | (HID_REQ_SET_REPORT << 8) | (0x0200 << 16)  ; output, ID 0
    mov esi, 1
    lea rcx, [rbx + usb_hid.led]
    call usb_hid_ctl
.recover:
    btr dword [rbx + usb_hid.flags], 0  ; USB_HID_RECOVER
    jnc .hid
    cmp dword [rbx + usb_hid.xfer + usb_xfer.status], -USB_ENODEV
    je .dead
    cmp dword [rbx + usb_hid.errors], USB_HID_MAX_ERRORS
    ja .dead
    mov rax, [rbx + usb_hid.dev]
    mov rdi, [rax + usb_device.hc]
    movzx esi, byte [rax + usb_device.slot]
    mov edx, [rbx + usb_hid.dci]
    call xhci_ep_recover
    test eax, eax
    js .dead
    mov rax, [rbx + usb_hid.dev]
    mov rdi, [rax + usb_device.hc]
    lea rsi, [rbx + usb_hid.xfer]
    call xhci_submit
    test eax, eax
    jz .hid
.dead:
    or dword [rbx + usb_hid.flags], USB_HID_DEAD
    jmp .hid
.out:
    mov eax, r13d
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_USB_CLASS_HID_HID_ASM
