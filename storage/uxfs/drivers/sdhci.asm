; =============================================================================
; Tattva OS — storage/uxfs/drivers/sdhci.asm
; =============================================================================
; SD Host Controller (SDHCI) Driver with ADMA2 Scatter-Gather.
;
; Implements:
;   - Controller reset and clock/power bring-up (`uxfs_sdhci_init`)
;   - Card initialisation: CMD0/CMD8/ACMD41/CMD2/CMD3 (`uxfs_sdhci_card_init`)
;   - Command issue with response handling (`uxfs_sdhci_send_cmd`)
;   - ADMA2 descriptor table construction (`uxfs_sdhci_build_adma2_desc`)
;   - Multi-block read and write (`uxfs_sdhci_read/write_sectors`)
;
; Two details drive most of the complexity here.
;
; First, addressing. Standard-capacity (SDSC) cards take a BYTE offset in the
; command argument; high-capacity (SDHC/SDXC) cards take a BLOCK index. Sending
; a byte offset to an SDHC card silently addresses the wrong place, so the
; capacity class discovered during ACMD41 has to be remembered and applied on
; every transfer.
;
; Second, ACMD41 is a polling loop, not a single command. The card reports busy
; until its internal power-up completes, and the host must keep asking while
; advertising the voltage range it can supply. The HCS bit in that argument is
; what tells the card high-capacity mode is acceptable.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

; SDHCI register offsets from the controller's MMIO base.
%define SDHCI_REG_SDMA_ADDR         0x00
%define SDHCI_REG_BLOCK_SIZE        0x04
%define SDHCI_REG_BLOCK_COUNT       0x06
%define SDHCI_REG_ARGUMENT          0x08
%define SDHCI_REG_TRANSFER_MODE     0x0C
%define SDHCI_REG_COMMAND           0x0E
%define SDHCI_REG_RESPONSE          0x10
%define SDHCI_REG_PRESENT_STATE     0x24
%define SDHCI_REG_HOST_CONTROL      0x28
%define SDHCI_REG_POWER_CONTROL     0x29
%define SDHCI_REG_CLOCK_CONTROL     0x2C
%define SDHCI_REG_SOFTWARE_RESET    0x2F
%define SDHCI_REG_INT_STATUS        0x30
%define SDHCI_REG_INT_ENABLE        0x34
%define SDHCI_REG_ADMA_SYS_ADDR     0x58

; ADMA2 descriptor attribute bits.
%define ADMA2_F_VALID               0x01
%define ADMA2_F_END                 0x02
%define ADMA2_F_INT                 0x04
%define ADMA2_F_ACT_TRAN            0x20

; Present-state bits.
%define SDHCI_STATE_CMD_INHIBIT     0x00000001
%define SDHCI_STATE_DAT_INHIBIT     0x00000002

; Interrupt-status bits.
%define SDHCI_INT_CMD_COMPLETE      0x00000001
%define SDHCI_INT_XFER_COMPLETE     0x00000002
%define SDHCI_INT_ERROR             0x00008000

; Software reset bits.
%define SDHCI_RESET_ALL             0x01
%define SDHCI_RESET_CMD             0x02
%define SDHCI_RESET_DATA            0x04

; Clock control bits.
%define SDHCI_CLOCK_INT_EN          0x0001
%define SDHCI_CLOCK_INT_STABLE      0x0002
%define SDHCI_CLOCK_CARD_EN         0x0004

; Transfer mode bits.
%define SDHCI_TRNS_DMA              0x01
%define SDHCI_TRNS_BLK_CNT_EN       0x02
%define SDHCI_TRNS_AUTO_CMD12       0x04
%define SDHCI_TRNS_READ             0x10
%define SDHCI_TRNS_MULTI            0x20

; Command response types, encoded into the command register.
%define SDHCI_CMD_RESP_NONE         0x00
%define SDHCI_CMD_RESP_LONG         0x01
%define SDHCI_CMD_RESP_SHORT        0x02
%define SDHCI_CMD_DATA_PRESENT      0x20

