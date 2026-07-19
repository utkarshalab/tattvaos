; =============================================================================
; lib/io/block/virtio_blk.asm
; Virtio-Blk asynchronous block device driver using legacy PCI.
;
; Implements dynamic interrupt vector allocation and IO-APIC routing per §1.E.
; The probe path allocates a vector via intr/vector.asm, programs the IO-APIC
; redirection entry via intr/ioapic.asm, and registers the ISR handler. This
; replaces the previous static PCI interrupt line approach.
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
global virtio_allocated_vector
virtio_allocated_vector: resq 1     ; Dynamically allocated interrupt vector

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

extern pci_config_read
extern pci_config_write
extern dma_alloc
extern idt_register_handler
extern lapic_send_eoi
extern port_in8
extern port_out8
extern port_in32
extern vector_alloc
extern ioapic_route_irq
extern virt_to_phys
extern global_plug_depth

; =============================================================================
; virtio_blk_probe — Probe and initialize Virtio-Blk legacy PCI device
;
; Dynamic Interrupt Routing (§1.E):
;   1. Read the PCI interrupt pin to determine which legacy IRQ pin is wired
;   2. Allocate a dynamic vector in range [0x40, 0xEF] via vector_alloc
;   3. Program the IO-APIC redirection table entry for the IRQ pin with
;      the allocated vector, target APIC ID, edge trigger, active high
;   4. Register the ISR handler at the allocated vector via idt_register_handler
;
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
    push    r14

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

    ; 5. Allocate Virtqueue rings (single contiguous page)
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
    shr     rcx, 12                 ; Convert physical address to PFN
    mov     rdx, r13
    add     rdx, VIRTIO_PCI_QUEUE_PFN
    mov     eax, ecx
    out     dx, eax

    ; 7. Feature negotiation and FEATURES_OK step
    mov     rdx, r13
    add     rdx, VIRTIO_PCI_HOST_FEATURES
    in      eax, dx                 ; Read host features

    mov     rdx, r13
    add     rdx, VIRTIO_PCI_GUEST_FEATURES
    out     dx, eax                 ; Echo back as guest features

    mov     rdx, r13
    add     rdx, VIRTIO_PCI_STATUS
    mov     al, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK
    out     dx, al

    ; Verify device accepted features
    in      al, dx
    test    al, VIRTIO_STATUS_FEATURES_OK
    jz      .err_no_device

    ; 8. Allocate status byte in DMA space
    mov     rdi, 64
    mov     rsi, 64
    xor     rdx, rdx
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem
    mov     [rel virtio_active_status_phys], rax
    mov     [rel virtio_active_status_virt], rbx

    ; =========================================================================
    ; 9. Dynamic Interrupt Routing (§1.E / §6 Vector Map)
    ;
    ; Instead of using the raw PCI interrupt line directly:
    ;   a) Read the PCI interrupt pin (0x3D) to get the IRQ pin identity
    ;   b) Allocate a dynamic vector in [0x40, 0xEF] from the vector pool
    ;   c) Program IO-APIC redirection: map the IRQ pin -> allocated vector
    ;   d) Register the ISR handler at the allocated vector in the IDT
    ; =========================================================================

    ; 9a. Read PCI interrupt line (IRQ) from config space offset 0x3C
    mov     rdi, r12
    shr     rdi, 16                 ; Bus
    mov     rsi, r12
    shr     rsi, 8
    and     rsi, 0x1F               ; Device
    mov     rdx, r12
    and     rdx, 0x07               ; Function
    mov     rcx, 0x3C               ; Interrupt Line/Pin offset
    mov     r8, 2                   ; 2 bytes (line + pin)
    call    pci_config_read

    mov     r14, rax                ; R14[7:0] = IRQ line, R14[15:8] = IRQ pin
    and     r14, 0xFF               ; R14 = IRQ line number (IO-APIC input pin)
    test    r14, r14
    jz      .skip_irq               ; IRQ line 0 = not wired

    ; 9b. Allocate a dynamic vector from the vector pool
    call    vector_alloc
    test    rax, rax
    js      .skip_irq               ; Negative = allocation failed, skip IRQ setup
    mov     [rel virtio_allocated_vector], rax
    push    rax                     ; Save allocated vector on stack

    ; 9c. Program IO-APIC: route IRQ pin -> allocated vector on BSP (APIC ID 0)
    ;     ioapic_route_irq(irq_pin, vector, target_apic_id)
    mov     rdi, r14                ; RDI = IRQ pin (from PCI config)
    mov     rsi, rax                ; RSI = allocated vector number
    xor     rdx, rdx                ; RDX = target APIC ID (0 = BSP)
    call    ioapic_route_irq

    ; 9d. Register ISR handler in the IDT at the allocated vector
    ;     idt_register_handler(vector, handler_addr, ist_index)
    pop     rdi                     ; RDI = allocated vector (restore from stack)
    lea     rsi, [rel virtio_blk_isr] ; RSI = ISR handler address
    xor     rdx, rdx                ; RDX = IST index 0 (normal stack)
    call    idt_register_handler

