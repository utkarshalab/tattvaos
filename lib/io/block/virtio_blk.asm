; =============================================================================
; lib/io/block/virtio_blk.asm
; Virtio-Blk asynchronous block device driver using legacy PCI.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_VIRTIO_BLK_ASM
%define IO_BLOCK_VIRTIO_BLK_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"
%include "lib/io/intr/isr.asm"

; Virtio Legacy PCI Register Offsets
VIRTIO_PCI_HOST_FEATURES    equ 0x00    ; 32-bit R
VIRTIO_PCI_GUEST_FEATURES   equ 0x04    ; 32-bit W
VIRTIO_PCI_QUEUE_PFN         equ 0x08    ; 32-bit RW
VIRTIO_PCI_QUEUE_NUM         equ 0x0C    ; 16-bit R
VIRTIO_PCI_QUEUE_SEL         equ 0x0E    ; 16-bit W
VIRTIO_PCI_QUEUE_NOTIFY      equ 0x10    ; 16-bit W
VIRTIO_PCI_STATUS            equ 0x12    ; 8-bit RW
VIRTIO_PCI_ISR               equ 0x13    ; 8-bit R

; Virtio Status Bits
VIRTIO_STATUS_ACKNOWLEDGE   equ 1
VIRTIO_STATUS_DRIVER        equ 2
VIRTIO_STATUS_DRIVER_OK     equ 4
VIRTIO_STATUS_FEATURES_OK   equ 8
VIRTIO_STATUS_FAILED        equ 128

; Virtqueue Descriptor Flags
VRING_DESC_F_NEXT           equ 1
VRING_DESC_F_WRITE          equ 2

section .bss
global virtio_device_io_base
virtio_device_io_base: resw 1       ; Mapped I/O BAR0 base address
global virtio_queue_size
virtio_queue_size: resw 1

; Pointers to our allocated virtqueue rings
global virtio_desc_table_phys
virtio_desc_table_phys: resq 1
global virtio_desc_table_virt
virtio_desc_table_virt: resq 1

; Global pointer to wait on status updates
global virtio_active_request
virtio_active_request: resq 1
global virtio_active_status_phys
virtio_active_status_phys: resq 1
global virtio_active_status_virt
virtio_active_status_virt: resq 1

section .rodata
drv_name_virtio:    db "virtio_blk", 0

section .text

; These will be resolved during compilation/linking (same unit)
;extern pci_config_read
;extern pci_config_write
;extern dma_alloc
;extern idt_register_handler
;extern lapic_send_eoi
;extern port_in8
;extern port_out8

; =============================================================================
; virtio_blk_probe — Probe and initialize Virtio-Blk legacy PCI device
; In : RDI = -> device_t object to populate
;      RSI = PCI address location (bus << 16 | dev << 8 | func)
; Out: RAX = 0 on success, or a negative error code on failure
; =============================================================================
IO_FUNC virtio_blk_probe
    guard_null rdi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     rbx, rdi                ; RBX = -> device_t
    mov     r12, rsi                ; R12 = PCI Address Location

    ; 1. Read BAR0 to get I/O Port Base Address
    mov     rdi, r12
    shr     rdi, 16                 ; Bus
    mov     rsi, r12
    shr     rsi, 8
    and     rsi, 0x1F               ; Device
    mov     rdx, r12
    and     rdx, 0x07               ; Function
    mov     rcx, 0x10               ; BAR0 offset
    mov     r8, 4                   ; Read 32 bits
    call    pci_config_read
    
    ; BAR0 is I/O if bit 0 is 1. Check it.
    test    al, 0x01
    jz      .err_no_device          ; Not an I/O BAR, fail probe

    and     eax, 0xFFFFFFFC         ; Clear low 2 bits
    mov     r13, rax                ; R13 = I/O base port address
    mov     [rel virtio_device_io_base], ax

    ; 2. Device Reset
    mov     rdx, r13
    add     rdx, VIRTIO_PCI_STATUS
    xor     eax, eax
    out     dx, al                  ; Write status 0 to reset

    ; 3. Set ACKNOWLEDGE and DRIVER status bits
    mov     al, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER
    out     dx, al

    ; 4. Configure Queue 0
    mov     rdx, r13
    add     rdx, VIRTIO_PCI_QUEUE_SEL
    xor     eax, eax
    out     dx, ax                  ; Select Queue 0

    mov     rdx, r13
    add     rdx, VIRTIO_PCI_QUEUE_NUM
    in      ax, dx                  ; Read Queue Size
    mov     [rel virtio_queue_size], ax
    test    ax, ax
    jz      .err_no_device          ; Queue 0 not active, fail

    ; 5. Allocate Virtqueue rings (we allocate a single contiguous page)
    ; Descriptors (2048 bytes) + Avail Ring (262 bytes) + Used Ring (1030 bytes)
    mov     rdi, 4096               ; Size = 4KB
    mov     rsi, 4096               ; Alignment = 4KB page aligned
    xor     rdx, rdx                ; No flags
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem

    mov     [rel virtio_desc_table_phys], rax
    mov     [rel virtio_desc_table_virt], rbx

    ; 6. Write physical PFN to Queue PFN register
    mov     rcx, rax
    shr     rcx, 12                 ; Convert physical address to PFN (page number)
    mov     rdx, r13
    add     rdx, VIRTIO_PCI_QUEUE_PFN
    mov     eax, ecx
    out     dx, eax                 ; Write Queue PFN

    ; Feature negotiation and FEATURES_OK step
    mov     rdx, r13
    add     rdx, VIRTIO_PCI_HOST_FEATURES
    in      eax, dx                 ; Read host features

    mov     rdx, r13
    add     rdx, VIRTIO_PCI_GUEST_FEATURES
    out     dx, eax                 ; Write guest features

    mov     rdx, r13
    add     rdx, VIRTIO_PCI_STATUS
    mov     al, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK
    out     dx, al                  ; Set FEATURES_OK status

    ; Verify device accepted features
    in      al, dx
    test    al, VIRTIO_STATUS_FEATURES_OK
    jz      .err_no_device

    ; 7. Allocate status byte in DMA space
    mov     rdi, 64
    mov     rsi, 64
    xor     rdx, rdx
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem
    mov     [rel virtio_active_status_phys], rax
    mov     [rel virtio_active_status_virt], rbx

    ; 8. Register IDT handler for Virtio Interrupt
    ; Read interrupt pin/line from PCI configuration
    mov     rdi, r12
    shr     rdi, 16                 ; Bus
    mov     rsi, r12
    shr     rsi, 8
    and     rsi, 0x1F               ; Device
    mov     rdx, r12
    and     rdx, 0x07               ; Function
    mov     rcx, 0x3C               ; Interrupt Line/Pin offset
    mov     r8, 2                   ; 2 bytes
    call    pci_config_read
    and     rax, 0xFF               ; AL = interrupt line (IRQ)

    test    al, al
    jz      .skip_irq

    mov     rdi, rax                ; RDI = IRQ
    lea     rsi, [rel virtio_blk_isr] ; RSI = handler
    xor     rdx, rdx                ; No IST
    call    idt_register_handler