; SD commands.
%define SD_CMD_GO_IDLE              0
%define SD_CMD_ALL_SEND_CID         2
%define SD_CMD_SEND_RELATIVE_ADDR   3
%define SD_CMD_SELECT_CARD          7
%define SD_CMD_SEND_IF_COND         8
%define SD_CMD_SET_BLOCKLEN         16
%define SD_CMD_READ_MULTIPLE        18
%define SD_CMD_WRITE_MULTIPLE       25
%define SD_CMD_APP_CMD              55
%define SD_ACMD_SEND_OP_COND        41

%define SD_OCR_HCS                  0x40000000  ; Host supports high capacity
%define SD_OCR_BUSY                 0x80000000  ; Clear while card powers up
%define SD_OCR_CCS                  0x40000000  ; Card is high capacity
%define SD_VOLTAGE_WINDOW           0x00FF8000  ; 2.7V - 3.6V

%define SDHCI_TIMEOUT               0x00400000
%define SDHCI_MAX_ADMA_DESC         64
%define SDHCI_SECTOR_SIZE           512

struc uxfs_sdhci_adma2_desc_t
    .attribute:         resw 1      ; VALID / END / INT / ACT
    .length:            resw 1      ; Byte length, 0 means 65536
    .phys_addr:         resq 1      ; 64-bit physical buffer address
endstruc

section .data
align 64

global uxfs_sdhci_base
uxfs_sdhci_base:        dq 0        ; Controller MMIO base
uxfs_sdhci_rca:         dd 0        ; Relative card address from CMD3
uxfs_sdhci_high_cap:    dd 0        ; Non-zero when the card is SDHC/SDXC

align 64
uxfs_sdhci_adma_table:
    times SDHCI_MAX_ADMA_DESC * uxfs_sdhci_adma2_desc_t_size db 0

uxfs_sdhci_cmd_errors:  dq 0
uxfs_sdhci_transfers:   dq 0

section .text

global uxfs_sdhci_init
global uxfs_sdhci_card_init
global uxfs_sdhci_send_cmd
global uxfs_sdhci_build_adma2_desc
global uxfs_sdhci_read_sectors
global uxfs_sdhci_write_sectors
global uxfs_sdhci_wait_ready

; -----------------------------------------------------------------------------
; uxfs_sdhci_wait_ready
;
; Spins until neither the command nor the data line is inhibited.
;
; Inputs:
;   EDI = Inhibit bits to wait on
;
; Returns:
;   EAX = 0 when clear, POSIX_EIO on timeout
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_wait_ready:
    push rbx
    push r12

    mov r12d, edi
    mov rbx, SDHCI_TIMEOUT
    mov rdx, [uxfs_sdhci_base]
    add rdx, SDHCI_REG_PRESENT_STATE

.wr_poll:
    mov eax, dword [rdx]
    test eax, r12d
    jz .wr_ready

    pause
    dec rbx
    jnz .wr_poll

    mov eax, POSIX_EIO
    pop r12
    pop rbx
    ret

.wr_ready:
    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_sdhci_init
;
; Resets the controller, enables the internal clock, and powers the bus.
;
; Inputs:
;   RDI = Controller MMIO base address
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on timeout
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_init:
    push rbx
    push r12

    test rdi, rdi
    jz .si_inval
    mov [uxfs_sdhci_base], rdi
    mov rbx, rdi

    ; Full software reset.
    mov byte [rbx + SDHCI_REG_SOFTWARE_RESET], SDHCI_RESET_ALL

    mov r12, SDHCI_TIMEOUT
.si_reset_wait:
    mov al, byte [rbx + SDHCI_REG_SOFTWARE_RESET]
    test al, SDHCI_RESET_ALL
    jz .si_reset_done
    pause
    dec r12
    jnz .si_reset_wait
    jmp .si_timeout

.si_reset_done:
    ; Enable the internal clock and wait for it to stabilise. Driving the card
    ; before the PLL locks produces intermittent command timeouts.
    mov word [rbx + SDHCI_REG_CLOCK_CONTROL], SDHCI_CLOCK_INT_EN

    mov r12, SDHCI_TIMEOUT
.si_clock_wait:
    mov ax, word [rbx + SDHCI_REG_CLOCK_CONTROL]
    test ax, SDHCI_CLOCK_INT_STABLE
    jnz .si_clock_ok
    pause
    dec r12
    jnz .si_clock_wait
    jmp .si_timeout

