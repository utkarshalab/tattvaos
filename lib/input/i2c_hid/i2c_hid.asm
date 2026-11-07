; =============================================================================
; Utkarsha OS — lib/input/i2c_hid/i2c_hid.asm
; =============================================================================
; HID devices on I2C: touchpads, touch screens, keyboards. The protocol:
;   - a 30-byte HID descriptor at a register the device's _DSM names;
;   - commands (reset, power, get and set report) through its command
;     register; input reports read from its input register, each starting
;     with its own length (0: nothing, as after a reset);
;   - an interrupt line, here a GPIO pin, asserted while a report waits.
;
;   i2c_hid_probe(ctrl, addr, desc_reg)   bring a device up → its number
;   i2c_hid_attention(dev)                its interrupt fired (interrupt
;                                         context: only marks it)
;   i2c_hid_service()                     read and turn into events every
;                                         marked device's report (fiber)
;   i2c_hid_set_after(dev, fn, cookie)    called after each service (the
;                                         GPIO glue re-arms the pin there)
;
; Touchpads are switched to multi-touch mode (the Input Mode feature) and
; report every finger as INPUT_TOUCH contacts, one scan ended by a frame
; end, plus the click button. Canvas drops touch records until it routes
; them (its TCH-01), so while i2c_hid_pointer_emulation is 1 the first
; finger also moves the pointer. Mice and touchpads still in mouse mode
; report motion, buttons and the wheel.
;
; Transfers go through i2c_hid_xfer_fn (i2c_write_read in the kernel) and
; waits through i2c_hid_delay_fn, so host tests stand in for both.
; =============================================================================

%ifndef LIB_INPUT_I2C_HID_ASM
%define LIB_INPUT_I2C_HID_ASM

%define I2C_HID_MAX_DEV     2
%define I2C_HID_MAX_FINGERS 10
%define I2C_HID_MAX_SLOTS   32
%define I2C_HID_MAX_REPORT  1024        ; bytes of one input report
%define I2C_HID_MAX_RDESC   4096        ; bytes of the report descriptor
%define I2C_HID_MAX_FEATURE 32          ; bytes of a feature report we set
%define I2C_HID_DESC_LEN    30
%define I2C_HID_RESET_TRIES 50          ; × 10 ms for the reset to finish
%define I2C_HID_EMU_DIV     4           ; device units per pointer step

%define I2C_HID_OP_RESET    0x01
%define I2C_HID_OP_SET_REPORT 0x03
%define I2C_HID_OP_SET_POWER 0x08

%define I2C_HID_TOUCHPAD    1
%define I2C_HID_MOUSE       2

; usages
%define U_X                 0x00010030
%define U_Y                 0x00010031
%define U_WHEEL             0x00010038
%define U_MOUSE             0x00010002
%define U_BUTTON1           0x00090001
%define U_TOUCHPAD          0x000D0005
%define U_TIP               0x000D0042
%define U_CONFIDENCE        0x000D0047
%define U_CONTACT_ID        0x000D0051
%define U_CONTACT_COUNT     0x000D0054
%define U_CONTACT_MAX       0x000D0055
%define U_INPUT_MODE        0x000D0052
%define U_SURFACE_SWITCH    0x000D0057
%define U_BUTTON_SWITCH     0x000D0058
%define INPUT_MODE_TOUCHPAD 3

struc i2c_hid
    .state:         resd 1          ; 0 free, 1 ready
    .ctrl:          resd 1
    .addr:          resd 1
    .pending:       resd 1          ; set by i2c_hid_attention
    .kind:          resd 1          ; I2C_HID_TOUCHPAD, I2C_HID_MOUSE, 0
    .input_dev:     resd 1          ; lib/input device ID
    .report_desc_len: resd 1
    .report_desc_reg: resd 1
    .input_reg:     resd 1
    .max_input:     resd 1
    .command_reg:   resd 1
    .data_reg:      resd 1
    .vendor:        resd 1
    .product:       resd 1
    .after_fn:      resq 1
    .after_cookie:  resq 1
    ; touchpad
    .fingers:       resd 1
    .tp_id:         resd 1          ; its input report ID
    .f_x:           resq I2C_HID_MAX_FINGERS   ; hid_field* per finger
    .f_y:           resq I2C_HID_MAX_FINGERS
    .f_tip:         resq I2C_HID_MAX_FINGERS
    .f_conf:        resq I2C_HID_MAX_FINGERS
    .f_cid:         resq I2C_HID_MAX_FINGERS
    .f_xi:          resd I2C_HID_MAX_FINGERS   ; element indexes
    .f_yi:          resd I2C_HID_MAX_FINGERS
    .f_tipi:        resd I2C_HID_MAX_FINGERS
    .f_confi:       resd I2C_HID_MAX_FINGERS
    .f_cidi:        resd I2C_HID_MAX_FINGERS
    .count_field:   resq 1
    .count_i:       resd 1
    .button_i:      resd 1
    .button_field:  resq 1
    .slots_down:    resd 1          ; one bit per slot
    .buttons:       resd 1          ; last button bits sent
    .emu_slot:      resd 1          ; finger moving the pointer, or -1
    .emu_x:         resd 1
    .emu_y:         resd 1
    .emu_rx:        resd 1          ; remainders below one step
    .emu_ry:        resd 1
    ; mouse
    .m_id:          resd 1
    .m_buttons:     resq 1          ; a variable field of buttons
    .m_x:           resq 1
    .m_y:           resq 1
    .m_wheel:       resq 1
    .m_xi:          resd 1
    .m_yi:          resd 1
    .m_wheeli:      resd 1
    .pad0:          resd 1
    .desc:          resb 32
    .rbuf:          resb I2C_HID_MAX_REPORT + 8
    .rdesc:         resb I2C_HID_MAX_RDESC  ; the report descriptor
    .hid:           resb hid_desc_size
