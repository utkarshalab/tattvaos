; =============================================================================
; Utkarsha OS — lib/ubt/tr/usb.asm — HCI over USB
; =============================================================================
; A USB Bluetooth controller (class E0, subclass 01, protocol 01) on its
; first interface: commands go as class control requests, events come on
; the interrupt endpoint, ACL data on the bulk pair. Interface 1 (SCO,
; isochronous) waits for classic audio.
;
;   ubt_init()              register the USB driver; empty the adapter list
;   ubt_usb_attach(dev)     the driver's attach: endpoints, transfers, then
;                           the HCI bring-up (MediaTek parts are marked
;                           as needing their firmware patch instead)
;   ubt_usb_acl_send(adapter, packet, length)   the transport's ACL out:
;                           one packet at a time
;   ubt_service()           from the fiber: endpoints that failed recovered
;   ubt_adapter_count(), ubt_adapter_get(i)
;
; Events and ACL packets come in pieces of an endpoint packet: they are put
; back together from their own length fields.
; =============================================================================

%ifndef LIB_UBT_TR_USB_ASM
%define LIB_UBT_TR_USB_ASM

%define UBT_VID_MEDIATEK    0x0E8D

section .data
align 8
ubt_usb_driver:
    dw USB_MATCH_IF_CLASS | USB_MATCH_IF_SUB | USB_MATCH_IF_PROTO, 0, 0
    db USB_CLASS_WIRELESS, 1, 1
    times 7 db 0
    dq ubt_usb_attach, ubt_drv_name

section .bss
alignb 8
global ubt_adapters
ubt_adapters:       resq UBT_MAX_ADAPTERS
global ubt_adapter_total
ubt_adapter_total:  resd 1
global ubt_next_index
ubt_next_index:     resd 1
global ubt_adapter_fn
ubt_adapter_fn:     resq 1          ; RDI = adapter, after its attach

section .rodata
ubt_drv_name:       db "bluetooth", 0
; where the host tests find their way around a ubt_adapter
global ubt_layout
ubt_layout:
    dd ubt_adapter.state, ubt_adapter.index, ubt_adapter.credits, ubt_adapter.failed_op
    dd ubt_adapter.failed_status, ubt_adapter.hci_version, ubt_adapter.hci_revision
    dd ubt_adapter.lmp_version, ubt_adapter.manufacturer, ubt_adapter.lmp_subversion
    dd ubt_adapter.bdaddr, ubt_adapter.le, ubt_adapter.features, ubt_adapter.commands
    dd ubt_adapter.acl_mtu, ubt_adapter.sco_mtu, ubt_adapter.acl_count, ubt_adapter.sco_count
    dd ubt_adapter.le_mtu, ubt_adapter.le_count, ubt_adapter.events, ubt_adapter.acl_rx
    dd ubt_adapter.acl_tx, ubt_adapter.errors, ubt_adapter.hw_errors, ubt_adapter.event_fn
    dd ubt_adapter.acl_fn, ubt_adapter.wait_buf, ubt_adapter.out_busy, ubt_adapter_size
UBT_LAYOUT_FIELDS equ 30

section .text

; -----------------------------------------------------------------------------
; ubt_init — the driver in the USB table, no adapters
; -----------------------------------------------------------------------------
global ubt_init
ubt_init:
    sub rsp, 8
    mov dword [rel ubt_adapter_total], 0
    mov dword [rel ubt_next_index], 0
    lea rdi, [rel ubt_usb_driver]
    call usb_driver_register
    add rsp, 8
    ret

global ubt_adapter_count
ubt_adapter_count:
    mov eax, [rel ubt_adapter_total]
    ret

global ubt_adapter_get
ubt_adapter_get:
    xor eax, eax
    cmp edi, [rel ubt_adapter_total]
    jae .out
    mov edi, edi
    lea rax, [rel ubt_adapters]
    mov rax, [rax + rdi * 8]
.out:
    ret

; ubt_hc — RBX = adapter → RDI = its controller, ESI = its slot
ubt_hc:
    mov rax, [rbx + ubt_adapter.dev]
    mov rdi, [rax + usb_device.hc]
    movzx esi, byte [rax + usb_device.slot]
    ret