.si_clock_ok:
    mov ax, word [rbx + SDHCI_REG_CLOCK_CONTROL]
    or ax, SDHCI_CLOCK_CARD_EN
    mov word [rbx + SDHCI_REG_CLOCK_CONTROL], ax

    ; Bus power on at 3.3V.
    mov byte [rbx + SDHCI_REG_POWER_CONTROL], 0x0F

    ; Unmask the completion and error interrupts we poll on.
    mov dword [rbx + SDHCI_REG_INT_ENABLE], 0xFFFFFFFF

    mov dword [uxfs_sdhci_rca], 0
    mov dword [uxfs_sdhci_high_cap], 0

    xor eax, eax
    pop r12
    pop rbx
    ret

.si_timeout:
    mov eax, POSIX_EIO
    pop r12
    pop rbx
    ret

.si_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_sdhci_send_cmd
;
; Issues one command and waits for completion.
;
; Inputs:
;   EDI = Command index
;   ESI = 32-bit argument
;   EDX = Response type and data flags (SDHCI_CMD_*)
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on error or timeout
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_send_cmd:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi                   ; Command index
    mov r13d, esi                   ; Argument
    mov r14d, edx                   ; Flags

    mov rbx, [uxfs_sdhci_base]
    test rbx, rbx
    jz .sc_inval

    ; Both lines must be idle before a new command is accepted.
    mov edi, SDHCI_STATE_CMD_INHIBIT | SDHCI_STATE_DAT_INHIBIT
    call uxfs_sdhci_wait_ready
    test eax, eax
    jnz .sc_fail

    ; Clear stale status so the poll below sees only this command.
    mov dword [rbx + SDHCI_REG_INT_STATUS], 0xFFFFFFFF

    mov dword [rbx + SDHCI_REG_ARGUMENT], r13d

    ; Command register: index in bits 8..13, flags in the low byte.
    mov eax, r12d
    shl eax, 8
    or eax, r14d
    mov word [rbx + SDHCI_REG_COMMAND], ax

    ; Wait for command completion.
    mov r12, SDHCI_TIMEOUT
.sc_wait:
    mov eax, dword [rbx + SDHCI_REG_INT_STATUS]
    test eax, SDHCI_INT_ERROR
    jnz .sc_fail
    test eax, SDHCI_INT_CMD_COMPLETE
    jnz .sc_done
    pause
    dec r12
    jnz .sc_wait
    jmp .sc_fail

.sc_done:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.sc_fail:
    inc qword [uxfs_sdhci_cmd_errors]
    mov eax, POSIX_EIO
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.sc_inval:
    mov eax, POSIX_EINVAL
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_sdhci_card_init
;
; Runs the card identification sequence and records the capacity class.
;
; Returns:
;   EAX = 0 on success, POSIX_ENODEV when no card responds
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_card_init:
    push rbx
    push r12
    push r13

    mov rbx, [uxfs_sdhci_base]
    test rbx, rbx
    jz .ci_inval

    ; CMD0: reset the card to idle.
    mov edi, SD_CMD_GO_IDLE
    xor esi, esi
    mov edx, SDHCI_CMD_RESP_NONE
    call uxfs_sdhci_send_cmd

    ; CMD8: advertise 2.7-3.6V and a check pattern. A card that answers is
    ; v2.0 or later and may be high capacity.
    mov edi, SD_CMD_SEND_IF_COND
    mov esi, 0x000001AA
    mov edx, SDHCI_CMD_RESP_SHORT
    call uxfs_sdhci_send_cmd

    ; ACMD41 loop: keep asking until the card clears its busy bit.
    mov r12, SDHCI_TIMEOUT

.ci_acmd41:
    mov edi, SD_CMD_APP_CMD         ; CMD55 prefixes every ACMD
    xor esi, esi
    mov edx, SDHCI_CMD_RESP_SHORT
    call uxfs_sdhci_send_cmd
    test eax, eax
    jnz .ci_nodev

    mov edi, SD_ACMD_SEND_OP_COND
    mov esi, SD_OCR_HCS | SD_VOLTAGE_WINDOW
    mov edx, SDHCI_CMD_RESP_SHORT
    call uxfs_sdhci_send_cmd
    test eax, eax
    jnz .ci_nodev

    mov r13d, dword [rbx + SDHCI_REG_RESPONSE]
    test r13d, SD_OCR_BUSY
    jnz .ci_powered                 ; Busy bit set means power-up finished

    pause
    dec r12
    jnz .ci_acmd41
    jmp .ci_nodev