endstruc

section .data
align 8
global i2c_hid_xfer_fn
i2c_hid_xfer_fn:    dq 0    ; as i2c_write_read: EDI ctrl, ESI addr, RDX wbuf,
                            ; ECX wlen, R8 rbuf, R9D rlen → EAX
global i2c_hid_delay_fn
i2c_hid_delay_fn:   dq 0    ; RDI = microseconds
global i2c_hid_pointer_emulation
i2c_hid_pointer_emulation: dd 1

section .bss
alignb 16
i2c_hid_devs:       resb I2C_HID_MAX_DEV * i2c_hid_size
global i2c_hid_bad_reports
i2c_hid_bad_reports: resd 1         ; reports with an impossible length
global i2c_hid_read_errors
i2c_hid_read_errors: resd 1
i2c_hid_cmd:        resb 16         ; command bytes being sent

section .rodata
i2c_hid_name_touchpad: db "I2C touchpad", 0
i2c_hid_name_mouse:    db "I2C mouse", 0
i2c_hid_name_other:    db "I2C HID device", 0

section .text

; -----------------------------------------------------------------------------
; i2c_hid_xfer — a transfer through the hook
; Input:  RBX = device; RDX = write bytes, ECX = count, R8 = read buffer,
;         R9D = count
; Output: EAX
; -----------------------------------------------------------------------------
i2c_hid_xfer:
    mov rax, [rel i2c_hid_xfer_fn]
    test rax, rax
    jz .none
    mov edi, [rbx + i2c_hid.ctrl]
    mov esi, [rbx + i2c_hid.addr]
    sub rsp, 8
    call rax
    add rsp, 8
    ret
.none:
    mov eax, -INPUT_ENODEV
    ret

; -----------------------------------------------------------------------------
; i2c_hid_delay — wait (microseconds in EDI) through the hook
; -----------------------------------------------------------------------------
i2c_hid_delay:
    mov rax, [rel i2c_hid_delay_fn]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; i2c_hid_command — send a command: register, (type << 4 | id), opcode,
;                   then ECX more bytes from RSI
; Input:  RBX = device, EDI = byte 2, ESI = opcode, RDX = extra bytes,
;         ECX = their count (up to 8)
; Output: EAX
; -----------------------------------------------------------------------------
i2c_hid_command:
    lea r8, [rel i2c_hid_cmd]
    mov eax, [rbx + i2c_hid.command_reg]
    mov [r8], ax
    mov [r8 + 2], dil
    mov [r8 + 3], sil
    xor eax, eax
.copy:
    cmp eax, ecx
    jae .send
    mov r9b, [rdx + rax]
    mov [r8 + 4 + rax], r9b
    inc eax
    jmp .copy
.send:
    lea ecx, [rcx + 4]
    mov rdx, r8
    xor r8d, r8d
    xor r9d, r9d
    jmp i2c_hid_xfer

; -----------------------------------------------------------------------------
; i2c_hid_read_input — read one input report into the device's buffer
; Input:  RBX = device
; Output: EAX = the report's length from its own header (0: nothing), or a
;         negative error
; -----------------------------------------------------------------------------
i2c_hid_read_input:
    sub rsp, 8                          ; keeps the stack aligned for the hook
    lea r8, [rbx + i2c_hid.rbuf]
    mov r9d, [rbx + i2c_hid.max_input]
    xor edx, edx
    xor ecx, ecx
    call i2c_hid_xfer
    add rsp, 8
    test eax, eax
    jnz .error
    movzx eax, word [rbx + i2c_hid.rbuf]
    ret
.error:
    inc dword [rel i2c_hid_read_errors]
    ret

; -----------------------------------------------------------------------------
; i2c_hid_find — the element with a usage, in a collection (0xFFFF: any)
;                and an application (0: any)
; Input:  RBX = device, ESI = kind, EDX = usage, ECX = collection,
;         R8D = application, R9 = where the first search starts (a
;         hid_field*, 0 for the first)
; Output: RAX = hid_field* or 0; EDX = element
; -----------------------------------------------------------------------------
i2c_hid_find:
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 16
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov [rsp], r9
.next:
    lea rdi, [rbx + i2c_hid.hid]
    mov esi, r12d
    mov edx, r13d
    lea rcx, [rsp]
    lea r8, [rsp + 8]
    call hid_find_usage
    test eax, eax
    jz .none
    mov rax, [rsp]
    cmp r14d, 0xFFFF
    je .coll_ok
    movzx ecx, word [rax + hid_field.collection]
    cmp ecx, r14d
    jne .next
.coll_ok:
    test r15d, r15d
    jz .found
    cmp [rax + hid_field.application], r15d
    jne .next
.found:
    mov edx, [rsp + 8]
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, 16
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; i2c_hid_feature_value — what we set a feature element to
; Input:  EAX = its usage
; Output: ECX = the value: Input Mode 3 (multi-touch), surface and button
;         switches 1 (on), anything else 0
; -----------------------------------------------------------------------------
i2c_hid_feature_value:
    xor ecx, ecx
    cmp eax, U_INPUT_MODE
    jne .switch
    mov ecx, INPUT_MODE_TOUCHPAD
    ret
