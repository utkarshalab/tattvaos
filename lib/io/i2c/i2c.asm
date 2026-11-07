; =============================================================================
; Utkarsha OS — lib/io/i2c/i2c.asm
; =============================================================================
; I2C host controllers with the DesignWare core: AMD (ACPI AMDI0010 and
; relatives) and, later, Intel LPSS.
;
;   i2c_dw_attach(base, clock_khz)              a controller → its number
;   i2c_dw_set_speed(ctrl, hz, hcnt, lcnt, hold) bus speed and timing
;   i2c_xfer(ctrl, msgs, count)                 one transfer
;   i2c_write_read(ctrl, addr, wbuf, wlen, rbuf, rlen)
;                                               the usual register read
;
; Transfers are polled: the caller waits for the stop, so this runs on a
; fiber, never in an interrupt. All messages of a transfer go to one target
; and are joined by repeated starts. Every wait is bounded.
;
; Timing comes from ACPI where the firmware gives it (the controller's
; SSCN, FMCN methods); otherwise it is worked out from the controller's
; input clock and the minimum high and low times of the bus speed.
;
; Register access goes through i2c_read32_fn and i2c_write32_fn, so host
; tests can stand in for the hardware.
; =============================================================================

%ifndef LIB_IO_I2C_I2C_ASM
%define LIB_IO_I2C_I2C_ASM

%include "lib/io/i2c/i2c.inc"

; DesignWare registers
%define DW_CON              0x00
%define DW_TAR              0x04
%define DW_DATA_CMD         0x10
%define DW_SS_HCNT          0x14
%define DW_SS_LCNT          0x18
%define DW_FS_HCNT          0x1C
%define DW_FS_LCNT          0x20
%define DW_INTR_MASK        0x30
%define DW_RAW_INTR         0x34
%define DW_CLR_INTR         0x40
%define DW_CLR_TX_ABRT      0x54
%define DW_CLR_STOP_DET     0x60
%define DW_ENABLE           0x6C
%define DW_STATUS           0x70
%define DW_SDA_HOLD         0x7C
%define DW_ABRT_SOURCE      0x80
%define DW_ENABLE_STATUS    0x9C
%define DW_COMP_PARAM_1     0xF4
%define DW_COMP_TYPE        0xFC

%define DW_TYPE             0x44570140  ; "DW" and the component number

%define DW_CON_MASTER       (1 << 0)
%define DW_CON_SPEED_SHIFT  1           ; 1 standard, 2 fast, 3 high
%define DW_CON_10BIT_MASTER (1 << 4)
%define DW_CON_RESTART_EN   (1 << 5)
%define DW_CON_SLAVE_OFF    (1 << 6)
%define DW_TAR_10BIT        (1 << 12)

%define DW_CMD_READ         (1 << 8)
%define DW_CMD_STOP         (1 << 9)
%define DW_CMD_RESTART      (1 << 10)

%define DW_ST_ACTIVITY      (1 << 0)
%define DW_ST_TFNF          (1 << 1)    ; transmit FIFO not full
%define DW_ST_RFNE          (1 << 3)    ; receive FIFO not empty
%define DW_ST_MST_ACTIVITY  (1 << 5)

%define DW_INTR_TX_ABRT     (1 << 6)
%define DW_INTR_STOP_DET    (1 << 9)

%define DW_ABRT_ADDR_NACK   0x07        ; 7-bit, 10-bit first and second byte

; register polls before giving up; a poll is one register read, about a
; microsecond on real hardware
%define I2C_SPIN            200000

section .data
align 8
global i2c_read32_fn
i2c_read32_fn:      dq i2c_mmio_read32  ; RDI = address → EAX
global i2c_write32_fn
i2c_write32_fn:     dq i2c_mmio_write32 ; RDI = address, ESI = value

section .bss
alignb 8
i2c_base:           resq I2C_MAX_CTRL
i2c_clock_khz:      resd I2C_MAX_CTRL
i2c_speed:          resd I2C_MAX_CTRL   ; DW_CON speed code
i2c_used:           resd I2C_MAX_CTRL
global i2c_aborts
i2c_aborts:         resd 1              ; transfers aborted by the bus
global i2c_timeouts
i2c_timeouts:       resd 1
global i2c_last_abort
i2c_last_abort:     resd 1              ; the last abort source register

section .text

i2c_mmio_read32:
    mov eax, [rdi]
    ret

i2c_mmio_write32:
    mov [rdi], esi
    ret

