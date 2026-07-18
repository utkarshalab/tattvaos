; =============================================================================
; lib/io/block/ata_pio.asm
; Legacy IDE / ATA PIO polling block driver.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_ATA_PIO_ASM
%define IO_BLOCK_ATA_PIO_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; ATA Registers
ATA_PORT_DATA       equ 0x1F0
ATA_PORT_ERR        equ 0x1F1
ATA_PORT_SECT_CNT   equ 0x1F2
ATA_PORT_LBA_LOW    equ 0x1F3
ATA_PORT_LBA_MID    equ 0x1F4
ATA_PORT_LBA_HIGH   equ 0x1F5
ATA_PORT_DRV_SEL    equ 0x1F6
ATA_PORT_CMD_STAT   equ 0x1F7

; ATA Commands
ATA_CMD_READ        equ 0x20
ATA_CMD_WRITE       equ 0x30

; Status Bits
ATA_STAT_BSY        equ 0x80        ; Busy
ATA_STAT_DRDY       equ 0x40        ; Drive Ready
ATA_STAT_DF         equ 0x20        ; Drive Fault
ATA_STAT_DRQ        equ 0x08        ; Data Request
ATA_STAT_ERR        equ 0x01        ; Error

section .rodata
drv_name_ata:       db "ata_pio", 0

section .text

extern port_in8
extern port_out8

; =============================================================================
; ata_pio_probe — Probe for Primary Master IDE/ATA drive presence
; In : RDI = -> device_t object to populate
; Out: RAX = 0 on success, or negative error band code if absent
; RSO: RAX owned-out
; =============================================================================
IO_FUNC ata_pio_probe
    guard_null rdi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    mov     rbx, rdi                ; RBX = -> device_t

    ; 1. Check controller existence using sector count/LBA pattern test
    mov     rdi, ATA_PORT_DRV_SEL
    mov     rsi, 0xA0               ; Select primary master
    call    port_out8

    mov     rdi, ATA_PORT_SECT_CNT
    mov     rsi, 0x55
    call    port_out8

    mov     rdi, ATA_PORT_LBA_LOW
    mov     rsi, 0xAA
    call    port_out8

    ; Read back and verify
    mov     rdi, ATA_PORT_SECT_CNT
    call    port_in8
    cmp     al, 0x55
    jne     .absent

    mov     rdi, ATA_PORT_LBA_LOW
    call    port_in8
    cmp     al, 0xAA
    jne     .absent

    ; 2. Check if drive status is floating/disconnected (status = 0xFF)
    mov     rdi, ATA_PORT_CMD_STAT
    call    port_in8
    cmp     al, 0xFF
    je      .absent

    ; Drive detected, initialize device_t fields
    lea     rdi, [rbx + device_t.name]
    lea     rsi, [rel drv_name_ata]
    mov     rcx, 8
    rep     movsb                   ; Copy name "ata_pio"

    mov     qword [rbx + device_t.type], FD_TYPE_BLOCK
    mov     qword [rbx + device_t.state], DEV_STATE_ONLINE
    mov     qword [rbx + device_t.sector_size], 512
    mov     qword [rbx + device_t.capacity], 0x100000 ; Approx 512MB (1M sectors)

    ; Map operation hooks
    lea     rax, [rel ata_pio_read]
    mov     [rbx + device_t.read], rax
    lea     rax, [rel ata_pio_write]
    mov     [rbx + device_t.write], rax

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.absent:
    mov     rax, IO_ERR_NO_DEVICE

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC ata_pio_probe

; =============================================================================
; ata_pio_read — Read sectors synchronously from Primary Master drive
; In : RDI = -> device_t
;      RSI = LBA (starting sector address)
;      RDX = Count of sectors
;      RCX = -> Destination buffer
; Out: RAX = 0 on success, or negative error code on failure
; =============================================================================
IO_FUNC ata_pio_read
    guard_null rdi
    guard_null rcx
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rsi                ; R12 = LBA
    mov     r13, rdx                ; R13 = sector count
    mov     r14, rcx                ; R14 = buffer pointer

.sector_loop:
    test    r13, r13
    jz      .success

    ; 1. Wait for controller to not be busy
    call    .wait_ready
    test    rax, rax
    jnz     .err_fault

    ; 2. Write parameters
    mov     rdi, ATA_PORT_SECT_CNT
    mov     rsi, 1                  ; Transfer 1 sector at a time
    call    port_out8

    ; Write LBA bits 0-7
    mov     rdi, ATA_PORT_LBA_LOW
    mov     rsi, r12
    and     rsi, 0xFF
    call    port_out8

    ; Write LBA bits 8-15
    mov     rdi, ATA_PORT_LBA_MID
    mov     rsi, r12
    shr     rsi, 8
    and     rsi, 0xFF
    call    port_out8

    ; Write LBA bits 16-23
    mov     rdi, ATA_PORT_LBA_HIGH
    mov     rsi, r12
    shr     rsi, 16
    and     rsi, 0xFF
    call    port_out8

    ; Write LBA bits 24-27 + select primary master (0xE0)
    mov     rdi, ATA_PORT_DRV_SEL
    mov     rsi, r12
    shr     rsi, 24
    and     rsi, 0x0F
    or      rsi, 0xE0               ; LBA mode, master drive
    call    port_out8

    ; 3. Write READ SECTORS command
    mov     rdi, ATA_PORT_CMD_STAT
    mov     rsi, ATA_CMD_READ
    call    port_out8

    ; 4. Wait for sector data ready (DRQ set)
    call    .wait_drq
    test    rax, rax
    jnz     .err_fault

    ; 5. Read 256 words (512 bytes) from Data register (0x1F0)
    mov     rdx, ATA_PORT_DATA      ; DX = Data port
    mov     rcx, 256                ; Words count
    mov     rdi, r14                ; Destination buffer

