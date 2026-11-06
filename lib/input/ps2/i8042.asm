; =============================================================================
; Utkarsha OS — lib/input/ps2/i8042.asm
; =============================================================================
; The PS/2 controller (i8042): ports 0x60 (data) and 0x64 (status and
; commands), keyboard on the first port, IRQ 1.
;
; Phase 1 uses the fixed legacy ports and IRQ; ACPI resources replace them
; once lib/io/acpi has its AML interpreter (ROADMAP.md, decision I1).
; The controller translates the keyboard's scan code set 2 into set 1, which
; is what ps2/kbd.asm decodes. The second (mouse) port stays off until
; Phase 4; bytes from it are dropped.
; =============================================================================

%ifndef LIB_INPUT_PS2_I8042_ASM
%define LIB_INPUT_PS2_I8042_ASM

%define I8042_DATA          0x60
%define I8042_STATUS        0x64    ; read
%define I8042_CMD           0x64    ; write

%define I8042_ST_OBF        (1 << 0)    ; a byte waits in the output buffer
%define I8042_ST_IBF        (1 << 1)    ; the controller has not taken our byte
%define I8042_ST_AUX        (1 << 5)    ; the byte came from the second port
%define I8042_ST_ERRORS     0xC0        ; timeout, parity

%define I8042_CMD_READ_CFG  0x20
%define I8042_CMD_WRITE_CFG 0x60
%define I8042_CMD_AUX_OFF   0xA7
%define I8042_CMD_SELFTEST  0xAA
%define I8042_CMD_KBD_TEST  0xAB
%define I8042_CMD_KBD_OFF   0xAD
%define I8042_CMD_KBD_ON    0xAE

%define I8042_CFG_KBD_IRQ   (1 << 0)
%define I8042_CFG_AUX_IRQ   (1 << 1)
%define I8042_CFG_KBD_CLKOFF (1 << 4)
%define I8042_CFG_XLATE     (1 << 6)

%define I8042_SELFTEST_OK   0x55

; Status polls before giving up. A poll is one port read, about a
; microsecond on real hardware, so this is roughly 200 ms.
%define I8042_SPIN          200000

section .bss
alignb 4
global i8042_present
i8042_present:      resd 1
global i8042_errors
i8042_errors:       resd 1              ; bytes with timeout or parity errors
global i8042_aux_bytes
i8042_aux_bytes:    resd 1              ; bytes from the second port, dropped
i8042_cfg:          resd 1              ; configuration byte as last written

section .text

; -----------------------------------------------------------------------------
; i8042_wait_write — wait until the controller can take a byte
; Output: CF = 1 on timeout
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
i8042_wait_write:
    push rbx
    mov ebx, I8042_SPIN
.poll:
    mov edi, I8042_STATUS
    call input_inb
    test al, I8042_ST_IBF
    jz .ready
    dec ebx
    jnz .poll
    pop rbx
    stc
    ret
.ready:
    pop rbx
    clc
    ret

; -----------------------------------------------------------------------------
; i8042_read — wait for a byte and read it
; Input:  ESI = polls to wait (I8042_SPIN for most replies)
; Output: EAX = the byte; CF = 1 on timeout
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global i8042_read
i8042_read:
    push rbx
    mov ebx, esi
.poll:
    mov edi, I8042_STATUS
    call input_inb
    test al, I8042_ST_OBF
    jnz .ready
    dec ebx
    jnz .poll
    pop rbx
    stc
    ret
.ready:
    mov edi, I8042_DATA
    call input_inb
    pop rbx
    clc
    ret

