; =============================================================================
; Utkarsha OS — lib/input/kernel_touchpad.asm
; =============================================================================
; The built-in I2C-HID touchpad inside the kernel. Included by
; kernel/entry.asm after the AML interpreter, lib/io/gpio, lib/io/i2c and
; lib/input.
;
; input_touchpad_init, after acpi_kernel_init:
;   1. the first present PNP0C50 (or ACPI0C50) device;
;   2. its _CRS: the I2C connection (address, speed, controller path) and
;      its interrupt: a GPIO interrupt (pin, controller path) or a plain
;      interrupt (GSI);
;   3. _DSM function 1 of the I2C-HID UUID: the HID descriptor register;
;   4. the I2C controller: its _CRS memory, attached with the 133 MHz input
;      clock of AMD controllers; FMCN or SSCN timing when the firmware
;      gives it;
;   5. the GPIO controller: its _CRS memory and interrupt, attached, and its
;      interrupt routed with the trigger and polarity ACPI declares;
;   6. i2c_hid_probe; the pin claimed as the touchpad's interrupt.
; On each interrupt the touchpad is marked; the input fiber reads its report
; (i2c_hid_service) and re-arms the pin. Nothing here stops the boot.
;
; Other pins the firmware left enabled on the GPIO controller have no
; handler yet and are turned off as they fire (ACPI _AEI events come later,
; lib/io/gpio ROADMAP.md Phase 2).
; =============================================================================

%ifndef LIB_INPUT_KERNEL_TOUCHPAD_ASM
%define LIB_INPUT_KERNEL_TOUCHPAD_ASM

%define ITP_OWNER           0x48494432  ; "2DIH": the touchpad's pin owner
%define ITP_I2C_CLOCK_KHZ   133000      ; AMD I2C controllers' input clock
%define ITP_PATH_MAX        64
%define ITP_GPIO_PINS       190         ; pin registers below the status ones

section .rodata
itp_id_hid:         db "PNP0C50", 0
itp_id_hid2:        db "ACPI0C50", 0
; _DSM UUID 3CDFF6F7-4267-4555-AD05-B30A3D8938DE, ToUUID byte order
itp_dsm_uuid:       db 0xF7, 0xF6, 0xDF, 0x3C, 0x67, 0x42, 0x55, 0x45
                    db 0xAD, 0x05, 0xB3, 0x0A, 0x3D, 0x89, 0x38, 0xDE
itp_fmcn:           db ".FMCN", 0
itp_sscn:           db ".SSCN", 0
msg_itp_none:       db "INPUT: no I2C-HID touchpad in ACPI", 0x0D, 0x0A, 0
msg_itp_crs:        db "INPUT: touchpad _CRS has no I2C connection or interrupt", 0x0D, 0x0A, 0
msg_itp_dsm:        db "INPUT: touchpad _DSM gave no HID descriptor register", 0x0D, 0x0A, 0
msg_itp_i2c:        db "INPUT: touchpad I2C controller not usable", 0x0D, 0x0A, 0
msg_itp_gpio:       db "INPUT: touchpad GPIO controller not usable", 0x0D, 0x0A, 0
msg_itp_route:      db "INPUT: touchpad interrupt could not be routed", 0x0D, 0x0A, 0
msg_itp_probe:      db "INPUT: touchpad did not answer as I2C-HID, error -", 0
msg_itp_ready:      db "INPUT: I2C-HID touchpad at address ", 0
msg_itp_pin:        db ", GPIO pin ", 0
msg_itp_crlf:       db 0x0D, 0x0A, 0

section .bss
alignb 8
global itp_state
itp_state:          resd 1          ; 1 once the touchpad works
itp_addr:           resd 1          ; I2C address
itp_speed:          resd 1
itp_pin:            resd 1          ; GPIO pin, or -1 for a plain interrupt
itp_pin_flags:      resd 1          ; aml_res flags of the interrupt
itp_gsi:            resd 1          ; plain interrupt, or the GPIO controller's
itp_gsi_flags:      resd 1
itp_desc_reg:       resd 1
itp_i2c_ctrl:       resd 1
itp_gpio_ctrl:      resd 1
itp_dev:            resd 1          ; i2c_hid device
itp_vector:         resd 1
itp_route_flags:    resd 1          ; ioapic_route_gsi flags, unmasked
itp_i2c_path:       resb ITP_PATH_MAX + 8
itp_gpio_path:      resb ITP_PATH_MAX + 8
itp_res:            resb aml_res_size
alignb 8
itp_value:          resb aml_value_size
itp_offset:         resd 1

