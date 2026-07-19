; =============================================================================
; lib/io/block/nvme_diag.asm
; Block device controller hardware register diagnostics and status dumper.
;
; Performs register dumps for Virtio legacy controllers to help resolve
; transaction hangs and log controller fatal states to the serial console.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_NVME_DIAG_ASM
%define IO_BLOCK_NVME_DIAG_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .data
msg_diag_start:      db "DIAG:START_BLOCK_REG_DUMP", 0
msg_status_prefix:   db "DIAG:VIRTIO_STATUS=0x", 0
msg_isr_prefix:      db "DIAG:VIRTIO_ISR=0x", 0
msg_done:            db "DIAG:DUMP_COMPLETE", 0

section .bss
align 8
hex_buffer:          resb 16

section .text

global bdev_dump_diagnostics

extern console_milestone
extern port_in8

; =============================================================================
; bdev_dump_diagnostics — Dump status register diagnostics for a block device
; In : RDI = -> device_t structure
; =============================================================================
IO_FUNC bdev_dump_diagnostics
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12

    mov     rbx, rdi                ; RBX = -> device_t

    ; 1. Print starting diagnostics milestone
    lea     rdi, [rel msg_diag_start]
    call    console_milestone

    ; Check if private driver context is mapped
    mov     r12, [rbx + device_t.private]
    test    r12, r12
    jz      .done                   ; Legacy ATA or null private context

    ; 2. Read Virtio Device Status (offset 18 of I/O BAR)
    mov     rdi, r12
    add     rdi, 18                 ; VIRTIO_PCI_STATUS
    call    port_in8                ; AL = status byte
    
    ; Convert AL to hex characters and append to status prefix
    lea     rdi, [rel msg_status_prefix]
    call    .print_reg_hex

    ; 3. Read Virtio Interrupt Status (offset 19 of I/O BAR)
    mov     rdi, r12
    add     rdi, 19                 ; VIRTIO_PCI_ISR
    call    port_in8                ; AL = ISR byte
    
    ; Convert AL to hex and print
    lea     rdi, [rel msg_isr_prefix]
    call    .print_reg_hex

.done:
    lea     rdi, [rel msg_done]
    call    console_milestone

    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; Helper: .print_reg_hex
; Combines prefix string in RDI with byte in AL formatted as 2-character hex
; -----------------------------------------------------------------------------
.print_reg_hex:
    push    rbx
    push    rdi
    push    rax

    mov     rbx, rdi                ; RBX = Prefix pointer
    
    ; 1. Copy prefix to BSS hex buffer
    lea     rdi, [rel hex_buffer]
    mov     rsi, rbx
.copy_loop:
    lodsb
    stosb
    test    al, al
    jnz     .copy_loop
    dec     rdi                     ; Align to overwrite null terminator

    ; 2. Format byte in AL to 2 hex characters
    pop     rax                     ; Restore input AL value
    push    rax
    
    ; High nibble
    mov     ah, al
    shr     ah, 4
    and     ah, 0x0F
    add     ah, '0'
    cmp     ah, '9'
    jbe     .write_high
    add     ah, 7                   ; Adjust to 'A'-'F' range
.write_high:
    mov     [rdi], ah
    inc     rdi

    ; Low nibble
    and     al, 0x0F
    add     al, '0'
    cmp     al, '9'
    jbe     .write_low
    add     al, 7
.write_low:
    mov     [rdi], al
    inc     rdi

    ; Write null terminator
    mov     byte [rdi], 0

    ; 3. Emit completed string as console milestone
    lea     rdi, [rel hex_buffer]
    call    console_milestone

    pop     rax
    pop     rdi
    pop     rbx
    ret
IO_ENDFUNC bdev_dump_diagnostics

%endif ; IO_BLOCK_NVME_DIAG_ASM