.switch:
    cmp eax, U_SURFACE_SWITCH
    je .on
    cmp eax, U_BUTTON_SWITCH
    jne .out
.on:
    mov ecx, 1
.out:
    ret

; -----------------------------------------------------------------------------
; i2c_hid_set_features — SET_REPORT for one feature report, every element
;                        set by i2c_hid_feature_value, so features sharing
;                        a report are set together
; Input:  RBX = device, ESI = report ID
; Output: EAX
; Command: register, type 3 << 4 | ID (0xF and an extra ID byte for IDs
; from 15), opcode, data register, length (2 + ID byte + data), ID, data.
; -----------------------------------------------------------------------------
i2c_hid_set_features:
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 64                         ; the command and report; [56] count
    mov r12d, esi                       ; ID
    lea rdi, [rbx + i2c_hid.hid]
    mov edx, HID_FEATURE
    call hid_report_bits
    add eax, 7
    shr eax, 3
    test eax, eax
    jz .invalid
    cmp eax, I2C_HID_MAX_FEATURE
    ja .invalid
    mov r13d, eax                       ; data bytes
    xor eax, eax
    lea rdi, [rsp]
    mov ecx, 64
    rep stosb
    ; the header
    mov eax, [rbx + i2c_hid.command_reg]
    mov [rsp], ax
    mov eax, r12d
    cmp eax, 15
    jb .short_id
    mov byte [rsp + 2], 0x3F
    mov byte [rsp + 3], I2C_HID_OP_SET_REPORT
    mov [rsp + 4], r12b
    mov ebp, 5
    jmp .data_reg
.short_id:
    or eax, 0x30
    mov [rsp + 2], al
    mov byte [rsp + 3], I2C_HID_OP_SET_REPORT
    mov ebp, 4
.data_reg:
    mov eax, [rbx + i2c_hid.data_reg]
    mov [rsp + rbp], ax
    lea eax, [r13 + 2]                  ; length: itself, ID, data
    test r12d, r12d
    jz .no_id_len
    inc eax
.no_id_len:
    mov [rsp + rbp + 2], ax
    add ebp, 4
    test r12d, r12d
    jz .fill
    mov [rsp + rbp], r12b
    inc ebp
.fill:
    ; R14 = where the data starts; each feature element of this report
    lea r14, [rsp + rbp]
    lea rax, [rbx + i2c_hid.hid]
    lea r15, [rax + hid_desc.fields]
    mov ecx, [rax + hid_desc.field_count]
    mov [rsp + 56], ecx
.field:
    cmp dword [rsp + 56], 0
    je .send
    dec dword [rsp + 56]
    cmp byte [r15 + hid_field.kind], HID_FEATURE
    jne .next_field
    movzx eax, byte [r15 + hid_field.report_id]
    cmp eax, r12d
    jne .next_field
    test word [r15 + hid_field.flags], HID_F_VARIABLE
    jz .next_field
    xor r8d, r8d                        ; element
.element:
    movzx eax, word [r15 + hid_field.count]
    cmp r8d, eax
    jae .next_field
    push r8
    sub rsp, 8
    lea rdi, [rbx + i2c_hid.hid]
    mov rsi, r15
    mov edx, r8d
    call hid_field_usage
    add rsp, 8
    pop r8
    call i2c_hid_feature_value          ; ECX = value
    ; its bits: bit_offset + element × size, size bits
    movzx r9d, word [r15 + hid_field.size]
    mov eax, r8d
    imul eax, r9d
    add eax, [r15 + hid_field.bit_offset]
    xor edx, edx
.bit:
    cmp edx, r9d
    jae .next_element
    cmp edx, 32
    jae .next_element
    bt ecx, edx
    jnc .zero
    lea r10d, [rax + rdx]
    bts [r14], r10d
.zero:
    inc edx
    jmp .bit
.next_element:
    inc r8d
    jmp .element
.next_field:
    add r15, hid_field_size
    jmp .field
.send:
    lea ecx, [rbp + r13]
    mov rdx, rsp
    xor r8d, r8d
    xor r9d, r9d
    call i2c_hid_xfer
    jmp .out
.invalid:
    mov eax, -INPUT_EINVAL
.out:
    add rsp, 64
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; i2c_hid_probe — bring a device up
; Input:  EDI = I2C controller, ESI = address, EDX = HID descriptor register
; Output: EAX = device number, or a negative error (-INPUT_ENODEV: it does
;         not answer or is not an I2C-HID device; -INPUT_EINVAL: its
;         descriptors make no sense; -INPUT_ENOSPC: no free slot)
; -----------------------------------------------------------------------------
global i2c_hid_probe
i2c_hid_probe:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov r12d, edi
    mov r13d, esi
    mov r14d, edx
    ; a free slot
    lea rbx, [rel i2c_hid_devs]
    xor r15d, r15d
.slot:
    cmp r15d, I2C_HID_MAX_DEV
    jae .full
    cmp dword [rbx + i2c_hid.state], 0
    je .free
    add rbx, i2c_hid_size
    inc r15d
    jmp .slot
