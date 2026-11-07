; =============================================================================
; Utkarsha OS — lib/usb/hcd/xhci/init.asm — bringing a controller up
; =============================================================================
;   xhci_attach(bar) → RAX = xhci_hc*, or 0 (EDX = what went wrong)
;
;   1. Take it from firmware (USB legacy support capability); firmware that
;      will not let go in a second is overruled and its SMIs turned off.
;   2. Halt, reset, wait for Controller Not Ready to clear.
;   3. Slots, the device context array, scratchpad buffers.
;   4. Command ring, event ring with its segment table on interrupter 0.
;   5. Which ports are USB 2 and which USB 3 (supported protocol caps).
;   6. Run.
; Interrupts stay off: events are polled (xhci_poll) until MSI-X arrives.
; =============================================================================

%ifndef LIB_USB_HCD_XHCI_INIT_ASM
%define LIB_USB_HCD_XHCI_INIT_ASM

; why xhci_attach failed (EDX)
%define XHCI_FAIL_NOMEM     1
%define XHCI_FAIL_HALT      2
%define XHCI_FAIL_RESET     3
%define XHCI_FAIL_RUN       4
%define XHCI_FAIL_TOOMANY   5
%define XHCI_FAIL_64BIT     6       ; memory above 4 GB on a 32-bit controller

section .bss
alignb 8
global xhci_hcs
xhci_hcs:       resq XHCI_MAX_HC
global xhci_hc_count
xhci_hc_count:  resd 1

section .rodata
; where the host tests find their way around an xhci_hc
global xhci_layout
xhci_layout:
    dd xhci_hc_size, xhci_hc.max_slots, xhci_hc.max_ports, xhci_hc.ctx_size
    dd xhci_hc.scratch, xhci_hc.dcbaa, xhci_hc.handoff, xhci_hc.port_major
    dd xhci_hc.slots, xhci_hc.cmd, xhci_hc.evt_deq, xhci_hc.hc_events
    dd xhci_hc.port_change, xhci_slot.eps, xhci_ep_size

section .text

; -----------------------------------------------------------------------------
; xhci_wait — poll a register until (value & mask) == want
; Input:  RDI = address, ESI = mask, EDX = want, ECX = tries (1 ms apart)
; Output: CF = 1 when it never did
; -----------------------------------------------------------------------------
xhci_wait:
    push rbx
.try:
    call usb_rd32
    and eax, esi
    cmp eax, edx
    je .ok
    dec ecx
    jz .timeout
    mov rbx, rdi
    mov edi, 1000
    call usb_delay
    mov rdi, rbx
    jmp .try
.ok:
    clc
    pop rbx
    ret
.timeout:
    stc
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_alloc_dma — usb_alloc, refused when a 32-bit controller cannot reach it
; Input:  RDI = size, RSI = alignment, RBX = hc
; Output: RAX, or 0
; -----------------------------------------------------------------------------
xhci_alloc_dma:
    sub rsp, 8
    call usb_alloc
    add rsp, 8
    test rax, rax
    jz .out
    test byte [rbx + xhci_hc.ac64], 1    ; 64-bit addressing
    jnz .out
    push rcx
    mov rcx, rax
    add rcx, rdi
    shr rcx, 32
    pop rcx
    jz .out
    xor eax, eax
.out:
    ret

; -----------------------------------------------------------------------------
; xhci_attach
; -----------------------------------------------------------------------------
global xhci_attach
xhci_attach:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; the BAR
    mov r15d, XHCI_FAIL_TOOMANY
    cmp dword [rel xhci_hc_count], XHCI_MAX_HC
    jae .fail
    mov r15d, XHCI_FAIL_NOMEM
    mov edi, xhci_hc_size
    mov esi, 64
    call usb_alloc
    test rax, rax
    jz .fail
    mov rbx, rax
    mov [rbx + xhci_hc.base], r12

    ; the register blocks
    mov rdi, r12
    call usb_rd32
    movzx ecx, al                       ; CAPLENGTH
    shr eax, 16
    mov [rbx + xhci_hc.version], eax
    lea rax, [r12 + rcx]
    mov [rbx + xhci_hc.op], rax
    lea rdi, [r12 + XHCI_DBOFF]
    call usb_rd32
    and eax, ~3
    lea rax, [r12 + rax]
    mov [rbx + xhci_hc.db], rax
    lea rdi, [r12 + XHCI_RTSOFF]
    call usb_rd32
    and eax, ~31
    lea rax, [r12 + rax]
    mov [rbx + xhci_hc.rt], rax
    lea rdi, [r12 + XHCI_HCSPARAMS1]
    call usb_rd32
    mov ecx, eax
    and ecx, 0xFF
    cmp ecx, XHCI_MAX_SLOTS
    jbe .slots
    mov ecx, XHCI_MAX_SLOTS
