; =============================================================================
; Utkarsha OS — lib/usb/core/match.asm — which driver takes a device
; =============================================================================
;   usb_driver_register(driver)     add a driver (16 at most); registered
;                                   ones are tried before the built-in ones,
;                                   so one for a particular vendor and
;                                   product comes first
;   usb_driver_matches(driver, dev) whether its match fields fit the device
;   usb_attach_drivers(dev)         each driver whose fields fit, in turn,
;                                   until one takes it (attach > 0)
;
; Match fields: vendor, product, device class, and an interface's class,
; subclass and protocol (any interface's first alternate setting).
; =============================================================================

%ifndef LIB_USB_CORE_MATCH_ASM
%define LIB_USB_CORE_MATCH_ASM

%define USB_DRIVERS_MAX     16

%define USB_MATCH_VENDOR    (1 << 0)
%define USB_MATCH_PRODUCT   (1 << 1)
%define USB_MATCH_DEV_CLASS (1 << 2)
%define USB_MATCH_IF_CLASS  (1 << 3)
%define USB_MATCH_IF_SUB    (1 << 4)
%define USB_MATCH_IF_PROTO  (1 << 5)

struc usb_driver
    .match:         resw 1          ; USB_MATCH_*
    .vendor:        resw 1
    .product:       resw 1
    .class:         resb 1          ; the device's, or the interface's
    .subclass:      resb 1
    .protocol:      resb 1
    .pad:           resb 7
    .attach:        resq 1          ; RDI = usb_device* → EAX > 0 when taken
    .name:          resq 1
endstruc                            ; 32 bytes

section .data
align 8
usb_builtin_drivers:
    ; hubs, as devices or as interfaces
    dw USB_MATCH_DEV_CLASS, 0, 0
    db USB_CLASS_HUB, 0, 0
    times 7 db 0
    dq usb_hub_attach, usb_drv_name_hub
    dw USB_MATCH_IF_CLASS, 0, 0
    db USB_CLASS_HUB, 0, 0
    times 7 db 0
    dq usb_hub_attach, usb_drv_name_hub
    ; keyboards, mice, media keys
    dw USB_MATCH_IF_CLASS, 0, 0
    db USB_CLASS_HID, 0, 0
    times 7 db 0
    dq usb_hid_attach, usb_drv_name_hid
usb_builtin_end:

section .bss
alignb 8
global usb_drivers
usb_drivers:        resq USB_DRIVERS_MAX
global usb_driver_count
usb_driver_count:   resd 1

section .rodata
usb_drv_name_hub:   db "hub", 0
usb_drv_name_hid:   db "hid", 0

section .text

; -----------------------------------------------------------------------------
; usb_driver_register — RDI = usb_driver* (kept, not copied)
; Output: EAX = 0, -USB_ENOMEM when the table is full, -USB_EINVAL with no
;         attach function
; -----------------------------------------------------------------------------
global usb_driver_register
usb_driver_register:
    mov eax, -USB_EINVAL
    cmp qword [rdi + usb_driver.attach], 0
    je .out
    mov eax, -USB_ENOMEM
    mov ecx, [rel usb_driver_count]
    cmp ecx, USB_DRIVERS_MAX
    jae .out
    lea rax, [rel usb_drivers]
    mov [rax + rcx * 8], rdi
    inc dword [rel usb_driver_count]
    xor eax, eax
.out:
    ret

; -----------------------------------------------------------------------------
; usb_driver_matches — RDI = usb_driver*, RSI = usb_device* → EAX = 1 or 0
; -----------------------------------------------------------------------------
global usb_driver_matches
usb_driver_matches:
    movzx r8d, word [rdi + usb_driver.match]
    test r8d, USB_MATCH_VENDOR
    jz .product
    mov ax, [rsi + usb_device.desc + usb_device_desc.idVendor]
    cmp ax, [rdi + usb_driver.vendor]
    jne .no
.product:
    test r8d, USB_MATCH_PRODUCT
    jz .dev_class
    mov ax, [rsi + usb_device.desc + usb_device_desc.idProduct]
    cmp ax, [rdi + usb_driver.product]
    jne .no
.dev_class:
    test r8d, USB_MATCH_DEV_CLASS
    jz .ifaces
    mov al, [rsi + usb_device.desc + usb_device_desc.bDeviceClass]
    cmp al, [rdi + usb_driver.class]
    jne .no
.ifaces:
    test r8d, USB_MATCH_IF_CLASS | USB_MATCH_IF_SUB | USB_MATCH_IF_PROTO
    jz .yes
    mov r9, [rsi + usb_device.config]
    test r9, r9
    jz .no
    xor ecx, ecx
.iface:
    cmp cl, [r9 + usb_config.iface_count]
    jae .no
    movzx eax, cl
    imul eax, eax, usb_iface_size
    lea r10, [r9 + usb_config.ifaces + rax]
    inc ecx
    cmp byte [r10 + usb_iface.alt], 0
    jne .iface
    test r8d, USB_MATCH_IF_CLASS
    jz .if_sub
    mov al, [r10 + usb_iface.class]
    cmp al, [rdi + usb_driver.class]
    jne .iface
.if_sub:
    test r8d, USB_MATCH_IF_SUB
    jz .if_proto
    mov al, [r10 + usb_iface.subclass]
    cmp al, [rdi + usb_driver.subclass]
    jne .iface
.if_proto:
    test r8d, USB_MATCH_IF_PROTO
    jz .yes
    mov al, [r10 + usb_iface.protocol]
    cmp al, [rdi + usb_driver.protocol]
    jne .iface
.yes:
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usb_attach_drivers — offer a new device to the drivers that match it
; Input:  RDI = usb_device*
; Output: EAX = 1 when one took it
; -----------------------------------------------------------------------------
global usb_attach_drivers
usb_attach_drivers:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    xor r12d, r12d
.registered:
    cmp r12d, [rel usb_driver_count]
    jae .builtin
    lea rax, [rel usb_drivers]
    mov r13, [rax + r12 * 8]
    inc r12d
    call .try
    jnc .registered
    jmp .taken
.builtin:
    lea r13, [rel usb_builtin_drivers]
.next:
    lea rax, [rel usb_builtin_end]
    cmp r13, rax
    jae .none
    call .try
    jc .taken
    add r13, usb_driver_size
    jmp .next
.none:
    xor eax, eax
    jmp .out
.taken:
    mov eax, 1
.out:
    pop r13
    pop r12
    pop rbx
    ret

; the driver R13 for the device RBX: CF = 1 when it took it
.try:
    sub rsp, 8                          ; the return address put it off by 8
    mov rdi, r13
    mov rsi, rbx
    call usb_driver_matches
    test eax, eax
    jz .not
    mov rdi, rbx
    call [r13 + usb_driver.attach]
    add rsp, 8
    test eax, eax
    jle .not_taken
    stc
    ret
.not:
    add rsp, 8
.not_taken:
    clc
    ret

%endif ; LIB_USB_CORE_MATCH_ASM