section .text

; -----------------------------------------------------------------------------
; itp_copy_path — copy a resource source name (RSI, NUL-terminated) to RDI
; Output: CF = 1 when there is none or it is too long
; -----------------------------------------------------------------------------
itp_copy_path:
    test rsi, rsi
    jz .bad
    xor ecx, ecx
.byte:
    mov al, [rsi + rcx]
    mov [rdi + rcx], al
    test al, al
    jz .ok
    inc ecx
    cmp ecx, ITP_PATH_MAX
    jb .byte
.bad:
    stc
    ret
.ok:
    test ecx, ecx
    jz .bad
    clc
    ret

; -----------------------------------------------------------------------------
; itp_mmio_base — the first memory range of a device's _CRS
; Input:  RDI = device node
; Output: CF = 0 with RAX = base, RDX = length; CF = 1 when there is none
;         (also the first interrupt of it into itp_gsi / itp_gsi_flags)
; -----------------------------------------------------------------------------
itp_mmio_base:
    push rbx
    push r12
    push r13
    xor r12d, r12d                      ; base
    xor r13d, r13d                      ; length
    mov dword [rel itp_gsi], -1
    lea rsi, [rel itp_value]
    call aml_get_crs
    test eax, eax
    jnz .none
    mov dword [rel itp_offset], 0
.next:
    mov rdi, [rel itp_value + aml_value.data]
    mov esi, [rel itp_value + aml_value.len]
    lea rdx, [rel itp_offset]
    lea rcx, [rel itp_res]
    call aml_res_next
    cmp eax, 1
    jne .done
    movzx eax, byte [rel itp_res + aml_res.kind]
    cmp eax, AML_RES_FIXED_MEM32
    je .memory
    cmp eax, AML_RES_MEM32
    je .memory
    cmp eax, AML_RES_EXT_IRQ
    je .irq
    jmp .next
.memory:
    test r12, r12
    jnz .next
    mov r12, [rel itp_res + aml_res.base]
    mov r13, [rel itp_res + aml_res.len]
    jmp .next
.irq:
    cmp dword [rel itp_gsi], -1
    jne .next
    mov rax, [rel itp_res + aml_res.base]
    mov [rel itp_gsi], eax
    movzx eax, byte [rel itp_res + aml_res.flags]
    mov [rel itp_gsi_flags], eax
    jmp .next
.done:
    test r12, r12
    jz .none
    mov rax, r12
    mov rdx, r13
    clc
    jmp .out
.none:
    stc
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; itp_i2c_timing — FMCN (fast) or SSCN (standard) from the controller:
;                  a package of SCL high count, low count, SDA hold
; Input:  R12 = controller path (text), EBX = speed in Hz
; Output: EAX = high, EDX = low, ECX = hold; all 0 when not given
; -----------------------------------------------------------------------------
itp_i2c_timing:
    push r13
    push r14
    sub rsp, 88                         ; the path + method, a value
    ; the path with the method's name after it
    lea rdi, [rsp + 16]
    mov rsi, r12
    xor ecx, ecx
.copy:
    mov al, [rsi + rcx]
    test al, al
    jz .copied
    mov [rdi + rcx], al
    inc ecx
    cmp ecx, ITP_PATH_MAX
    jb .copy
    jmp .none
.copied:
    lea rsi, [rel itp_fmcn]
    cmp ebx, 100000
    ja .method
    lea rsi, [rel itp_sscn]
.method:
    xor edx, edx
.append:
    mov al, [rsi + rdx]
    mov [rdi + rcx], al
    inc ecx
    inc edx
    test al, al
    jnz .append
    lea rdi, [rsp + 16]
    xor esi, esi
    xor edx, edx
    lea rcx, [rsp]
    call aml_eval_path
    test eax, eax
    jnz .none
    cmp byte [rsp + aml_value.type], AML_T_PACKAGE
    jne .none
    cmp dword [rsp + aml_value.len], 3
    jb .none
    mov r13, [rsp + aml_value.data]
    cmp byte [r13 + aml_value.type], AML_T_INTEGER
    jne .none
    cmp byte [r13 + 16 + aml_value.type], AML_T_INTEGER
    jne .none
    cmp byte [r13 + 32 + aml_value.type], AML_T_INTEGER
    jne .none
    mov eax, [r13 + aml_value.data]
    mov edx, [r13 + 16 + aml_value.data]
    mov ecx, [r13 + 32 + aml_value.data]
    jmp .out
