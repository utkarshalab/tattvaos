; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/events.asm
; =============================================================================
; ACPI events: the SCI, the fixed events (power and sleep button), the
; general-purpose events (GPEs), and Notify.
;
;   acpi_events_init     the FADT's event and control blocks; ACPI mode;
;                        every GPE with a _Lxx or _Exx method (or the
;                        embedded controller's) enabled
;   acpi_ev_sci_irq         the SCI (interrupt context): what fired is masked
;                        and marked
;   acpi_events_service  on a fiber: runs the GPE methods and embedded
;                        controller queries for what fired, re-enables them,
;                        and hands queued Notify to the lid and button hooks
;   acpi_events_notify   aml_notify_fn: Notify is queued, since the
;                        interpreter cannot be re-entered from inside a method
;
; Consumers (lib/input) set acpi_lid_fn (EDI = 1 closed, 0 open) and
; acpi_button_fn (EDI = 1 power, 2 sleep). Ports go through acpi_port_in_fn
; and acpi_port_out_fn (kernel.asm), so host tests stand in for hardware.
; A GPE firing more than ACPI_GPE_STORM times a second stays disabled.
; Only I/O-space event blocks are supported, which is what x86 firmware
; uses.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_EVENTS_ASM
%define LIB_IO_ACPI_AML_EVENTS_ASM

; FADT offsets
%define FADT_SCI_INT        46
%define FADT_SMI_CMD        48
%define FADT_ACPI_ENABLE    52
%define FADT_PM1A_EVT       56
%define FADT_PM1B_EVT       60
%define FADT_PM1A_CNT       64
%define FADT_PM1B_CNT       68
%define FADT_GPE0           80
%define FADT_GPE1           84
%define FADT_PM1_EVT_LEN    88
%define FADT_GPE0_LEN       92
%define FADT_GPE1_LEN       93
%define FADT_GPE1_BASE      94
%define FADT_FLAGS          112
%define FADT_X_PM1A_EVT     148         ; generic addresses, 12 bytes each
%define FADT_X_PM1B_EVT     160
%define FADT_X_PM1A_CNT     172
%define FADT_X_PM1B_CNT     184
%define FADT_X_GPE0         220
%define FADT_X_GPE1         232

%define FADT_F_PWR_BUTTON   (1 << 4)    ; set: a control-method power button
%define FADT_F_SLP_BUTTON   (1 << 5)
%define FADT_F_HW_REDUCED   (1 << 20)

%define PM1_PWRBTN          (1 << 8)
%define PM1_SLPBTN          (1 << 9)
%define PM1_CNT_SCI_EN      (1 << 0)

%define ACPI_MAX_GPE        256
%define ACPI_GPE_LEVEL      1
%define ACPI_GPE_EDGE       2
%define ACPI_GPE_EC         3
%define ACPI_GPE_STORM      1000        ; per second
%define ACPI_NOTIFY_QUEUE   32
%define ACPI_ENABLE_POLLS   100000

section .bss
alignb 8
acpi_fadt:          resq 1
global acpi_pm1a_evt
acpi_pm1a_evt:      resd 1          ; ports (0: none)
acpi_pm1b_evt:      resd 1
acpi_pm1_half:      resd 1          ; bytes of the status half
acpi_pm1a_cnt:      resd 1
acpi_pm1b_cnt:      resd 1
global acpi_gpe0
acpi_gpe0:          resd 1
acpi_gpe0_half:     resd 1          ; status bytes (enable bytes follow)
acpi_gpe1:          resd 1
acpi_gpe1_half:     resd 1
acpi_gpe1_base:     resd 1
global acpi_sci_int
acpi_sci_int:       resd 1
acpi_fixed_enabled: resd 1          ; PM1 enable bits we set
acpi_fixed_pending: resd 1          ; PM1 bits fired, not yet handled
acpi_gpe_node:      resq 1          ; \_GPE
global acpi_gpe_type
acpi_gpe_type:      resb ACPI_MAX_GPE
acpi_gpe_pending:   resb ACPI_MAX_GPE / 8
acpi_gpe_storm:     resb ACPI_MAX_GPE / 8   ; disabled for firing too often
alignb 8
acpi_gpe_window:    resq ACPI_MAX_GPE
acpi_gpe_count:     resd ACPI_MAX_GPE
global acpi_gpes_enabled
acpi_gpes_enabled:  resd 1
global acpi_gpe_runs
acpi_gpe_runs:      resd 1          ; GPE methods run
global acpi_gpe_storms
acpi_gpe_storms:    resd 1
global acpi_sci_count
acpi_sci_count:     resd 1
acpi_events_ready:  resd 1
acpi_any_pending:   resd 1
; Notify queue: node, value
alignb 8
acpi_notify_q:      resq ACPI_NOTIFY_QUEUE * 2
global acpi_notify_head
acpi_notify_head:   resd 1
global acpi_notify_tail
acpi_notify_tail:   resd 1
global acpi_notify_dropped
acpi_notify_dropped: resd 1
global acpi_notifies
acpi_notifies:      resd 1          ; Notify not for the lid or a button
alignb 8
global acpi_lid_node
acpi_lid_node:      resq 1
acpi_power_node:    resq 1
acpi_sleep_node:    resq 1
global acpi_lid_fn
acpi_lid_fn:        resq 1          ; EDI = 1 closed, 0 open
global acpi_button_fn
acpi_button_fn:     resq 1          ; EDI = 1 power, 2 sleep
acpi_ev_value:      resb aml_value_size
acpi_ev_name:       resb 8          ; a node name being printed

section .rodata
acpi_ev_id_lid:     db "PNP0C0D", 0
acpi_ev_id_power:   db "PNP0C0C", 0
acpi_ev_id_sleep:   db "PNP0C0E", 0
acpi_ev_gpe_path:   db "\_GPE", 0
msg_acpi_events:    db "ACPI: events: SCI ", 0
msg_acpi_gpes:      db ", GPEs enabled ", 0
msg_acpi_storm:     db "ACPI: GPE firing too often, left disabled: ", 0
msg_acpi_mode:      db "ACPI: could not switch to ACPI mode", 0x0D, 0x0A, 0
msg_acpi_ev_crlf:   db 0x0D, 0x0A, 0
msg_acpi_ev_notify: db "ACPI: Notify ", 0
msg_acpi_ev_value:  db " value ", 0

section .text

; -----------------------------------------------------------------------------
; acpi_in, acpi_out — ports through the hooks
; acpi_in:  EDI = port, ESI = width in bits → EAX
; acpi_out: EDI = port, ESI = width in bits, EDX = value
; Clobber the caller-saved registers.
; -----------------------------------------------------------------------------
acpi_in:
    mov rax, [rel acpi_port_in_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    ret

acpi_out:
    mov rax, [rel acpi_port_out_fn]
    sub rsp, 8
    call rax
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; acpi_fadt_port — an event or control block: the 64-bit generic address if
;                  the FADT has one in I/O space, else the 32-bit field
; Input:  RBX = FADT, ECX = 32-bit field offset, EDX = generic address
;         offset
; Output: EAX = the port, or 0
; -----------------------------------------------------------------------------
acpi_fadt_port:
    mov eax, edx
    add eax, 12
    cmp [rbx + 4], eax
    jb .legacy
    cmp byte [rbx + rdx], 1             ; system I/O
    jne .legacy
    mov rax, [rbx + rdx + 4]
    test rax, rax
    jz .legacy
    cmp rax, 0xFFFF
    ja .none
    ret
.legacy:
    mov eax, [rbx + rcx]
    cmp eax, 0xFFFF
    ja .none
    ret
.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; acpi_gpe_ports — a GPE's status and enable ports
; Input:  EDI = GPE number
; Output: CF = 0 with EAX = status port, EDX = enable port, ECX = bit;
;         CF = 1 for a GPE in no block
; -----------------------------------------------------------------------------
acpi_gpe_ports:
    mov eax, [rel acpi_gpe0]
    test eax, eax
    jz .block1
    mov ecx, [rel acpi_gpe0_half]
    shl ecx, 3                          ; GPEs in block 0
    cmp edi, ecx
    jae .block1
    mov ecx, edi
    shr ecx, 3
    add eax, ecx                        ; status byte
    lea edx, [rax]
    add edx, [rel acpi_gpe0_half]
    mov ecx, edi
    and ecx, 7
    clc
    ret
.block1:
    mov eax, [rel acpi_gpe1]
    test eax, eax
    jz .none
    mov ecx, edi
    sub ecx, [rel acpi_gpe1_base]
    jb .none
    mov r8d, [rel acpi_gpe1_half]
    shl r8d, 3
    cmp ecx, r8d
    jae .none
    mov r8d, ecx
    shr r8d, 3
    add eax, r8d
    lea edx, [rax]
    add edx, [rel acpi_gpe1_half]
    and ecx, 7
    clc
    ret
.none:
    stc
    ret

; -----------------------------------------------------------------------------
; acpi_gpe_enable — set or clear a GPE's enable bit
; Input:  EDI = GPE, ESI = 1 / 0
; -----------------------------------------------------------------------------
acpi_gpe_enable:
    push rbx
    push r12
    push r13
    mov r12d, esi
    call acpi_gpe_ports
    jc .out
    mov ebx, edx                        ; enable port
    mov r13d, ecx                       ; bit
    mov edi, ebx
    mov esi, 8
    call acpi_in
    btr eax, r13d
    test r12d, r12d
    jz .write
    bts eax, r13d
.write:
    mov edx, eax
    mov edi, ebx
    mov esi, 8
    call acpi_out
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_gpe_clear — clear a GPE's status (write 1 to its bit)
; Input:  EDI = GPE
; -----------------------------------------------------------------------------
acpi_gpe_clear:
    sub rsp, 8
    call acpi_gpe_ports
    jc .out
    mov edi, eax
    mov edx, 1
    shl edx, cl
    mov esi, 8
    call acpi_out
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; acpi_gpe_seg — the name _Lxx or _Exx for a GPE
; Input:  EDI = GPE, ESI = 'L' or 'E'
; Output: EAX = the name segment
; -----------------------------------------------------------------------------
acpi_gpe_seg:
    mov eax, edi
    shr eax, 4
    and eax, 0x0F
    add eax, '0'
    cmp eax, '9'
    jbe .hi
    add eax, 'A' - '9' - 1
.hi:
    mov ecx, edi
    and ecx, 0x0F
    add ecx, '0'
    cmp ecx, '9'
    jbe .lo
    add ecx, 'A' - '9' - 1
.lo:
    shl ecx, 24
    shl eax, 16
    or eax, ecx
    shl esi, 8
    or eax, esi
    or eax, '_'
    ret

; -----------------------------------------------------------------------------
; acpi_events_init — event blocks, ACPI mode, GPEs, buttons and the lid
; Output: EAX = 0, or -1 when the machine has no usable event blocks
; -----------------------------------------------------------------------------
global acpi_events_init
acpi_events_init:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov dword [rel acpi_events_ready], 0
    mov dword [rel acpi_gpes_enabled], 0
    ; the Notify queue is kept: _INI methods may already have queued some
    mov dword [rel acpi_any_pending], 0
    mov dword [rel acpi_fixed_pending], 0
    lea rdi, [rel acpi_gpe_type]
    mov ecx, ACPI_MAX_GPE + ACPI_MAX_GPE / 8 * 2
    xor eax, eax
    rep stosb
    lea rdi, [rel acpi_gpe_window]
    mov ecx, ACPI_MAX_GPE * 12
    rep stosb
    ; the lid and buttons Notify talks about, whatever the
    ; event hardware: Notify reaches them through GPE and EC methods too
    lea rdi, [rel acpi_ev_id_lid]
    xor esi, esi
    call aml_find_device
    mov [rel acpi_lid_node], rax
    lea rdi, [rel acpi_ev_id_power]
    xor esi, esi
    call aml_find_device
    mov [rel acpi_power_node], rax
    lea rdi, [rel acpi_ev_id_sleep]
    xor esi, esi
    call aml_find_device
    mov [rel acpi_sleep_node], rax

    mov rbx, [rel acpi_fadt]
    test rbx, rbx
    jz .none
    test dword [rbx + FADT_FLAGS], FADT_F_HW_REDUCED
    jnz .none                           ; no SCI or fixed hardware

    movzx eax, word [rbx + FADT_SCI_INT]
    mov [rel acpi_sci_int], eax
    mov ecx, FADT_PM1A_EVT
    mov edx, FADT_X_PM1A_EVT
    call acpi_fadt_port
    mov [rel acpi_pm1a_evt], eax
    mov ecx, FADT_PM1B_EVT
    mov edx, FADT_X_PM1B_EVT
    call acpi_fadt_port
    mov [rel acpi_pm1b_evt], eax
    movzx eax, byte [rbx + FADT_PM1_EVT_LEN]
    shr eax, 1
    mov [rel acpi_pm1_half], eax
    mov ecx, FADT_PM1A_CNT
    mov edx, FADT_X_PM1A_CNT
    call acpi_fadt_port
    mov [rel acpi_pm1a_cnt], eax
    mov ecx, FADT_PM1B_CNT
    mov edx, FADT_X_PM1B_CNT
    call acpi_fadt_port
    mov [rel acpi_pm1b_cnt], eax
    mov ecx, FADT_GPE0
    mov edx, FADT_X_GPE0
    call acpi_fadt_port
    mov [rel acpi_gpe0], eax
    movzx eax, byte [rbx + FADT_GPE0_LEN]
    shr eax, 1
    mov [rel acpi_gpe0_half], eax
    mov ecx, FADT_GPE1
    mov edx, FADT_X_GPE1
    call acpi_fadt_port
    mov [rel acpi_gpe1], eax
    movzx eax, byte [rbx + FADT_GPE1_LEN]
    shr eax, 1
    mov [rel acpi_gpe1_half], eax
    movzx eax, byte [rbx + FADT_GPE1_BASE]
    mov [rel acpi_gpe1_base], eax
    cmp dword [rel acpi_pm1a_evt], 0
    je .none
    cmp dword [rel acpi_pm1_half], 0
    je .none

    ; ACPI mode: SCI_EN, or ask the firmware for it
    mov edi, [rel acpi_pm1a_cnt]
    test edi, edi
    jz .mode_done
    mov esi, 16
    call acpi_in
    test eax, PM1_CNT_SCI_EN
    jnz .mode_done
    mov edi, [rbx + FADT_SMI_CMD]
    movzx edx, byte [rbx + FADT_ACPI_ENABLE]
    test edi, edi
    jz .mode_failed
    test edx, edx
    jz .mode_failed
    mov esi, 8
    call acpi_out
    mov r12d, ACPI_ENABLE_POLLS
.mode_wait:
    mov edi, [rel acpi_pm1a_cnt]
    mov esi, 16
    call acpi_in
    test eax, PM1_CNT_SCI_EN
    jnz .mode_done
    dec r12d
    jnz .mode_wait
.mode_failed:
    lea rsi, [rel msg_acpi_mode]
    call uart_print_str
.mode_done:

    ; every GPE off and clear, then on for those with a method
    mov r12d, 0
.gpe_off:
    cmp r12d, ACPI_MAX_GPE
    jae .gpe_scan
    mov edi, r12d
    call acpi_gpe_ports
    jc .gpe_off_next
    mov r13d, eax                       ; status
    mov r14d, edx                       ; enable
    mov r15d, ecx
    test r15d, r15d
    jnz .gpe_off_next                   ; once per byte
    mov edi, r14d
    mov esi, 8
    xor edx, edx
    call acpi_out
    mov edi, r13d
    mov esi, 8
    mov edx, 0xFF
    call acpi_out
.gpe_off_next:
    inc r12d
    jmp .gpe_off
.gpe_scan:
    lea rdi, [rel acpi_ev_gpe_path]
    call aml_find
    mov [rel acpi_gpe_node], rax
    xor r12d, r12d
.gpe:
    cmp r12d, ACPI_MAX_GPE
    jae .gpes_done
    mov edi, r12d
    call acpi_gpe_ports
    jc .gpe_next
    ; the embedded controller's GPE is its own
    cmp dword [rel acpi_ec_ready], 0
    je .methods
    cmp r12d, [rel acpi_ec_gpe]
    jne .methods
    mov r13d, ACPI_GPE_EC
    jmp .enable
.methods:
    mov r14, [rel acpi_gpe_node]
    test r14, r14
    jz .gpe_next
    mov edi, r12d
    mov esi, 'L'
    call acpi_gpe_seg
    mov rdi, r14
    mov esi, eax
    call aml_child
    mov r13d, ACPI_GPE_LEVEL
    test rax, rax
    jnz .enable
    mov edi, r12d
    mov esi, 'E'
    call acpi_gpe_seg
    mov rdi, r14
    mov esi, eax
    call aml_child
    mov r13d, ACPI_GPE_EDGE
    test rax, rax
    jz .gpe_next
.enable:
    lea rcx, [rel acpi_gpe_type]
    mov [rcx + r12], r13b
    mov edi, r12d
    mov esi, 1
    call acpi_gpe_enable
    inc dword [rel acpi_gpes_enabled]
.gpe_next:
    inc r12d
    jmp .gpe

.gpes_done:
    ; fixed buttons: clear, then enable those not done by methods
    xor r12d, r12d
    test dword [rbx + FADT_FLAGS], FADT_F_PWR_BUTTON
    jnz .slp
    or r12d, PM1_PWRBTN
.slp:
    test dword [rbx + FADT_FLAGS], FADT_F_SLP_BUTTON
    jnz .fixed
    or r12d, PM1_SLPBTN
.fixed:
    mov [rel acpi_fixed_enabled], r12d
    mov edi, [rel acpi_pm1a_evt]
    mov esi, 16
    mov edx, PM1_PWRBTN | PM1_SLPBTN
    call acpi_out                       ; clear their status
    mov edi, [rel acpi_pm1a_evt]
    add edi, [rel acpi_pm1_half]
    mov esi, 16
    mov edx, r12d
    call acpi_out                       ; enable

    mov dword [rel acpi_events_ready], 1
    lea rsi, [rel msg_acpi_events]
    call uart_print_str
    mov eax, [rel acpi_sci_int]
    call uart_print_dec
    lea rsi, [rel msg_acpi_gpes]
    call uart_print_str
    mov eax, [rel acpi_gpes_enabled]
    call uart_print_dec
    lea rsi, [rel msg_acpi_ev_crlf]
    call uart_print_str
    xor eax, eax
    jmp .out
.none:
    mov eax, -1
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ev_sci_irq — the SCI (interrupt context): mask and mark what fired
; Output: EAX = events marked
; -----------------------------------------------------------------------------
global acpi_ev_sci_irq
acpi_ev_sci_irq:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r15d, r15d
    cmp dword [rel acpi_events_ready], 0
    je .out
    inc dword [rel acpi_sci_count]
    ; fixed events
    mov edi, [rel acpi_pm1a_evt]
    mov esi, 16
    call acpi_in
    mov ebx, eax
    mov edi, [rel acpi_pm1b_evt]
    test edi, edi
    jz .pm1
    mov esi, 16
    call acpi_in
    or ebx, eax
.pm1:
    and ebx, [rel acpi_fixed_enabled]
    jz .gpes
    or [rel acpi_fixed_pending], ebx
    mov edi, [rel acpi_pm1a_evt]
    mov esi, 16
    mov edx, ebx
    call acpi_out                       ; clear (write 1)
    mov edi, [rel acpi_pm1b_evt]
    test edi, edi
    jz .fixed_done
    mov esi, 16
    mov edx, ebx
    call acpi_out
.fixed_done:
    inc r15d
    mov dword [rel acpi_any_pending], 1
.gpes:
    ; GPEs, a byte at a time
    xor r12d, r12d                      ; GPE number of the byte's bit 0
.byte:
    cmp r12d, ACPI_MAX_GPE
    jae .out
    mov edi, r12d
    call acpi_gpe_ports
    jc .next_byte
    mov r13d, eax                       ; status port
    mov r14d, edx                       ; enable port
    mov edi, r13d
    mov esi, 8
    call acpi_in
    mov ebx, eax
    mov edi, r14d
    mov esi, 8
    call acpi_in
    and ebx, eax
    jz .next_byte
    ; mask them all, mark them, clear the edge ones now
    not ebx
    and eax, ebx
    not ebx
    mov edx, eax
    mov edi, r14d
    mov esi, 8
    call acpi_out
    xor ecx, ecx
.bit:
    cmp ecx, 8
    jae .next_byte
    bt ebx, ecx
    jnc .next_bit
    lea eax, [r12 + rcx]
    bts [rel acpi_gpe_pending], eax
    inc r15d
    lea rdx, [rel acpi_gpe_type]
    cmp byte [rdx + rax], ACPI_GPE_LEVEL
    je .next_bit
    push rcx
    sub rsp, 8
    mov edi, r13d
    mov edx, 1
    shl edx, cl
    mov esi, 8
    call acpi_out
    add rsp, 8
    pop rcx
.next_bit:
    inc ecx
    jmp .bit
.next_byte:
    add r12d, 8
    jmp .byte
.out:
    test r15d, r15d
    jz .ret
    mov dword [rel acpi_any_pending], 1
.ret:
    mov eax, r15d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_events_notify — aml_notify_fn: queue it (RDI = node, RSI = value)
; -----------------------------------------------------------------------------
global acpi_events_notify
acpi_events_notify:
    mov eax, [rel acpi_notify_tail]
    mov ecx, eax
    sub ecx, [rel acpi_notify_head]
    cmp ecx, ACPI_NOTIFY_QUEUE
    jae .full
    and eax, ACPI_NOTIFY_QUEUE - 1
    shl eax, 4
    lea rcx, [rel acpi_notify_q]
    mov [rcx + rax], rdi
    mov [rcx + rax + 8], rsi
    inc dword [rel acpi_notify_tail]
    ret
.full:
    inc dword [rel acpi_notify_dropped]
    ret

; -----------------------------------------------------------------------------
; acpi_lid_state — the lid now: EAX = 1 closed, 0 open, -1 unknown
; -----------------------------------------------------------------------------
global acpi_lid_state
acpi_lid_state:
    sub rsp, 8
    mov rdi, [rel acpi_lid_node]
    test rdi, rdi
    jz .unknown
    mov esi, AML_SEG('_','L','I','D')
    lea rdx, [rel acpi_ev_value]
    call aml_eval_child_of
    test eax, eax
    jnz .unknown
    lea rdi, [rel acpi_ev_value]
    xor esi, esi
    call aml_to_int
    test eax, eax
    jnz .unknown
    xor eax, eax
    test rdx, rdx
    setz al                             ; _LID: 0 closed
    add rsp, 8
    ret
.unknown:
    mov eax, -1
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; acpi_events_service — run what the SCI marked (fiber; the only place AML
;                       runs after start-up)
; Output: EAX = events handled
; -----------------------------------------------------------------------------
global acpi_events_service
acpi_events_service:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r15d, r15d
    cmp dword [rel acpi_events_ready], 0
    je .notifies
    xor eax, eax
    xchg eax, [rel acpi_any_pending]
    test eax, eax
    jz .notifies

    ; fixed buttons
    xor ebx, ebx
    xchg ebx, [rel acpi_fixed_pending]
    test ebx, PM1_PWRBTN
    jz .sleep_btn
    mov edi, 1
    call acpi_report_button
    inc r15d
.sleep_btn:
    test ebx, PM1_SLPBTN
    jz .gpes
    mov edi, 2
    call acpi_report_button
    inc r15d

.gpes:
    xor r12d, r12d
.gpe:
    cmp r12d, ACPI_MAX_GPE
    jae .notifies
    btr [rel acpi_gpe_pending], r12d
    jnc .next
    inc r15d
    call acpi_gpe_storm_check
    jc .next                            ; left disabled
    lea rcx, [rel acpi_gpe_type]
    movzx r13d, byte [rcx + r12]
    cmp r13d, ACPI_GPE_EC
    je .ec
    ; the method
    mov edi, r12d
    mov esi, 'L'
    cmp r13d, ACPI_GPE_LEVEL
    je .seg
    mov esi, 'E'
.seg:
    call acpi_gpe_seg
    mov rdi, [rel acpi_gpe_node]
    test rdi, rdi
    jz .rearm
    mov esi, eax
    lea rdx, [rel acpi_ev_value]
    call aml_eval_child_of
    inc dword [rel acpi_gpe_runs]
    jmp .rearm
.ec:
    call acpi_ec_query_all
.rearm:
    cmp r13d, ACPI_GPE_LEVEL
    jne .enable
    mov edi, r12d
    call acpi_gpe_clear                 ; level: cleared after the method
.enable:
    mov edi, r12d
    mov esi, 1
    call acpi_gpe_enable
.next:
    inc r12d
    jmp .gpe

.notifies:
    ; Notify queued by the methods
    mov eax, [rel acpi_notify_head]
    cmp eax, [rel acpi_notify_tail]
    je .out
    and eax, ACPI_NOTIFY_QUEUE - 1
    shl eax, 4
    lea rcx, [rel acpi_notify_q]
    mov rbx, [rcx + rax]                ; node
    mov r12, [rcx + rax + 8]            ; value
    inc dword [rel acpi_notify_head]
    inc r15d
    cmp rbx, [rel acpi_lid_node]
    je .lid
    cmp r12, 0x80                       ; a button press
    jne .other
    cmp rbx, [rel acpi_power_node]
    je .power
    cmp rbx, [rel acpi_sleep_node]
    je .sleep
    jmp .other
.lid:
    call acpi_lid_state
    test eax, eax
    js .notifies
    mov rcx, [rel acpi_lid_fn]
    test rcx, rcx
    jz .notifies
    mov edi, eax
    call rcx
    jmp .notifies
.power:
    mov edi, 1
    call acpi_report_button
    jmp .notifies
.sleep:
    mov edi, 2
    call acpi_report_button
    jmp .notifies
.other:
    mov rdi, rbx                        ; a battery, the adapter, a zone
    mov rsi, r12
    call acpi_power_notify
    test eax, eax
    jnz .notifies
    inc dword [rel acpi_notifies]
    lea rsi, [rel msg_acpi_ev_notify]
    call uart_print_str
    mov eax, [rbx + aml_node.name]
    mov [rel acpi_ev_name], eax
    lea rsi, [rel acpi_ev_name]
    call uart_print_str
    lea rsi, [rel msg_acpi_ev_value]
    call uart_print_str
    mov rax, r12
    call uart_print_hex64
    lea rsi, [rel msg_acpi_ev_crlf]
    call uart_print_str
    jmp .notifies
.out:
    mov eax, r15d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; EDI = 1 power, 2 sleep
acpi_report_button:
    mov rax, [rel acpi_button_fn]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; acpi_gpe_storm_check — R12D = GPE; CF = 1 (and left disabled) when it has
;                        fired more than ACPI_GPE_STORM times in a second
; -----------------------------------------------------------------------------
acpi_gpe_storm_check:
    sub rsp, 8
    bt [rel acpi_gpe_storm], r12d
    jc .stormy
    mov rax, [rel aml_clock_fn]
    test rax, rax
    jz .fine
    call rax
    lea rcx, [rel acpi_gpe_window]
    mov rdx, rax
    sub rdx, [rcx + r12 * 8]
    cmp rdx, 1000000000
    jb .counted
    mov [rcx + r12 * 8], rax
    lea rcx, [rel acpi_gpe_count]
    mov dword [rcx + r12 * 4], 0
.counted:
    lea rcx, [rel acpi_gpe_count]
    inc dword [rcx + r12 * 4]
    cmp dword [rcx + r12 * 4], ACPI_GPE_STORM
    jbe .fine
    bts [rel acpi_gpe_storm], r12d
    inc dword [rel acpi_gpe_storms]
    lea rsi, [rel msg_acpi_storm]
    call uart_print_str
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_acpi_ev_crlf]
    call uart_print_str
.stormy:
    add rsp, 8
    stc
    ret
.fine:
    add rsp, 8
    clc
    ret

%endif ; LIB_IO_ACPI_AML_EVENTS_ASM
