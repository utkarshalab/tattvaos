; =============================================================================
; Utkarsha OS — lib/io/gpio/gpio.asm
; =============================================================================
; GPIO pins and their interrupts, for every driver that needs one: the
; I2C-HID touchpad's interrupt, Bluetooth power and wake lines, reset pins.
;
;   gpio_amd_attach(base, pins)                 a controller → its number
;   gpio_claim(ctrl, pin, owner)                take a pin (owner: any
;   gpio_release(ctrl, pin, owner)              nonzero value of the driver)
;   gpio_get(ctrl, pin)                         its level
;   gpio_set / gpio_direction / gpio_pull / gpio_debounce / gpio_wake
;   gpio_irq_setup(ctrl, pin, owner, mode, handler, cookie)
;   gpio_irq_unmask / gpio_irq_disable
;   gpio_irq(ctrl)                              the controller's interrupt
;
; Only a pin's owner may change it; anyone may read it. Handlers run in
; interrupt context: handler(RDI = cookie, ESI = pin). A level-triggered
; pin is masked before its handler runs and stays masked until its owner
; calls gpio_irq_unmask, after the device has been serviced. A pin that
; interrupts too often (GPIO_STORM_COUNT within GPIO_STORM_NS) is masked
; and reported; the others keep working.
;
; Register access goes through gpio_read32_fn and gpio_write32_fn, so host
; tests can stand in for the hardware.
;
; AMD controllers (ACPI AMDI0030 and relatives): one 32-bit register per
; pin; two summary registers with one bit per group of four pins; an
; end-of-interrupt bit in the master register. The layout below has not
; yet been checked against hardware.
; =============================================================================

%ifndef LIB_IO_GPIO_GPIO_ASM
%define LIB_IO_GPIO_GPIO_ASM

%include "lib/io/gpio/gpio.inc"

; AMD pin register bits
%define AMD_DB_TIME_MASK    0x0F        ; debounce count
%define AMD_DB_UNIT         (1 << 4)
%define AMD_DB_CTRL_SHIFT   5
%define AMD_DB_CTRL_MASK    (3 << 5)
%define AMD_DB_REMOVE_GLITCH (3 << 5)
%define AMD_DB_LARGE        (1 << 7)
%define AMD_LEVEL_TRIG      (1 << 8)    ; 1 level, 0 edge
%define AMD_ACTIVE_SHIFT    9           ; 0 high, 1 low, 2 both edges
%define AMD_ACTIVE_MASK     (3 << 9)
%define AMD_INT_ENABLE      (1 << 11)
%define AMD_INT_DELIVER     (1 << 12)   ; 1: the interrupt reaches the CPU
%define AMD_WAKE_MASK       (7 << 13)   ; wake from S0i3, S3, S4/S5
%define AMD_PIN_LEVEL       (1 << 16)
%define AMD_PULL_UP         (1 << 20)
%define AMD_PULL_DOWN       (1 << 21)
%define AMD_OUTPUT_VALUE    (1 << 22)
%define AMD_OUTPUT_ENABLE   (1 << 23)
%define AMD_INT_STATUS      (1 << 28)   ; write 1 to clear
%define AMD_WAKE_STATUS     (1 << 29)   ; write 1 to clear
%define AMD_W1C             (AMD_INT_STATUS | AMD_WAKE_STATUS)

%define AMD_REG_STATUS0     0x2F8       ; pins 0-127, a bit per four pins
%define AMD_REG_STATUS1     0x2FC       ; pins 128-255
%define AMD_REG_MASTER      0xFC
%define AMD_MASTER_EOI      (1 << 29)

section .data
align 8
global gpio_read32_fn
gpio_read32_fn:     dq gpio_mmio_read32     ; RDI = address → EAX
global gpio_write32_fn
gpio_write32_fn:    dq gpio_mmio_write32    ; RDI = address, ESI = value
global gpio_clock_fn
gpio_clock_fn:      dq 0                    ; RAX = monotonic ns (storms)