.skip_irq:
    ; 9. Setup device_t metadata
    lea     rdi, [rbx + device_t.name]
    lea     rsi, [rel drv_name_virtio]
    mov     rcx, 11
    rep     movsb

    mov     qword [rbx + device_t.type], FD_TYPE_BLOCK
    mov     qword [rbx + device_t.state], DEV_STATE_ONLINE
    mov     qword [rbx + device_t.sector_size], 512
    mov     qword [rbx + device_t.capacity], 0x800000 ; 8M sectors (4GB)

    ; Map submit function hook
    lea     rax, [rel virtio_blk_submit]
    mov     [rbx + device_t.submit], rax

    ; Set DRIVER_OK status
    mov     rdx, r13
    add     rdx, VIRTIO_PCI_STATUS
    mov     al, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK | VIRTIO_STATUS_DRIVER_OK
    out     dx, al

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_nomem:
    mov     rax, IO_ERR_NOMEM
    jmp     .done

.err_no_device:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC virtio_blk_probe

; =============================================================================
; virtio_blk_submit — Asynchronously submit request to Virtio-Blk
; In : RDI = -> device_t
;      RSI = -> io_request_t
; Out: RAX = 0 on success, or a negative error code on failure
; =============================================================================
IO_FUNC virtio_blk_submit
    guard_null rdi
    guard_null rsi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi                ; RBX = dev
    mov     r12, rsi                ; R12 = req

    ; Allocate virtio request header on stack
    ; virtio_blk_req_t is 16 bytes. Align RSP.
    sub     rsp, 16
    mov     r13, rsp                ; R13 = &blk_req

    ; Fill in virtio request header
    mov     rax, [r12 + io_request_t.opcode]
    cmp     rax, IO_OP_READ
    je      .set_read
    mov     dword [r13 + virtio_blk_req_t.type], 1 ; WRITE (1)
    jmp     .set_lba
.set_read:
    mov     dword [r13 + virtio_blk_req_t.type], 0 ; READ (0)
