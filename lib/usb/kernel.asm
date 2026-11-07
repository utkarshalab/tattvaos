; =============================================================================
; Utkarsha OS — lib/usb/kernel.asm — the USB stack in the kernel
; =============================================================================
;   usb_kernel_init     at start-up: every xHCI controller on PCI (class
;                       0C/03, interface 30) sized, mapped uncached and
;                       given memory decoding and bus mastering; the stack's
;                       memory from a page pool; each controller attached,
;                       its devices enumerated, keyboards and mice claimed.
;                       Never stops the boot.
;   usb_kernel_poll     from the input fiber: events, hubs' ports,
;                       keyboard LEDs and recovery, devices plugged in and
;                       pulled out (with everything behind them)
;
; Events are polled (no MSI-X yet), at the fiber's pace. Keyboards that
; arrive after start-up are held back until their code is typed on them
; (usb_new_keyboard_check, decision U3); the code goes to the console.
; =============================================================================

%ifndef LIB_USB_KERNEL_ASM
%define LIB_USB_KERNEL_ASM

%define USB_POOL_PAGES      512                 ; 2 MB for rings, contexts, records
%define USB_MMIO_SEARCH     0x0000600010000000  ; where controller registers go
%define USB_MMIO_MAX        (16 << 20)
%define USB_PCI_CLASS_XHCI  0x0C0330            ; class, subclass, interface
%define USB_PAGE_MMIO       ((1 << 1) | (1 << 3) | (1 << 4) | (1 << 63)) ; W, PWT, PCD, NX
%define USB_VMA_RW          ((1 << 0) | (1 << 1))

section .bss
alignb 8
global usb_pool_next
usb_pool_next:      resq 1
usb_pool_end:       resq 1
global usb_pool_free
usb_pool_free:      resq 7                  ; free blocks of 64 B ... 4 KB
global usb_k_bdf
usb_k_bdf:          resd XHCI_MAX_HC        ; each controller's PCI address
global usb_k_ports
usb_k_ports:        resb XHCI_MAX_HC * 32   ; root ports with a device on them
global usb_k_failed
usb_k_failed:       resd 1                  ; controllers that would not start
usb_k_text:         resb 16

section .rodata
msg_usb_xhci:       db "USB: xHCI ", 0
msg_usb_at:         db " registers at ", 0
msg_usb_ports:      db ", ports ", 0
msg_usb_ok:         db ", running", 0x0D, 0x0A, 0
msg_usb_nobar:      db ": unusable registers", 0x0D, 0x0A, 0
msg_usb_nomap:      db ": registers could not be mapped", 0x0D, 0x0A, 0
msg_usb_fail:       db ": did not start, step ", 0
msg_usb_nopool:     db "USB: no memory for the stack", 0x0D, 0x0A, 0
msg_usb_none:       db "USB: no xHCI controller", 0x0D, 0x0A, 0
msg_usb_port:       db "USB:   port ", 0
msg_usb_colon:      db ": ", 0
msg_usb_space:      db " ", 0
msg_usb_comma:      db ", ", 0
msg_usb_claimed:    db " (input)", 0
msg_usb_hub:        db " (hub)", 0
msg_usb_crlf:       db 0x0D, 0x0A, 0
msg_usb_auth_show:  db "USB: a new keyboard. To use it, type this code on it, then Enter: ", 0
msg_usb_auth_ok:    db "USB: keyboard accepted", 0x0D, 0x0A, 0
msg_usb_auth_wrong: db "USB: wrong code for the new keyboard; tries left: ", 0
msg_usb_auth_no:    db "USB: keyboard refused; unplug it to try again", 0x0D, 0x0A, 0
msg_usb_gone:       db "USB:   gone from port ", 0
msg_usb_speed:      db "?", 0, 0, 0, 0, 0, 0, 0
                    db "full", 0, 0, 0, 0
                    db "low", 0, 0, 0, 0, 0
                    db "high", 0, 0, 0, 0
                    db "5G", 0, 0, 0, 0, 0, 0
                    db "10G", 0, 0, 0, 0, 0
                    db "20G", 0, 0, 0, 0, 0