; -----------------------------------------------------------------------------
; ubt_tr_send_cmd — RDI = adapter, RSI = command bytes, EDX = length
; Output: EAX = bytes sent, or negative
; -----------------------------------------------------------------------------
global ubt_tr_send_cmd
ubt_tr_send_cmd:
    push rbx
    mov rbx, rdi
    mov rcx, rsi
    mov r8d, edx
    ; class request to the device: bmRequestType 0x20, bRequest 0, wValue 0,
    ; wIndex the interface, wLength the command's length
    mov eax, [rbx + ubt_adapter.iface]
    shl rax, 32
    mov edx, r8d
    shl rdx, 48
    or rdx, rax
    or rdx, 0x20
    push rcx
    push r8
    call ubt_hc
    pop r8
    pop rcx
    call xhci_control
    pop rbx
    ret

; ubt_tr_poll — RDI = adapter: let its controller's events in
global ubt_tr_poll
ubt_tr_poll:
    mov rax, [rdi + ubt_adapter.dev]
    mov rdi, [rax + usb_device.hc]
    jmp xhci_poll

; -----------------------------------------------------------------------------
; ubt_usb_attach
; Input:  RDI = usb_device*
; Output: EAX = 1 when taken, 0 when not, or negative
; -----------------------------------------------------------------------------
global ubt_usb_attach
ubt_usb_attach:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    mov r12, rdi
    mov r13, [r12 + usb_device.config]
    xor eax, eax
    test r13, r13
    jz .out
    cmp dword [rel ubt_adapter_total], UBT_MAX_ADAPTERS
    jae .out
    ; the HCI interface
    xor r14d, r14d
.iface:
    cmp r14b, [r13 + usb_config.iface_count]
    jae .out
    mov eax, r14d
    imul eax, eax, usb_iface_size
    lea rbp, [r13 + usb_config.ifaces + rax]
    cmp byte [rbp + usb_iface.alt], 0
    jne .next_iface
    cmp byte [rbp + usb_iface.class], USB_CLASS_WIRELESS
    jne .next_iface
    cmp word [rbp + usb_iface.subclass], 0x0101     ; subclass 1, protocol 1
    je .found
.next_iface:
    inc r14d
    jmp .iface
.found:
    mov edi, ubt_adapter_size
    mov esi, 8
    call usb_alloc
    mov rbx, rax
    mov eax, -UBT_ENOMEM
    test rbx, rbx
    jz .out
    mov [rbx + ubt_adapter.dev], r12
    movzx eax, byte [rbp + usb_iface.number]
    mov [rbx + ubt_adapter.iface], eax
    ; its endpoints: interrupt IN (events), bulk IN and OUT (ACL)
    movzx ecx, byte [rbp + usb_iface.first_ep]
    movzx r15d, byte [rbp + usb_iface.ep_count]
.ep:
    test r15d, r15d
    jz .eps_found
    mov eax, ecx
    shl eax, 4
    lea r8, [r13 + usb_config.eps + rax]
    mov dl, [r8 + usb_ep.address]
    mov al, [r8 + usb_ep.attributes]
    and al, USB_EP_TYPE_MASK
    cmp al, USB_EP_INTERRUPT
    jne .bulk
    test dl, USB_EP_DIR_IN
    jz .ep_next
    mov [rbx + ubt_adapter.ev_ep], dl
    movzx eax, word [r8 + usb_ep.max_packet]
    and eax, 0x7FF
    cmp eax, 64
    jbe .ev_len
    mov eax, 64
.ev_len:
    mov [rbx + ubt_adapter.ev_xfer + usb_xfer.length], eax
    jmp .ep_next
.bulk:
    cmp al, USB_EP_BULK
    jne .ep_next
    test dl, USB_EP_DIR_IN
    jz .bulk_out
    mov [rbx + ubt_adapter.acl_in_ep], dl
    jmp .ep_next
.bulk_out:
    mov [rbx + ubt_adapter.acl_out_ep], dl
.ep_next:
    inc ecx
    dec r15d
    jmp .ep
.eps_found:
    cmp byte [rbx + ubt_adapter.ev_ep], 0
    je .drop
    cmp byte [rbx + ubt_adapter.acl_in_ep], 0
    je .drop
    cmp byte [rbx + ubt_adapter.acl_out_ep], 0
    je .drop
    ; its configuration, its endpoints
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
    js .drop
    mov al, [r13 + usb_config.value]
    mov [r12 + usb_device.config_value], al
    mov byte [r12 + usb_device.state], USB_DEV_CONFIGURED