.read_word_loop:
    in      ax, dx
    mov     [rdi], ax
    add     rdi, 2
    dec     rcx
    jnz     .read_word_loop

    mov     r14, rdi                ; Advance buffer pointer
    inc     r12                     ; Increment LBA
    dec     r13                     ; Decrement sector count
    jmp     .sector_loop

.success:
    xor     rax, rax
    jmp     .done

.err_fault:
    mov     rax, IO_ERR_PCI_BAR     ; General I/O fault

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC ata_pio_read

; =============================================================================
; ata_pio_write — Write sectors synchronously to Primary Master drive
; In : RDI = -> device_t
;      RSI = LBA (starting sector address)
;      RDX = Count of sectors
;      RCX = -> Source buffer
; Out: RAX = 0 on success, or negative error code on failure
; =============================================================================
IO_FUNC ata_pio_write
    guard_null rdi
    guard_null rcx
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rsi
    mov     r13, rdx
    mov     r14, rcx

.sector_loop:
    test    r13, r13
    jz      .success

    ; 1. Wait for controller
    call    .wait_ready
    test    rax, rax
    jnz     .err_fault

    ; 2. Write parameters
    mov     rdi, ATA_PORT_SECT_CNT
    mov     rsi, 1
    call    port_out8

    mov     rdi, ATA_PORT_LBA_LOW
    mov     rsi, r12
    and     rsi, 0xFF
    call    port_out8

    mov     rdi, ATA_PORT_LBA_MID
    mov     rsi, r12
    shr     rsi, 8
    and     rsi, 0xFF
    call    port_out8

    mov     rdi, ATA_PORT_LBA_HIGH
    mov     rsi, r12
    shr     rsi, 16
    and     rsi, 0xFF
    call    port_out8

    mov     rdi, ATA_PORT_DRV_SEL
    mov     rsi, r12
    shr     rsi, 24
    and     rsi, 0x0F
    or      rsi, 0xE0
    call    port_out8

    ; 3. Write WRITE SECTORS command
    mov     rdi, ATA_PORT_CMD_STAT
    mov     rsi, ATA_CMD_WRITE
    call    port_out8

    ; 4. Wait until DRQ is ready to accept data
    call    .wait_drq
    test    rax, rax
    jnz     .err_fault

    ; 5. Write 256 words (512 bytes) to Data register (0x1F0)
    mov     rdx, ATA_PORT_DATA
    mov     rcx, 256
    mov     rsi, r14                ; Source buffer

.write_word_loop:
    mov     ax, [rsi]
    out     dx, ax
    add     rsi, 2
    dec     rcx
    jnz     .write_word_loop

    mov     r14, rsi                ; Advance buffer pointer
    inc     r12
    dec     r13
    jmp     .sector_loop

.success:
    xor     rax, rax
    jmp     .done

.err_fault:
    mov     rax, IO_ERR_PCI_BAR

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC ata_pio_write

; -----------------------------------------------------------------------------
; Helper: .wait_ready
; Poll status until BSY (bit 7) is 0 and DRDY (bit 6) is 1.
; Out: RAX = 0 on success, -1 on timeout/fault
; -----------------------------------------------------------------------------
.wait_ready:
    push    rcx
    mov     rcx, 100000             ; Timeout counter

.ready_loop:
    mov     rdi, ATA_PORT_CMD_STAT
    call    port_in8
    
    ; Check for error or device fault bits
    test    al, ATA_STAT_ERR | ATA_STAT_DF
    jnz     .ready_fail

    test    al, ATA_STAT_BSY
    jnz     .ready_retry
    test    al, ATA_STAT_DRDY
    jnz     .ready_ok

.ready_retry:
    dec     rcx
    jnz     .ready_loop
.ready_fail:
    mov     rax, -1                 ; Timeout/Fault failure
    jmp     .ready_done

.ready_ok:
    xor     rax, rax

.ready_done:
    pop     rcx
    ret

; -----------------------------------------------------------------------------
; Helper: .wait_drq
; Poll status until BSY is 0 and DRQ (bit 3) is 1.
; Out: RAX = 0 on success, -1 on timeout/fault
; -----------------------------------------------------------------------------
.wait_drq:
    push    rcx
    mov     rcx, 100000             ; Timeout counter

.drq_loop:
    mov     rdi, ATA_PORT_CMD_STAT
    call    port_in8

    ; Check for error or device fault bits
    test    al, ATA_STAT_ERR | ATA_STAT_DF
    jnz     .drq_fail

    test    al, ATA_STAT_BSY
    jnz     .drq_retry
    test    al, ATA_STAT_DRQ
    jnz     .drq_ok

.drq_retry:
    dec     rcx
    jnz     .drq_loop
.drq_fail:
    mov     rax, -1                 ; Timeout/Fault failure
    jmp     .drq_done

.drq_ok:
    xor     rax, rax

.drq_done:
    pop     rcx
    ret

%endif ; IO_BLOCK_ATA_PIO_ASM