.none:
    xor eax, eax
    xor edx, edx
    xor ecx, ecx
.out:
    add rsp, 88
    pop r14
    pop r13
    ret

; -----------------------------------------------------------------------------
; input_touchpad_init — find the touchpad and bring it up
; -----------------------------------------------------------------------------
global input_touchpad_init
input_touchpad_init:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword [rel itp_state], 0
    cmp dword [rel acpi_ready], 1
    jne .no_device

    ; 1. the device
    lea rdi, [rel itp_id_hid]
    xor esi, esi
    call aml_find_device
    test rax, rax
    jnz .have_device
    lea rdi, [rel itp_id_hid2]
    xor esi, esi
    call aml_find_device
    test rax, rax
    jz .no_device
.have_device:
    mov r15, rax                        ; the touchpad node

    ; 2. its resources
    mov dword [rel itp_addr], -1
    mov dword [rel itp_pin], -1
    mov dword [rel itp_gsi], -1
    mov byte [rel itp_i2c_path], 0
    mov byte [rel itp_gpio_path], 0
    mov rdi, r15
    lea rsi, [rel itp_value]
    call aml_get_crs
    test eax, eax
    jnz .bad_crs
    mov dword [rel itp_offset], 0
.res:
    mov rdi, [rel itp_value + aml_value.data]
    mov esi, [rel itp_value + aml_value.len]
    lea rdx, [rel itp_offset]
    lea rcx, [rel itp_res]
    call aml_res_next
    cmp eax, 1
    jne .res_done
    movzx eax, byte [rel itp_res + aml_res.kind]
    cmp eax, AML_RES_I2C
    je .res_i2c
    cmp eax, AML_RES_GPIO_INT
    je .res_gpio
    cmp eax, AML_RES_EXT_IRQ
    je .res_irq
    jmp .res
.res_i2c:
    cmp dword [rel itp_addr], -1
    jne .res
    mov rax, [rel itp_res + aml_res.base]
    mov [rel itp_addr], eax
    mov rax, [rel itp_res + aml_res.len]
    mov [rel itp_speed], eax
    lea rdi, [rel itp_i2c_path]
    mov rsi, [rel itp_res + aml_res.source]
    call itp_copy_path
    jmp .res
.res_gpio:
    cmp dword [rel itp_pin], -1
    jne .res
    mov rax, [rel itp_res + aml_res.base]
    mov [rel itp_pin], eax
    movzx eax, byte [rel itp_res + aml_res.flags]
    mov [rel itp_pin_flags], eax
    lea rdi, [rel itp_gpio_path]
    mov rsi, [rel itp_res + aml_res.source]
    call itp_copy_path
    jmp .res
.res_irq:
    cmp dword [rel itp_gsi], -1
    jne .res
    mov rax, [rel itp_res + aml_res.base]
    mov [rel itp_gsi], eax
    movzx eax, byte [rel itp_res + aml_res.flags]
    mov [rel itp_gsi_flags], eax
    jmp .res
.res_done:
    cmp dword [rel itp_addr], -1
    je .bad_crs
    cmp byte [rel itp_i2c_path], 0
    je .bad_crs
    cmp dword [rel itp_pin], -1
    jne .have_irq
    cmp dword [rel itp_gsi], -1
    je .bad_crs