.free:
    lea rdi, [rbx + i2c_hid.state]
    mov ecx, i2c_hid.hid                ; clear all but the parsed descriptor
    xor eax, eax
    rep stosb
    mov [rbx + i2c_hid.ctrl], r12d
    mov [rbx + i2c_hid.addr], r13d
    mov dword [rbx + i2c_hid.emu_slot], -1

    ; the HID descriptor
    mov [rsp], r14w
    lea rdx, [rsp]
    mov ecx, 2
    lea r8, [rbx + i2c_hid.desc]
    mov r9d, I2C_HID_DESC_LEN
    call i2c_hid_xfer
    test eax, eax
    jnz .nodev
    lea rsi, [rbx + i2c_hid.desc]
    cmp word [rsi], I2C_HID_DESC_LEN
    jne .nodev
    cmp word [rsi + 2], 0x0100
    jne .nodev
    movzx eax, word [rsi + 4]
    test eax, eax
    jz .invalid
    cmp eax, 4096
    ja .invalid
    mov [rbx + i2c_hid.report_desc_len], eax
    movzx eax, word [rsi + 6]
    mov [rbx + i2c_hid.report_desc_reg], eax
    movzx eax, word [rsi + 8]
    mov [rbx + i2c_hid.input_reg], eax
    movzx eax, word [rsi + 10]
    cmp eax, 2
    jb .invalid
    cmp eax, I2C_HID_MAX_REPORT
    ja .invalid
    mov [rbx + i2c_hid.max_input], eax
    movzx eax, word [rsi + 16]
    mov [rbx + i2c_hid.command_reg], eax
    movzx eax, word [rsi + 18]
    mov [rbx + i2c_hid.data_reg], eax
    movzx eax, word [rsi + 20]
    mov [rbx + i2c_hid.vendor], eax
    movzx eax, word [rsi + 22]
    mov [rbx + i2c_hid.product], eax

    ; power on, reset, and wait for the reset's empty report
    xor edi, edi                        ; ON
    mov esi, I2C_HID_OP_SET_POWER
    xor ecx, ecx
    call i2c_hid_command
    test eax, eax
    jnz .nodev
    xor edi, edi
    mov esi, I2C_HID_OP_RESET
    xor ecx, ecx
    call i2c_hid_command
    test eax, eax
    jnz .nodev
    mov r14d, I2C_HID_RESET_TRIES
.reset_wait:
    mov edi, 10000
    call i2c_hid_delay
    call i2c_hid_read_input
    test eax, eax
    jz .reset_done
    dec r14d
    jnz .reset_wait                     ; some devices never send it
.reset_done:

    ; the report descriptor, into the parsed form
    cmp dword [rbx + i2c_hid.report_desc_len], I2C_HID_MAX_RDESC
    ja .invalid
    mov eax, [rbx + i2c_hid.report_desc_reg]
    mov [rsp], ax
    lea rdx, [rsp]
    mov ecx, 2
    lea r8, [rbx + i2c_hid.rdesc]
    mov r9d, [rbx + i2c_hid.report_desc_len]
    call i2c_hid_xfer
    test eax, eax
    jnz .nodev
    lea rdi, [rbx + i2c_hid.rdesc]
    mov esi, [rbx + i2c_hid.report_desc_len]
    lea rdx, [rbx + i2c_hid.hid]
    call hid_parse
    test eax, eax
    jnz .invalid

    call i2c_hid_classify
    mov dword [rbx + i2c_hid.state], 1
    mov eax, r15d
    jmp .out
.full:
    mov eax, -INPUT_ENOSPC
    jmp .out
.nodev:
    mov eax, -INPUT_ENODEV
    jmp .out
.invalid:
    mov eax, -INPUT_EINVAL
.out:
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i2c_hid_classify — touchpad, mouse or other; find the fields; switch a
;                    touchpad to multi-touch; add the input device
; Input:  RBX = device
; -----------------------------------------------------------------------------
i2c_hid_classify:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    ; a touchpad: X fields in the touchpad application, one per finger
    xor r12d, r12d                      ; fingers
    xor r13d, r13d                      ; search position
.finger:
    cmp r12d, I2C_HID_MAX_FINGERS
    jae .fingers_done
    mov esi, HID_INPUT
    mov edx, U_X
    mov ecx, 0xFFFF
    mov r8d, U_TOUCHPAD
    mov r9, r13
    call i2c_hid_find
    test rax, rax
    jz .fingers_done
    mov r13, rax
    mov [rbx + i2c_hid.f_x + r12 * 8], rax
    mov [rbx + i2c_hid.f_xi + r12 * 4], edx
    movzx r14d, word [rax + hid_field.collection]
    movzx eax, byte [rax + hid_field.report_id]
    mov [rbx + i2c_hid.tp_id], eax
    ; the rest of this finger, in the same collection
%macro FINGER_PART 3                    ; usage, field array, index array
    mov esi, HID_INPUT
    mov edx, %1
    mov ecx, r14d
    xor r8d, r8d
    xor r9d, r9d
    call i2c_hid_find
    mov [rbx + %2 + r12 * 8], rax
    mov [rbx + %3 + r12 * 4], edx
%endmacro
    FINGER_PART U_Y, i2c_hid.f_y, i2c_hid.f_yi
    FINGER_PART U_TIP, i2c_hid.f_tip, i2c_hid.f_tipi
    FINGER_PART U_CONFIDENCE, i2c_hid.f_conf, i2c_hid.f_confi
    FINGER_PART U_CONTACT_ID, i2c_hid.f_cid, i2c_hid.f_cidi
%unmacro FINGER_PART 3
    cmp qword [rbx + i2c_hid.f_y + r12 * 8], 0
    je .fingers_done                    ; no Y: not a finger
    cmp qword [rbx + i2c_hid.f_tip + r12 * 8], 0
    je .fingers_done
    inc r12d
    jmp .finger
