; =============================================================================
; Utkarsha OS — lib/usb/class/hid/hid.asm — USB keyboards and mice
; =============================================================================
; The USB transport for HID; what a report means is lib/input/hid's.
;
;   usb_hid_attach(dev)     claim an enumerated device's HID interfaces:
;                           boot keyboards in boot protocol; mice in report
;                           protocol when their report descriptor reads
;                           (more buttons, wide motion, horizontal wheels),
;                           else boot; any other interface for what its
;                           report descriptor holds (keyboard, pointer,
;                           media keys). Its configuration, no idle repeat,
;                           the endpoint, the input device, then reports.
;                           EAX = interfaces claimed
;   usb_hid_service()       from the input fiber: keyboard LEDs after a lock
;                           key, and recovery of endpoints that failed
;
; Reports arrive through xhci_poll: each is turned into events at once and
; the transfer put back. Nothing in the completion waits on the controller;
; what has to (LEDs, recovery) is left for usb_hid_service.
;
; Report protocol goes through lib/input/hid (report.asm, media.asm): a
; keyboard report becomes a boot report there, so LEDs and the new-keyboard
; check (decision U3) work the same for both. Touch and pens come later.
; =============================================================================

%ifndef LIB_USB_CLASS_HID_HID_ASM
%define LIB_USB_CLASS_HID_HID_ASM

%define USB_HID_MAX         8
%define USB_HID_MAX_ERRORS  8       ; failed reports before giving up
%define USB_HID_KEYBOARD    1
%define USB_HID_MOUSE       2
%define USB_HID_REPORT      3       ; report protocol: keyboard, pointer,
                                    ; media keys, as its descriptor says
%define USB_HID_RDESC_MAX   4096
%define USB_HID_REPORT_MAX  64