.skip_irq:
    ; 10. Setup device_t metadata
    lea     rdi, [rbx + device_t.name]
    lea     rsi, [rel drv_name_virtio]
    mov     rcx, 11
    rep     movsb

    mov     qword [rbx + device_t.type], FD_TYPE_BLOCK
    mov     qword [rbx + device_t.state], DEV_STATE_ONLINE
    ; Auto-negotiate block capacity (offset 20 of Virtio config BAR space)
    movzx   rdi, word [rel virtio_device_io_base]
    add     rdi, 20                 ; Offset of low 32-bits of capacity
    call    port_in32
    mov     r8, rax                 ; R8 = low dword of capacity

    movzx   rdi, word [rel virtio_device_io_base]
    add     rdi, 24                 ; Offset of high 32-bits of capacity
    call    port_in32
    shl     rax, 32
    or      r8, rax                 ; R8 = 64-bit capacity (in sectors)
    mov     [rbx + device_t.capacity], r8

    ; Auto-negotiate block/sector size (offset 40 of Virtio config BAR space)
    movzx   rdi, word [rel virtio_device_io_base]
    add     rdi, 40
    call    port_in32
    test    rax, rax
    jnz     .set_sector_size
    mov     rax, 512                ; Default fallback to 512 bytes
.set_sector_size:
    mov     [rbx + device_t.sector_size], rax

    ; Map submit function hook
    lea     rax, [rel virtio_blk_submit]
    mov     [rbx + device_t.submit], rax

    ; Map flush function hook for batching
    lea     rax, [rel virtio_blk_flush]
    mov     [rbx + device_t.flush], rax

    ; Set DRIVER_OK status — device is fully initialized
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
    pop     r14
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

    ; Allocate virtio request header on stack (16 bytes, aligned)
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

    ; 1. Build descriptors table
    mov     r14, [rel virtio_desc_table_virt]

    ; Desc 0: Header (R13), Read-Only by device
    mov     rdi, r13
    call    virt_to_phys
    mov     [r14 + 0], rax          ; addr
    mov     dword [r14 + 8], 16     ; len = 16
    mov     word [r14 + 12], VRING_DESC_F_NEXT
    mov     word [r14 + 14], 1      ; next = 1

    ; Desc 1: Data buffer
    mov     rax, [r12 + io_request_t.iov]
    mov     rcx, [rax + iovec_t.phys]
    mov     rdx, [rax + iovec_t.len]
    mov     [r14 + 16], rcx         ; addr
    mov     [r14 + 24], edx         ; len
    mov     word [r14 + 28], VRING_DESC_F_NEXT
    mov     rax, [r12 + io_request_t.opcode]
    cmp     rax, IO_OP_READ
    jne     .desc1_next
    or      word [r14 + 28], VRING_DESC_F_WRITE