section .text

; -----------------------------------------------------------------------------
; usb_kpool_class — the block class of a request
; Input:  RDI = size, RSI = alignment
; Output: ECX = class (0 for 64 bytes ... 6 for 4096), or -1 for a larger
;         block (taken from the pool for good); RAX = the class's block size
; -----------------------------------------------------------------------------
usb_kpool_class:
    mov rax, rdi
    cmp rax, rsi
    jae .big
    mov rax, rsi
.big:
    cmp rax, 64
    jae .small
    mov eax, 64
.small:
    mov ecx, -1
    cmp rax, 4096
    ja .out
    dec rax
    bsr rcx, rax
    inc ecx                             ; log2 of the power of two at or above
    mov eax, 1
    shl eax, cl
    sub ecx, 6
.out:
    ret

; -----------------------------------------------------------------------------
; usb_kpool_alloc — usb_alloc_fn: RDI = size, RSI = alignment → RAX, or 0
; Blocks up to 4 KB come in power-of-two classes, aligned to their size,
; and go back on their class's free list; larger ones are never freed.
; -----------------------------------------------------------------------------
global usb_kpool_alloc
usb_kpool_alloc:
    call usb_kpool_class
    test ecx, ecx
    js .bump                            ; RDI, RSI as asked
    lea rdx, [rel usb_pool_free]
    mov r8, [rdx + rcx * 8]
    test r8, r8
    jz .fresh
    mov r9, [r8]                        ; the next free block
    mov [rdx + rcx * 8], r9
    mov rax, r8
    ret
.fresh:
    mov rdi, rax                        ; a new block of the class's size,
    mov rsi, rax                        ; aligned to it
.bump:
    mov rax, [rel usb_pool_next]
    test rax, rax
    jz .none
    lea rcx, [rsi - 1]
    add rax, rcx
    not rcx
    and rax, rcx
    lea rdx, [rax + rdi]
    cmp rdx, [rel usb_pool_end]
    ja .none
    mov [rel usb_pool_next], rdx
    ret
.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usb_kpool_free — usb_free_fn: RDI = block, RSI = size, RDX = alignment
; -----------------------------------------------------------------------------
global usb_kpool_free
usb_kpool_free:
    push rdi
    mov rdi, rsi
    mov rsi, rdx
    call usb_kpool_class
    pop rdi
    test ecx, ecx
    js .out                             ; a large block stays taken
    lea rdx, [rel usb_pool_free]
    mov rax, [rdx + rcx * 8]
    mov [rdi], rax
    mov [rdx + rcx * 8], rdi
.out:
    ret

; usb_kdelay — usb_delay_fn: RDI = microseconds
usb_kdelay:
    jmp udelay

; -----------------------------------------------------------------------------
; usb_k_hex — print EAX as ECX hex digits
; -----------------------------------------------------------------------------
usb_k_hex:
    push rsi
    lea rsi, [rel usb_k_text]
    mov byte [rsi + rcx], 0
.digit:
    dec ecx
    js .print
    mov edx, eax
    and edx, 15
    add edx, '0'
    cmp edx, '9'
    jbe .store
    add edx, 'a' - '9' - 1
.store:
    mov [rsi + rcx], dl
    shr eax, 4
    jmp .digit
.print:
    call uart_print_str
    pop rsi
    ret

; usb_k_bdf_print — EDI = BDF as bb:dd.f
usb_k_bdf_print:
    push rbx
    mov ebx, edi
    mov eax, ebx
    shr eax, 8
    mov ecx, 2
    call usb_k_hex
    lea rsi, [rel usb_k_text]
    mov word [rsi], ':'
    call uart_print_str
    mov eax, ebx
    shr eax, 3
    and eax, 31
    mov ecx, 2
    call usb_k_hex
    lea rsi, [rel usb_k_text]
    mov word [rsi], '.'
    call uart_print_str
    mov eax, ebx
    and eax, 7
    mov ecx, 1
    call usb_k_hex
    pop rbx
    ret