.have_irq:
    ; the plain interrupt, if any, is the touchpad's own
    mov eax, [rel itp_gsi]
    mov r14d, eax
    mov eax, [rel itp_gsi_flags]
    mov r13d, eax

    ; 3. the HID descriptor register
    mov rdi, r15
    lea rsi, [rel itp_dsm_uuid]
    mov edx, 1
    mov ecx, 1
    lea r8, [rel itp_value]
    call aml_dsm
    test eax, eax
    jnz .bad_dsm
    lea rdi, [rel itp_value]
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .bad_dsm
    test edx, edx
    jz .bad_dsm
    cmp edx, 0xFFFF
    ja .bad_dsm
    mov [rel itp_desc_reg], edx

    ; 4. the I2C controller
    lea rdi, [rel itp_i2c_path]
    call aml_find
    test rax, rax
    jz .bad_i2c
    mov rdi, rax
    call itp_mmio_base
    jc .bad_i2c
    lea rcx, [rax + rdx]
    cmp rcx, [rel acpi_limit]
    ja .bad_i2c
    mov rdi, rax
    mov esi, ITP_I2C_CLOCK_KHZ
    call i2c_dw_attach
    test eax, eax
    js .bad_i2c
    mov [rel itp_i2c_ctrl], eax
    mov ebx, [rel itp_speed]
    lea r12, [rel itp_i2c_path]
    call itp_i2c_timing                 ; EAX high, EDX low, ECX hold
    mov r8d, ecx
    mov ecx, edx
    mov edx, eax
    mov edi, [rel itp_i2c_ctrl]
    mov esi, [rel itp_speed]
    call i2c_dw_set_speed
    test eax, eax
    jnz .bad_i2c

    ; 5. the interrupt: through the GPIO controller, or the touchpad's own
    mov eax, [rel itp_pin]
    cmp eax, -1
    je .plain_irq
    lea rdi, [rel itp_gpio_path]
    call aml_find
    test rax, rax
    jz .bad_gpio
    mov rdi, rax
    call itp_mmio_base                  ; also its interrupt into itp_gsi
    jc .bad_gpio
    lea rcx, [rax + rdx]
    cmp rcx, [rel acpi_limit]
    ja .bad_gpio
    cmp dword [rel itp_gsi], -1
    je .bad_gpio
    mov rdi, rax
    mov esi, ITP_GPIO_PINS
    call gpio_amd_attach
    test eax, eax
    js .bad_gpio
    mov [rel itp_gpio_ctrl], eax
    mov r14d, [rel itp_gsi]
    mov r13d, [rel itp_gsi_flags]
    lea rbx, [rel itp_gpio_isr]
    jmp .route
.plain_irq:
    lea rbx, [rel itp_plain_isr]
.route:
    call vector_alloc
    cmp eax, IOAPIC_VECTOR_FIRST
    jb .bad_route
    cmp eax, IOAPIC_VECTOR_LAST
    ja .bad_route
    mov [rel itp_vector], eax
    mov edi, eax
    mov rsi, rbx
    xor edx, edx
    call register_idt_handler
    ; the interrupt descriptor's flags into IOAPIC flags, routed masked
    xor r12d, r12d
    test r13d, AML_RES_EDGE
    jnz .edge
    or r12d, IOAPIC_GSI_LEVEL
.edge:
    test r13d, AML_RES_ACTIVE_LOW
    jz .high
    or r12d, IOAPIC_GSI_LOW
.high:
    mov [rel itp_gsi], r14d             ; the line routed (for the ISRs)
    mov [rel itp_route_flags], r12d
    mov edi, r14d
    mov esi, [rel itp_vector]
    mov edx, [rel smp_bsp_apic_id]
    mov ecx, r12d
    or ecx, IOAPIC_GSI_MASKED
    call ioapic_route_gsi
    jc .bad_route

    ; 6. the device itself
    lea rax, [rel i2c_write_read]
    mov [rel i2c_hid_xfer_fn], rax
    lea rax, [rel udelay]
    mov [rel i2c_hid_delay_fn], rax
    mov edi, [rel itp_i2c_ctrl]
    mov esi, [rel itp_addr]
    mov edx, [rel itp_desc_reg]
    call i2c_hid_probe
    test eax, eax
    js .bad_probe
    mov [rel itp_dev], eax
    ; GPIO: the pin as the touchpad's interrupt, re-armed after each report
    cmp dword [rel itp_pin], -1
    jne .gpio_pin
    ; a plain interrupt: masked by its handler, unmasked after each report
    mov edi, [rel itp_dev]
    lea rsi, [rel itp_after_plain]
    xor edx, edx
    call i2c_hid_set_after
    jmp .unmask
.gpio_pin:
    mov edi, [rel itp_gpio_ctrl]
    mov esi, [rel itp_pin]
    mov edx, ITP_OWNER
    call gpio_claim
    test eax, eax
    jnz .bad_gpio
    ; mode from the GPIO descriptor's flags
    xor ecx, ecx
    mov eax, [rel itp_pin_flags]
    test eax, AML_RES_EDGE
    jz .pin_low
    or ecx, GPIO_IRQ_EDGE