.fingers_done:
    mov [rbx + i2c_hid.fingers], r12d
    test r12d, r12d
    jz .mouse

    mov dword [rbx + i2c_hid.kind], I2C_HID_TOUCHPAD
    mov esi, HID_INPUT
    mov edx, U_CONTACT_COUNT
    mov ecx, 0xFFFF
    mov r8d, U_TOUCHPAD
    xor r9d, r9d
    call i2c_hid_find
    mov [rbx + i2c_hid.count_field], rax
    mov [rbx + i2c_hid.count_i], edx
    mov esi, HID_INPUT
    mov edx, U_BUTTON1
    mov ecx, 0xFFFF
    mov r8d, U_TOUCHPAD
    xor r9d, r9d
    call i2c_hid_find
    mov [rbx + i2c_hid.button_field], rax
    mov [rbx + i2c_hid.button_i], edx

    ; multi-touch mode, surface and button reports on: one SET_REPORT per
    ; feature report holding any of them
    mov esi, HID_FEATURE
    mov edx, U_INPUT_MODE
    mov ecx, 0xFFFF
    xor r8d, r8d
    xor r9d, r9d
    call i2c_hid_find
    mov r15d, -1                        ; the report already set
    test rax, rax
    jz .switches
    movzx esi, byte [rax + hid_field.report_id]
    mov r15d, esi
    call i2c_hid_set_features
.switches:
    mov esi, HID_FEATURE
    mov edx, U_SURFACE_SWITCH
    mov ecx, 0xFFFF
    xor r8d, r8d
    xor r9d, r9d
    call i2c_hid_find
    test rax, rax
    jz .button_switch
    movzx esi, byte [rax + hid_field.report_id]
    cmp esi, r15d
    je .button_switch
    call i2c_hid_set_features
.button_switch:
    ; the device: touch and pointer, ranges of the first finger
    lea rdi, [rel i2c_hid_name_touchpad]
    mov esi, INPUT_BUS_I2C
    mov edx, INPUT_CAP_TOUCH | INPUT_CAP_POINTER
    mov ecx, [rbx + i2c_hid.vendor]
    shl ecx, 16
    or ecx, [rbx + i2c_hid.product]
    call input_dev_add
    test eax, eax
    js .out
    mov [rbx + i2c_hid.input_dev], eax
    mov edi, eax
    call input_dev_find
    test rax, rax
    jz .out
    mov rcx, [rbx + i2c_hid.f_x]
    mov edx, [rcx + hid_field.logical_max]
    mov [rax + input_dev_info.max_x], edx
    call i2c_hid_resolution
    mov [rax + input_dev_info.res_x], edx
    mov rcx, [rbx + i2c_hid.f_y]
    mov edx, [rcx + hid_field.logical_max]
    mov [rax + input_dev_info.max_y], edx
    call i2c_hid_resolution
    mov [rax + input_dev_info.res_y], edx
    mov ecx, [rbx + i2c_hid.fingers]
    mov [rax + input_dev_info.slots], ecx
    jmp .out

.mouse:
    ; a mouse: X and Y in the mouse application
    mov esi, HID_INPUT
    mov edx, U_X
    mov ecx, 0xFFFF
    mov r8d, U_MOUSE
    xor r9d, r9d
    call i2c_hid_find
    test rax, rax
    jz .other
    mov dword [rbx + i2c_hid.kind], I2C_HID_MOUSE
    mov [rbx + i2c_hid.m_x], rax
    mov [rbx + i2c_hid.m_xi], edx
    movzx ecx, byte [rax + hid_field.report_id]
    mov [rbx + i2c_hid.m_id], ecx
    mov esi, HID_INPUT
    mov edx, U_Y
    mov ecx, 0xFFFF
    mov r8d, U_MOUSE
    xor r9d, r9d
    call i2c_hid_find
    mov [rbx + i2c_hid.m_y], rax
    mov [rbx + i2c_hid.m_yi], edx
    mov esi, HID_INPUT
    mov edx, U_WHEEL
    mov ecx, 0xFFFF
    mov r8d, U_MOUSE
    xor r9d, r9d
    call i2c_hid_find
    mov [rbx + i2c_hid.m_wheel], rax
    mov [rbx + i2c_hid.m_wheeli], edx
    mov esi, HID_INPUT
    mov edx, U_BUTTON1
    mov ecx, 0xFFFF
    mov r8d, U_MOUSE
    xor r9d, r9d
    call i2c_hid_find
    mov [rbx + i2c_hid.m_buttons], rax
    lea rdi, [rel i2c_hid_name_mouse]
    mov edx, INPUT_CAP_POINTER
    jmp .add
.other:
    lea rdi, [rel i2c_hid_name_other]
    xor edx, edx
.add:
    mov esi, INPUT_BUS_I2C
    mov ecx, [rbx + i2c_hid.vendor]
    shl ecx, 16
    or ecx, [rbx + i2c_hid.product]
    call input_dev_add
    test eax, eax
    js .out
    mov [rbx + i2c_hid.input_dev], eax
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; i2c_hid_resolution — device units per millimetre of a field (RCX)
; Output: EDX (0 when the field does not say); preserves RAX
; Units: centimetres (0x11) or inches (0x13), with the unit exponent.
; -----------------------------------------------------------------------------
i2c_hid_resolution:
    push rax
    xor edx, edx
    mov eax, [rcx + hid_field.unit]
    and eax, 0xFF
    mov r8d, 10                         ; mm per cm, ×1
    mov r9d, 1
    cmp eax, 0x11
    je .unit
    mov r8d, 254                        ; mm per inch, ×10
    mov r9d, 10
    cmp eax, 0x13
    jne .out