; usb_k_cfg — EDI = BDF, ESI = offset → EAX (a dword; -1 when it fails)
usb_k_cfg:
    sub rsp, 8
    mov edx, 4
    call kpci_cfg_read
    jnc .out
    mov eax, -1
.out:
    add rsp, 8
    ret

; usb_k_cfg_set — EDI = BDF, ESI = offset, ECX = dword
usb_k_cfg_set:
    sub rsp, 8
    mov edx, 4
    call kpci_cfg_write
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; usb_kernel_init
; -----------------------------------------------------------------------------
global usb_kernel_init
usb_kernel_init:
    push rbx
    push r12
    push r13
    mov dword [rel usb_k_failed], 0
    mov edi, USB_POOL_PAGES
    call phys_alloc_pages
    test rax, rax
    jz .nopool
    mov [rel usb_pool_next], rax
    add rax, USB_POOL_PAGES * 4096
    mov [rel usb_pool_end], rax
    xor eax, eax
    lea rdi, [rel usb_pool_free]
    mov ecx, 7
    rep stosq
    lea rax, [rel usb_kpool_alloc]
    mov [rel usb_alloc_fn], rax
    lea rax, [rel usb_kpool_free]
    mov [rel usb_free_fn], rax
    lea rax, [rel usb_kdelay]
    mov [rel usb_delay_fn], rax
    lea rax, [rel usb_kernel_device]
    mov [rel usb_found_fn], rax
    lea rax, [rel usb_kernel_auth]
    mov [rel usb_keyboard_auth_fn], rax
    mov dword [rel usb_hid_trusting], 1     ; what is plugged in at boot

    ; every function on every bus
    xor ebx, ebx                        ; BDF
.function:
    cmp ebx, 0x10000
    jae .scanned
    mov edi, ebx
    xor esi, esi
    call usb_k_cfg
    cmp ax, 0xFFFF
    je .absent
    mov edi, ebx
    mov esi, 0x08
    call usb_k_cfg
    shr eax, 8
    cmp eax, USB_PCI_CLASS_XHCI
    jne .not_xhci
    mov edi, ebx
    call usb_kernel_xhci
.not_xhci:
    test ebx, 7
    jnz .next                           ; function 1-7: the device has them
    mov edi, ebx
    mov esi, 0x0C
    call usb_k_cfg
    test eax, 0x00800000                ; header type bit 7: several functions
    jnz .next
    add ebx, 8                          ; one function: the next device
    jmp .function
.absent:
    test ebx, 7
    jnz .next
    add ebx, 8                          ; no function 0: no device
    jmp .function
.next:
    inc ebx
    jmp .function
.scanned:
    mov dword [rel usb_hid_trusting], 0     ; from now on, new keyboards ask
    cmp dword [rel xhci_hc_count], 0
    jne .out
    cmp dword [rel usb_k_failed], 0
    jne .out
    lea rsi, [rel msg_usb_none]
    call uart_print_str
    jmp .out
.nopool:
    lea rsi, [rel msg_usb_nopool]
    call uart_print_str
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_kernel_xhci — one controller: BAR, mapping, attach, devices
; Input:  EDI = BDF
; -----------------------------------------------------------------------------
usb_kernel_xhci:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] command, [rsp+8] BAR size
    mov ebx, edi
    lea rsi, [rel msg_usb_xhci]
    call uart_print_str
    mov edi, ebx
    call usb_k_bdf_print
    lea rsi, [rel msg_usb_space]
    call uart_print_str
    mov edi, ebx
    xor esi, esi
    call usb_k_cfg
    mov r12d, eax
    and eax, 0xFFFF
    mov ecx, 4
    call usb_k_hex
    lea rsi, [rel usb_k_text]
    mov word [rsi], ':'
    call uart_print_str
    mov eax, r12d
    shr eax, 16
    mov ecx, 4
    call usb_k_hex

    ; BAR 0: memory, 32 or 64 bits
    mov edi, ebx
    mov esi, 0x10
    call usb_k_cfg
    mov r12d, eax
    test eax, 1
    jnz .nobar                          ; I/O space: not an xHCI register block
    xor r13d, r13d                      ; the high half
    mov eax, r12d
    shr eax, 1
    and eax, 3
    cmp eax, 2
    jne .bar32
    mov edi, ebx
    mov esi, 0x14
    call usb_k_cfg
    mov r13d, eax
