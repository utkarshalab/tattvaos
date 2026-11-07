; =============================================================================
; Utkarsha OS — lib/usb/core/enum.asm — enumeration
; =============================================================================
;   usb_enumerate(hc, port)     reset the port, address the device, read its
;                               device and configuration descriptors
;                               EAX = 0 or a negative USB_E*; RDX = device
;   usb_get_descriptor(dev, type, index, lang, buffer, length)
;   usb_get_string(dev, index, out, size)       UTF-8, the first language
;   usb_scan(hc)                every connected root port; EAX = devices
;   usb_device_count, usb_device_get(i)
;
; The device is left addressed, not configured: choosing a configuration
; waits for authorisation and a driver (ROADMAP.md §6.8, Phase 2). Only
; xHCI exists yet, so the controller is called directly.
; =============================================================================

%ifndef LIB_USB_CORE_ENUM_ASM
%define LIB_USB_CORE_ENUM_ASM

%define USB_CONFIG_MAX      4096    ; configuration bytes kept at most

section .bss
alignb 8
global usb_devices
usb_devices:        resq USB_MAX_DEVICES
global usb_device_total
usb_device_total:   resd 1
global usb_enum_errors
usb_enum_errors:    resd 1

section .text

; -----------------------------------------------------------------------------
; usb_get_descriptor — GET_DESCRIPTOR on EP0
; Input:  RDI = usb_device*, ESI = type, EDX = index, ECX = language,
;         R8 = buffer, R9D = length
; Output: EAX = bytes read, or a negative USB_E*
; -----------------------------------------------------------------------------
global usb_get_descriptor
usb_get_descriptor:
    sub rsp, 8
    ; setup: 80 06 index type lang length
    movzx eax, r9w
    shl rax, 48
    movzx r10d, cx
    shl r10, 32
    or rax, r10
    movzx r10d, dl
    shl r10d, 16
    or rax, r10
    movzx r10d, sil
    shl r10d, 24
    or rax, r10
    or rax, (USB_REQ_GET_DESCRIPTOR << 8) | USB_DIR_IN
    mov rdx, rax
    movzx esi, byte [rdi + usb_device.slot]
    mov rcx, r8
    mov r8d, r9d
    mov rdi, [rdi + usb_device.hc]
    call xhci_control
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; usb_get_string — string descriptor INDEX as UTF-8 in the first language
; Input:  RDI = usb_device*, ESI = index, RDX = out, ECX = out size
; Output: EAX = bytes written, or a negative USB_E* (index 0: none)
; -----------------------------------------------------------------------------
global usb_get_string
usb_get_string:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                        ; the descriptor
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    mov eax, -USB_EDESC
    test r12d, r12d
    jz .out
    ; the languages: string 0
    mov rdi, rbx
    mov esi, USB_DT_STRING
    xor edx, edx
    xor ecx, ecx
    mov r8, rsp
    mov r9d, 255
    call usb_get_descriptor
    test eax, eax
    js .out
    mov r15d, 0x0409                    ; when it lists none
    cmp eax, 4
    jb .read
    cmp byte [rsp], 4
    jb .read
    movzx r15d, word [rsp + 2]
.read:
    mov rdi, rbx
    mov esi, USB_DT_STRING
    mov edx, r12d
    mov ecx, r15d
    mov r8, rsp
    mov r9d, 255
    call usb_get_descriptor
    test eax, eax
    js .out
    mov rdi, rsp
    mov esi, eax
    mov rdx, r13
    mov ecx, r14d
    call usb_string_utf8
.out:
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_enumerate
; Input:  RDI = hc, ESI = root port
; Output: EAX = 0 or a negative USB_E*; RDX = usb_device* (0 on failure)
; -----------------------------------------------------------------------------
global usb_enumerate
usb_enumerate:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12, rdi
    mov r13d, esi
    mov eax, -USB_ENOMEM
    cmp dword [rel usb_device_total], USB_MAX_DEVICES
    jae .fail
    mov edi, usb_device_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .fail
    mov rbx, rax
    mov [rbx + usb_device.hc], r12
    mov [rbx + usb_device.port], r13b
    mov [rbx + usb_device.root_port], r13b
    mov byte [rbx + usb_device.state], USB_DEV_ATTACHED

    ; reset and enable the port
    mov rdi, r12
    mov esi, r13d
    call xhci_port_reset
    test eax, eax
    js .fail
    mov [rbx + usb_device.speed], al
    mov r14d, eax

    ; a slot, and the address
    mov rdi, r12
    call xhci_enable_slot
    test eax, eax
    js .fail
    mov [rbx + usb_device.slot], al
    mov r15d, eax
    mov rcx, [r12 + xhci_hc.slots + r15 * 8]
    mov [rcx + xhci_slot.dev], rbx
    mov rdi, r12
    mov esi, r15d
    mov edx, r13d
    mov ecx, r14d
    xor r8d, r8d
    xor r9d, r9d
    call xhci_address_device
    test eax, eax
    js .fail
    mov [rbx + usb_device.address], dl
    mov byte [rbx + usb_device.state], USB_DEV_ADDRESSED

    ; the first 8 bytes say EP0's packet size
    mov edi, r14d
    call xhci_default_mps0
    mov [rbx + usb_device.max_packet0], ax
    mov rdi, rbx
    mov esi, USB_DT_DEVICE
    xor edx, edx
    xor ecx, ecx
    lea r8, [rbx + usb_device.desc]
    mov r9d, 8
    call usb_get_descriptor
    test eax, eax
    js .fail
    cmp eax, 8
    jb .bad
    movzx eax, byte [rbx + usb_device.desc + usb_device_desc.bMaxPacketSize0]
    cmp r14d, USB_SPEED_SUPER
    jb .mps
    mov ecx, eax                        ; SuperSpeed: an exponent
    cmp ecx, 15
    ja .bad
    mov eax, 1
    shl eax, cl