.unit:
    ; mm = physical_max × 10^exp × r8 / r9; res = range / mm
    movsx r10d, byte [rcx + hid_field.unit_exp]
    mov eax, [rcx + hid_field.physical_max]
    test eax, eax
    jle .out
    imul rax, r8                        ; physical × mm-per-unit × r9
    ; units per mm = range × r9 / (physical × r8 × 10^exp)
    mov r11d, [rcx + hid_field.logical_max]
    sub r11d, [rcx + hid_field.logical_min]
    imul r11, r9
.exp:
    test r10d, r10d
    jz .divide
    js .negative
    imul rax, 10
    dec r10d
    jmp .exp
.negative:
    imul r11, 10
    inc r10d
    jmp .exp
.divide:
    test rax, rax
    jz .out
    mov r10, rax
    mov rax, r11
    xor edx, edx
    div r10
    mov edx, eax
.out:
    pop rax
    ret

; -----------------------------------------------------------------------------
; i2c_hid_set_after — a function run after each service of a device
; Input:  EDI = device, RSI = function (RDI = cookie), RDX = cookie
; -----------------------------------------------------------------------------
global i2c_hid_set_after
i2c_hid_set_after:
    cmp edi, I2C_HID_MAX_DEV
    jae .out
    imul edi, edi, i2c_hid_size
    lea rax, [rel i2c_hid_devs]
    add rax, rdi
    mov [rax + i2c_hid.after_fn], rsi
    mov [rax + i2c_hid.after_cookie], rdx
.out:
    ret

; -----------------------------------------------------------------------------
; i2c_hid_attention — the device's interrupt fired (interrupt context)
; Input:  EDI = device
; -----------------------------------------------------------------------------
global i2c_hid_attention
i2c_hid_attention:
    cmp edi, I2C_HID_MAX_DEV
    jae .out
    imul edi, edi, i2c_hid_size
    lea rax, [rel i2c_hid_devs]
    mov dword [rax + rdi + i2c_hid.pending], 1
.out:
    ret

; -----------------------------------------------------------------------------
; i2c_hid_service — handle every device whose interrupt fired (fiber)
; Output: EAX = reports handled
; -----------------------------------------------------------------------------
global i2c_hid_service
i2c_hid_service:
    push rbx
    push r12
    push r13
    lea rbx, [rel i2c_hid_devs]
    xor r12d, r12d
    xor r13d, r13d
.dev:
    cmp r12d, I2C_HID_MAX_DEV
    jae .out
    cmp dword [rbx + i2c_hid.state], 1
    jne .next
    xor eax, eax
    xchg eax, [rbx + i2c_hid.pending]
    test eax, eax
    jz .next
    call i2c_hid_report
    add r13d, eax
    mov rax, [rbx + i2c_hid.after_fn]
    test rax, rax
    jz .next
    mov rdi, [rbx + i2c_hid.after_cookie]
    call rax
.next:
    add rbx, i2c_hid_size
    inc r12d
    jmp .dev
.out:
    mov eax, r13d
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; i2c_hid_value — an element's value from the report in the buffer
; Input:  RBX = device, RSI = hid_field, EDX = element, R12 = report data,
;         R13D = its length
; Output: RDX = value (0 when the element is missing or out of range)
; -----------------------------------------------------------------------------
i2c_hid_value:
    test rsi, rsi
    jz .zero
    mov rdi, r12
    mov ecx, edx
    mov rdx, rsi
    mov esi, r13d
    sub rsp, 8
    call hid_get
    add rsp, 8
    test eax, eax
    jnz .zero
    ret
.zero:
    xor edx, edx
    ret

; -----------------------------------------------------------------------------
; i2c_hid_post — an event from the fiber
; Input:  EDI = type, ESI = code, EDX = value; RBX = device
; -----------------------------------------------------------------------------
i2c_hid_post:
    mov ecx, [rbx + i2c_hid.input_dev]
    jmp input_post_safe

; -----------------------------------------------------------------------------
; i2c_hid_report — read one report and turn it into events
; Input:  RBX = device
; Output: EAX = 1 when a report was handled, else 0
; -----------------------------------------------------------------------------
i2c_hid_report:
    push r12
    push r13
    push r14
    push r15
    push rbp
    call i2c_hid_read_input
    test eax, eax
    jle .none                           ; error, or the empty reset report
    cmp eax, 3
    jb .bad
    cmp eax, [rbx + i2c_hid.max_input]
    ja .bad
    lea r12, [rbx + i2c_hid.rbuf + 2]   ; after the length
    lea r13d, [rax - 2]
    xor r14d, r14d                      ; report ID
    lea rcx, [rbx + i2c_hid.hid]
    cmp dword [rcx + hid_desc.uses_ids], 0
    je .id_known
    movzx r14d, byte [r12]
    inc r12
    dec r13d
.id_known:
    ; shorter than the descriptor says this report is: dropped
    lea rdi, [rbx + i2c_hid.hid]
    mov esi, r14d
    mov edx, HID_INPUT
    call hid_report_bits
    add eax, 7
    shr eax, 3
    cmp r13d, eax
    jb .bad
    cmp dword [rbx + i2c_hid.kind], I2C_HID_TOUCHPAD
    jne .try_mouse
    cmp r14d, [rbx + i2c_hid.tp_id]
    jne .try_mouse
    call i2c_hid_touchpad
    jmp .handled