.bar32:
    ; its size: decoding off, all ones written, read back, put back
    mov edi, ebx
    mov esi, 0x04
    call usb_k_cfg
    mov [rsp], eax
    mov ecx, eax
    and ecx, ~0x07                      ; I/O, memory, bus master off
    mov edi, ebx
    mov esi, 0x04
    call usb_k_cfg_set
    mov edi, ebx
    mov esi, 0x10
    mov ecx, -1
    call usb_k_cfg_set
    mov edi, ebx
    mov esi, 0x10
    call usb_k_cfg
    mov r14d, eax
    mov edi, ebx
    mov esi, 0x10
    mov ecx, r12d
    call usb_k_cfg_set
    mov r15d, -1                        ; high half of the mask
    mov eax, r12d
    shr eax, 1
    and eax, 3
    cmp eax, 2
    jne .sized
    mov edi, ebx
    mov esi, 0x14
    mov ecx, -1
    call usb_k_cfg_set
    mov edi, ebx
    mov esi, 0x14
    call usb_k_cfg
    mov r15d, eax
    mov edi, ebx
    mov esi, 0x14
    mov ecx, r13d
    call usb_k_cfg_set
.sized:
    mov rax, r15
    shl rax, 32
    and r14d, 0xFFFFFFF0
    or rax, r14
    not rax
    inc rax                             ; the size
    mov [rsp + 8], rax
    ; the base
    mov rbp, r13
    shl rbp, 32
    mov eax, r12d
    and eax, 0xFFFFFFF0
    or rbp, rax
    jz .restore_nobar
    mov rax, [rsp + 8]
    cmp rax, 4096
    jb .restore_nobar
    test rax, 4095
    jnz .restore_nobar
    test rbp, 4095
    jnz .restore_nobar
    cmp rax, USB_MMIO_MAX
    jbe .size_ok
    mov qword [rsp + 8], USB_MMIO_MAX
.size_ok:
    ; never RAM
    mov rdi, rbp
    mov rsi, [rsp + 8]
    shr rsi, 12
    call phys_range_is_online_usable
    test eax, eax
    jnz .restore_nobar
    ; decoding and bus mastering on, the legacy interrupt off (polled)
    mov ecx, [rsp]
    and ecx, 0xFFFF
    or ecx, (1 << 1) | (1 << 2) | (1 << 10)
    mov edi, ebx
    mov esi, 0x04
    call usb_k_cfg_set
    lea rsi, [rel msg_usb_at]
    call uart_print_str
    mov rax, rbp
    shr rax, 32
    mov ecx, 8
    call usb_k_hex
    mov eax, ebp
    mov ecx, 8
    call usb_k_hex

    ; mapped uncached
    mov rdi, [rsp + 8]
    mov rsi, USB_MMIO_SEARCH
    call virt_find_free_range
    test rax, rax
    jz .nomap
    mov r14, rax
    mov rdi, r14
    mov rsi, [rsp + 8]
    mov edx, USB_VMA_RW
    call vma_create
    test rax, rax
    jz .nomap
    xor r15d, r15d
.page:
    mov rax, r15
    shl rax, 12
    cmp rax, [rsp + 8]
    jae .mapped
    lea rdi, [r14 + rax]
    lea rsi, [rbp + rax]
    mov rdx, USB_PAGE_MMIO
    call virt_map
    test rax, rax
    jz .nomap
    inc r15d
    jmp .page