.mps:
    cmp ax, [rbx + usb_device.max_packet0]
    je .full_desc
    test eax, eax
    jz .bad
    mov [rbx + usb_device.max_packet0], ax
    mov rdi, r12
    mov esi, r15d
    mov edx, eax
    call xhci_set_mps0
    test eax, eax
    js .fail

.full_desc:
    mov rdi, rbx
    mov esi, USB_DT_DEVICE
    xor edx, edx
    xor ecx, ecx
    lea r8, [rbx + usb_device.desc]
    mov r9d, usb_device_desc_size
    call usb_get_descriptor
    test eax, eax
    js .fail
    lea rdi, [rbx + usb_device.desc]
    mov esi, eax
    call usb_device_check
    test eax, eax
    js .fail

    ; the first configuration: its header for the length, then all of it
    mov rdi, rbx
    mov esi, USB_DT_CONFIG
    xor edx, edx
    xor ecx, ecx
    mov r8, rsp
    mov r9d, 9
    call usb_get_descriptor
    test eax, eax
    js .fail
    cmp eax, 9
    jb .bad
    movzx r14d, word [rsp + 2]
    cmp r14d, 9
    jb .bad
    cmp r14d, USB_CONFIG_MAX
    jbe .config_len
    mov r14d, USB_CONFIG_MAX
.config_len:
    mov edi, r14d
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov [rbx + usb_device.config_raw], rax
    mov rdi, rbx
    mov esi, USB_DT_CONFIG
    xor edx, edx
    xor ecx, ecx
    mov r8, rax
    mov r9d, r14d
    call usb_get_descriptor
    test eax, eax
    js .fail
    mov r14d, eax
    mov edi, usb_config_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .nomem
    mov [rbx + usb_device.config], rax
    mov rdi, [rbx + usb_device.config_raw]
    mov esi, r14d
    mov rdx, rax
    call usb_config_parse
    test eax, eax
    js .fail

    ; kept
    mov eax, [rel usb_device_total]
    lea rcx, [rel usb_devices]
    mov [rcx + rax * 8], rbx
    inc dword [rel usb_device_total]
    xor eax, eax
    mov rdx, rbx
    jmp .out
.bad:
    mov eax, -USB_EDESC
    jmp .fail
.nomem:
    mov eax, -USB_ENOMEM
.fail:
    inc dword [rel usb_enum_errors]
    xor edx, edx
.out:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_scan — enumerate every root port with something connected
; Input:  RDI = hc
; Output: EAX = devices enumerated
; -----------------------------------------------------------------------------
global usb_scan
usb_scan:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    xor r12d, r12d
    mov r13d, 1
.port:
    cmp r13d, [rbx + xhci_hc.max_ports]
    ja .out
    mov rdi, rbx
    mov esi, r13d
    call xhci_portsc
    test eax, PORT_CCS
    jz .next
    mov rdi, rbx
    mov esi, r13d
    call xhci_port_ack
    mov rdi, rbx
    mov esi, r13d
    call usb_enumerate
    test eax, eax
    jnz .next
    inc r12d
.next:
    inc r13d
    jmp .port
.out:
    mov eax, r12d
    pop r13
    pop r12
    pop rbx
    ret

; usb_device_count → EAX;  usb_device_get — EDI = index → RAX, or 0
global usb_device_count
usb_device_count:
    mov eax, [rel usb_device_total]
    ret

global usb_device_get
usb_device_get:
    xor eax, eax
    cmp edi, [rel usb_device_total]
    jae .out
    mov edi, edi
    lea rax, [rel usb_devices]
    mov rax, [rax + rdi * 8]
.out:
    ret

%endif ; LIB_USB_CORE_ENUM_ASM