.ci_powered:
    ; CCS distinguishes SDHC/SDXC (block addressing) from SDSC (byte).
    xor eax, eax
    test r13d, SD_OCR_CCS
    jz .ci_store_cap
    mov eax, 1
.ci_store_cap:
    mov dword [uxfs_sdhci_high_cap], eax

    ; CMD2: fetch the CID.
    mov edi, SD_CMD_ALL_SEND_CID
    xor esi, esi
    mov edx, SDHCI_CMD_RESP_LONG
    call uxfs_sdhci_send_cmd

    ; CMD3: obtain the relative card address used to address the card.
    mov edi, SD_CMD_SEND_RELATIVE_ADDR
    xor esi, esi
    mov edx, SDHCI_CMD_RESP_SHORT
    call uxfs_sdhci_send_cmd
    test eax, eax
    jnz .ci_nodev

    mov eax, dword [rbx + SDHCI_REG_RESPONSE]
    shr eax, 16                     ; RCA occupies the upper 16 bits
    mov dword [uxfs_sdhci_rca], eax

    ; CMD7: select the card, moving it to the transfer state.
    mov edi, SD_CMD_SELECT_CARD
    mov esi, eax
    shl esi, 16
    mov edx, SDHCI_CMD_RESP_SHORT
    call uxfs_sdhci_send_cmd

    ; CMD16: fix the block length at 512 bytes. High-capacity cards ignore
    ; this but standard-capacity ones need it.
    mov edi, SD_CMD_SET_BLOCKLEN
    mov esi, SDHCI_SECTOR_SIZE
    mov edx, SDHCI_CMD_RESP_SHORT
    call uxfs_sdhci_send_cmd

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.ci_nodev:
    mov eax, POSIX_ENODEV
    pop r13
    pop r12
    pop rbx
    ret

.ci_inval:
    mov eax, POSIX_EINVAL
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_sdhci_build_adma2_desc
;
; Builds an ADMA2 descriptor chain over a physically contiguous buffer.
;
; ADMA2 caps each descriptor at 65536 bytes, so longer transfers are split
; across several entries with only the last carrying the END flag. A chain
; without END runs off the table into whatever follows it in memory.
;
; Inputs:
;   RDI = Physical buffer address
;   RSI = Total byte length
;
; Returns:
;   RAX = Descriptor count, or POSIX_ENOSPC when the table is too small
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_build_adma2_desc:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Running physical address
    mov r12, rsi                    ; Remaining bytes
    xor r13, r13                    ; Descriptor index

    test r12, r12
    jz .bd_inval

.bd_loop:
    test r12, r12
    jz .bd_terminate

    cmp r13, SDHCI_MAX_ADMA_DESC
    jae .bd_nospc

    mov rax, r13
    imul rax, uxfs_sdhci_adma2_desc_t_size
    lea r14, [uxfs_sdhci_adma_table]
    add r14, rax

    ; Clamp this entry to the 64KB ADMA2 maximum.
    mov rcx, r12
    cmp rcx, 65536
    jbe .bd_have_len
    mov rcx, 65536

.bd_have_len:
    mov [r14 + uxfs_sdhci_adma2_desc_t.phys_addr], rbx
    ; A length field of 0 encodes 65536 in ADMA2.
    mov eax, ecx
    cmp ecx, 65536
    jne .bd_store_len
    xor eax, eax
.bd_store_len:
    mov word [r14 + uxfs_sdhci_adma2_desc_t.length], ax
    mov word [r14 + uxfs_sdhci_adma2_desc_t.attribute], ADMA2_F_VALID | ADMA2_F_ACT_TRAN

    add rbx, rcx
    sub r12, rcx
    inc r13
    jmp .bd_loop

.bd_terminate:
    ; Mark the last descriptor as the end of the chain.
    test r13, r13
    jz .bd_inval

    mov rax, r13
    dec rax
    imul rax, uxfs_sdhci_adma2_desc_t_size
    lea r14, [uxfs_sdhci_adma_table]
    add r14, rax
    or word [r14 + uxfs_sdhci_adma2_desc_t.attribute], ADMA2_F_END | ADMA2_F_INT

    mov rax, r13
    jmp .bd_return

