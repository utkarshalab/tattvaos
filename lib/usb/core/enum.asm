; =============================================================================
; Utkarsha OS — lib/usb/core/enum.asm — enumeration
; =============================================================================
;   usb_enumerate(hc, port)     reset the port, address the device, read its
;                               device and configuration descriptors
;                               EAX = 0 or a negative USB_E*; RDX = device
;   usb_enumerate_at(hc, hub, port, speed)  the same behind a hub (route
;                               string, depth, transaction translator)
;   usb_device_remove(dev)      it went away: what is behind it, its driver,
;                               its slot and memory
;   usb_attach_drivers(dev)     offer it to the hub and HID drivers
;   usb_get_descriptor(dev, type, index, lang, buffer, length)
;   usb_get_string(dev, index, out, size)       UTF-8, the first language
;   usb_scan(hc)                every connected root port; EAX = devices
;   usb_device_count, usb_device_get(i)
;
; Enumeration leaves a device addressed, not configured: the driver that
; takes it sets its configuration and its usb_device.driver, called when it
; goes. Only xHCI exists yet, so the controller is called directly.
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
global usb_found_fn
usb_found_fn:       resq 1          ; RDI = a device found behind a hub

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
; usb_enumerate — a device on a root port: reset the port, then as below
; Input:  RDI = hc, ESI = root port
; Output: EAX = 0 or a negative USB_E*; RDX = usb_device* (0 on failure)
; -----------------------------------------------------------------------------
global usb_enumerate
usb_enumerate:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    call xhci_port_reset
    test eax, eax
    js .fail
    mov rdi, rbx
    xor esi, esi
    mov edx, r12d
    mov ecx, eax
    call usb_enumerate_at
    jmp .out
.fail:
    inc dword [rel usb_enum_errors]
    xor edx, edx
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_enumerate_at — a device whose port is already reset and enabled
; Input:  RDI = hc, RSI = parent hub's usb_device* (0: a root port),
;         EDX = port (on the parent, or the root port), ECX = speed
; Output: EAX = 0 or a negative USB_E*; RDX = usb_device* (0 on failure)
; Behind a hub: the route string gets the port in the parent's tier, the
; root port is the parent's, and a low- or full-speed device takes its
; transaction translator from the nearest high-speed hub above it.
; -----------------------------------------------------------------------------
global usb_enumerate_at
usb_enumerate_at:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24
    mov r12, rdi
    mov rbp, rsi
    mov r13d, edx
    mov r14d, ecx
    mov eax, -USB_ENOMEM
    cmp dword [rel usb_device_total], USB_MAX_DEVICES
    jae .fail_early
    mov eax, -USB_EINVAL
    test rbp, rbp
    jz .room
    cmp byte [rbp + usb_device.depth], 5
    jae .fail_early                     ; hubs go five deep at most
.room:
    mov edi, usb_device_size
    mov esi, 8
    call usb_alloc
    mov rbx, rax
    mov eax, -USB_ENOMEM
    test rbx, rbx
    jz .fail_early
    mov [rbx + usb_device.hc], r12
    mov [rbx + usb_device.parent], rbp
    mov [rbx + usb_device.port], r13b
    mov [rbx + usb_device.root_port], r13b
    mov [rbx + usb_device.speed], r14b
    mov byte [rbx + usb_device.state], USB_DEV_ATTACHED
    test rbp, rbp
    jz .placed
    ; where it is behind its hub
    mov al, [rbp + usb_device.root_port]
    mov [rbx + usb_device.root_port], al
    movzx ecx, byte [rbp + usb_device.depth]
    lea eax, [rcx + 1]
    mov [rbx + usb_device.depth], al
    mov eax, r13d
    cmp eax, 15
    jbe .nibble
    mov eax, 15                         ; ports past 15 share the last value
.nibble:
    shl ecx, 2
    shl eax, cl
    or eax, [rbp + usb_device.route]
    mov [rbx + usb_device.route], eax
    ; its transaction translator
    mov eax, [rbp + usb_device.tt]      ; inherited ...
    cmp r14d, USB_SPEED_HIGH
    jae .tt_set                         ; (high speed and above need none)
    cmp byte [rbp + usb_device.speed], USB_SPEED_HIGH
    jne .tt_set
    movzx eax, byte [rbp + usb_device.slot]     ; ... or the hub's own
    mov ecx, r13d
    and ecx, 0xFF
    shl ecx, 8
    or eax, ecx
    cmp byte [rbp + usb_device.desc + usb_device_desc.bDeviceProtocol], 2
    jne .tt_set
    or eax, 1 << 16                     ; one TT per port