.pin_low:
    test eax, AML_RES_ACTIVE_LOW
    jz .pin_both
    or ecx, GPIO_IRQ_LOW
.pin_both:
    test eax, AML_RES_BOTH_EDGES
    jz .pin_mode
    or ecx, GPIO_IRQ_BOTH | GPIO_IRQ_EDGE
.pin_mode:
    mov edi, [rel itp_gpio_ctrl]
    mov esi, [rel itp_pin]
    mov edx, ITP_OWNER
    lea r8, [rel itp_pin_handler]
    mov r9d, [rel itp_dev]
    call gpio_irq_setup
    test eax, eax
    jnz .bad_gpio
    mov edi, [rel itp_dev]
    lea rsi, [rel itp_after]
    xor edx, edx
    call i2c_hid_set_after
.unmask:
    mov edi, r14d
    mov esi, [rel itp_vector]
    mov edx, [rel smp_bsp_apic_id]
    mov ecx, r12d
    call ioapic_route_gsi
    mov dword [rel itp_state], 1
    lea rsi, [rel msg_itp_ready]
    call uart_print_str
    mov eax, [rel itp_addr]
    call uart_print_hex64
    lea rsi, [rel msg_itp_pin]
    call uart_print_str
    mov eax, [rel itp_pin]
    call uart_print_dec
    lea rsi, [rel msg_itp_crlf]
    call uart_print_str
    jmp .out

.no_device:
    lea rsi, [rel msg_itp_none]
    jmp .print
.bad_crs:
    lea rsi, [rel msg_itp_crs]
    jmp .print
.bad_dsm:
    lea rsi, [rel msg_itp_dsm]
    jmp .print
.bad_i2c:
    lea rsi, [rel msg_itp_i2c]
    jmp .print
.bad_gpio:
    lea rsi, [rel msg_itp_gpio]
    jmp .print
.bad_route:
    lea rsi, [rel msg_itp_route]
    jmp .print
.bad_probe:
    mov ebx, eax
    lea rsi, [rel msg_itp_probe]
    call uart_print_str
    mov eax, ebx
    neg eax
    call uart_print_dec
    lea rsi, [rel msg_itp_crlf]
.print:
    call uart_print_str
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; itp_pin_handler — gpio_irq handler for the touchpad's pin (interrupt
;                   context): mark it for the fiber
; Input:  RDI = cookie (the i2c_hid device), ESI = pin
; -----------------------------------------------------------------------------
itp_pin_handler:
    jmp i2c_hid_attention

; -----------------------------------------------------------------------------
; itp_after — after each service: re-arm the level-triggered pin
; -----------------------------------------------------------------------------
itp_after:
    mov edi, [rel itp_gpio_ctrl]
    mov esi, [rel itp_pin]
    mov edx, ITP_OWNER
    jmp gpio_irq_unmask

; -----------------------------------------------------------------------------
; itp_after_plain — after each service of a plain interrupt: unmask it
; -----------------------------------------------------------------------------
itp_after_plain:
    mov edi, [rel itp_gsi]
    mov esi, [rel itp_vector]
    mov edx, [rel smp_bsp_apic_id]
    mov ecx, [rel itp_route_flags]
    jmp ioapic_route_gsi

; -----------------------------------------------------------------------------
; itp_gpio_isr — the GPIO controller's interrupt: dispatch its pins
; itp_plain_isr — the touchpad's own interrupt (no GPIO): mark it
; -----------------------------------------------------------------------------
%macro ITP_ISR_SAVE 0
    push rax
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    cld
%endmacro
%macro ITP_ISR_RESTORE 0
    call smp_lapic_eoi
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rax
    iretq
%endmacro

itp_gpio_isr:
    ITP_ISR_SAVE
    mov edi, [rel itp_gpio_ctrl]
    call gpio_irq
    ITP_ISR_RESTORE

itp_plain_isr:
    ITP_ISR_SAVE
    ; a level line stays asserted until the report is read: mask it
    mov edi, [rel itp_gsi]
    mov esi, [rel itp_vector]
    mov edx, [rel smp_bsp_apic_id]
    mov ecx, [rel itp_route_flags]
    or ecx, IOAPIC_GSI_MASKED
    call ioapic_route_gsi
    mov edi, [rel itp_dev]
    call i2c_hid_attention
    ITP_ISR_RESTORE

%endif ; LIB_INPUT_KERNEL_TOUCHPAD_ASM