.bd_nospc:
    mov rax, POSIX_ENOSPC
    jmp .bd_return

.bd_inval:
    mov rax, POSIX_EINVAL

.bd_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_sdhci_transfer
;
; Shared read/write path: programs ADMA2, block geometry and transfer mode.
;
; Inputs:
;   RDI = Starting 512-byte sector
;   RSI = Physical buffer
;   RDX = Sector count
;   ECX = Non-zero for read, zero for write
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on failure
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_transfer:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; Sector
    mov r13, rsi                    ; Buffer
    mov r14, rdx                    ; Sector count
    mov r15d, ecx                   ; Direction

    mov rbx, [uxfs_sdhci_base]
    test rbx, rbx
    jz .tr_inval
    test r14, r14
    jz .tr_inval

    ; Build the scatter-gather chain.
    mov rdi, r13
    mov rsi, r14
    shl rsi, 9                      ; Sectors -> bytes
    call uxfs_sdhci_build_adma2_desc
    test rax, rax
    js .tr_fail

    lea rax, [uxfs_sdhci_adma_table]
    mov [rbx + SDHCI_REG_ADMA_SYS_ADDR], rax

    mov word [rbx + SDHCI_REG_BLOCK_SIZE], SDHCI_SECTOR_SIZE
    mov word [rbx + SDHCI_REG_BLOCK_COUNT], r14w

    ; Transfer mode: DMA, counted, multi-block, with AUTO CMD12 to issue the
    ; stop-transmission the card expects after a multi-block operation.
    mov ax, SDHCI_TRNS_DMA | SDHCI_TRNS_BLK_CNT_EN | SDHCI_TRNS_MULTI | SDHCI_TRNS_AUTO_CMD12
    test r15d, r15d
    jz .tr_mode
    or ax, SDHCI_TRNS_READ

.tr_mode:
    mov word [rbx + SDHCI_REG_TRANSFER_MODE], ax

    ; High-capacity cards address by block; standard-capacity by byte.
    mov rsi, r12
    cmp dword [uxfs_sdhci_high_cap], 0
    jne .tr_arg
    shl rsi, 9                      ; Byte offset for SDSC

.tr_arg:
    mov edi, SD_CMD_READ_MULTIPLE
    test r15d, r15d
    jnz .tr_cmd
    mov edi, SD_CMD_WRITE_MULTIPLE

.tr_cmd:
    mov edx, SDHCI_CMD_RESP_SHORT | SDHCI_CMD_DATA_PRESENT
    call uxfs_sdhci_send_cmd
    test eax, eax
    jnz .tr_fail

    ; Wait for the data phase, not just the command phase, to finish.
    mov r12, SDHCI_TIMEOUT
.tr_wait:
    mov eax, dword [rbx + SDHCI_REG_INT_STATUS]
    test eax, SDHCI_INT_ERROR
    jnz .tr_fail
    test eax, SDHCI_INT_XFER_COMPLETE
    jnz .tr_done
    pause
    dec r12
    jnz .tr_wait
    jmp .tr_fail

.tr_done:
    inc qword [uxfs_sdhci_transfers]
    xor eax, eax
    jmp .tr_return

.tr_fail:
    mov eax, POSIX_EIO
    jmp .tr_return

.tr_inval:
    mov eax, POSIX_EINVAL

.tr_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_sdhci_read_sectors
;
; Inputs:
;   RDI = Starting 512-byte sector
;   RSI = Physical destination buffer
;   RDX = Sector count
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on failure
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_read_sectors:
    mov ecx, 1                      ; Read
    jmp uxfs_sdhci_transfer

; -----------------------------------------------------------------------------
; uxfs_sdhci_write_sectors
;
; Inputs:
;   RDI = Starting 512-byte sector
;   RSI = Physical source buffer
;   RDX = Sector count
;
; Returns:
;   EAX = 0 on success, POSIX_EIO on failure
; -----------------------------------------------------------------------------
align 32
uxfs_sdhci_write_sectors:
    xor ecx, ecx                    ; Write
    jmp uxfs_sdhci_transfer