.try_mouse:
    cmp dword [rbx + i2c_hid.kind], I2C_HID_MOUSE
    jne .handled                        ; nothing we turn into events yet
    cmp r14d, [rbx + i2c_hid.m_id]
    jne .handled
    call i2c_hid_mouse
.handled:
    mov eax, 1
    jmp .out
.bad:
    inc dword [rel i2c_hid_bad_reports]
.none:
    xor eax, eax
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; i2c_hid_touchpad — a touchpad report (R12 data, R13D length) into touch
;                    contacts, a frame end, button changes, and pointer
;                    emulation
; -----------------------------------------------------------------------------
i2c_hid_touchpad:
    push r14
    push r15
    push rbp
    sub rsp, 32                 ; [0] seen slots, [8] contacts reported,
                                ; [16] x, [20] y, [24] slot, [28] slots
                                ; still to lift
    mov dword [rsp], 0
    ; how many fingers this report carries (all of them without a count)
    mov eax, [rbx + i2c_hid.fingers]
    mov [rsp + 8], eax
    mov rsi, [rbx + i2c_hid.count_field]
    test rsi, rsi
    jz .count_done
    mov edx, [rbx + i2c_hid.count_i]
    call i2c_hid_value
    cmp edx, [rbx + i2c_hid.fingers]
    jbe .count_ok
    mov edx, [rbx + i2c_hid.fingers]
.count_ok:
    mov [rsp + 8], edx
.count_done:
    xor ebp, ebp                        ; finger
.finger:
    cmp ebp, [rsp + 8]
    jae .lifted
    ; slot: the contact ID, else the finger's position in the report
    mov r15d, ebp
    mov rsi, [rbx + i2c_hid.f_cid + rbp * 8]
    test rsi, rsi
    jz .slot
    mov edx, [rbx + i2c_hid.f_cidi + rbp * 4]
    call i2c_hid_value
    mov r15d, edx
.slot:
    cmp r15d, I2C_HID_MAX_SLOTS
    jae .next_finger
    mov [rsp + 24], r15d
    mov rsi, [rbx + i2c_hid.f_x + rbp * 8]
    mov edx, [rbx + i2c_hid.f_xi + rbp * 4]
    call i2c_hid_value
    mov [rsp + 16], edx
    mov rsi, [rbx + i2c_hid.f_y + rbp * 8]
    mov edx, [rbx + i2c_hid.f_yi + rbp * 4]
    call i2c_hid_value
    mov [rsp + 20], edx
    mov rsi, [rbx + i2c_hid.f_tip + rbp * 8]
    mov edx, [rbx + i2c_hid.f_tipi + rbp * 4]
    call i2c_hid_value
    mov r14d, edx                       ; tip
    ; confidence: assumed when the device does not report it
    mov r9d, 1 << 12
    mov rsi, [rbx + i2c_hid.f_conf + rbp * 8]
    test rsi, rsi
    jz .conf_known
    mov edx, [rbx + i2c_hid.f_confi + rbp * 4]
    call i2c_hid_value
    xor r9d, r9d
    test edx, edx
    jz .conf_known
    mov r9d, 1 << 12
.conf_known:
    mov ecx, [rsp + 24]
    test r14d, r14d
    jz .up
    ; down or moving
    bts dword [rsp], ecx
    mov eax, 1 << 8                     ; move
    bt dword [rbx + i2c_hid.slots_down], ecx
    jc .phase
    xor eax, eax                        ; down
    bts dword [rbx + i2c_hid.slots_down], ecx
.phase:
    or eax, ecx
    or eax, r9d
    mov esi, eax
    movzx edx, word [rsp + 20]
    shl edx, 16
    mov ax, [rsp + 16]
    or dx, ax
    mov edi, INPUT_TOUCH
    call i2c_hid_post
    call i2c_hid_emulate
    jmp .next_finger
.up:
    btr dword [rbx + i2c_hid.slots_down], ecx
    jnc .next_finger
    bts dword [rsp], ecx
    call i2c_hid_lift
.next_finger:
    inc ebp
    jmp .finger
.lifted:
    ; fingers down before and not in this report have lifted
    mov eax, [rbx + i2c_hid.slots_down]
    mov ecx, [rsp]
    not ecx
    and eax, ecx
    mov [rsp + 28], eax
.lift:
    mov eax, [rsp + 28]
    test eax, eax
    jz .frame
    bsf ecx, eax
    btr [rsp + 28], ecx
    btr dword [rbx + i2c_hid.slots_down], ecx
    mov [rsp + 24], ecx
    call i2c_hid_lift
    jmp .lift
.frame:
    mov edi, INPUT_TOUCH
    mov esi, 3 << 8                     ; frame end, other fields 0
    xor edx, edx
    call i2c_hid_post
    ; the click button
    mov rsi, [rbx + i2c_hid.button_field]
    test rsi, rsi
    jz .out
    mov edx, [rbx + i2c_hid.button_i]
    call i2c_hid_value
    and edx, 1
    cmp edx, [rbx + i2c_hid.buttons]
    je .out
    mov [rbx + i2c_hid.buttons], edx
    mov edi, INPUT_BUTTON
    xor esi, esi                        ; left
    call i2c_hid_post
.out:
    add rsp, 32
    pop rbp
    pop r15
    pop r14
    ret