.configured:
    mov rdi, [r12 + usb_device.hc]
    movzx esi, byte [r12 + usb_device.slot]
    mov rdx, r13
    mov ecx, r14d
    call xhci_configure_iface
    test eax, eax
    js .drop
    ; listed, the device's driver
    mov eax, [rel ubt_next_index]
    mov [rbx + ubt_adapter.index], eax
    inc dword [rel ubt_next_index]
    mov eax, [rel ubt_adapter_total]
    lea rcx, [rel ubt_adapters]
    mov [rcx + rax * 8], rbx
    inc dword [rel ubt_adapter_total]
    lea rax, [rel ubt_usb_detach]
    mov [r12 + usb_device.driver], rax
    ; the transport's functions
    lea rax, [rel ubt_tr_send_cmd]
    mov [rbx + ubt_adapter.tr_cmd], rax
    lea rax, [rel ubt_usb_acl_send]
    mov [rbx + ubt_adapter.tr_acl], rax
    lea rax, [rel ubt_tr_poll]
    mov [rbx + ubt_adapter.tr_poll], rax
    ; reading events and ACL data from now on
    call ubt_ev_submit
    call ubt_acl_submit
    ; a MediaTek controller runs nothing until its patch is loaded
    cmp word [r12 + usb_device.desc + usb_device_desc.idVendor], UBT_VID_MEDIATEK
    jne .bring_up
    mov dword [rbx + ubt_adapter.state], UBT_NEED_FIRMWARE
    jmp .said
.bring_up:
    mov rdi, rbx
    call ubt_hci_init
.said:
    mov rax, [rel ubt_adapter_fn]
    test rax, rax
    jz .taken
    mov rdi, rbx
    call rax
.taken:
    mov eax, 1
    jmp .out
.drop:
    mov rdi, rbx
    mov esi, ubt_adapter_size
    mov edx, 8
    call usb_free
    xor eax, eax
.out:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_ev_submit, ubt_acl_submit — RBX = adapter: the next read
ubt_ev_submit:
    sub rsp, 8
    lea rsi, [rbx + ubt_adapter.ev_xfer]
    mov rax, [rbx + ubt_adapter.dev]
    mov [rsi + usb_xfer.dev], rax
    mov al, [rbx + ubt_adapter.ev_ep]
    mov [rsi + usb_xfer.endpoint], al
    mov byte [rsi + usb_xfer.type], USB_EP_INTERRUPT
    lea rax, [rbx + ubt_adapter.ev_pkt]
    mov [rsi + usb_xfer.buffer], rax
    lea rax, [rel ubt_ev_done]
    mov [rsi + usb_xfer.done], rax
    mov [rsi + usb_xfer.context], rbx
    mov rax, [rbx + ubt_adapter.dev]
    mov rdi, [rax + usb_device.hc]
    call xhci_submit
    test eax, eax
    jz .out
    or byte [rbx + ubt_adapter.flags], 1
.out:
    add rsp, 8
    ret

ubt_acl_submit:
    sub rsp, 8
    lea rsi, [rbx + ubt_adapter.acl_xfer]
    mov rax, [rbx + ubt_adapter.dev]
    mov [rsi + usb_xfer.dev], rax
    mov al, [rbx + ubt_adapter.acl_in_ep]
    mov [rsi + usb_xfer.endpoint], al
    mov byte [rsi + usb_xfer.type], USB_EP_BULK
    ; into the space left after what has come of a packet so far
    mov eax, [rbx + ubt_adapter.acl_len]
    lea rcx, [rbx + ubt_adapter.acl_buf + rax]
    mov [rsi + usb_xfer.buffer], rcx
    mov ecx, UBT_ACL_MAX + 3
    sub ecx, eax
    mov [rsi + usb_xfer.length], ecx
    lea rax, [rel ubt_acl_done]
    mov [rsi + usb_xfer.done], rax
    mov [rsi + usb_xfer.context], rbx
    mov rax, [rbx + ubt_adapter.dev]
    mov rdi, [rax + usb_device.hc]
    call xhci_submit
    test eax, eax
    jz .out
    or byte [rbx + ubt_adapter.flags], 2
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_ev_done — an interrupt packet: add it to the event, hand on whole ones
; Input:  RDI = usb_xfer*
; -----------------------------------------------------------------------------
ubt_ev_done:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, [r12 + usb_xfer.context]
    cmp dword [r12 + usb_xfer.status], 0
    jne .failed
    ; appended
    mov ecx, [r12 + usb_xfer.actual]
    mov eax, [rbx + ubt_adapter.ev_len]
    lea edx, [eax + ecx]
    cmp edx, UBT_EVENT_MAX
    jbe .append
    inc dword [rbx + ubt_adapter.errors]    ; more than any event: start over
    mov dword [rbx + ubt_adapter.ev_len], 0
    jmp .again