; -----------------------------------------------------------------------------
; i8042_command — send a controller command
; Input:  EDI = command
; Output: CF = 1 on timeout
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global i8042_command
i8042_command:
    push rbx
    mov ebx, edi
    call i8042_wait_write
    jc .out
    mov edi, I8042_CMD
    mov esi, ebx
    call input_outb
    clc
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i8042_write_data — send a byte to the keyboard (or a command's argument)
; Input:  EDI = byte
; Output: CF = 1 on timeout
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global i8042_write_data
i8042_write_data:
    push rbx
    mov ebx, edi
    call i8042_wait_write
    jc .out
    mov edi, I8042_DATA
    mov esi, ebx
    call input_outb
    clc
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i8042_flush — throw away whatever waits in the output buffer
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
i8042_flush:
    push rbx
    mov ebx, 32                         ; the buffer is far smaller
.poll:
    mov edi, I8042_STATUS
    call input_inb
    test al, I8042_ST_OBF
    jz .done
    mov edi, I8042_DATA
    call input_inb
    dec ebx
    jnz .poll
.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i8042_write_cfg — write the configuration byte
; Input:  EDI = the byte
; Output: CF = 1 on timeout
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
i8042_write_cfg:
    push rbx
    mov ebx, edi
    mov [rel i8042_cfg], edi
    mov edi, I8042_CMD_WRITE_CFG
    call i8042_command
    jc .out
    mov edi, ebx
    call i8042_write_data
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i8042_init — find and reset the controller; leave the keyboard port on
;              with its interrupt off
; Output: EAX = 0; -INPUT_ENODEV with no controller or no keyboard port;
;         -INPUT_EIO when the controller fails its self-test
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global i8042_init
i8042_init:
    push rbx
    mov dword [rel i8042_present], 0
    mov dword [rel i8042_errors], 0
    mov dword [rel i8042_aux_bytes], 0

    ; A missing controller reads as all ones
    mov edi, I8042_STATUS
    call input_inb
    cmp al, 0xFF
    je .absent

    ; Both ports off while we set up, and nothing left over
    mov edi, I8042_CMD_KBD_OFF
    call i8042_command
    jc .absent
    mov edi, I8042_CMD_AUX_OFF
    call i8042_command
    jc .absent
    call i8042_flush

    ; Configuration: interrupts off, translation on
    mov edi, I8042_CMD_READ_CFG
    call i8042_command
    jc .absent
    mov esi, I8042_SPIN
    call i8042_read
    jc .absent
    and eax, ~(I8042_CFG_KBD_IRQ | I8042_CFG_AUX_IRQ)
    or eax, I8042_CFG_XLATE
    mov ebx, eax
    mov edi, eax
    call i8042_write_cfg
    jc .absent

    ; Self-test. Some controllers reset their configuration during it, so
    ; it is written again afterwards.
    mov edi, I8042_CMD_SELFTEST
    call i8042_command
    jc .absent
    mov esi, I8042_SPIN
    call i8042_read
    jc .absent
    cmp al, I8042_SELFTEST_OK
    jne .failed
    mov edi, ebx
    call i8042_write_cfg
    jc .absent

    ; The keyboard port's own test: 0 means the lines are fine
    mov edi, I8042_CMD_KBD_TEST
    call i8042_command
    jc .absent
    mov esi, I8042_SPIN
    call i8042_read
    jc .absent
    test al, al
    jnz .absent

    mov edi, I8042_CMD_KBD_ON
    call i8042_command
    jc .absent

    mov dword [rel i8042_present], 1
    xor eax, eax
    pop rbx
    ret
.absent:
    mov eax, -INPUT_ENODEV
    pop rbx
    ret
.failed:
    mov eax, -INPUT_EIO
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i8042_irq_enable — let the keyboard port raise IRQ 1
; Call after the interrupt is routed, so no byte arrives unannounced.
; Output: CF = 1 on timeout
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global i8042_irq_enable
i8042_irq_enable:
    mov edi, [rel i8042_cfg]
    or edi, I8042_CFG_KBD_IRQ
    and edi, ~I8042_CFG_KBD_CLKOFF
    jmp i8042_write_cfg

; -----------------------------------------------------------------------------
; i8042_irq — the IRQ 1 work: read every waiting byte and decode it
; Called from the interrupt handler (lib/input/kernel.asm) or by a poll.
; Output: EAX = bytes read
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global i8042_irq
i8042_irq:
    push rbx
    push r12
    sub rsp, 8
    xor r12d, r12d
    mov ebx, 16                         ; bounded: a stuck bit cannot hang us
.next:
    mov edi, I8042_STATUS
    call input_inb
    test al, I8042_ST_OBF
    jz .done
    mov [rsp], al
    mov edi, I8042_DATA
    call input_inb
    inc r12d
    mov cl, [rsp]
    test cl, I8042_ST_ERRORS
    jnz .error
    test cl, I8042_ST_AUX
    jnz .aux
    mov edi, eax
    call ps2_kbd_byte
    jmp .more
.error:
    inc dword [rel i8042_errors]
    jmp .more
.aux:
    inc dword [rel i8042_aux_bytes]
.more:
    dec ebx
    jnz .next
.done:
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

%endif ; LIB_INPUT_PS2_I8042_ASM