.desc1_next:
    mov     word [r14 + 30], 2      ; next = 2

    ; Desc 2: Status byte, Write-Only by device
    mov     rax, [rel virtio_active_status_phys]
    mov     [r14 + 32], rax         ; addr
    mov     dword [r14 + 40], 1     ; len = 1
    mov     word [r14 + 44], VRING_DESC_F_WRITE
    mov     word [r14 + 46], 0

    ; 2. Add descriptor chain to Avail Ring
    mov     r14, [rel virtio_desc_table_virt]
    lea     rax, [r14 + 2048]       ; RAX = -> avail ring

    movzx   rcx, word [rax + 2]     ; RCX = avail.idx
    and     rcx, 127                ; mask by queue size
    lea     rdx, [rax + 4 + rcx * 2]
    mov     word [rdx], 0           ; head descriptor index

    sfence                          ; Fence 1: descriptors + avail entry visible

    inc     word [rax + 2]          ; Bump avail.idx

    sfence                          ; Fence 2: index visible before notify

    ; 3. Notify device (unless doorbell is plugged/batched)
    mov     rax, [rel global_plug_depth]
    test    rax, rax
    jnz     .plugged                ; Skip notify and wait

    movzx   rdx, word [rel virtio_device_io_base]
    add     rdx, VIRTIO_PCI_QUEUE_NOTIFY
    xor     eax, eax
    out     dx, ax

    ; 4. Polling wait with timeout
    mov     rcx, [rel virtio_active_status_virt]
    mov     rsi, 50000000           ; Timeout counter

.wait_loop:
    movzx   rax, byte [rcx]
    cmp     al, 0xFF
    jne     .check_status

    dec     rsi
    jz      .err_timeout

    pause
    jmp     .wait_loop

.err_timeout:
    mov     qword [r12 + io_request_t.state], IO_REQ_TIMEOUT
    mov     qword [r12 + io_request_t.status], IO_ERR_TIMEOUT
    mov     rax, IO_ERR_TIMEOUT
    jmp     .done

.check_status:
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

.plugged:
    mov     qword [r12 + io_request_t.state], IO_REQ_PENDING
    xor     rax, rax
    jmp     .done

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
; virtio_blk_flush — Flush pending descriptors (write doorbell notification)
; In : RDI = -> device_t
; =============================================================================
global virtio_blk_flush
IO_FUNC virtio_blk_flush
    push    rdx
    push    rax
    movzx   rdx, word [rel virtio_device_io_base]
    add     rdx, VIRTIO_PCI_QUEUE_NOTIFY
    xor     eax, eax
    out     dx, ax                  ; Trigger MMIO notification
    pop     rax
    pop     rdx
IO_ENDFUNC virtio_blk_flush


; =============================================================================
; virtio_blk_isr — Interrupt Service Routine for Virtio-Blk completions
; =============================================================================
global virtio_blk_isr
virtio_blk_isr:
    ISR_ENTRY

    ; 1. Acknowledge interrupt in device ISR register (read clears it)
    movzx   rdx, word [rel virtio_device_io_base]
    add     rdx, VIRTIO_PCI_ISR
    in      al, dx
    test    al, 0x01
    jz      .done

    ; 2. The status byte in DMA space is already written by the device before
    ;    the interrupt fires. The polling loop in virtio_blk_submit will observe
    ;    the updated byte and exit. In future async mode, we would push a
    ;    completion entry into the per-core SPSC completion ring here.
    mov     rax, [rel virtio_active_request]
    test    rax, rax
    jz      .done

    ; Future: spsc_ring_push(percpu->complete_ring, completion_entry)

.done:
    call    lapic_send_eoi          ; MANDATORY LAPIC EOI (§13.5.2)
    ISR_EXIT

%endif ; IO_BLOCK_VIRTIO_BLK_ASM