.append:
    lea rdi, [rbx + ubt_adapter.ev_buf + rax]
    lea rsi, [rbx + ubt_adapter.ev_pkt]
    mov [rbx + ubt_adapter.ev_len], edx
    rep movsb
.whole:
    mov eax, [rbx + ubt_adapter.ev_len]
    cmp eax, 2
    jb .again
    movzx r13d, byte [rbx + ubt_adapter.ev_buf + 1]
    add r13d, 2                         ; code, length, parameters
    cmp eax, r13d
    jb .again
    mov rdi, rbx
    lea rsi, [rbx + ubt_adapter.ev_buf]
    mov edx, r13d
    call ubt_hci_event
    ; what is left belongs to the next event
    mov ecx, [rbx + ubt_adapter.ev_len]
    sub ecx, r13d
    mov [rbx + ubt_adapter.ev_len], ecx
    lea rdi, [rbx + ubt_adapter.ev_buf]
    lea rsi, [rdi + r13]
    rep movsb
    jmp .whole
.again:
    call ubt_ev_submit
    jmp .out
.failed:
    inc dword [rbx + ubt_adapter.errors]
    or byte [rbx + ubt_adapter.flags], 1
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_acl_done — bulk data: whole ACL packets to adapter.acl_fn
; Input:  RDI = usb_xfer*
; -----------------------------------------------------------------------------
ubt_acl_done:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov rbx, [r12 + usb_xfer.context]
    cmp dword [r12 + usb_xfer.status], 0
    jne .failed
    mov eax, [r12 + usb_xfer.actual]
    add [rbx + ubt_adapter.acl_len], eax
.whole:
    mov eax, [rbx + ubt_adapter.acl_len]
    cmp eax, 4
    jb .again
    movzx r13d, word [rbx + ubt_adapter.acl_buf + 2]
    add r13d, 4                         ; handle, length, data
    cmp r13d, UBT_ACL_MAX
    jbe .size_ok
    inc dword [rbx + ubt_adapter.errors]    ; longer than any packet: dropped
    mov dword [rbx + ubt_adapter.acl_len], 0
    jmp .again
.size_ok:
    cmp eax, r13d
    jb .again
    mov rdi, rbx
    lea rsi, [rbx + ubt_adapter.acl_buf]
    mov edx, r13d
    call ubt_acl_input                  ; links and L2CAP (counts it too)
.consumed:
    mov ecx, [rbx + ubt_adapter.acl_len]
    sub ecx, r13d
    mov [rbx + ubt_adapter.acl_len], ecx
    lea rdi, [rbx + ubt_adapter.acl_buf]
    lea rsi, [rdi + r13]
    rep movsb
    jmp .whole
.again:
    call ubt_acl_submit
    jmp .out
.failed:
    inc dword [rbx + ubt_adapter.errors]
    or byte [rbx + ubt_adapter.flags], 2
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_usb_acl_send — the transport's tr_acl: RDI = adapter, RSI = ACL
;                    packet (header and data), EDX = length
; Output: EAX = 0, -UBT_EBUSY (one at a time), -UBT_EIO
; -----------------------------------------------------------------------------
ubt_usb_acl_send:
    push rbx
    mov rbx, rdi
    mov eax, -UBT_EBUSY
    cmp dword [rbx + ubt_adapter.out_busy], 0
    jne .out
    mov eax, -UBT_EIO
    cmp edx, 4
    jb .out
    cmp edx, UBT_ACL_MAX
    ja .out
    lea rdi, [rbx + ubt_adapter.out_buf]
    mov ecx, edx
    mov r8d, edx
    rep movsb
    mov dword [rbx + ubt_adapter.out_busy], 1
    lea rsi, [rbx + ubt_adapter.out_xfer]
    mov rax, [rbx + ubt_adapter.dev]
    mov [rsi + usb_xfer.dev], rax
    mov al, [rbx + ubt_adapter.acl_out_ep]
    mov [rsi + usb_xfer.endpoint], al
    mov byte [rsi + usb_xfer.type], USB_EP_BULK
    mov [rsi + usb_xfer.length], r8d
    lea rax, [rbx + ubt_adapter.out_buf]
    mov [rsi + usb_xfer.buffer], rax
    lea rax, [rel ubt_out_done]
    mov [rsi + usb_xfer.done], rax
    mov [rsi + usb_xfer.context], rbx
    mov rax, [rbx + ubt_adapter.dev]
    mov rdi, [rax + usb_device.hc]
    call xhci_submit
    test eax, eax
    jz .sent
    mov dword [rbx + ubt_adapter.out_busy], 0
    mov eax, -UBT_EIO
    jmp .out
