; =============================================================================
; Utkarsha OS — lib/input/kernel.asm
; =============================================================================
; lib/input inside the kernel: the input fiber, the IRQ 1 handler, and
; start-up. Included by kernel/entry.asm after lib/input/input.asm.
;
; Start-up has two steps, because kernel_main creates fibers before the
; other CPUs start and routes interrupts only after the I/O APICs are set:
;   input_kernel_prepare  before smp_start: empty state, the input fiber
;   input_kernel_start    after ioapic_init: the clock, the PS/2 keyboard,
;                         IRQ 1
; Neither step stops the boot: a machine without a PS/2 keyboard just has
; no PS/2 keyboard.
; =============================================================================

%ifndef LIB_INPUT_KERNEL_ASM
%define LIB_INPUT_KERNEL_ASM

%define INPUT_PS2_KBD_IRQ   1

section .data
msg_input_fiber_failed: db "INPUT: fiber_create failed; no input events", 0x0D, 0x0A, 0
msg_input_no_ps2:       db "INPUT: no PS/2 keyboard", 0x0D, 0x0A, 0
msg_input_no_vector:    db "INPUT: no interrupt vector for the PS/2 keyboard", 0x0D, 0x0A, 0
msg_input_no_route:     db "INPUT: IRQ 1 could not be routed", 0x0D, 0x0A, 0
msg_input_ps2_ready:    db "INPUT: PS/2 keyboard on IRQ 1", 0x0D, 0x0A, 0

section .bss
alignb 4
input_ps2_vector:   resd 1

section .text

; -----------------------------------------------------------------------------
; input_kernel_prepare — empty state and the input fiber (before smp_start)
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_kernel_prepare
input_kernel_prepare:
    sub rsp, 8
    call input_init
    mov rdi, input_fiber
    xor rsi, rsi
    mov rdx, PRIO_NORMAL
    mov rcx, FIBER_RESTART_ALWAYS       ; events must keep flowing
    call fiber_create
    test rax, rax
    jnz .out
    mov rsi, msg_input_fiber_failed
    call uart_print_str
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; input_kernel_start — the clock, the PS/2 keyboard and IRQ 1
;                      (after ioapic_init, on the BSP)
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_kernel_start
input_kernel_start:
    push rbx
    lea rax, [rel mono_get_nanos]
    mov [rel input_clock_fn], rax

    call ps2_init
    test eax, eax
    jnz .no_ps2

    call vector_alloc
    cmp eax, IOAPIC_VECTOR_FIRST
    jb .no_vector
    cmp eax, IOAPIC_VECTOR_LAST
    ja .no_vector
    mov ebx, eax
    mov [rel input_ps2_vector], eax
    mov edi, eax
    lea rsi, [rel input_ps2_isr]
    xor edx, edx
    call register_idt_handler

    ; route while masked, then unmask once the route is complete
    mov edi, INPUT_PS2_KBD_IRQ
    mov esi, ebx
    mov edx, [rel smp_bsp_apic_id]
    mov ecx, 1
    call ioapic_route_legacy_irq
    jc .no_route
    mov edi, INPUT_PS2_KBD_IRQ
    mov esi, ebx
    mov edx, [rel smp_bsp_apic_id]
    xor ecx, ecx
    call ioapic_route_legacy_irq
    jc .no_route

    call i8042_irq_enable
    mov rsi, msg_input_ps2_ready
    call uart_print_str
    jmp .out
.no_ps2:
    mov rsi, msg_input_no_ps2
    call uart_print_str
    jmp .out
.no_vector:
    mov rsi, msg_input_no_vector
    call uart_print_str
    jmp .out
.no_route:
    mov rsi, msg_input_no_route
    call uart_print_str
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; input_fiber — deliver events and run the drivers' fiber-side work, forever
; -----------------------------------------------------------------------------
input_fiber:
    sub rsp, 8                          ; align the SysV calls below
.loop:
    call input_pump
    call ps2_kbd_service
    call fiber_yield
    jmp .loop

; -----------------------------------------------------------------------------
; input_ps2_isr — IRQ 1: read the keyboard's bytes, queue their events
; -----------------------------------------------------------------------------
input_ps2_isr:
    ; the CPU leaves RSP at 8 mod 16; nine pushes make it 0 for the calls
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
    call i8042_irq
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

%endif ; LIB_INPUT_KERNEL_ASM