; -----------------------------------------------------------------------------
; i2c_rd, i2c_wr — a register of the controller whose base is in R15
; i2c_rd: EDI = offset → EAX.  i2c_wr: EDI = offset, ESI = value.
; Clobber the caller-saved registers.
; -----------------------------------------------------------------------------
i2c_rd:
    add rdi, r15
    mov rax, [rel i2c_read32_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    ret

i2c_wr:
    add rdi, r15
    mov rax, [rel i2c_write32_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; i2c_detach_all — forget every controller (start-up and tests)
; -----------------------------------------------------------------------------
global i2c_detach_all
i2c_detach_all:
    lea rcx, [rel i2c_used]
    xor eax, eax
    mov [rcx], eax
    mov [rcx + 4], eax
    mov [rcx + 8], eax
    mov [rcx + 12], eax
    mov [rel i2c_aborts], eax
    mov [rel i2c_timeouts], eax
    mov [rel i2c_last_abort], eax
    ret

; -----------------------------------------------------------------------------
; i2c_dw_attach — add a DesignWare controller
; Input:  RDI = register base (mapped), ESI = its input clock in kHz (0 if
;         unknown: timing must then come from ACPI)
; Output: EAX = controller number; -I2C_ENODEV when the registers do not
;         identify a DesignWare controller; -I2C_ENOSPC; -I2C_EINVAL
; The bus starts at 400 kHz when the clock is known.
; -----------------------------------------------------------------------------
global i2c_dw_attach
i2c_dw_attach:
    push rbx
    push r12
    push r15
    test rdi, rdi
    jz .invalid
    mov r15, rdi
    mov r12d, esi
    mov edi, DW_COMP_TYPE
    call i2c_rd
    cmp eax, DW_TYPE
    jne .nodev
    lea rcx, [rel i2c_used]
    xor ebx, ebx
.slot:
    cmp ebx, I2C_MAX_CTRL
    jae .full
    cmp dword [rcx + rbx * 4], 0
    je .free
    inc ebx
    jmp .slot
.free:
    mov dword [rcx + rbx * 4], 1
    lea rcx, [rel i2c_base]
    mov [rcx + rbx * 8], r15
    lea rcx, [rel i2c_clock_khz]
    mov [rcx + rbx * 4], r12d
    lea rcx, [rel i2c_speed]
    mov dword [rcx + rbx * 4], 2
    test r12d, r12d
    jz .done
    mov edi, ebx
    mov esi, 400000
    xor edx, edx
    xor ecx, ecx
    xor r8d, r8d
    call i2c_dw_set_speed
.done:
    mov eax, ebx
    jmp .out
.invalid:
    mov eax, -I2C_EINVAL
    jmp .out
.nodev:
    mov eax, -I2C_ENODEV
    jmp .out
.full:
    mov eax, -I2C_ENOSPC
.out:
    pop r15
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i2c_ctrl — a controller's base into R15
; Input:  EDI = controller
; Output: CF = 0 with R15 = base; CF = 1 when there is no such controller
; Clobbers: RCX
; -----------------------------------------------------------------------------
i2c_ctrl:
    cmp edi, I2C_MAX_CTRL
    jae .bad
    lea rcx, [rel i2c_used]
    cmp dword [rcx + rdi * 4], 0
    je .bad
    lea rcx, [rel i2c_base]
    mov r15, [rcx + rdi * 8]
    clc
    ret
.bad:
    stc
    ret

; -----------------------------------------------------------------------------
; i2c_disable — turn the controller off and wait until it is
; Output: CF = 1 on timeout
; Needs R15. Clobbers the caller-saved registers.
; -----------------------------------------------------------------------------
i2c_disable:
    push rbx
    xor esi, esi
    mov edi, DW_ENABLE
    call i2c_wr
    mov ebx, I2C_SPIN
.poll:
    mov edi, DW_ENABLE_STATUS
    call i2c_rd
    test eax, 1
    jz .off
    dec ebx
    jnz .poll
    pop rbx
    stc
    ret
.off:
    pop rbx
    clc
    ret

; -----------------------------------------------------------------------------
; i2c_dw_set_speed — bus speed and timing
; Input:  EDI = controller, ESI = speed in Hz (up to 1 MHz),
;         EDX = SCL high count, ECX = SCL low count (both 0: work them out
;         from the input clock), R8D = SDA hold (0: leave it)
; Output: EAX = 0 or -I2C_EINVAL (no controller, too fast, or no clock to
;         work the counts out from)
; -----------------------------------------------------------------------------
global i2c_dw_set_speed
i2c_dw_set_speed:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    push r8
    sub rsp, 8
    call i2c_ctrl
    jc .invalid
    test r12d, r12d
    jz .invalid
    cmp r12d, 1000000
    ja .invalid
    ; standard mode up to 100 kHz, fast (and fast plus) above
    mov eax, 1
    cmp r12d, 100000
    jbe .mode
    mov eax, 2
.mode:
    lea rcx, [rel i2c_speed]
    mov [rcx + rbx * 4], eax
    test r13d, r13d
    jnz .counts
    test r14d, r14d
    jnz .counts
    ; work them out: count = clock (kHz) × minimum time (ns) / 10^6,
    ; less the controller's own delays (7 cycles high, 1 low)
    lea rcx, [rel i2c_clock_khz]
    mov ecx, [rcx + rbx * 4]
    test ecx, ecx
    jz .invalid
    mov r8d, 4000                       ; standard: 4.0 us high, 4.7 us low
    mov r9d, 4700
    cmp r12d, 100000
    jbe .times
    mov r8d, 600                        ; fast: 0.6 us high, 1.3 us low
    mov r9d, 1300
    cmp r12d, 400000
    jbe .times
    mov r8d, 260                        ; fast plus: 0.26 us, 0.5 us
    mov r9d, 500
.times:
    mov eax, ecx
    imul rax, r8
    add rax, 999999
    xor edx, edx
    mov r10d, 1000000
    div r10
    sub eax, 7
    cmp eax, 6
    jge .high_ok
    mov eax, 6
.high_ok:
    mov r13d, eax
    mov eax, ecx
    imul rax, r9
    add rax, 999999
    xor edx, edx
    div r10
    sub eax, 1
    cmp eax, 8
    jge .low_ok
    mov eax, 8
.low_ok:
    mov r14d, eax
.counts:
    call i2c_disable
    jc .invalid
    mov edi, DW_FS_HCNT
    mov edx, DW_FS_LCNT
    lea rcx, [rel i2c_speed]
    cmp dword [rcx + rbx * 4], 1
    jne .write
    mov edi, DW_SS_HCNT
    mov edx, DW_SS_LCNT
.write:
    push rdx
    sub rsp, 8
    mov esi, r13d
    call i2c_wr
    add rsp, 8
    pop rdi
    mov esi, r14d
    call i2c_wr
    mov rax, [rsp + 8]                  ; SDA hold
    test eax, eax
    jz .ok
    mov esi, eax
    mov edi, DW_SDA_HOLD
    call i2c_wr
.ok:
    xor eax, eax
    jmp .out
.invalid:
    mov eax, -I2C_EINVAL
.out:
    add rsp, 8
    pop r8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i2c_xfer — one transfer
; Input:  EDI = controller, RSI = i2c_msg array, EDX = message count
; Output: EAX = 0; -I2C_ENXIO when nobody answers at the address;
;         -I2C_EIO when the transfer is aborted otherwise; -I2C_ETIMEDOUT;
;         -I2C_EINVAL (no controller, no messages, a message with no bytes,
;         messages to different targets)
; -----------------------------------------------------------------------------
global i2c_xfer
i2c_xfer:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 56                 ; [0] read msg, [8] read offset, [16] reads
                                ; left, [24] message index, [32] byte index,
                                ; [40] controller
    mov r12, rsi                ; messages
    mov r13d, edx               ; count
    mov [rsp + 40], rdi
    call i2c_ctrl
    jc .invalid
    test r13d, r13d
    jz .invalid
    test r12, r12
    jz .invalid

    ; all to one target, every message with bytes; count the reads
    movzx ebx, word [r12 + i2c_msg.addr]
    movzx ebp, word [r12 + i2c_msg.flags]
    and ebp, I2C_M_TEN
    xor ecx, ecx
    xor eax, eax                        ; bytes to read
.check:
    cmp ecx, r13d
    jae .checked
    mov rdx, rcx
    shl rdx, 4
    cmp word [r12 + rdx + i2c_msg.addr], bx
    jne .invalid
    movzx r8d, word [r12 + rdx + i2c_msg.flags]
    mov r9d, r8d
    and r9d, I2C_M_TEN
    cmp r9d, ebp
    jne .invalid
    mov r9d, [r12 + rdx + i2c_msg.len]
    test r9d, r9d
    jz .invalid
    test r8d, I2C_M_READ
    jz .next_check
    add eax, r9d
.next_check:
    inc ecx
    jmp .check
.checked:
    mov [rsp + 16], rax

    ; the bus must be idle
    mov r14d, I2C_SPIN
.idle:
    mov edi, DW_STATUS
    call i2c_rd
    test eax, DW_ST_MST_ACTIVITY
    jz .is_idle
    dec r14d
    jnz .idle
    jmp .timeout
.is_idle:
    ; off, set up, on
    call i2c_disable
    jc .timeout
    mov ecx, [rsp + 40]
    lea rax, [rel i2c_speed]
    mov esi, [rax + rcx * 4]
    shl esi, DW_CON_SPEED_SHIFT
    or esi, DW_CON_MASTER | DW_CON_RESTART_EN | DW_CON_SLAVE_OFF
    test ebp, ebp
    jz .con
    or esi, DW_CON_10BIT_MASTER
.con:
    mov edi, DW_CON
    call i2c_wr
    mov esi, ebx
    test ebp, ebp
    jz .tar
    or esi, DW_TAR_10BIT
.tar:
    mov edi, DW_TAR
    call i2c_wr
    xor esi, esi
    mov edi, DW_INTR_MASK               ; polled: no interrupts
    call i2c_wr
    mov esi, 1
    mov edi, DW_ENABLE
    call i2c_wr
    mov edi, DW_CLR_INTR
    call i2c_rd

    ; reads land in the read messages in order
    mov qword [rsp], 0                  ; read message index (searched)
    mov qword [rsp + 8], 0              ; offset in it
    call i2c_next_read_msg              ; first read message

    ; commands, one per byte
    mov qword [rsp + 24], 0             ; message
.msg:
    mov eax, [rsp + 24]
    cmp eax, r13d
    jae .sent
    mov qword [rsp + 32], 0             ; byte
.byte:
    mov rax, [rsp + 24]
    shl rax, 4
    lea r14, [r12 + rax]                ; this message
    mov eax, [rsp + 32]
    cmp eax, [r14 + i2c_msg.len]
    jae .next_msg
    ; room in the FIFO; take what has arrived meanwhile
    mov ebp, I2C_SPIN
.room:
    call i2c_drain
    test eax, eax
    jnz .aborted
    mov edi, DW_STATUS
    call i2c_rd
    test eax, DW_ST_TFNF
    jnz .push
    dec ebp
    jnz .room
    jmp .timeout
.push:
    xor esi, esi
    test word [r14 + i2c_msg.flags], I2C_M_READ
    jnz .read_cmd
    mov rcx, [r14 + i2c_msg.buf]
    mov edx, [rsp + 32]
    movzx esi, byte [rcx + rdx]
    jmp .flags
.read_cmd:
    mov esi, DW_CMD_READ
.flags:
    cmp dword [rsp + 32], 0
    jne .not_first
    cmp dword [rsp + 24], 0
    je .not_first
    or esi, DW_CMD_RESTART              ; a new message: repeated start
.not_first:
    mov eax, [rsp + 32]
    inc eax
    cmp eax, [r14 + i2c_msg.len]
    jne .write_cmd
    mov eax, [rsp + 24]
    inc eax
    cmp eax, r13d
    jne .write_cmd
    or esi, DW_CMD_STOP                 ; the last byte of all
.write_cmd:
    mov edi, DW_DATA_CMD
    call i2c_wr
    inc dword [rsp + 32]
    jmp .byte
.next_msg:
    inc dword [rsp + 24]
    jmp .msg

.sent:
    ; every read byte, then the stop
    mov ebp, I2C_SPIN
.finish:
    call i2c_drain
    test eax, eax
    jnz .aborted
    cmp qword [rsp + 16], 0
    jne .wait
    mov edi, DW_RAW_INTR
    call i2c_rd
    test eax, DW_INTR_STOP_DET
    jnz .done
.wait:
    dec ebp
    jnz .finish
    jmp .timeout
.done:
    mov edi, DW_CLR_STOP_DET
    call i2c_rd
    xor eax, eax
    jmp .out

.aborted:
    ; EAX = the abort source
    mov [rel i2c_last_abort], eax
    inc dword [rel i2c_aborts]
    mov ebx, eax
    mov edi, DW_CLR_TX_ABRT
    call i2c_rd
    mov eax, -I2C_ENXIO
    test ebx, DW_ABRT_ADDR_NACK
    jnz .out
    mov eax, -I2C_EIO
    jmp .out
.timeout:
    inc dword [rel i2c_timeouts]
    call i2c_disable                    ; stop whatever was going on
    mov eax, -I2C_ETIMEDOUT
    jmp .out
.invalid:
    mov eax, -I2C_EINVAL
.out:
    add rsp, 56
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i2c_next_read_msg — move i2c_xfer's read cursor to the first read message
;                     with room left, from the message it points at
; Called from i2c_xfer only: its frame starts one return address up, so
; the cursor is [rsp + 8] (message) and [rsp + 16] (offset) here.
; -----------------------------------------------------------------------------
i2c_next_read_msg:
.find:
    mov rax, [rsp + 8]
    cmp eax, r13d
    jae .none
    mov rcx, rax
    shl rcx, 4
    test word [r12 + rcx + i2c_msg.flags], I2C_M_READ
    jz .skip
    mov edx, [rsp + 16]
    cmp edx, [r12 + rcx + i2c_msg.len]
    jb .out
.skip:
    inc qword [rsp + 8]
    mov qword [rsp + 16], 0
    jmp .find
.none:
.out:
    ret

; -----------------------------------------------------------------------------
; i2c_drain — take received bytes into the read messages; check for abort
; Called from i2c_xfer only: after the PUSH below, its frame starts at
; [rsp + 16]: cursor message, cursor offset, reads left.
; Output: EAX = 0, or the abort source (nonzero) when the controller
;         aborted
; -----------------------------------------------------------------------------
i2c_drain:
    push rbx                            ; frame now 16 bytes away
.check:
    mov edi, DW_RAW_INTR
    call i2c_rd
    test eax, DW_INTR_TX_ABRT
    jnz .abort
    mov edi, DW_STATUS
    call i2c_rd
    test eax, DW_ST_RFNE
    jz .empty
    mov edi, DW_DATA_CMD
    call i2c_rd
    mov ebx, eax
    ; where it goes
    cmp qword [rsp + 16 + 16], 0        ; reads left
    je .check                           ; more than asked for: dropped
    mov rax, [rsp + 16]                 ; read message
    cmp eax, r13d
    jae .check
    shl rax, 4
    mov rcx, [r12 + rax + i2c_msg.buf]
    mov edx, [rsp + 16 + 8]
    mov [rcx + rdx], bl
    inc dword [rsp + 16 + 8]
    dec qword [rsp + 16 + 16]
    ; the message full: on to the next read message
    mov edx, [rsp + 16 + 8]
    cmp edx, [r12 + rax + i2c_msg.len]
    jb .check
.advance:
    inc qword [rsp + 16]
    mov qword [rsp + 16 + 8], 0
    mov rax, [rsp + 16]
    cmp eax, r13d
    jae .check
    shl rax, 4
    test word [r12 + rax + i2c_msg.flags], I2C_M_READ
    jz .advance
    jmp .check
.empty:
    xor eax, eax
    pop rbx
    ret
.abort:
    mov edi, DW_ABRT_SOURCE
    call i2c_rd
    test eax, eax
    jnz .src
    mov eax, 0x80000000                 ; aborted with no source given
.src:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i2c_write_read — write bytes (a register address), then read with a
;                  repeated start; RLEN 0 makes it a plain write
; Input:  EDI = controller, ESI = address, RDX = write buffer, ECX = write
;         length, R8 = read buffer, R9D = read length
; Output: as i2c_xfer
; -----------------------------------------------------------------------------
global i2c_write_read
i2c_write_read:
    sub rsp, 40                         ; two messages, padding
    mov [rsp + i2c_msg.addr], si
    mov word [rsp + i2c_msg.flags], 0
    mov [rsp + i2c_msg.len], ecx
    mov [rsp + i2c_msg.buf], rdx
    mov [rsp + 16 + i2c_msg.addr], si
    mov word [rsp + 16 + i2c_msg.flags], I2C_M_READ
    mov [rsp + 16 + i2c_msg.len], r9d
    mov [rsp + 16 + i2c_msg.buf], r8
    mov edx, 2
    test r9d, r9d
    jnz .two
    mov edx, 1
.two:
    test ecx, ecx
    jnz .go
    ; nothing to write: just the read
    lea rsi, [rsp + 16]
    mov edx, 1
    call i2c_xfer
    add rsp, 40
    ret
.go:
    mov rsi, rsp
    call i2c_xfer
    add rsp, 40
    ret

%endif ; LIB_IO_I2C_I2C_ASM