.sent:
    inc dword [rbx + ubt_adapter.acl_tx]
.out:
    pop rbx
    ret

ubt_out_done:
    sub rsp, 8
    mov rax, [rdi + usb_xfer.context]
    mov dword [rax + ubt_adapter.out_busy], 0
    cmp dword [rdi + usb_xfer.status], 0
    je .next
    inc dword [rax + ubt_adapter.errors]
.next:
    mov rdi, rax                        ; the next fragment, if one waits
    call ubt_conn_pump
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_service — every adapter's queued commands, L2CAP timeouts and waiting
;               ACL; USB endpoints that failed recovered and read again
; -----------------------------------------------------------------------------
global ubt_service
ubt_service:
    push rbx
    push r12
    push r13
    xor r12d, r12d
.adapter:
    cmp r12d, [rel ubt_adapter_total]
    jae .out
    lea rax, [rel ubt_adapters]
    mov rbx, [rax + r12 * 8]
    inc r12d
    ; commands queued while events were handled, L2CAP's timeouts
    mov rdi, rbx
    call ubt_hci_drain
    mov rdi, rbx
    call l2cap_tick
    mov rdi, rbx
    call ubt_sec_tick
    mov rdi, rbx
    call ubt_conn_pump
    test byte [rbx + ubt_adapter.flags], 1          ; the event endpoint
    jz .acl
    and byte [rbx + ubt_adapter.flags], ~1
    movzx r13d, byte [rbx + ubt_adapter.ev_ep]
    call .recover
    call ubt_ev_submit
.acl:
    test byte [rbx + ubt_adapter.flags], 2          ; the ACL one
    jz .adapter
    and byte [rbx + ubt_adapter.flags], ~2
    movzx r13d, byte [rbx + ubt_adapter.acl_in_ep]
    call .recover
    mov dword [rbx + ubt_adapter.acl_len], 0
    call ubt_acl_submit
    jmp .adapter
.out:
    pop r13
    pop r12
    pop rbx
    ret

; endpoint R13 of adapter RBX: Reset Endpoint, Set TR Dequeue
.recover:
    sub rsp, 8
    call ubt_hc
    mov edx, r13d
    and edx, USB_EP_NUM_MASK
    shl edx, 1
    test r13d, USB_EP_DIR_IN
    jz .dci
    inc edx
.dci:
    call xhci_ep_recover
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_usb_detach — usb_device.driver: the controller went
; Input:  RDI = usb_device*
; -----------------------------------------------------------------------------
ubt_usb_detach:
    push rbx
    xor ecx, ecx
    lea rdx, [rel ubt_adapters]
.find:
    cmp ecx, [rel ubt_adapter_total]
    jae .out
    mov rbx, [rdx + rcx * 8]
    cmp [rbx + ubt_adapter.dev], rdi
    je .unlist
    inc ecx
    jmp .find
.unlist:
    dec dword [rel ubt_adapter_total]
.shift:
    cmp ecx, [rel ubt_adapter_total]
    jae .free
    mov rax, [rdx + rcx * 8 + 8]
    mov [rdx + rcx * 8], rax
    inc ecx
    jmp .shift
.free:
    mov dword [rbx + ubt_adapter.state], UBT_GONE
    call ubt_conns_drop                 ; its links: channels closed, freed
    mov rax, [rel ubt_adapter_fn]
    test rax, rax
    jz .release
    mov rdi, rbx
    call rax                            ; told it went
.release:
    mov rdi, rbx
    mov esi, ubt_adapter_size
    mov edx, 8
    call usb_free
.out:
    pop rbx
    ret

%endif ; LIB_UBT_TR_USB_ASM