.slots:
    mov [rbx + xhci_hc.max_slots], ecx
    mov ecx, eax
    shr ecx, 8
    and ecx, 0x7FF
    mov [rbx + xhci_hc.max_intrs], ecx
    shr eax, 24
    mov [rbx + xhci_hc.max_ports], eax
    lea rdi, [r12 + XHCI_HCSPARAMS2]
    call usb_rd32
    mov ecx, eax
    shr ecx, 27                         ; low five bits of the count
    shr eax, 21
    and eax, 31                         ; high five
    shl eax, 5
    or eax, ecx
    mov [rbx + xhci_hc.scratch], eax
    lea rdi, [r12 + XHCI_HCCPARAMS1]
    call usb_rd32
    mov r13d, eax                       ; kept for xECP
    mov ecx, 32
    test eax, 1 << 2                    ; CSZ: 64-byte contexts
    jz .csz
    mov ecx, 64
.csz:
    mov [rbx + xhci_hc.ctx_size], ecx
    and eax, 1                          ; AC64
    mov [rbx + xhci_hc.ac64], eax

    ; 1. firmware hand-off, and 5. the port protocols
    mov rdi, rbx
    mov esi, r13d
    call xhci_ext_caps

    ; 2. halt, then reset
    mov r15d, XHCI_FAIL_HALT
    mov rdi, [rbx + xhci_hc.op]
    call usb_rd32
    and eax, ~(CMD_RS | CMD_INTE | CMD_HSEE)
    mov esi, eax
    call usb_wr32
    add rdi, XHCI_USBSTS
    mov esi, STS_HCH
    mov edx, STS_HCH
    mov ecx, 20
    call xhci_wait
    jc .fail
    mov r15d, XHCI_FAIL_RESET
    mov rdi, [rbx + xhci_hc.op]
    mov esi, CMD_HCRST
    call usb_wr32
    mov esi, CMD_HCRST
    xor edx, edx
    mov ecx, 1000
    call xhci_wait
    jc .fail
    add rdi, XHCI_USBSTS
    mov esi, STS_CNR
    xor edx, edx
    mov ecx, 1000
    call xhci_wait
    jc .fail

    ; 3. slots and the device context array (entry 0: the scratchpads)
    mov r15d, XHCI_FAIL_NOMEM
    mov rdi, [rbx + xhci_hc.op]
    add rdi, XHCI_CONFIG
    mov esi, [rbx + xhci_hc.max_slots]
    call usb_wr32
    mov edi, 256 * 8
    mov esi, 64
    call xhci_alloc_dma
    test rax, rax
    jz .fail
    mov [rbx + xhci_hc.dcbaa], rax
    mov ecx, [rbx + xhci_hc.scratch]
    test ecx, ecx
    jz .no_scratch
    mov r14d, ecx
    lea edi, [rcx * 8]
    mov esi, 64
    call xhci_alloc_dma
    test rax, rax
    jz .fail
    mov r13, rax
    mov rcx, [rbx + xhci_hc.dcbaa]
    mov [rcx], r13
.scratch_page:
    mov edi, 4096                       ; PAGESIZE is 4 KB on every PC part
    mov esi, 4096
    call xhci_alloc_dma
    test rax, rax
    jz .fail
    dec r14d
    mov [r13 + r14 * 8], rax
    jnz .scratch_page