section .bss
alignb 8
gpio_ctrl_base:     resq GPIO_MAX_CTRL
gpio_ctrl_kind:     resd GPIO_MAX_CTRL
gpio_ctrl_pins:     resd GPIO_MAX_CTRL
gpio_owner:         resq GPIO_MAX_CTRL * GPIO_MAX_PINS
gpio_handler:       resq GPIO_MAX_CTRL * GPIO_MAX_PINS
gpio_cookie:        resq GPIO_MAX_CTRL * GPIO_MAX_PINS
gpio_window:        resq GPIO_MAX_CTRL * GPIO_MAX_PINS   ; storm window start
gpio_count:         resd GPIO_MAX_CTRL * GPIO_MAX_PINS   ; interrupts in it
global gpio_pin_flags
gpio_pin_flags:     resb GPIO_MAX_CTRL * GPIO_MAX_PINS
global gpio_spurious
gpio_spurious:      resd 1              ; interrupts no handler wanted
global gpio_storms
gpio_storms:        resd 1              ; pins masked as storms
global gpio_dispatched
gpio_dispatched:    resd 1              ; handler calls

section .text

gpio_mmio_read32:
    mov eax, [rdi]
    ret

gpio_mmio_write32:
    mov [rdi], esi
    ret

; -----------------------------------------------------------------------------
; gpio_rd, gpio_wr — register access through the hooks
; gpio_rd: RDI = address → EAX.  gpio_wr: RDI = address, ESI = value.
; Clobber the caller-saved registers.
; -----------------------------------------------------------------------------
gpio_rd:
    mov rax, [rel gpio_read32_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    ret

gpio_wr:
    mov rax, [rel gpio_write32_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; gpio_index — check a controller and pin
; Input:  EDI = controller, ESI = pin
; Output: CF = 0 with RAX = table index (controller * 256 + pin) and
;         RDX = the pin register's address; CF = 1 when either is invalid
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
gpio_index:
    cmp edi, GPIO_MAX_CTRL
    jae .bad
    lea rcx, [rel gpio_ctrl_kind]
    cmp dword [rcx + rdi * 4], GPIO_KIND_NONE
    je .bad
    lea rcx, [rel gpio_ctrl_pins]
    cmp esi, [rcx + rdi * 4]
    jae .bad
    lea rcx, [rel gpio_ctrl_base]
    mov rdx, [rcx + rdi * 8]
    lea rdx, [rdx + rsi * 4]
    mov eax, edi
    shl eax, 8
    add eax, esi
    clc
    ret
.bad:
    stc
    ret

; -----------------------------------------------------------------------------
; gpio_owned — check that OWNER (RDX in) owns the pin
; Input:  EDI = controller, ESI = pin, RDX = owner
; Output: CF = 0 with RAX = index and R8 = register address;
;         CF = 1 with EAX = -GPIO_EINVAL (bad pin, no owner given, or the
;         pin is unclaimed) or -GPIO_EBUSY (another owner has it)
; Clobbers: RAX, RCX, RDX, R8, R9
; -----------------------------------------------------------------------------
gpio_owned:
    mov r9, rdx
    test r9, r9
    jz .invalid
    call gpio_index
    jc .invalid
    mov r8, rdx
    lea rcx, [rel gpio_owner]
    mov rdx, [rcx + rax * 8]
    test rdx, rdx
    jz .invalid                         ; nobody claimed it: claim it first
    cmp rdx, r9
    jne .busy                           ; someone else's
    clc
    ret
.invalid:
    mov eax, -GPIO_EINVAL
    stc
    ret
.busy:
    mov eax, -GPIO_EBUSY
    stc
    ret

; -----------------------------------------------------------------------------
; gpio_rmw — change a pin register: clear CLEAR bits, set SET bits, and
;            never write 1 to the write-1-to-clear status bits
; Input:  R8 = register address, ECX = bits to clear, EDX = bits to set
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
gpio_rmw:
    push rbx
    push r12
    push r13
    mov rbx, r8
    mov r12d, ecx
    mov r13d, edx
    mov rdi, rbx
    call gpio_rd
    not r12d
    and eax, r12d
    or eax, r13d
    and eax, ~AMD_W1C
    mov rdi, rbx
    mov esi, eax
    call gpio_wr
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_amd_attach — add an AMD controller
; Input:  RDI = register base (mapped), ESI = pin count (1-256)
; Output: EAX = controller number, -GPIO_EINVAL or -GPIO_ENOSPC
; -----------------------------------------------------------------------------
global gpio_amd_attach
gpio_amd_attach:
    test rdi, rdi
    jz .invalid
    test esi, esi
    jz .invalid
    cmp esi, GPIO_MAX_PINS
    ja .invalid
    lea rcx, [rel gpio_ctrl_kind]
    xor eax, eax
.slot:
    cmp eax, GPIO_MAX_CTRL
    jae .full
    cmp dword [rcx + rax * 4], GPIO_KIND_NONE
    je .free
    inc eax
    jmp .slot
.free:
    mov dword [rcx + rax * 4], GPIO_KIND_AMD
    lea rcx, [rel gpio_ctrl_base]
    mov [rcx + rax * 8], rdi
    lea rcx, [rel gpio_ctrl_pins]
    mov [rcx + rax * 4], esi
    ; empty tables for its pins
    push rax
    mov edx, eax
    shl edx, 8
    xor ecx, ecx
.clear:
    lea r8d, [rdx + rcx]
    lea r9, [rel gpio_owner]
    mov qword [r9 + r8 * 8], 0
    lea r9, [rel gpio_handler]
    mov qword [r9 + r8 * 8], 0
    lea r9, [rel gpio_cookie]
    mov qword [r9 + r8 * 8], 0
    lea r9, [rel gpio_window]
    mov qword [r9 + r8 * 8], 0
    lea r9, [rel gpio_count]
    mov dword [r9 + r8 * 4], 0
    lea r9, [rel gpio_pin_flags]
    mov byte [r9 + r8], 0
    inc ecx
    cmp ecx, GPIO_MAX_PINS
    jb .clear
    pop rax
    ret
.invalid:
    mov eax, -GPIO_EINVAL
    ret
.full:
    mov eax, -GPIO_ENOSPC
    ret

; -----------------------------------------------------------------------------
; gpio_detach_all — forget every controller (start-up and tests)
; -----------------------------------------------------------------------------
global gpio_detach_all
gpio_detach_all:
    lea rcx, [rel gpio_ctrl_kind]
    mov dword [rcx], GPIO_KIND_NONE
    mov dword [rcx + 4], GPIO_KIND_NONE
    xor eax, eax
    mov [rel gpio_spurious], eax
    mov [rel gpio_storms], eax
    mov [rel gpio_dispatched], eax
    ret

; -----------------------------------------------------------------------------
; gpio_claim — take a pin
; Input:  EDI = controller, ESI = pin, RDX = owner (nonzero)
; Output: EAX = 0, -GPIO_EBUSY (someone else has it) or -GPIO_EINVAL
; -----------------------------------------------------------------------------
global gpio_claim
gpio_claim:
    test rdx, rdx
    jz .invalid
    mov r9, rdx
    call gpio_index
    jc .invalid
    lea rcx, [rel gpio_owner]
    mov rdx, [rcx + rax * 8]
    test rdx, rdx
    jz .take
    cmp rdx, r9
    je .ok                              ; already its own
    mov eax, -GPIO_EBUSY
    ret
.take:
    mov [rcx + rax * 8], r9
.ok:
    xor eax, eax
    ret
.invalid:
    mov eax, -GPIO_EINVAL
    ret

; -----------------------------------------------------------------------------
; gpio_release — give a pin back; its interrupt is turned off
; Input:  EDI = controller, ESI = pin, RDX = owner
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_release
gpio_release:
    push rbx
    push r12
    push r13
    mov ebx, edi
    mov r12d, esi
    mov r13, rdx
    call gpio_irq_disable
    test eax, eax
    jnz .out
    mov edi, ebx
    mov esi, r12d
    call gpio_index
    lea rcx, [rel gpio_owner]
    mov qword [rcx + rax * 8], 0
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_get — a pin's input level
; Input:  EDI = controller, ESI = pin
; Output: EAX = 0 or 1, or -GPIO_EINVAL
; -----------------------------------------------------------------------------
global gpio_get
gpio_get:
    call gpio_index
    jc .invalid
    sub rsp, 8
    mov rdi, rdx
    call gpio_rd
    add rsp, 8
    shr eax, 16
    and eax, 1
    ret
.invalid:
    mov eax, -GPIO_EINVAL
    ret

; -----------------------------------------------------------------------------
; gpio_set — drive an output pin
; Input:  EDI = controller, ESI = pin, RDX = owner, ECX = 0 or 1
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_set
gpio_set:
    push rbx
    mov ebx, ecx
    call gpio_owned
    jc .out
    mov ecx, AMD_OUTPUT_VALUE
    xor edx, edx
    test ebx, ebx
    jz .write
    xor ecx, ecx
    mov edx, AMD_OUTPUT_VALUE
.write:
    call gpio_rmw
    xor eax, eax
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_direction — input, or output with a starting value
; Input:  EDI = controller, ESI = pin, RDX = owner, ECX = 1 output / 0
;         input, R8D = the output value
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_direction
gpio_direction:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, ecx
    mov r12d, r8d
    call gpio_owned
    jc .out
    test ebx, ebx
    jnz .output
    mov ecx, AMD_OUTPUT_ENABLE
    xor edx, edx
    call gpio_rmw
    jmp .ok
.output:
    ; the value first, so the pin never shows the wrong level
    mov ecx, AMD_OUTPUT_VALUE
    xor edx, edx
    test r12d, r12d
    jz .value
    xor ecx, ecx
    mov edx, AMD_OUTPUT_VALUE
.value:
    or edx, AMD_OUTPUT_ENABLE
    call gpio_rmw
.ok:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_pull — pull-up, pull-down or neither
; Input:  EDI = controller, ESI = pin, RDX = owner, ECX = GPIO_PULL_*
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_pull
gpio_pull:
    push rbx
    mov ebx, ecx
    cmp ebx, GPIO_PULL_DOWN
    ja .invalid
    call gpio_owned
    jc .out
    mov ecx, AMD_PULL_UP | AMD_PULL_DOWN
    xor edx, edx
    cmp ebx, GPIO_PULL_UP
    jne .down
    mov edx, AMD_PULL_UP
.down:
    cmp ebx, GPIO_PULL_DOWN
    jne .write
    mov edx, AMD_PULL_DOWN
.write:
    call gpio_rmw
    xor eax, eax
    jmp .out
.invalid:
    mov eax, -GPIO_EINVAL
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_debounce — filter glitches shorter than a time
; Input:  EDI = controller, ESI = pin, RDX = owner, ECX = microseconds
;         (0 turns debouncing off; 1 000 000 and more is -GPIO_EINVAL)
; The hardware counts in steps of about 61 us, 244 us, 15.6 ms or
; 62.5 ms; the time is rounded down to a whole number of steps.
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_debounce
gpio_debounce:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, ecx
    call gpio_owned
    jc .out
    mov r12, r8
    ; EDX = the new debounce bits
    test ebx, ebx
    jz .off
    cmp ebx, 1000000
    jae .invalid
    cmp ebx, 61
    jae .fine
    mov edx, 1                          ; one step: the shortest filter
    jmp .set
.fine:
    cmp ebx, 976
    jae .unit
    mov eax, ebx
    xor edx, edx
    mov ecx, 61
    div ecx
    mov edx, eax
    jmp .set
.unit:
    cmp ebx, 3900
    jae .large
    mov eax, ebx
    xor edx, edx
    mov ecx, 244
    div ecx
    mov edx, eax
    or edx, AMD_DB_UNIT
    jmp .set
.large:
    cmp ebx, 250000
    jae .large_unit
    mov eax, ebx
    xor edx, edx
    mov ecx, 15625
    div ecx
    mov edx, eax
    or edx, AMD_DB_LARGE
    jmp .set
.large_unit:
    mov eax, ebx
    xor edx, edx
    mov ecx, 62500
    div ecx
    mov edx, eax
    or edx, AMD_DB_LARGE | AMD_DB_UNIT
.set:
    or edx, AMD_DB_REMOVE_GLITCH
    jmp .write
.off:
    xor edx, edx
.write:
    mov r8, r12
    mov ecx, AMD_DB_TIME_MASK | AMD_DB_UNIT | AMD_DB_CTRL_MASK | AMD_DB_LARGE
    call gpio_rmw
    xor eax, eax
    jmp .out
.invalid:
    mov eax, -GPIO_EINVAL
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_wake — let the pin wake the machine from sleep, or not
; Input:  EDI = controller, ESI = pin, RDX = owner, ECX = 1 / 0
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_wake
gpio_wake:
    push rbx
    mov ebx, ecx
    call gpio_owned
    jc .out
    mov ecx, AMD_WAKE_MASK
    xor edx, edx
    test ebx, ebx
    jz .write
    xor ecx, ecx
    mov edx, AMD_WAKE_MASK
.write:
    call gpio_rmw
    xor eax, eax
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_irq_setup — take a pin's interrupt
; Input:  EDI = controller, ESI = pin, RDX = owner, ECX = GPIO_IRQ_* mode,
;         R8 = handler, R9 = cookie
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_irq_setup
gpio_irq_setup:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, ecx
    mov r12, r8
    mov r13, r9
    test r12, r12
    jz .invalid
    test ebx, GPIO_IRQ_BOTH             ; both edges only in edge mode
    jz .mode_ok
    test ebx, GPIO_IRQ_EDGE
    jz .invalid
.mode_ok:
    call gpio_owned
    jc .out
    mov r14, rax                        ; index
    mov r15, r8                         ; register
    lea rcx, [rel gpio_handler]
    mov [rcx + r14 * 8], r12
    lea rcx, [rel gpio_cookie]
    mov [rcx + r14 * 8], r13
    lea rcx, [rel gpio_count]
    mov dword [rcx + r14 * 4], 0
    lea rcx, [rel gpio_window]
    mov qword [rcx + r14 * 8], 0
    ; the register: trigger, polarity, enable, deliver
    xor edx, edx
    mov al, GPIO_PIN_IRQ
    test ebx, GPIO_IRQ_EDGE
    jnz .edge
    or edx, AMD_LEVEL_TRIG
    or al, GPIO_PIN_LEVEL
.edge:
    lea rcx, [rel gpio_pin_flags]
    mov [rcx + r14], al
    test ebx, GPIO_IRQ_BOTH
    jz .low
    or edx, 2 << AMD_ACTIVE_SHIFT
    jmp .enable
.low:
    test ebx, GPIO_IRQ_LOW
    jz .enable
    or edx, 1 << AMD_ACTIVE_SHIFT
.enable:
    or edx, AMD_INT_ENABLE | AMD_INT_DELIVER
    mov r8, r15
    mov ecx, AMD_LEVEL_TRIG | AMD_ACTIVE_MASK | AMD_INT_ENABLE | AMD_INT_DELIVER
    call gpio_rmw
    xor eax, eax
    jmp .out
.invalid:
    mov eax, -GPIO_EINVAL
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_irq_unmask — deliver a level-triggered pin's interrupts again
;                   (after its device has been serviced), or a pin masked
;                   as a storm
; Input:  EDI = controller, ESI = pin, RDX = owner
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_irq_unmask
gpio_irq_unmask:
    push rbx
    call gpio_owned
    jc .out
    lea rcx, [rel gpio_pin_flags]
    test byte [rcx + rax], GPIO_PIN_IRQ
    jz .invalid
    and byte [rcx + rax], ~GPIO_PIN_STORM
    lea rcx, [rel gpio_count]
    mov dword [rcx + rax * 4], 0
    ; clear the status latched while masked, and deliver again in the same
    ; write: a line still asserted latches again at once, a released one
    ; does not fire a stale interrupt
    mov rbx, r8
    mov rdi, rbx
    call gpio_rd
    and eax, ~AMD_WAKE_STATUS
    or eax, AMD_INT_STATUS | AMD_INT_DELIVER
    mov esi, eax
    mov rdi, rbx
    call gpio_wr
    xor eax, eax
    jmp .out
.invalid:
    mov eax, -GPIO_EINVAL
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_irq_disable — stop a pin's interrupt and forget its handler
; Input:  EDI = controller, ESI = pin, RDX = owner
; Output: EAX = 0 or a negative error
; -----------------------------------------------------------------------------
global gpio_irq_disable
gpio_irq_disable:
    sub rsp, 8
    call gpio_owned
    jc .out
    lea rcx, [rel gpio_pin_flags]
    mov byte [rcx + rax], 0
    lea rcx, [rel gpio_handler]
    mov qword [rcx + rax * 8], 0
    mov ecx, AMD_INT_ENABLE | AMD_INT_DELIVER
    xor edx, edx
    call gpio_rmw
    xor eax, eax
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; gpio_irq — a controller's interrupt: run the handler of every pin with
;            its status set, clear the status, signal end of interrupt
; Input:  EDI = controller
; Output: EAX = handlers called, or -GPIO_EINVAL
; Interrupt context.
; -----------------------------------------------------------------------------
global gpio_irq
gpio_irq:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 8
    cmp edi, GPIO_MAX_CTRL
    jae .invalid
    lea rcx, [rel gpio_ctrl_kind]
    cmp dword [rcx + rdi * 4], GPIO_KIND_AMD
    jne .invalid
    mov ebx, edi                        ; controller
    lea rcx, [rel gpio_ctrl_base]
    mov r12, [rcx + rbx * 8]            ; base
    xor r15d, r15d                      ; handlers called
    ; the summary: bit N means one of pins 4N .. 4N+3
    lea rdi, [r12 + AMD_REG_STATUS0]
    call gpio_rd
    mov r13d, eax
    lea rdi, [r12 + AMD_REG_STATUS1]
    call gpio_rd
    shl rax, 32
    or r13, rax
.group:
    test r13, r13
    jz .eoi
    bsf rcx, r13
    btr r13, rcx
    lea r14d, [rcx * 4]                 ; first pin of the group
    lea ebp, [r14 + 4]                  ; one past the last
.pin:
    cmp r14d, ebp
    jae .group
    lea rcx, [rel gpio_ctrl_pins]
    cmp r14d, [rcx + rbx * 4]
    jae .group
    mov edi, ebx
    mov esi, r14d
    call gpio_pin_irq
    add r15d, eax
    inc r14d
    jmp .pin
.eoi:
    lea rdi, [r12 + AMD_REG_MASTER]
    call gpio_rd
    or eax, AMD_MASTER_EOI
    mov esi, eax
    lea rdi, [r12 + AMD_REG_MASTER]
    call gpio_wr
    mov eax, r15d
    jmp .out
.invalid:
    mov eax, -GPIO_EINVAL
.out:
    add rsp, 8
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; gpio_pin_irq — one pin during gpio_irq
; Input:  EDI = controller, ESI = pin
; Output: EAX = 1 when its handler ran, else 0
; -----------------------------------------------------------------------------
gpio_pin_irq:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r14d, esi                       ; pin
    call gpio_index
    mov rbx, rax                        ; index
    mov r12, rdx                        ; register
    mov rdi, r12
    call gpio_rd
    test eax, AMD_INT_STATUS
    jz .none
    mov r13d, eax                       ; the register as read
    lea rcx, [rel gpio_pin_flags]
    movzx r15d, byte [rcx + rbx]
    test r15d, GPIO_PIN_IRQ
    jz .spurious
    lea rcx, [rel gpio_handler]
    cmp qword [rcx + rbx * 8], 0
    je .spurious

    ; storm check
    mov rax, [rel gpio_clock_fn]
    test rax, rax
    jz .deliver
    call rax
    lea rcx, [rel gpio_window]
    mov rdx, rax
    sub rdx, [rcx + rbx * 8]
    cmp rdx, GPIO_STORM_NS
    jb .counted
    mov [rcx + rbx * 8], rax            ; a new window
    lea rcx, [rel gpio_count]
    mov dword [rcx + rbx * 4], 0
.counted:
    lea rcx, [rel gpio_count]
    inc dword [rcx + rbx * 4]
    cmp dword [rcx + rbx * 4], GPIO_STORM_COUNT
    jbe .deliver
    ; a storm: mask it, keep the handler for a later unmask
    inc dword [rel gpio_storms]
    lea rcx, [rel gpio_pin_flags]
    or byte [rcx + rbx], GPIO_PIN_STORM
    mov esi, r13d
    and esi, ~(AMD_INT_DELIVER | AMD_WAKE_STATUS)
    or esi, AMD_INT_STATUS
    mov rdi, r12
    call gpio_wr
    jmp .none

.deliver:
    ; clear the status; a level pin is masked until its owner unmasks it
    mov esi, r13d
    and esi, ~AMD_WAKE_STATUS
    or esi, AMD_INT_STATUS
    test r15d, GPIO_PIN_LEVEL
    jz .write
    and esi, ~AMD_INT_DELIVER
.write:
    mov rdi, r12
    call gpio_wr
    inc dword [rel gpio_dispatched]
    lea rcx, [rel gpio_cookie]
    mov rdi, [rcx + rbx * 8]
    mov esi, r14d
    lea rcx, [rel gpio_handler]
    call [rcx + rbx * 8]
    mov eax, 1
    jmp .out
.spurious:
    ; nobody wants it: turn it off so it cannot keep firing
    inc dword [rel gpio_spurious]
    mov esi, r13d
    and esi, ~(AMD_INT_ENABLE | AMD_INT_DELIVER | AMD_WAKE_STATUS)
    or esi, AMD_INT_STATUS
    mov rdi, r12
    call gpio_wr
.none:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_IO_GPIO_GPIO_ASM