; -----------------------------------------------------------------------------
; i2c_hid_lift — a contact leaves: an up record; the pointer finger let go
; Input:  the slot at [rsp + 8 + 24] of i2c_hid_touchpad's frame (called
;         from it: one return address away)
; -----------------------------------------------------------------------------
i2c_hid_lift:
    mov ecx, [rsp + 8 + 24]
    mov esi, ecx
    or esi, 2 << 8                      ; up
    xor edx, edx
    mov edi, INPUT_TOUCH
    push rcx
    call i2c_hid_post
    pop rcx
    cmp ecx, [rbx + i2c_hid.emu_slot]
    jne .out
    mov dword [rbx + i2c_hid.emu_slot], -1
.out:
    ret

; -----------------------------------------------------------------------------
; i2c_hid_emulate — pointer motion from the first finger down
; Input:  slot, x, y at [rsp + 8 + 24], [rsp + 8 + 16], [rsp + 8 + 20] of
;         i2c_hid_touchpad's frame
; -----------------------------------------------------------------------------
i2c_hid_emulate:
    cmp dword [rel i2c_hid_pointer_emulation], 0
    je .out
    mov ecx, [rsp + 8 + 24]
    mov eax, [rbx + i2c_hid.emu_slot]
    cmp eax, -1
    jne .tracking
    ; take this finger
    mov [rbx + i2c_hid.emu_slot], ecx
    mov eax, [rsp + 8 + 16]
    mov [rbx + i2c_hid.emu_x], eax
    mov eax, [rsp + 8 + 20]
    mov [rbx + i2c_hid.emu_y], eax
    mov dword [rbx + i2c_hid.emu_rx], 0
    mov dword [rbx + i2c_hid.emu_ry], 0
    ret
.tracking:
    cmp eax, ecx
    jne .out
    ; motion in device units, plus what was left over, in whole steps
    mov eax, [rsp + 8 + 16]
    mov edx, eax
    sub eax, [rbx + i2c_hid.emu_x]
    mov [rbx + i2c_hid.emu_x], edx
    add eax, [rbx + i2c_hid.emu_rx]
    cdq
    mov r8d, I2C_HID_EMU_DIV
    idiv r8d
    mov [rbx + i2c_hid.emu_rx], edx
    mov r10d, eax                       ; dx
    mov eax, [rsp + 8 + 20]
    mov edx, eax
    sub eax, [rbx + i2c_hid.emu_y]
    mov [rbx + i2c_hid.emu_y], edx
    add eax, [rbx + i2c_hid.emu_ry]
    cdq
    idiv r8d
    mov [rbx + i2c_hid.emu_ry], edx
    mov r11d, eax                       ; dy
    mov eax, r10d
    or eax, r11d
    jz .out
    mov edi, INPUT_MOTION
    mov esi, r10d
    mov edx, r11d
    sub rsp, 8
    call i2c_hid_post
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; i2c_hid_mouse — a mouse report (R12 data, R13D length) into motion,
;                 wheel and button events
; -----------------------------------------------------------------------------
i2c_hid_mouse:
    push r14
    push r15
    push rbp
    mov rsi, [rbx + i2c_hid.m_x]
    mov edx, [rbx + i2c_hid.m_xi]
    call i2c_hid_value
    mov r14d, edx
    mov rsi, [rbx + i2c_hid.m_y]
    mov edx, [rbx + i2c_hid.m_yi]
    call i2c_hid_value
    mov r15d, edx
    mov eax, r14d
    or eax, r15d
    jz .wheel
    mov edi, INPUT_MOTION
    mov esi, r14d
    mov edx, r15d
    call i2c_hid_post
.wheel:
    mov rsi, [rbx + i2c_hid.m_wheel]
    test rsi, rsi
    jz .buttons
    mov edx, [rbx + i2c_hid.m_wheeli]
    call i2c_hid_value
    test edx, edx
    jz .buttons
    neg edx                             ; wheel up is negative steps (up)
    mov edi, INPUT_AXIS
    xor esi, esi
    call i2c_hid_post
.buttons:
    ; up to three buttons: left, right, middle
    mov rsi, [rbx + i2c_hid.m_buttons]
    test rsi, rsi
    jz .out
    xor ebp, ebp
.button:
    cmp ebp, 3
    jae .out
    mov rsi, [rbx + i2c_hid.m_buttons]
    movzx eax, word [rsi + hid_field.count]
    cmp ebp, eax
    jae .out
    mov edx, ebp
    call i2c_hid_value
    and edx, 1
    mov eax, [rbx + i2c_hid.buttons]
    bt eax, ebp
    setc al
    movzx eax, al
    cmp eax, edx
    je .next_button
    btc dword [rbx + i2c_hid.buttons], ebp
    mov edi, INPUT_BUTTON
    mov esi, ebp
    call i2c_hid_post
.next_button:
    inc ebp
    jmp .button
.out:
    pop rbp
    pop r15
    pop r14
    ret

; -----------------------------------------------------------------------------
; i2c_hid_reset_all — forget every device (start-up and tests)
; -----------------------------------------------------------------------------
global i2c_hid_reset_all
i2c_hid_reset_all:
    lea rax, [rel i2c_hid_devs]
    mov dword [rax + i2c_hid.state], 0
    mov dword [rax + i2c_hid_size + i2c_hid.state], 0
    mov dword [rel i2c_hid_bad_reports], 0
    mov dword [rel i2c_hid_read_errors], 0
    ret

%endif ; LIB_INPUT_I2C_HID_ASM
