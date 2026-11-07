; =============================================================================
; Utkarsha OS — lib/usb/core/desc.asm — descriptor parsers
; =============================================================================
; Every byte here comes from a device, and a device can be hostile: each
; length is checked against what was read before anything is touched, and
; nothing is written outside the caller's record.
;
;   usb_device_check(buf, len)              the 18-byte device descriptor
;   usb_config_parse(buf, len, usb_config*) a configuration and everything
;                                           in it
;   usb_desc_next(buf, len, &off)           walk descriptors (class drivers,
;                                           over an interface's body)
;   usb_string_utf8(desc, len, out, size)   a string descriptor as UTF-8
;   usb_bos_parse(buf, len, usb_bos*)       the BOS and its capabilities
;
; Results: EAX = 0 or a negated USB_E* (usb_string_utf8: bytes written).
; =============================================================================

%ifndef LIB_USB_CORE_DESC_ASM
%define LIB_USB_CORE_DESC_ASM

%include "lib/usb/usb.inc"

section .rodata
; the record sizes, for the host tests to hold their copies of the layouts to
global usb_layout
usb_layout: dd usb_iface_size, usb_ep_size, usb_iad_size, usb_config_size, usb_bos_size
            dd usb_device_size, usb_xfer_size

section .text

; -----------------------------------------------------------------------------
; usb_device_check — whether a device descriptor can be used
; Input:  RDI = bytes, ESI = bytes read
; Output: EAX = 0, or -USB_EDESC
; -----------------------------------------------------------------------------
global usb_device_check
usb_device_check:
    mov eax, -USB_EDESC
    cmp esi, usb_device_desc_size
    jb .out
    cmp byte [rdi + usb_device_desc.bLength], usb_device_desc_size
    jb .out
    cmp byte [rdi + usb_device_desc.bDescriptorType], USB_DT_DEVICE
    jne .out
    cmp byte [rdi + usb_device_desc.bNumConfigurations], 0
    je .out
    movzx ecx, byte [rdi + usb_device_desc.bMaxPacketSize0]
    cmp word [rdi + usb_device_desc.bcdUSB], 0x0300
    jb .usb2
    cmp ecx, 9                          ; SuperSpeed: 2^9 = 512
    jne .out
    xor eax, eax
    ret
.usb2:
    cmp ecx, 8
    je .ok
    cmp ecx, 16
    je .ok
    cmp ecx, 32
    je .ok
    cmp ecx, 64
    jne .out
.ok:
    xor eax, eax
.out:
    ret

; -----------------------------------------------------------------------------
; usb_desc_next — the descriptor at *off, and *off moved past it
; Input:  RDI = bytes, ESI = length, RDX = dword* offset
; Output: RAX = the descriptor, or 0 at the end or when it does not fit
; -----------------------------------------------------------------------------
global usb_desc_next
usb_desc_next:
    mov ecx, [rdx]
    mov eax, esi
    sub eax, ecx
    jbe .none                           ; at or past the end
    cmp eax, 2
    jb .none
    movzx r8d, byte [rdi + rcx]
    cmp r8d, 2
    jb .none
    cmp r8d, eax
    ja .none
    lea rax, [rdi + rcx]
    add ecx, r8d
    mov [rdx], ecx
    ret
.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; usb_config_parse — a configuration descriptor and what follows it
; Input:  RDI = bytes, ESI = bytes read, RDX = usb_config* to fill
; Output: EAX = 0; -USB_EDESC (malformed), -USB_ETRUNC (read the
;         wTotalLength bytes and try again), -USB_ETOOMANY
; -----------------------------------------------------------------------------
; RBX bytes, R12D wTotalLength, R13 the record, R14D offset, R15D the
; current interface (-1 before one); [rsp] the last endpoint (-1 none),
; [rsp + 4] interface numbers seen (below 32), [rsp + 8] one at 32 or more
global usb_config_parse
usb_config_parse:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r13, rdx
    mov r12d, esi
    mov rdi, r13
    mov ecx, usb_config_size
    xor eax, eax
    rep stosb
    mov esi, r12d
    cmp esi, 9
    jb .bad
    cmp byte [rbx + 1], USB_DT_CONFIG
    jne .bad
    movzx eax, byte [rbx]
    cmp eax, 9
    jb .bad
    movzx r12d, word [rbx + 2]
    cmp r12d, eax
    jb .bad
    cmp r12d, esi
    ja .trunc
    mov [r13 + usb_config.total], r12w
    mov cl, [rbx + 4]
    mov [r13 + usb_config.num_ifaces], cl
    mov cl, [rbx + 5]
    mov [r13 + usb_config.value], cl
    mov cl, [rbx + 6]
    mov [r13 + usb_config.string], cl
    mov cl, [rbx + 7]
    mov [r13 + usb_config.attributes], cl
    mov cl, [rbx + 8]
    mov [r13 + usb_config.max_power], cl
    mov r14d, eax
    mov r15d, -1
    mov dword [rsp], -1
    mov qword [rsp + 4], 0
    mov dword [rsp + 12], 0

.walk:
    cmp r14d, r12d
    jae .done
    mov eax, r12d
    sub eax, r14d
    cmp eax, 2
    jb .bad
    movzx ecx, byte [rbx + r14]
    cmp ecx, 2
    jb .bad
    cmp ecx, eax
    ja .bad
    lea rsi, [rbx + r14]
    movzx edx, byte [rsi + 1]
    cmp edx, USB_DT_INTERFACE
    je .iface
    cmp edx, USB_DT_ENDPOINT
    je .ep
    cmp edx, USB_DT_SS_EP_COMP
    je .comp
    cmp edx, USB_DT_SSP_ISOC_COMP
    je .sspcomp
    cmp edx, USB_DT_IAD
    je .iad
    cmp edx, USB_DT_HID
    je .hid
    inc byte [r13 + usb_config.other]
.next:
    movzx ecx, byte [rbx + r14]
    add r14d, ecx
    jmp .walk

.iface:
    cmp ecx, 9
    jb .bad
    call .close_body
    movzx eax, byte [r13 + usb_config.iface_count]
    cmp eax, USB_MAX_IFACES
    jae .toomany
    mov r15d, eax
    inc byte [r13 + usb_config.iface_count]
    imul eax, eax, usb_iface_size
    lea rdi, [r13 + usb_config.ifaces + rax]
    mov al, [rsi + 2]
    mov [rdi + usb_iface.number], al
    movzx edx, al
    cmp edx, 32
    jae .iface_high
    bts dword [rsp + 4], edx
    jmp .iface_fields
.iface_high:
    mov dword [rsp + 8], 1
.iface_fields:
    mov al, [rsi + 3]
    mov [rdi + usb_iface.alt], al
    mov al, [rsi + 4]
    mov [rdi + usb_iface.num_ep], al
    mov al, [rsi + 5]
    mov [rdi + usb_iface.class], al
    mov al, [rsi + 6]
    mov [rdi + usb_iface.subclass], al
    mov al, [rsi + 7]
    mov [rdi + usb_iface.protocol], al
    mov al, [rsi + 8]
    mov [rdi + usb_iface.string], al
    mov al, [r13 + usb_config.ep_count]
    mov [rdi + usb_iface.first_ep], al
    mov byte [rdi + usb_iface.func], USB_NO_FUNC
    lea eax, [r14d + ecx]
    mov [rdi + usb_iface.body_off], ax
    mov dword [rsp], -1
    jmp .next

.ep:
    cmp ecx, 7
    jb .bad
    test r15d, r15d
    jns .ep_owned
    or byte [r13 + usb_config.warn], USB_WARN_EP_ORPHAN
    jmp .next
.ep_owned:
    movzx eax, byte [r13 + usb_config.ep_count]
    cmp eax, USB_MAX_EPS
    jae .toomany
    mov [rsp], eax
    inc byte [r13 + usb_config.ep_count]
    shl eax, 4                          ; usb_ep_size
    lea rdi, [r13 + usb_config.eps + rax]
    mov al, [rsi + 2]
    mov [rdi + usb_ep.address], al
    mov al, [rsi + 3]
    mov [rdi + usb_ep.attributes], al
    mov ax, [rsi + 4]
    mov [rdi + usb_ep.max_packet], ax
    mov al, [rsi + 6]
    mov [rdi + usb_ep.interval], al
    mov [rdi + usb_ep.iface], r15b
    cmp ecx, 9
    jb .ep_count
    mov al, [rsi + 7]
    mov [rdi + usb_ep.refresh], al
    mov al, [rsi + 8]
    mov [rdi + usb_ep.synch], al
.ep_count:
    mov eax, r15d
    imul eax, eax, usb_iface_size
    inc byte [r13 + usb_config.ifaces + rax + usb_iface.ep_count]
    jmp .next

.comp:
    cmp ecx, 6
    jb .bad
    mov eax, [rsp]
    test eax, eax
    js .next                            ; no endpoint to go with
    shl eax, 4
    lea rdi, [r13 + usb_config.eps + rax]
    mov al, [rsi + 2]
    mov [rdi + usb_ep.ss_burst], al
    mov al, [rsi + 3]
    mov [rdi + usb_ep.ss_attr], al
    movzx eax, word [rsi + 4]
    mov [rdi + usb_ep.ss_bpi], eax
    jmp .next

.sspcomp:
    cmp ecx, 8
    jb .bad
    mov eax, [rsp]
    test eax, eax
    js .next
    shl eax, 4
    mov edx, [rsi + 4]
    mov [r13 + usb_config.eps + rax + usb_ep.ss_bpi], edx
    jmp .next

.iad:
    cmp ecx, 8
    jb .bad
    movzx eax, byte [r13 + usb_config.iad_count]
    cmp eax, USB_MAX_IADS
    jb .iad_keep
    or byte [r13 + usb_config.warn], USB_WARN_IADS
    jmp .next
.iad_keep:
    inc byte [r13 + usb_config.iad_count]
    lea rdi, [r13 + usb_config.iads + rax * 8]
    mov eax, [rsi + 2]                  ; first, count, class, subclass
    mov [rdi], eax
    mov ax, [rsi + 6]                   ; protocol, string
    mov [rdi + usb_iad.protocol], ax
    jmp .next

.hid:
    cmp ecx, 6
    jb .bad
    test r15d, r15d
    js .next
    mov eax, r15d
    imul eax, eax, usb_iface_size
    lea rdi, [r13 + usb_config.ifaces + rax]
    mov al, [rsi + 4]
    mov [rdi + usb_iface.hid_country], al
    movzx r8d, byte [rsi + 5]
    mov [rdi + usb_iface.hid_count], r8b
    xor edx, edx                        ; entry
.hid_entry:
    cmp edx, r8d
    jae .next
    lea eax, [rdx + rdx * 2]
    add eax, 9                          ; 6 + 3 (j + 1)
    cmp eax, ecx
    ja .next                            ; past the descriptor's end
    cmp byte [rsi + rax - 3], USB_DT_HID_REPORT
    jne .hid_skip
    cmp word [rdi + usb_iface.hid_report_len], 0
    jne .hid_skip
    mov ax, [rsi + rax - 2]
    mov [rdi + usb_iface.hid_report_len], ax
.hid_skip:
    inc edx
    jmp .hid_entry

; the body of the interface R15D ends at the offset R14D
.close_body:
    test r15d, r15d
    js .close_out
    mov eax, r15d
    imul eax, eax, usb_iface_size
    lea rdi, [r13 + usb_config.ifaces + rax]
    mov eax, r14d
    sub ax, [rdi + usb_iface.body_off]
    mov [rdi + usb_iface.body_len], ax
.close_out:
    ret

.done:
    call .close_body
    ; associations, endpoint counts
    xor ecx, ecx
.check:
    cmp cl, [r13 + usb_config.iface_count]
    jae .count_ifaces
    movzx eax, cl
    imul eax, eax, usb_iface_size
    lea rdi, [r13 + usb_config.ifaces + rax]
    mov al, [rdi + usb_iface.num_ep]
    cmp al, [rdi + usb_iface.ep_count]
    je .assoc
    or byte [r13 + usb_config.warn], USB_WARN_EP_COUNT
.assoc:
    movzx eax, byte [rdi + usb_iface.number]
    xor edx, edx
.iad_scan:
    cmp dl, [r13 + usb_config.iad_count]
    jae .check_next
    movzx r8d, byte [r13 + usb_config.iads + rdx * 8 + usb_iad.first]
    cmp eax, r8d
    jb .iad_scan_next
    movzx r9d, byte [r13 + usb_config.iads + rdx * 8 + usb_iad.count]
    add r8d, r9d
    cmp eax, r8d
    jae .iad_scan_next
    mov [rdi + usb_iface.func], dl
    jmp .check_next
.iad_scan_next:
    inc edx
    jmp .iad_scan
.check_next:
    inc ecx
    jmp .check
.count_ifaces:
    cmp dword [rsp + 8], 0
    jne .ok                             ; numbers past 31: not counted
    popcnt eax, dword [rsp + 4]
    cmp al, [r13 + usb_config.num_ifaces]
    je .ok
    or byte [r13 + usb_config.warn], USB_WARN_IFACES
.ok:
    xor eax, eax
    jmp .out
.bad:
    mov eax, -USB_EDESC
    jmp .out
.trunc:
    mov eax, -USB_ETRUNC
    jmp .out
.toomany:
    mov eax, -USB_ETOOMANY
.out:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_string_utf8 — a string descriptor as NUL-terminated UTF-8
; Input:  RDI = descriptor, ESI = bytes read, RDX = out, ECX = out size
; Output: EAX = bytes written (the NUL not counted), or -USB_EDESC
; Unpaired surrogates become U+FFFD; a NUL code unit ends the text; a
; character that does not fit whole is left out, and so is the rest.
; -----------------------------------------------------------------------------
global usb_string_utf8
usb_string_utf8:
    push rbx
    push r12
    test ecx, ecx
    jz .bad                             ; not even the NUL fits
    mov r12d, ecx
    dec r12d                            ; room before the NUL
    mov byte [rdx], 0
    cmp esi, 2
    jb .bad
    movzx r8d, byte [rdi]
    cmp r8d, 2
    jb .bad
    cmp r8d, esi
    ja .bad
    cmp byte [rdi + 1], USB_DT_STRING
    jne .bad
    sub r8d, 2
    shr r8d, 1                          ; code units
    lea r9, [rdi + 2]
    xor r10d, r10d                      ; unit index
    xor r11d, r11d                      ; bytes out
.unit:
    cmp r10d, r8d
    jae .end
    movzx eax, word [r9 + r10 * 2]
    inc r10d
    test eax, eax
    jz .end
    mov ecx, eax
    and ecx, 0xFC00
    cmp ecx, 0xDC00
    je .replace                         ; a low surrogate alone
    cmp ecx, 0xD800
    jne .encode
    cmp r10d, r8d
    jae .replace
    movzx ecx, word [r9 + r10 * 2]
    mov ebx, ecx
    and ebx, 0xFC00
    cmp ebx, 0xDC00
    jne .replace
    inc r10d
    sub eax, 0xD800
    shl eax, 10
    sub ecx, 0xDC00
    add eax, ecx
    add eax, 0x10000
    jmp .encode
.replace:
    mov eax, 0xFFFD
.encode:
    cmp eax, 0x80
    jae .two
    lea ecx, [r11d + 1]
    cmp ecx, r12d
    ja .end
    mov [rdx + r11], al
    mov r11d, ecx
    jmp .unit
.two:
    cmp eax, 0x800
    jae .three
    lea ecx, [r11d + 2]
    cmp ecx, r12d
    ja .end
    mov ecx, eax
    shr ecx, 6
    or cl, 0xC0
    mov [rdx + r11], cl
    and al, 0x3F
    or al, 0x80
    mov [rdx + r11 + 1], al
    add r11d, 2
    jmp .unit
.three:
    cmp eax, 0x10000
    jae .four
    lea ecx, [r11d + 3]
    cmp ecx, r12d
    ja .end
    mov ecx, eax
    shr ecx, 12
    or cl, 0xE0
    mov [rdx + r11], cl
    mov ecx, eax
    shr ecx, 6
    and cl, 0x3F
    or cl, 0x80
    mov [rdx + r11 + 1], cl
    and al, 0x3F
    or al, 0x80
    mov [rdx + r11 + 2], al
    add r11d, 3
    jmp .unit
.four:
    lea ecx, [r11d + 4]
    cmp ecx, r12d
    ja .end
    mov ecx, eax
    shr ecx, 18
    or cl, 0xF0
    mov [rdx + r11], cl
    mov ecx, eax
    shr ecx, 12
    and cl, 0x3F
    or cl, 0x80
    mov [rdx + r11 + 1], cl
    mov ecx, eax
    shr ecx, 6
    and cl, 0x3F
    or cl, 0x80
    mov [rdx + r11 + 2], cl
    and al, 0x3F
    or al, 0x80
    mov [rdx + r11 + 3], al
    add r11d, 4
    jmp .unit
.end:
    mov byte [rdx + r11], 0
    mov eax, r11d
    jmp .out
.bad:
    mov eax, -USB_EDESC
.out:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; usb_bos_parse — the Binary Object Store and the capabilities used here
; Input:  RDI = bytes, ESI = bytes read, RDX = usb_bos* to fill
; Output: EAX = 0, -USB_EDESC or -USB_ETRUNC
; -----------------------------------------------------------------------------
global usb_bos_parse
usb_bos_parse:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r13, rdx
    mov r12d, esi
    mov rdi, r13
    mov ecx, usb_bos_size
    xor eax, eax
    rep stosb
    cmp r12d, 5
    jb .bad
    cmp byte [rbx + 1], USB_DT_BOS
    jne .bad
    movzx eax, byte [rbx]
    cmp eax, 5
    jb .bad
    movzx ecx, word [rbx + 2]
    cmp ecx, eax
    jb .bad
    cmp ecx, r12d
    ja .trunc
    mov r12d, ecx
    mov r14d, eax
.walk:
    cmp r14d, r12d
    jae .ok
    mov eax, r12d
    sub eax, r14d
    cmp eax, 3
    jb .bad
    movzx ecx, byte [rbx + r14]
    cmp ecx, 3
    jb .bad
    cmp ecx, eax
    ja .bad
    lea rsi, [rbx + r14]
    cmp byte [rsi + 1], USB_DT_DEV_CAP
    jne .next
    inc byte [r13 + usb_bos.caps]
    movzx edx, byte [rsi + 2]
    cmp edx, USB_CAP_USB2_EXT
    je .usb2
    cmp edx, USB_CAP_SS
    je .ss
    cmp edx, USB_CAP_CONTAINER_ID
    je .container
    cmp edx, USB_CAP_SSP
    je .ssp
.next:
    movzx ecx, byte [rbx + r14]
    add r14d, ecx
    jmp .walk
.usb2:
    cmp ecx, 7
    jb .bad
    mov eax, [rsi + 3]
    bt eax, 1
    setc byte [r13 + usb_bos.lpm]
    bt eax, 2
    setc byte [r13 + usb_bos.besl]
    jmp .next
.ss:
    cmp ecx, 10
    jb .bad
    mov byte [r13 + usb_bos.ss], 1
    mov ax, [rsi + 4]
    mov [r13 + usb_bos.ss_speeds], ax
    mov al, [rsi + 6]
    mov [r13 + usb_bos.ss_func], al
    mov al, [rsi + 7]
    mov [r13 + usb_bos.u1_lat], al
    mov ax, [rsi + 8]
    mov [r13 + usb_bos.u2_lat], ax
    jmp .next
.container:
    cmp ecx, 20
    jb .bad
    mov byte [r13 + usb_bos.has_container], 1
    mov rax, [rsi + 4]
    mov [r13 + usb_bos.container], rax
    mov rax, [rsi + 12]
    mov [r13 + usb_bos.container + 8], rax
    jmp .next
.ssp:
    cmp ecx, 12
    jb .bad
    mov eax, [rsi + 4]
    and eax, 0x1F
    inc eax                             ; sublink speed attributes
    lea edx, [rax * 4 + 12]
    cmp edx, ecx
    ja .bad
    mov byte [r13 + usb_bos.ssp], 1
    xor edx, edx
.attr:
    cmp edx, eax
    jae .next
    mov r8d, [rsi + rdx * 4 + 12]
    mov r9d, r8d
    shr r9d, 16                         ; mantissa
    mov r10d, r8d
    shr r10d, 4
    and r10d, 3                         ; exponent: b, Kb, Mb, Gb per second
    cmp r10d, 3
    je .gbps
    cmp r10d, 2
    je .mbps
    cmp r10d, 1
    jne .bps
    push rax
    push rdx
    mov eax, r9d
    xor edx, edx
    mov r11d, 1000
    div r11d
    mov r9d, eax
    pop rdx
    pop rax
    jmp .mbps
.bps:
    xor r9d, r9d                        ; under 1 Mbit/s: not a fast link
    jmp .mbps
.gbps:
    imul r9d, r9d, 1000
.mbps:
    cmp r9d, [r13 + usb_bos.ssp_max_mbps]
    jbe .attr_next
    mov [r13 + usb_bos.ssp_max_mbps], r9d
.attr_next:
    inc edx
    jmp .attr
.ok:
    xor eax, eax
    jmp .out
.bad:
    mov eax, -USB_EDESC
    jmp .out
.trunc:
    mov eax, -USB_ETRUNC
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_USB_CORE_DESC_ASM