.set_lba:
    mov     dword [r13 + virtio_blk_req_t.reserved], 0
    mov     rax, [r12 + io_request_t.lba]
    mov     [r13 + virtio_blk_req_t.sector], rax

    ; Set request state to SUBMITTED
    mov     qword [r12 + io_request_t.state], IO_REQ_SUBMITTED
    mov     [rel virtio_active_request], r12

    ; Initialize status byte to 0xFF (pending)
    mov     rcx, [rel virtio_active_status_virt]
    mov     byte [rcx], 0xFF

    ; 1. Build descriptors table:
    ; Desc 0: Header (R13), Read-Only
    ; Desc 1: Data buffer, Read or Write depending on opcode
    ; Desc 2: Status byte (active_status_phys), Write-Only by device
    mov     r14, [rel virtio_desc_table_virt]

    ; Desc 0
    ; Convert stack R13 address to physical (we can assume stack is physically contiguous for 16-byte block)
    mov     rdi, r13
    call    virt_to_phys
    mov     [r14 + 0], rax          ; addr
    mov     dword [r14 + 8], 16     ; len = 16
    mov     word [r14 + 12], VRING_DESC_F_NEXT ; flags (next = 1, read-only)
    mov     word [r14 + 14], 1      ; next = 1

    ; Desc 1
    mov     rax, [r12 + io_request_t.iov]
    mov     rcx, [rax + iovec_t.phys]
    mov     rdx, [rax + iovec_t.len]
    mov     [r14 + 16], rcx         ; addr
    mov     [r14 + 24], edx         ; len
    mov     word [r14 + 28], VRING_DESC_F_NEXT ; flags
    ; Set write flag if READ operation
    mov     rax, [r12 + io_request_t.opcode]
    cmp     rax, IO_OP_READ
    jne     .desc1_next
    or      word [r14 + 28], VRING_DESC_F_WRITE
.desc1_next:
    mov     word [r14 + 30], 2      ; next = 2

    ; Desc 2
    mov     rax, [rel virtio_active_status_phys]
    mov     [r14 + 32], rax         ; addr
    mov     dword [r14 + 40], 1     ; len = 1
    mov     word [r14 + 44], VRING_DESC_F_WRITE ; flags (write-only, no next)
    mov     word [r14 + 46], 0

    ; 2. Add descriptor chain to Avail Ring
    ; Avail Ring structure layout:
    ; offset 2048: flags (2 bytes)
    ; offset 2050: idx (2 bytes)
    ; offset 2052: ring (array of 128 words)
    mov     r14, [rel virtio_desc_table_virt]
    lea     rax, [r14 + 2048]       ; RAX = -> avail ring

    movzx   rcx, word [rax + 2]     ; RCX = avail.idx
    and     rcx, 127                ; mask by size (128)
    lea     rdx, [rax + 4 + rcx * 2] ; RDX = &avail.ring[idx]
    mov     word [rdx], 0           ; Write head descriptor index (0)

    sfence                          ; Fence 1: Ensure descriptor writes and avail ring entry are visible

    ; Increment avail.idx
    inc     word [rax + 2]

    sfence                          ; Fence 2: Ensure index update is visible before device notification

    ; 3. Notify device
    movzx   rdx, word [rel virtio_device_io_base]
    add     rdx, VIRTIO_PCI_QUEUE_NOTIFY
    xor     eax, eax                ; Notify queue 0
    out     dx, ax

    ; 4. Polling wait for completion (until status updated to non-0xFF or timeout)
    mov     rcx, [rel virtio_active_status_virt]
    mov     rsi, 50000000           ; Timeout counter

.wait_loop:
    movzx   rax, byte [rcx]
    cmp     al, 0xFF
    jne     .check_status

    dec     rsi
    jz      .err_timeout

    pause                           ; Hint to CPU for spinning loop efficiency
    jmp     .wait_loop

.err_timeout:
    mov     qword [r12 + io_request_t.state], IO_REQ_TIMEOUT
    mov     qword [r12 + io_request_t.status], IO_ERR_TIMEOUT
    mov     rax, IO_ERR_TIMEOUT
    jmp     .done

.check_status:
    ; Handle final result
    test    al, al
    jnz     .err_io

    mov     qword [r12 + io_request_t.state], IO_REQ_COMPLETE
    mov     qword [r12 + io_request_t.status], 0
    xor     rax, rax
    jmp     .done

.err_io:
    mov     qword [r12 + io_request_t.state], IO_REQ_ERROR
    mov     qword [r12 + io_request_t.status], IO_ERR_MEDIA
    mov     rax, IO_ERR_MEDIA

.done:
    add     rsp, 16
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC virtio_blk_submit

; =============================================================================
; virtio_blk_isr — Interrupt Service Routine for Virtio-Blk completions
; =============================================================================
global virtio_blk_isr
virtio_blk_isr:
    ISR_ENTRY

    ; 1. Acknowledge interrupt in ISR register (reading it clears it)
    movzx   rdx, word [rel virtio_device_io_base]
    add     rdx, VIRTIO_PCI_ISR
    in      al, dx
    test    al, 0x01                ; Check queue completion interrupt
    jz      .done                   ; Not for us

    ; 2. Complete active request (in polling bring-up, wait loop handles state,
    ; but ISR confirms used ring update and clears the interrupt signal)
    mov     rax, [rel virtio_active_request]
    test    rax, rax
    jz      .done

.done:
    call    lapic_send_eoi          ; Acknowledge vector in LAPIC
    ISR_EXIT

%endif ; IO_BLOCK_VIRTIO_BLK_ASM