.mapped:
    mov rdi, r14
    call xhci_attach
    test rax, rax
    jz .failed
    mov r12, rax
    mov eax, [rel xhci_hc_count]
    dec eax
    lea rcx, [rel usb_k_bdf]
    mov [rcx + rax * 4], ebx
    lea rsi, [rel msg_usb_ports]
    call uart_print_str
    mov eax, [r12 + xhci_hc.max_ports]
    call uart_print_dec
    lea rsi, [rel msg_usb_ok]
    call uart_print_str
    ; its devices
    ; (the root ports' devices only: what hubs bring is handled as they
    ; are, and joins the list behind them)
    mov r13d, [rel usb_device_total]
    mov rdi, r12
    call usb_scan
    mov r14d, [rel usb_device_total]
.device:
    cmp r13d, r14d
    jae .out
    mov edi, r13d
    call usb_device_get
    mov rdi, rax
    call usb_kernel_device
    inc r13d
    jmp .device

.restore_nobar:
    mov ecx, [rsp]
    and ecx, 0xFFFF
    mov edi, ebx
    mov esi, 0x04
    call usb_k_cfg_set
.nobar:
    lea rsi, [rel msg_usb_nobar]
    call uart_print_str
    inc dword [rel usb_k_failed]
    jmp .out
.nomap:
    lea rsi, [rel msg_usb_nomap]
    call uart_print_str
    inc dword [rel usb_k_failed]
    jmp .out
.failed:
    mov r12d, edx
    lea rsi, [rel msg_usb_fail]
    call uart_print_str
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_usb_crlf]
    call uart_print_str
    inc dword [rel usb_k_failed]
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
; usb_kernel_device — a device just enumerated: mark its port, say what it
;                     is, hand it to the drivers
; Input:  RDI = usb_device*
; -----------------------------------------------------------------------------
usb_kernel_device:
    push rbx
    push r12
    sub rsp, 72                         ; its product string
    mov rbx, rdi
    ; which controller: its port bitmap
    mov rax, [rbx + usb_device.hc]
    xor ecx, ecx
.which:
    cmp ecx, [rel xhci_hc_count]
    jae .said
    lea rdx, [rel xhci_hcs]
    cmp [rdx + rcx * 8], rax
    je .mark
    inc ecx
    jmp .which
.mark:
    shl ecx, 5
    lea rdx, [rel usb_k_ports]
    movzx eax, byte [rbx + usb_device.root_port]
    bts [rdx + rcx], eax
.said:
    lea rsi, [rel msg_usb_port]
    call uart_print_str
    movzx eax, byte [rbx + usb_device.root_port]
    call uart_print_dec
    ; behind hubs: each hub's port, as 1.2.3
    xor r12d, r12d
.tier:
    cmp r12b, [rbx + usb_device.depth]
    jae .path_done
    lea rsi, [rel usb_k_text]
    mov word [rsi], '.'
    call uart_print_str
    mov eax, [rbx + usb_device.route]
    lea ecx, [r12d * 4]
    shr eax, cl
    and eax, 15
    call uart_print_dec
    inc r12d
    jmp .tier
.path_done:
    lea rsi, [rel msg_usb_colon]
    call uart_print_str
    movzx eax, word [rbx + usb_device.desc + usb_device_desc.idVendor]
    mov ecx, 4
    call usb_k_hex
    lea rsi, [rel usb_k_text]
    mov word [rsi], ':'
    call uart_print_str
    movzx eax, word [rbx + usb_device.desc + usb_device_desc.idProduct]
    mov ecx, 4
    call usb_k_hex
    lea rsi, [rel msg_usb_space]
    call uart_print_str
    movzx eax, byte [rbx + usb_device.speed]
    cmp eax, 6
    jbe .speed
    xor eax, eax
.speed:
    lea rsi, [rel msg_usb_speed]
    lea rsi, [rsi + rax * 8]
    call uart_print_str
    movzx esi, byte [rbx + usb_device.desc + usb_device_desc.iProduct]
    test esi, esi
    jz .drivers
    mov rdi, rbx
    mov rdx, rsp
    mov ecx, 64
    call usb_get_string
    test eax, eax
    jle .drivers
    lea rsi, [rel msg_usb_comma]
    call uart_print_str
    mov rsi, rsp
    call uart_print_str