.no_scratch:
    mov rdi, [rbx + xhci_hc.op]
    add rdi, XHCI_DCBAAP
    mov rsi, [rbx + xhci_hc.dcbaa]
    call usb_wr64

    ; 4. command ring
    mov edi, XHCI_CMD_TRBS
    call xhci_ring_new
    test rax, rax
    jz .fail
    mov [rbx + xhci_hc.cmd], rax
    mov rsi, [rax + xhci_ring.trbs]
    or rsi, CRCR_RCS
    mov rdi, [rbx + xhci_hc.op]
    add rdi, XHCI_CRCR
    call usb_wr64

    ; ... event ring and its one-entry segment table
    mov edi, XHCI_EVT_TRBS * 16
    mov esi, 4096
    call xhci_alloc_dma
    test rax, rax
    jz .fail
    mov [rbx + xhci_hc.evt], rax
    mov dword [rbx + xhci_hc.evt_cycle], 1
    mov edi, 64
    mov esi, 64
    call xhci_alloc_dma
    test rax, rax
    jz .fail
    mov [rbx + xhci_hc.erst], rax
    mov rcx, [rbx + xhci_hc.evt]
    mov [rax], rcx
    mov dword [rax + 8], XHCI_EVT_TRBS
    mov r13, [rbx + xhci_hc.rt]
    lea rdi, [r13 + XHCI_IR0 + IR_ERSTSZ]
    mov esi, 1
    call usb_wr32
    lea rdi, [r13 + XHCI_IR0 + IR_ERDP]
    mov rsi, [rbx + xhci_hc.evt]
    call usb_wr64
    lea rdi, [r13 + XHCI_IR0 + IR_ERSTBA]   ; last: this starts the ring
    mov rsi, [rbx + xhci_hc.erst]
    call usb_wr64
    lea rdi, [r13 + XHCI_IR0 + IR_IMOD]
    mov esi, 4000                       ; 1 ms between interrupts at most
    call usb_wr32
    lea rdi, [r13 + XHCI_IR0 + IR_IMAN]
    mov esi, IMAN_IP | IMAN_IE
    call usb_wr32

    ; 6. run
    mov r15d, XHCI_FAIL_RUN
    mov rdi, [rbx + xhci_hc.op]
    mov esi, CMD_RS
    call usb_wr32
    add rdi, XHCI_USBSTS
    mov esi, STS_HCH
    xor edx, edx
    mov ecx, 20
    call xhci_wait
    jc .fail

    mov eax, [rel xhci_hc_count]
    lea rcx, [rel xhci_hcs]
    mov [rcx + rax * 8], rbx
    inc dword [rel xhci_hc_count]
    mov rax, rbx
    xor edx, edx
    jmp .out
.fail:
    xor eax, eax
    mov edx, r15d
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xhci_ext_caps — walk the extended capabilities: hand-off and protocols
; Input:  RDI = hc, ESI = HCCPARAMS1
; -----------------------------------------------------------------------------
xhci_ext_caps:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    shr esi, 16                         ; xECP, in dwords
    jz .out
    mov r12, [rbx + xhci_hc.base]
    lea r12, [r12 + rsi * 4]
    mov r13d, 64                        ; capabilities at most: a loop guard
.cap:
    mov rdi, r12
    call usb_rd32
    cmp al, XECP_LEGACY
    je .legacy
    cmp al, XECP_PROTOCOL
    je .protocol
.next:
    mov rdi, r12
    call usb_rd32
    movzx eax, ah                       ; next, in dwords
    test eax, eax
    jz .out
    lea r12, [r12 + rax * 4]
    dec r13d
    jnz .cap
    jmp .out

.legacy:
    test eax, LEGSUP_BIOS
    jz .ours
    or eax, LEGSUP_OS
    mov esi, eax
    mov rdi, r12
    call usb_wr32
    mov esi, LEGSUP_BIOS
    xor edx, edx
    mov ecx, 1000                       ; a second
    call xhci_wait
    jnc .ours
    ; firmware kept it: take it, and stop its SMIs
    mov rdi, r12
    call usb_rd32
    and eax, ~LEGSUP_BIOS
    or eax, LEGSUP_OS
    mov esi, eax
    call usb_wr32
    mov dword [rbx + xhci_hc.handoff], 2
    jmp .smis
.ours:
    cmp dword [rbx + xhci_hc.handoff], 0
    jne .smis
    mov dword [rbx + xhci_hc.handoff], 1
.smis:
    ; USBLEGCTLSTS: SMI enables off, the latched SMI events cleared
    lea rdi, [r12 + 4]
    call usb_rd32
    and eax, 0xFFFF1FEE                 ; enables 0, 4, 13-15 off
    or eax, 0xE0000000                  ; write 1 to clear 29-31
    mov esi, eax
    call usb_wr32
    jmp .next

.protocol:
    shr eax, 24                         ; major revision
    mov ecx, eax
    lea rdi, [r12 + 8]
    call usb_rd32
    movzx edx, al                       ; first port (1-based)
    movzx eax, ah                       ; count
    test edx, edx
    jz .next
.port:
    test eax, eax
    jz .next
    cmp edx, 255
    ja .next
    mov [rbx + xhci_hc.port_major + rdx], cl
    inc edx
    dec eax
    jmp .port
.out:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_USB_HCD_XHCI_INIT_ASM