%define USB_HID_RECOVER     (1 << 0)
%define USB_HID_LEDS        (1 << 1)
%define USB_HID_DEAD        (1 << 2)
%define USB_HID_PENDING     (1 << 3)    ; a new keyboard not accepted yet
%define USB_HID_OWN_CODE    (1 << 4)    ; ... with a code of its own (else it
                                        ; waits for its device's keyboard)
%define USB_HID_HAS_MEDIA   4           ; usb_hid_report_setup's result bit
%define USB_HID_AUTH_TRIES  3

; what usb_keyboard_auth_fn is told (EDI)
%define USB_AUTH_SHOW       1       ; ESI = the code to type on it
%define USB_AUTH_ACCEPTED   2
%define USB_AUTH_WRONG      3       ; ESI = tries left
%define USB_AUTH_REFUSED    4

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
    .auth_code:     resd 1          ; six digits
    .auth_typed:    resd 1          ; what was typed so far
    .auth_digits:   resd 1
    .auth_fails:    resd 1
    .media:         resb hid_media_size
    .rmap:          resb hid_rmap_size
    .boot8:         resb 8          ; a report-protocol keyboard report as a
endstruc                            ; boot one

section .bss
alignb 8
global usb_hids
usb_hids:           resq USB_HID_MAX
global usb_hid_count
usb_hid_count:      resd 1
usb_hid_rdesc:      resb USB_HID_RDESC_MAX  ; a report descriptor being read
alignb 8
usb_hid_parsed:     resb hid_desc_size  ; ... and parsed: only for attach

section .data
align 8
global usb_new_keyboard_check
usb_new_keyboard_check: dd 1        ; decision U3: on unless an admin turns it off
global usb_hid_trusting
usb_hid_trusting:   dd 1            ; keyboards there at start-up need no code;
                                    ; the kernel clears this once it has started
global usb_keyboard_auth_fn
usb_keyboard_auth_fn: dq 0          ; EDI = USB_AUTH_*, ESI = code or tries,
                                    ; RDX = the usb_device*
global usb_auth_seed
usb_auth_seed:      dq 0x9E3779B97F4A7C15

section .rodata
usb_hid_name_kbd:   db "USB keyboard", 0
usb_hid_name_mouse: db "USB mouse", 0
usb_hid_name_media: db "USB media keys", 0

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
    sub rsp, 24                         ; [rsp] endpoint, [+8] pass, [+12] kind
    mov r12, rdi
    mov r13, [r12 + usb_device.config]
    mov eax, -USB_EINVAL
    test r13, r13
    jz .out
    xor r15d, r15d                      ; claimed
    mov dword [rsp + 8], 0              ; boot keyboards and mice first, so
.pass:                                  ; media keys know if one is held back
    xor r14d, r14d                      ; interface index
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
    movzx eax, byte [rbp + usb_iface.protocol]
    cmp byte [rbp + usb_iface.subclass], 1     ; boot interface
    jne .not_boot
    cmp eax, USB_HID_KEYBOARD
    je .boot
    cmp eax, USB_HID_MOUSE
    je .boot
.not_boot:
    ; the second pass: any other HID interface, for what its report
    ; descriptor holds
    cmp dword [rsp + 8], 1
    jne .next
    cmp word [rbp + usb_iface.hid_report_len], 0
    je .next
    mov eax, USB_HID_REPORT
    jmp .kind_ok
.boot:
    cmp dword [rsp + 8], 0
    jne .next
.kind_ok:
    mov [rsp + 12], eax
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
    mov eax, [rsp + 12]
    mov [rbx + usb_hid.kind], eax
    movzx eax, byte [rbp + usb_iface.number]
    mov [rbx + usb_hid.iface], eax
    cmp dword [rbx + usb_hid.kind], USB_HID_REPORT
    je .report
    cmp dword [rbx + usb_hid.kind], USB_HID_MOUSE
    jne .boot_protocol
    ; a mouse: report protocol when its descriptor reads and has a pointer
    cmp word [rbp + usb_iface.hid_report_len], 0
    je .boot_protocol
    movzx esi, word [rbp + usb_iface.hid_report_len]
    call usb_hid_report_setup
    test eax, eax
    jle .boot_protocol                  ; unreadable: boot protocol it is
    test eax, HID_RMAP_POINTER
    jz .boot_protocol
    mov dword [rbx + usb_hid.kind], USB_HID_REPORT
    mov edi, 0x21 | (HID_REQ_SET_PROTOCOL << 8) | (1 << 16)  ; report
    xor esi, esi
    xor ecx, ecx
    call usb_hid_ctl
    jmp .idle
.report:
    movzx esi, word [rbp + usb_iface.hid_report_len]
    call usb_hid_report_setup
    test eax, eax
    jg .idle
    mov rdi, rbx                        ; nothing for this driver in it
    mov esi, usb_hid_size
    mov edx, 8
    call usb_free
    jmp .next
.boot_protocol:
    ; boot protocol; no repeats while nothing changes (both may stall:
    ; a boot interface works without them)
    mov edi, 0x21 | (HID_REQ_SET_PROTOCOL << 8)
    xor esi, esi
    xor ecx, ecx
    call usb_hid_ctl
.idle:
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
    js .drop
    lea rax, [rel usb_hid_detach]
    mov [r12 + usb_device.driver], rax
    ; the input device, unless the new-keyboard check holds it back
    cmp dword [rbx + usb_hid.kind], USB_HID_REPORT
    jne .keyboard
    call usb_hid_device_pending         ; a keyboard of this device waits:
    test eax, eax                       ; so does all the rest of it
    jz .own
    or dword [rbx + usb_hid.flags], USB_HID_PENDING
    jmp .added
.own:
    test dword [rbx + usb_hid.rmap + hid_rmap.has], HID_RMAP_KEYBOARD
    jz .add_now
    jmp .check
.keyboard:
    cmp dword [rbx + usb_hid.kind], USB_HID_KEYBOARD
    jne .add_now
.check:
    cmp dword [rel usb_new_keyboard_check], 0
    je .add_now
    cmp dword [rel usb_hid_trusting], 0
    jne .add_now
    call usb_hid_auth_start
    jmp .added
.add_now:
    call usb_hid_input_add
    test eax, eax
    js .drop
.added:
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
    cmp dword [rsp + 8], 0
    jne .claimed
    mov dword [rsp + 8], 1
    jmp .pass
.claimed:
    mov eax, r15d
    jmp .out
.drop:
    mov r15d, eax
    mov rdi, rbx
    mov esi, usb_hid_size
    mov edx, 8
    call usb_free
    mov eax, r15d
    jmp .out
.nomem:
    mov eax, -USB_ENOMEM
.out:
    add rsp, 24
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; usb_hid_caps — EDX = the INPUT_CAP_* of RBX (usb_hid*), by kind and what
; its report descriptor holds
usb_hid_caps:
    mov edx, INPUT_CAP_KEYBOARD
    cmp dword [rbx + usb_hid.kind], USB_HID_KEYBOARD
    je .out
    mov edx, INPUT_CAP_POINTER
    cmp dword [rbx + usb_hid.kind], USB_HID_MOUSE
    je .out
    xor edx, edx
    test dword [rbx + usb_hid.rmap + hid_rmap.has], HID_RMAP_POINTER
    jz .keys
    mov edx, INPUT_CAP_POINTER
.keys:
    test dword [rbx + usb_hid.rmap + hid_rmap.has], HID_RMAP_KEYBOARD
    jnz .keyboard
    cmp dword [rbx + usb_hid.media + hid_media.nfields], 0
    je .out
.keyboard:
    or edx, INPUT_CAP_KEYBOARD
.out:
    ret

; -----------------------------------------------------------------------------
; usb_hid_post_device — an INPUT_DEVICE event: EDI = 0 added, 1 removed;
;                       RBX = usb_hid*
; -----------------------------------------------------------------------------
usb_hid_post_device:
    sub rsp, 8
    mov esi, edi
    xor edx, edx
    test esi, esi
    jnz .post
    call usb_hid_caps
.post:
    mov edi, INPUT_DEVICE
    mov ecx, [rbx + usb_hid.boot + hid_boot.dev]
    call input_post_safe
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; usb_hid_input_add — the lib/input device for RBX (usb_hid*), and its
;                     arrival posted
; Output: EAX = its ID, or a negative error
; -----------------------------------------------------------------------------
usb_hid_input_add:
    push r12
    mov r12, [rbx + usb_hid.dev]
    call usb_hid_caps
    lea rdi, [rel usb_hid_name_kbd]
    cmp dword [rbx + usb_hid.kind], USB_HID_KEYBOARD
    je .add
    lea rdi, [rel usb_hid_name_mouse]
    cmp dword [rbx + usb_hid.kind], USB_HID_MOUSE
    je .add
    test dword [rbx + usb_hid.rmap + hid_rmap.has], HID_RMAP_KEYBOARD
    lea rdi, [rel usb_hid_name_kbd]
    jnz .add
    test dword [rbx + usb_hid.rmap + hid_rmap.has], HID_RMAP_POINTER
    lea rdi, [rel usb_hid_name_mouse]
    jnz .add
    lea rdi, [rel usb_hid_name_media]
.add:
    mov esi, INPUT_BUS_USB
    movzx ecx, word [r12 + usb_device.desc + usb_device_desc.idVendor]
    shl ecx, 16
    mov cx, [r12 + usb_device.desc + usb_device_desc.idProduct]
    call input_dev_add
    test eax, eax
    js .out
    mov [rbx + usb_hid.boot + hid_boot.dev], eax
    mov [rbx + usb_hid.media + hid_media.dev], eax
    mov [rbx + usb_hid.rmap + hid_rmap.dev], eax
    xor edi, edi
    call usb_hid_post_device
    mov eax, [rbx + usb_hid.boot + hid_boot.dev]
.out:
    pop r12
    ret

; usb_hid_auth_say — usb_keyboard_auth_fn(EDI, ESI, the device), if set
usb_hid_auth_say:
    mov rax, [rel usb_keyboard_auth_fn]
    test rax, rax
    jz .out
    mov rdx, [rbx + usb_hid.dev]
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; usb_hid_auth_start — hold a new keyboard back until its code is typed on it
; Input:  RBX = usb_hid*
; -----------------------------------------------------------------------------
usb_hid_auth_start:
    sub rsp, 8
    or dword [rbx + usb_hid.flags], USB_HID_PENDING | USB_HID_OWN_CODE
    ; six digits: the time stamp counter stirred into a running seed
    rdtsc
    shl rdx, 32
    or rax, rdx
    xor rax, [rel usb_auth_seed]
    xor rax, rbx
    mov rcx, 0x2545F4914F6CDD1D
    imul rax, rcx
    mov [rel usb_auth_seed], rax
    shr rax, 16
    xor edx, edx
    mov ecx, 900000
    div rcx
    add edx, 100000
    mov [rbx + usb_hid.auth_code], edx
    mov dword [rbx + usb_hid.auth_typed], 0
    mov dword [rbx + usb_hid.auth_digits], 0
    mov dword [rbx + usb_hid.auth_fails], 0
    mov edi, USB_AUTH_SHOW
    mov esi, edx
    call usb_hid_auth_say
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; usb_hid_auth_report — a report from a keyboard still held back: only its
;                       digits, Backspace and Enter count, and none of it
;                       reaches lib/input
; Input:  RBX = usb_hid*, EDX = report length
; -----------------------------------------------------------------------------
usb_hid_auth_report:
    push r12
    push r13
    push r14
    cmp edx, 3
    jb .out
    mov r14d, edx
    cmp r14d, 8
    jbe .keys
    mov r14d, 8
.keys:
    ; the right code was typed: it is let in once every key is up, so no
    ; key it was holding reaches lib/input half-pressed
    cmp dword [rbx + usb_hid.auth_digits], -1
    jne .typing
    cmp byte [rbx + usb_hid.buf], 0
    jne .keep
    mov ecx, 2
.up:
    cmp ecx, r14d
    jae .let_in
    cmp byte [rbx + usb_hid.buf + rcx], 0
    jne .keep
    inc ecx
    jmp .up
.let_in:
    and dword [rbx + usb_hid.flags], ~USB_HID_PENDING
    mov dword [rbx + usb_hid.auth_digits], 0
    mov edi, USB_AUTH_ACCEPTED
    xor esi, esi
    call usb_hid_auth_say
    call usb_hid_input_add
    call usb_hid_release_media
    jmp .keep
.typing:
    mov r12d, 2
.key:
    cmp r12d, r14d
    jae .keep
    movzx r13d, byte [rbx + usb_hid.buf + r12]
    inc r12d
    cmp r13d, 4
    jb .key
    ; newly pressed: not in the last report
    xor ecx, ecx
.held:
    cmp ecx, 6
    jae .pressed
    cmp [rbx + usb_hid.boot + hid_boot.prev + 2 + rcx], r13b
    je .key
    inc ecx
    jmp .held
.pressed:
    cmp r13d, 0x2A                      ; Backspace: start again
    je .clear
    cmp r13d, 0x28                      ; Enter, and keypad Enter
    je .enter
    cmp r13d, 0x58
    je .enter
    ; a digit, top row or keypad: usage order is 1-9, then 0
    lea eax, [r13d - 0x1E]
    cmp eax, 10
    jb .digit
    lea eax, [r13d - 0x59]
    cmp eax, 10
    jae .key
.digit:
    inc eax
    cmp eax, 10
    jb .add_digit
    xor eax, eax
.add_digit:
    cmp dword [rbx + usb_hid.auth_digits], 6
    jae .too_many
    mov ecx, [rbx + usb_hid.auth_typed]
    imul ecx, ecx, 10
    add ecx, eax
    mov [rbx + usb_hid.auth_typed], ecx
.too_many:
    inc dword [rbx + usb_hid.auth_digits]   ; more than six fails at Enter
    jmp .key
.clear:
    mov dword [rbx + usb_hid.auth_typed], 0
    mov dword [rbx + usb_hid.auth_digits], 0
    jmp .key
.enter:
    cmp dword [rbx + usb_hid.auth_digits], 6
    jne .wrong
    mov eax, [rbx + usb_hid.auth_typed]
    cmp eax, [rbx + usb_hid.auth_code]
    jne .wrong
    ; right: let in when its keys are all up (above)
    mov dword [rbx + usb_hid.auth_digits], -1
    jmp .keep
.wrong:
    mov dword [rbx + usb_hid.auth_typed], 0
    mov dword [rbx + usb_hid.auth_digits], 0
    inc dword [rbx + usb_hid.auth_fails]
    mov esi, USB_HID_AUTH_TRIES
    sub esi, [rbx + usb_hid.auth_fails]
    jle .refused
    mov edi, USB_AUTH_WRONG
    call usb_hid_auth_say
    jmp .key
.refused:
    or dword [rbx + usb_hid.flags], USB_HID_DEAD
    mov edi, USB_AUTH_REFUSED
    xor esi, esi
    call usb_hid_auth_say
.keep:
    ; the last report, for telling new presses from held keys
    mov qword [rbx + usb_hid.boot + hid_boot.prev], 0
    xor ecx, ecx
.copy:
    cmp ecx, r14d
    jae .out
    mov al, [rbx + usb_hid.buf + rcx]
    mov [rbx + usb_hid.boot + hid_boot.prev + rcx], al
    inc ecx
    jmp .copy
.out:
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; usb_hid_report_setup — read and parse the report descriptor of RBX's
;                        interface; keep its keyboard, pointer and media
;                        fields
; Input:  RBX = usb_hid*, ESI = the descriptor's length (from the HID one)
; Output: EAX = HID_RMAP_KEYBOARD | HID_RMAP_POINTER | USB_HID_HAS_MEDIA
;         for what it holds (0: nothing for this driver), or negative
; -----------------------------------------------------------------------------
usb_hid_report_setup:
    push r12
    mov r12d, esi
    cmp r12d, USB_HID_RDESC_MAX
    jbe .len
    mov r12d, USB_HID_RDESC_MAX
.len:
    mov edi, 0x81 | (USB_REQ_GET_DESCRIPTOR << 8) | (USB_DT_HID_REPORT << 24)
    mov esi, r12d
    lea rcx, [rel usb_hid_rdesc]
    call usb_hid_ctl
    test eax, eax
    jle .out
    lea rdi, [rel usb_hid_rdesc]
    mov esi, eax
    lea rdx, [rel usb_hid_parsed]
    call hid_parse
    test eax, eax
    jnz .bad
    lea rdi, [rel usb_hid_parsed]
    lea rsi, [rbx + usb_hid.rmap]
    call hid_rmap_prepare
    mov r12d, eax
    lea rdi, [rel usb_hid_parsed]
    lea rsi, [rbx + usb_hid.media]
    call hid_media_prepare
    test eax, eax
    jz .parts
    or r12d, USB_HID_HAS_MEDIA
.parts:
    mov eax, r12d
    jmp .out
.bad:
    xor eax, eax                        ; a descriptor that does not parse
.out:
    pop r12
    ret

; usb_hid_device_pending — EAX = 1 when a keyboard of RBX's device is held
; back by the new-keyboard check
usb_hid_device_pending:
    mov rdx, [rbx + usb_hid.dev]
    xor ecx, ecx
.next:
    cmp ecx, [rel usb_hid_count]
    jae .no
    lea rax, [rel usb_hids]
    mov rax, [rax + rcx * 8]
    inc ecx
    cmp [rax + usb_hid.dev], rdx
    jne .next
    mov r8d, [rax + usb_hid.flags]
    and r8d, USB_HID_PENDING | USB_HID_OWN_CODE
    cmp r8d, USB_HID_PENDING | USB_HID_OWN_CODE
    jne .next
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; usb_hid_release_media — RBX's keyboard was accepted: the media keys of
; the same device come in with it
usb_hid_release_media:
    push rbx
    push r12
    push r13
    mov r13, [rbx + usb_hid.dev]
    xor r12d, r12d
.next:
    cmp r12d, [rel usb_hid_count]
    jae .out
    lea rax, [rel usb_hids]
    mov rbx, [rax + r12 * 8]
    inc r12d
    cmp [rbx + usb_hid.dev], r13
    jne .next
    test dword [rbx + usb_hid.flags], USB_HID_OWN_CODE
    jnz .next                           ; a keyboard with its own code
    btr dword [rbx + usb_hid.flags], 3  ; USB_HID_PENDING
    jnc .next
    call usb_hid_input_add
    jmp .next
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_hid_detach — usb_device.driver: the device went; its keyboards and
;                  mice leave lib/input and their records go
; Input:  RDI = usb_device*
; -----------------------------------------------------------------------------
usb_hid_detach:
    push rbx
    push r12
    push r13
    mov r13, rdi
    xor r12d, r12d
.hid:
    cmp r12d, [rel usb_hid_count]
    jae .out
    lea rax, [rel usb_hids]
    mov rbx, [rax + r12 * 8]
    cmp [rbx + usb_hid.dev], r13
    je .remove
    inc r12d
    jmp .hid
.remove:
    cmp dword [rbx + usb_hid.boot + hid_boot.dev], 0
    je .unlist                          ; held back: never in lib/input
    mov edi, 1
    call usb_hid_post_device
    mov edi, [rbx + usb_hid.boot + hid_boot.dev]
    call input_dev_remove
.unlist:
    dec dword [rel usb_hid_count]
    mov ecx, r12d
    lea rdx, [rel usb_hids]
.shift:
    cmp ecx, [rel usb_hid_count]
    jae .free
    mov rax, [rdx + rcx * 8 + 8]
    mov [rdx + rcx * 8], rax
    inc ecx
    jmp .shift
.free:
    mov rdi, rbx
    mov esi, usb_hid_size
    mov edx, 8
    call usb_free
    jmp .hid                            ; the same index holds the next one
.out:
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
    test dword [rbx + usb_hid.flags], USB_HID_PENDING
    jz .accepted
    test dword [rbx + usb_hid.flags], USB_HID_OWN_CODE
    jz .again                           ; held back with its keyboard
    cmp dword [rbx + usb_hid.kind], USB_HID_REPORT
    jne .auth
    ; a report-protocol keyboard types its code as boot reports
    lea rdi, [rbx + usb_hid.rmap]
    lea rsi, [rbx + usb_hid.buf]
    lea rcx, [rbx + usb_hid.boot8]
    call hid_rmap_keyboard
    test eax, eax
    jz .again                           ; not its keyboard report
    mov rax, [rbx + usb_hid.boot8]
    mov [rbx + usb_hid.buf], rax
    mov edx, 8
.auth:
    call usb_hid_auth_report
    test dword [rbx + usb_hid.flags], USB_HID_DEAD
    jnz .out                            ; refused: no more reads
    jmp .again
.accepted:
    cmp dword [rbx + usb_hid.kind], USB_HID_REPORT
    jne .boot_report
    ; report protocol: its keyboard (as a boot report), pointer, media keys
    test dword [rbx + usb_hid.rmap + hid_rmap.has], HID_RMAP_KEYBOARD
    jz .pointer
    lea rdi, [rbx + usb_hid.rmap]
    lea rsi, [rbx + usb_hid.buf]
    mov edx, [r12 + usb_xfer.actual]
    lea rcx, [rbx + usb_hid.boot8]
    call hid_rmap_keyboard
    test eax, eax
    jz .pointer
    lea rdi, [rbx + usb_hid.boot]
    lea rsi, [rbx + usb_hid.boot8]
    mov edx, 8
    jmp .keys
.pointer:
    test dword [rbx + usb_hid.rmap + hid_rmap.has], HID_RMAP_POINTER
    jz .media_keys
    lea rdi, [rbx + usb_hid.rmap]
    lea rsi, [rbx + usb_hid.buf]
    mov edx, [r12 + usb_xfer.actual]
    call hid_rmap_pointer
    test eax, eax
    jnz .again
.media_keys:
    lea rdi, [rbx + usb_hid.media]
    lea rsi, [rbx + usb_hid.buf]
    mov edx, [r12 + usb_xfer.actual]
    call hid_media_report
    jmp .again
.boot_report:
    cmp dword [rbx + usb_hid.kind], USB_HID_KEYBOARD
    jne .mouse
.keys:
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
    cmp dword [rbx + usb_hid.kind], USB_HID_REPORT
    jne .send_leds
    cmp dword [rbx + usb_hid.rmap + hid_rmap.has_led], 0
    je .recover                         ; it has no LEDs
    mov ecx, [rbx + usb_hid.rmap + hid_rmap.led_id]
    test ecx, ecx
    jz .send_leds
    mov [rbx + usb_hid.led], cl         ; the report ID first, then the bits
    mov [rbx + usb_hid.led + 1], al
    shl ecx, 16
    or edi, ecx
    mov esi, 2
.send_leds:
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