.drivers:
    mov rdi, rbx
    call usb_attach_drivers
    test eax, eax
    jle .end
    lea rsi, [rel msg_usb_claimed]
    test word [rbx + usb_device.flags], USB_DEVF_HUB
    jz .claimed
    lea rsi, [rel msg_usb_hub]
.claimed:
    call uart_print_str
.end:
    lea rsi, [rel msg_usb_crlf]
    call uart_print_str
    ; a hub: what is on its ports now, each on a line of its own
    test word [rbx + usb_device.flags], USB_DEVF_HUB
    jz .done
    call usb_hub_service
.done:
    add rsp, 72
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_kernel_poll — the input fiber's turn for USB
; -----------------------------------------------------------------------------
global usb_kernel_poll
usb_kernel_poll:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12d, r12d
.hc:
    cmp r12d, [rel xhci_hc_count]
    jae .drivers
    lea rax, [rel xhci_hcs]
    mov rbx, [rax + r12 * 8]
    mov rdi, rbx
    call xhci_poll
    ; ports that changed: a new device on a free port is enumerated
    mov r13d, 1
.port:
    cmp r13d, [rbx + xhci_hc.max_ports]
    ja .next_hc
    bt [rbx + xhci_hc.port_change], r13d
    jnc .next_port
    mov rdi, rbx
    mov esi, r13d
    call xhci_portsc
    mov r14d, eax
    mov rdi, rbx
    mov esi, r13d
    call xhci_port_ack
    mov r15d, r12d
    shl r15d, 5
    lea rax, [rel usb_k_ports]
    add r15, rax                        ; this controller's port bitmap
    test r14d, PORT_CCS
    jnz .connected
    btr [r15], r13d                     ; gone: the port is free again
    jnc .next_port
    mov rdi, rbx
    mov esi, r13d
    call usb_kernel_gone
    jmp .next_port
.connected:
    bt [r15], r13d
    jc .next_port                       ; already has its device
    mov rdi, rbx
    mov esi, r13d
    call usb_enumerate
    test eax, eax
    jnz .next_port
    mov rdi, rdx
    call usb_kernel_device
.next_port:
    inc r13d
    jmp .port
.next_hc:
    inc r12d
    jmp .hc
.drivers:
    call usb_hub_service
    call usb_hid_service
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_kernel_gone — root port ESI of controller RDI lost its device: it, and
;                   whatever was behind it, removed
; -----------------------------------------------------------------------------
usb_kernel_gone:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
.find:
    xor ecx, ecx
.next:
    cmp ecx, [rel usb_device_total]
    jae .out
    lea rax, [rel usb_devices]
    mov r13, [rax + rcx * 8]
    inc ecx
    cmp [r13 + usb_device.hc], rbx
    jne .next
    cmp qword [r13 + usb_device.parent], 0
    jne .next
    movzx eax, byte [r13 + usb_device.root_port]
    cmp eax, r12d
    jne .next
    lea rsi, [rel msg_usb_gone]
    call uart_print_str
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_usb_crlf]
    call uart_print_str
    mov rdi, r13
    call usb_device_remove
    jmp .find
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_kernel_auth — usb_keyboard_auth_fn: EDI = USB_AUTH_*, ESI = code or
;                   tries left
; -----------------------------------------------------------------------------
usb_kernel_auth:
    push rbx
    mov ebx, esi
    cmp edi, USB_AUTH_SHOW
    je .show
    cmp edi, USB_AUTH_ACCEPTED
    je .ok
    cmp edi, USB_AUTH_WRONG
    je .wrong
    lea rsi, [rel msg_usb_auth_no]
    call uart_print_str
    jmp .out
.show:
    lea rsi, [rel msg_usb_auth_show]
    jmp .number
.wrong:
    lea rsi, [rel msg_usb_auth_wrong]
.number:
    call uart_print_str
    mov eax, ebx
    call uart_print_dec
    lea rsi, [rel msg_usb_crlf]
    call uart_print_str
    jmp .out
.ok:
    lea rsi, [rel msg_usb_auth_ok]
    call uart_print_str
.out:
    pop rbx
    ret

%endif ; LIB_USB_KERNEL_ASM