.tt_set:
    cmp r14d, USB_SPEED_HIGH
    jb .tt_store
    xor eax, eax
.tt_store:
    mov [rbx + usb_device.tt], eax
.placed:

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
    movzx edx, byte [rbx + usb_device.root_port]
    mov ecx, r14d
    mov r8d, [rbx + usb_device.route]
    mov r9d, [rbx + usb_device.tt]
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
    mov [rbx + usb_device.config_len], r14w
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
    ; give back what this attempt took: its slot, buffers, record
    mov [rsp + 16], eax
    mov rdi, rbx
    call usb_device_release
    mov eax, [rsp + 16]
.fail_early:
    inc dword [rel usb_enum_errors]
    xor edx, edx
.out:
    add rsp, 24
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_device_release — a device's slot, configuration and record given back
;                      (not in the device list, no driver: callers see to that)
; Input:  RDI = usb_device*
; -----------------------------------------------------------------------------
usb_device_release:
    push rbx
    mov rbx, rdi
    movzx esi, byte [rbx + usb_device.slot]
    test esi, esi
    jz .no_slot
    mov rdi, [rbx + usb_device.hc]
    call xhci_disable_slot
.no_slot:
    mov rdi, [rbx + usb_device.config_raw]
    movzx esi, word [rbx + usb_device.config_len]
    mov edx, 8
    call usb_free
    mov rdi, [rbx + usb_device.config]
    mov esi, usb_config_size
    mov edx, 8
    call usb_free
    mov rdi, rbx
    mov esi, usb_device_size
    mov edx, 8
    call usb_free
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_device_remove — a device went away: first everything behind it (a
;                     hub's devices), then its driver, its slot and memory
; Input:  RDI = usb_device*
; -----------------------------------------------------------------------------
global usb_device_remove
usb_device_remove:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov byte [rbx + usb_device.state], USB_DEV_GONE
.children:
    xor r12d, r12d
.child:
    cmp r12d, [rel usb_device_total]
    jae .own
    lea rax, [rel usb_devices]
    mov rdi, [rax + r12 * 8]
    inc r12d
    cmp [rdi + usb_device.parent], rbx
    jne .child
    call usb_device_remove              ; the list changed: look again
    jmp .children
.own:
    ; out of the list
    xor ecx, ecx
    lea rdx, [rel usb_devices]
.find:
    cmp ecx, [rel usb_device_total]
    jae .driver
    cmp [rdx + rcx * 8], rbx
    je .unlist
    inc ecx
    jmp .find
.unlist:
    dec dword [rel usb_device_total]
.shift:
    cmp ecx, [rel usb_device_total]
    jae .driver
    mov rax, [rdx + rcx * 8 + 8]
    mov [rdx + rcx * 8], rax
    inc ecx
    jmp .shift
.driver:
    ; the slot first: no completion reaches the driver after this
    movzx esi, byte [rbx + usb_device.slot]
    mov rdi, [rbx + usb_device.hc]
    call xhci_disable_slot
    mov byte [rbx + usb_device.slot], 0
    mov rax, [rbx + usb_device.driver]
    test rax, rax
    jz .release
    mov rdi, rbx
    call rax
.release:
    mov rdi, rbx
    call usb_device_release
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_attach_drivers — offer a new device to the class drivers
; Input:  RDI = usb_device*
; Output: EAX = 1 when one took it
; -----------------------------------------------------------------------------
global usb_attach_drivers
usb_attach_drivers:
    push rbx
    mov rbx, rdi
    call usb_hub_attach
    test eax, eax
    jg .taken
    mov rdi, rbx
    call usb_hid_attach
    test eax, eax
    jg .taken
    xor eax, eax
    pop rbx
    ret
.taken:
    mov eax, 1
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_device_found — a device enumerated after start-up (behind a hub):
;                    usb_found_fn when set (the kernel prints it first),
;                    else straight to the drivers
; Input:  RDI = usb_device*
; -----------------------------------------------------------------------------
global usb_device_found
usb_device_found:
    mov rax, [rel usb_found_fn]
    test rax, rax
    jz usb_attach_drivers
    jmp rax

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
