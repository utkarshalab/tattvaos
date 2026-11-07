; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/power.asm
; =============================================================================
; Batteries, the AC adapter and thermal zones, as data for kernel/power and
; the OS (ROADMAP.md §4.6). Mechanism only: what to do about a low battery
; or a hot CPU is kernel/power's policy.
;
;   acpi_power_init         find them and read them once
;   acpi_battery_info(i)    acpi_battery*: static information and state
;   acpi_ac_state()         1 online, 0 offline, -1 no adapter
;   acpi_thermal_info(i)    acpi_thermal*: temperature and trip points
;   acpi_power_notify       from the event service: Notify on one of them
;                           refreshes it and calls acpi_power_fn
;
; Batteries: _BIX (or _BIF on older firmware) for what does not change,
; _BST for the state. Values the firmware does not know are 0xFFFFFFFF.
; Thermal: _TMP and the _CRT, _HOT, _PSV trip points, all in tenths of a
; kelvin from firmware, kept here in tenths of a degree Celsius. A zone at
; or over its critical point is always reported.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_POWER_ASM
%define LIB_IO_ACPI_AML_POWER_ASM

%define ACPI_MAX_BATTERIES  2
%define ACPI_MAX_THERMAL    4
%define ACPI_UNKNOWN        0xFFFFFFFF
%define ACPI_STR_MAX        24

%define BAT_DISCHARGING     (1 << 0)
%define BAT_CHARGING        (1 << 1)
%define BAT_CRITICAL        (1 << 2)

; what acpi_power_fn is told changed (EDI), and which one (ESI)
%define POWER_BATTERY       1
%define POWER_AC            2
%define POWER_THERMAL       3

struc acpi_battery
    .node:          resq 1
    .present:       resd 1          ; from _STA bit 4
    .unit:          resd 1          ; 0 mWh/mW, 1 mAh/mA
    .design:        resd 1          ; design capacity
    .full:          resd 1          ; last full charge
    .design_mv:     resd 1
    .warning:       resd 1
    .low:           resd 1
    .technology:    resd 1          ; 0 primary, 1 rechargeable
    .cycles:        resd 1          ; _BIX only, else unknown
    .state:         resd 1          ; BAT_*
    .rate:          resd 1          ; present rate
    .remaining:     resd 1
    .voltage:       resd 1          ; present, mV
    .percent:       resd 1          ; 0-100, or unknown
    .model:         resb ACPI_STR_MAX
    .serial:        resb ACPI_STR_MAX
    .kind:          resb ACPI_STR_MAX   ; "LION" and the like
    .oem:           resb ACPI_STR_MAX
endstruc

struc acpi_thermal
    .node:          resq 1
    .temp:          resd 1          ; tenths of °C, or unknown
    .critical:      resd 1          ; trip points, tenths of °C, or unknown
    .hot:           resd 1
    .passive:       resd 1
    .over:          resd 1          ; 1 at or over critical
    .pad:           resd 1
endstruc

section .bss
alignb 8
global acpi_batteries
acpi_batteries:     resb ACPI_MAX_BATTERIES * acpi_battery_size
global acpi_battery_count
acpi_battery_count: resd 1
global acpi_thermals
acpi_thermals:      resb ACPI_MAX_THERMAL * acpi_thermal_size
global acpi_thermal_count
acpi_thermal_count: resd 1
alignb 8
acpi_ac_node:       resq 1
global acpi_ac_online
acpi_ac_online:     resd 1          ; 1, 0, or -1 without an adapter
global acpi_power_fn
acpi_power_fn:      resq 1          ; EDI = what, ESI = which
global acpi_thermal_critical_count
acpi_thermal_critical_count: resd 1
alignb 8
acpi_pw_value:      resb aml_value_size

section .rodata
acpi_pw_id_bat:     db "PNP0C0A", 0
acpi_pw_id_ac:      db "ACPI0003", 0
msg_pw_battery:     db "ACPI: battery ", 0
msg_pw_colon:       db ": ", 0
msg_pw_percent:     db "%", 0
msg_pw_charging:    db ", charging", 0
msg_pw_discharging: db ", discharging", 0
msg_pw_absent:      db "not present", 0
msg_pw_ac:          db "ACPI: AC adapter ", 0
msg_pw_online:      db "online", 0
msg_pw_offline:     db "offline", 0
msg_pw_thermal:     db "ACPI: thermal zone ", 0
msg_pw_degrees:     db " C", 0
msg_pw_crit:        db " (critical ", 0
msg_pw_close:       db " C)", 0
msg_pw_over:        db " AT OR OVER ITS CRITICAL TEMPERATURE", 0
msg_pw_minus:       db "-", 0
msg_pw_crlf:        db 0x0D, 0x0A, 0

section .text

; -----------------------------------------------------------------------------
; acpi_pw_int — a package element as an integer (references followed)
; Input:  RSI = aml_value* of the element
; Output: EAX = the value, or ACPI_UNKNOWN when it is not one
; -----------------------------------------------------------------------------
acpi_pw_int:
    movzx ecx, byte [rsi + aml_value.type]
    cmp ecx, AML_T_REF
    jne .direct
    cmp byte [rsi + aml_value.sub], AML_REF_NODE
    jne .unknown
    mov rsi, [rsi + aml_value.data]
    lea rsi, [rsi + aml_node.value]
    movzx ecx, byte [rsi + aml_value.type]
.direct:
    cmp ecx, AML_T_INTEGER
    jne .unknown
    mov eax, [rsi + aml_value.data]
    ret
.unknown:
    mov eax, ACPI_UNKNOWN
    ret

; -----------------------------------------------------------------------------
; acpi_pw_str — a package element as text into RDI (ACPI_STR_MAX bytes)
; Input:  RSI = aml_value*, RDI = destination
; -----------------------------------------------------------------------------
acpi_pw_str:
    mov byte [rdi], 0
    movzx ecx, byte [rsi + aml_value.type]
    cmp ecx, AML_T_STRING
    je .bytes
    cmp ecx, AML_T_BUFFER
    jne .out
.bytes:
    mov r8, [rsi + aml_value.data]
    mov r9d, [rsi + aml_value.len]
    xor ecx, ecx
.byte:
    cmp ecx, r9d
    jae .end
    cmp ecx, ACPI_STR_MAX - 1
    jae .end
    mov al, [r8 + rcx]
    test al, al
    jz .end
    mov [rdi + rcx], al
    inc ecx
    jmp .byte
.end:
    mov byte [rdi + rcx], 0
.out:
    ret

; -----------------------------------------------------------------------------
; acpi_pw_eval — evaluate a child method of a node into acpi_pw_value
; Input:  RDI = node, ESI = name
; Output: ZF = 0 (jnz) on failure; else RSI = elements, ECX = count for a
;         package
; -----------------------------------------------------------------------------
acpi_pw_eval:
    sub rsp, 8
    lea rdx, [rel acpi_pw_value]
    call aml_eval_child_of
    add rsp, 8
    test eax, eax
    jnz .out
    mov rsi, [rel acpi_pw_value + aml_value.data]
    mov ecx, [rel acpi_pw_value + aml_value.len]
    xor eax, eax
.out:
    ret

; -----------------------------------------------------------------------------
; acpi_battery_static — _BIX, else _BIF, into the record at RBX
; -----------------------------------------------------------------------------
acpi_battery_static:
    push r12
    push r13
    push r14
    mov rdi, [rbx + acpi_battery.node]
    mov esi, AML_SEG('_','B','I','X')
    call acpi_pw_eval
    jnz .bif
    cmp byte [rel acpi_pw_value + aml_value.type], AML_T_PACKAGE
    jne .bif
    cmp ecx, 20
    jb .bif
    mov r12, rsi
    mov r13d, 1                         ; _BIX: everything one later, and
    mov r14d, 1                         ; the cycle count before the strings
    jmp .fields
.bif:
    mov rdi, [rbx + acpi_battery.node]
    mov esi, AML_SEG('_','B','I','F')
    call acpi_pw_eval
    jnz .out
    cmp byte [rel acpi_pw_value + aml_value.type], AML_T_PACKAGE
    jne .out
    cmp ecx, 13
    jb .out
    mov r12, rsi
    xor r13d, r13d
    xor r14d, r14d
.fields:
    ; unit, design, full, technology, design voltage, warning, low
%macro BAT_FIELD 2
    mov eax, %1
    add eax, r13d
    shl eax, 4
    lea rsi, [r12 + rax]
    call acpi_pw_int
    mov [rbx + %2], eax
%endmacro
    BAT_FIELD 0, acpi_battery.unit
    BAT_FIELD 1, acpi_battery.design
    BAT_FIELD 2, acpi_battery.full
    BAT_FIELD 3, acpi_battery.technology
    BAT_FIELD 4, acpi_battery.design_mv
    BAT_FIELD 5, acpi_battery.warning
    BAT_FIELD 6, acpi_battery.low
%unmacro BAT_FIELD 2
    mov dword [rbx + acpi_battery.cycles], ACPI_UNKNOWN
    test r14d, r14d
    jz .strings
    lea rsi, [r12 + 8 * 16]             ; _BIX element 8
    call acpi_pw_int
    mov [rbx + acpi_battery.cycles], eax
.strings:
    ; model, serial, type, OEM: _BIF 9-12, _BIX 16-19
    mov eax, 9
    test r14d, r14d
    jz .str_base
    mov eax, 16
.str_base:
    shl eax, 4
    lea r12, [r12 + rax]
    lea rdi, [rbx + acpi_battery.model]
    mov rsi, r12
    call acpi_pw_str
    lea rdi, [rbx + acpi_battery.serial]
    lea rsi, [r12 + 16]
    call acpi_pw_str
    lea rdi, [rbx + acpi_battery.kind]
    lea rsi, [r12 + 32]
    call acpi_pw_str
    lea rdi, [rbx + acpi_battery.oem]
    lea rsi, [r12 + 48]
    call acpi_pw_str
.out:
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; acpi_battery_state — _STA's battery-present bit and _BST, for RBX
; -----------------------------------------------------------------------------
acpi_battery_state:
    push r12
    mov dword [rbx + acpi_battery.present], 0
    mov dword [rbx + acpi_battery.percent], ACPI_UNKNOWN
    mov rdi, [rbx + acpi_battery.node]
    mov esi, AML_SEG('_','S','T','A')
    call acpi_pw_eval
    cmp eax, AML_NO_CHILD
    je .present                         ; no _STA: there
    test eax, eax
    jnz .out
    lea rsi, [rel acpi_pw_value]
    call acpi_pw_int
    test eax, 1 << 4                    ; a battery is in the slot
    jz .out
.present:
    mov dword [rbx + acpi_battery.present], 1
    mov rdi, [rbx + acpi_battery.node]
    mov esi, AML_SEG('_','B','S','T')
    call acpi_pw_eval
    jnz .out
    cmp byte [rel acpi_pw_value + aml_value.type], AML_T_PACKAGE
    jne .out
    cmp ecx, 4
    jb .out
    mov r12, rsi
    mov rsi, r12
    call acpi_pw_int
    mov [rbx + acpi_battery.state], eax
    lea rsi, [r12 + 16]
    call acpi_pw_int
    mov [rbx + acpi_battery.rate], eax
    lea rsi, [r12 + 32]
    call acpi_pw_int
    mov [rbx + acpi_battery.remaining], eax
    lea rsi, [r12 + 48]
    call acpi_pw_int
    mov [rbx + acpi_battery.voltage], eax
    ; percent of the last full charge
    mov eax, [rbx + acpi_battery.remaining]
    mov ecx, [rbx + acpi_battery.full]
    cmp eax, ACPI_UNKNOWN
    je .out
    cmp ecx, ACPI_UNKNOWN
    je .out
    test ecx, ecx
    jz .out
    imul rax, rax, 100
    xor edx, edx
    div rcx
    cmp eax, 100
    jbe .pct
    mov eax, 100
.pct:
    mov [rbx + acpi_battery.percent], eax
.out:
    pop r12
    ret

; -----------------------------------------------------------------------------
; acpi_pw_kelvin — a temperature method of the zone RBX into tenths of °C
; Input:  ESI = name
; Output: EAX = tenths of °C, or ACPI_UNKNOWN
; -----------------------------------------------------------------------------
acpi_pw_kelvin:
    sub rsp, 8
    mov rdi, [rbx + acpi_thermal.node]
    call acpi_pw_eval
    jnz .unknown
    lea rsi, [rel acpi_pw_value]
    call acpi_pw_int
    cmp eax, ACPI_UNKNOWN
    je .out
    sub eax, 2732                       ; tenths of a kelvin to tenths of °C
    jmp .out
.unknown:
    mov eax, ACPI_UNKNOWN
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; acpi_thermal_read — refresh the zone RBX; a critical one is reported
; -----------------------------------------------------------------------------
acpi_thermal_read:
    sub rsp, 8
    mov esi, AML_SEG('_','T','M','P')
    call acpi_pw_kelvin
    mov [rbx + acpi_thermal.temp], eax
    mov esi, AML_SEG('_','C','R','T')
    call acpi_pw_kelvin
    mov [rbx + acpi_thermal.critical], eax
    mov esi, AML_SEG('_','H','O','T')
    call acpi_pw_kelvin
    mov [rbx + acpi_thermal.hot], eax
    mov esi, AML_SEG('_','P','S','V')
    call acpi_pw_kelvin
    mov [rbx + acpi_thermal.passive], eax
    mov dword [rbx + acpi_thermal.over], 0
    mov eax, [rbx + acpi_thermal.temp]
    mov ecx, [rbx + acpi_thermal.critical]
    cmp eax, ACPI_UNKNOWN
    je .out
    cmp ecx, ACPI_UNKNOWN
    je .out
    cmp eax, ecx
    jl .out
    mov dword [rbx + acpi_thermal.over], 1
    inc dword [rel acpi_thermal_critical_count]
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; acpi_ac_read — _PSR of the adapter
; -----------------------------------------------------------------------------
acpi_ac_read:
    sub rsp, 8
    mov dword [rel acpi_ac_online], -1
    mov rdi, [rel acpi_ac_node]
    test rdi, rdi
    jz .out
    mov esi, AML_SEG('_','P','S','R')
    call acpi_pw_eval
    jnz .out
    lea rsi, [rel acpi_pw_value]
    call acpi_pw_int
    cmp eax, ACPI_UNKNOWN
    je .out
    xor ecx, ecx
    test eax, eax
    setnz cl
    mov [rel acpi_ac_online], ecx
.out:
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; acpi_power_init — find batteries, the adapter and thermal zones; read them
; -----------------------------------------------------------------------------
global acpi_power_init
acpi_power_init:
    push rbx
    push r12
    sub rsp, 8
    xor eax, eax
    mov [rel acpi_battery_count], eax
    mov [rel acpi_thermal_count], eax
    mov [rel acpi_thermal_critical_count], eax
    ; batteries
    xor r12d, r12d
.battery:
    cmp r12d, ACPI_MAX_BATTERIES
    jae .ac
    lea rdi, [rel acpi_pw_id_bat]
    mov esi, r12d
    call aml_find_device
    test rax, rax
    jz .ac
    mov ecx, r12d
    imul ecx, ecx, acpi_battery_size
    lea rbx, [rel acpi_batteries]
    add rbx, rcx
    mov rdi, rbx
    mov rcx, acpi_battery_size
    push rax
    xor eax, eax
    rep stosb
    pop rax
    mov [rbx + acpi_battery.node], rax
    call acpi_battery_static
    call acpi_battery_state
    inc dword [rel acpi_battery_count]
    mov edi, r12d
    call acpi_print_battery
    inc r12d
    jmp .battery
.ac:
    lea rdi, [rel acpi_pw_id_ac]
    xor esi, esi
    call aml_find_device
    mov [rel acpi_ac_node], rax
    call acpi_ac_read
    cmp dword [rel acpi_ac_online], -1
    je .thermal
    call acpi_print_ac
.thermal:
    xor r12d, r12d
.zone:
    cmp r12d, ACPI_MAX_THERMAL
    jae .out
    mov edi, AML_T_THERMAL
    mov esi, r12d
    call aml_find_type
    test rax, rax
    jz .out
    mov ecx, r12d
    imul ecx, ecx, acpi_thermal_size
    lea rbx, [rel acpi_thermals]
    add rbx, rcx
    mov [rbx + acpi_thermal.node], rax
    call acpi_thermal_read
    inc dword [rel acpi_thermal_count]
    mov edi, r12d
    call acpi_print_thermal
    inc r12d
    jmp .zone
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_battery_info, acpi_thermal_info — EDI = index → RAX = record or 0
; acpi_ac_state — EAX = 1 online, 0 offline, -1 no adapter
; -----------------------------------------------------------------------------
global acpi_battery_info
acpi_battery_info:
    xor eax, eax
    cmp edi, [rel acpi_battery_count]
    jae .out
    imul edi, edi, acpi_battery_size
    lea rax, [rel acpi_batteries]
    add rax, rdi
.out:
    ret

global acpi_thermal_info
acpi_thermal_info:
    xor eax, eax
    cmp edi, [rel acpi_thermal_count]
    jae .out
    imul edi, edi, acpi_thermal_size
    lea rax, [rel acpi_thermals]
    add rax, rdi
.out:
    ret

global acpi_ac_state
acpi_ac_state:
    mov eax, [rel acpi_ac_online]
    ret

; -----------------------------------------------------------------------------
; acpi_power_notify — Notify for a battery, the adapter or a zone
; Input:  RDI = node, RSI = value
; Output: EAX = 1 when it was one of them (refreshed), else 0
; -----------------------------------------------------------------------------
global acpi_power_notify
acpi_power_notify:
    push rbx
    push r12
    push r13
    mov r12, rdi
    mov r13, rsi
    ; a battery: 0x80 state, 0x81 information too
    xor ecx, ecx
.bat:
    cmp ecx, [rel acpi_battery_count]
    jae .ac
    mov eax, ecx
    imul eax, eax, acpi_battery_size
    lea rbx, [rel acpi_batteries]
    add rbx, rax
    cmp [rbx + acpi_battery.node], r12
    je .bat_hit
    inc ecx
    jmp .bat
.bat_hit:
    push rcx
    sub rsp, 8
    cmp r13d, 0x81
    jne .bat_state
    call acpi_battery_static
.bat_state:
    call acpi_battery_state
    add rsp, 8
    pop rcx
    mov edi, POWER_BATTERY
    mov esi, ecx
    jmp .changed
.ac:
    cmp r12, [rel acpi_ac_node]
    jne .zones
    call acpi_ac_read
    mov edi, POWER_AC
    xor esi, esi
    jmp .changed
.zones:
    xor ecx, ecx
.zone:
    cmp ecx, [rel acpi_thermal_count]
    jae .none
    mov eax, ecx
    imul eax, eax, acpi_thermal_size
    lea rbx, [rel acpi_thermals]
    add rbx, rax
    cmp [rbx + acpi_thermal.node], r12
    je .zone_hit
    inc ecx
    jmp .zone
.zone_hit:
    push rcx
    sub rsp, 8
    call acpi_thermal_read
    add rsp, 8
    pop rcx
    cmp dword [rbx + acpi_thermal.over], 0
    je .zone_quiet
    push rcx
    sub rsp, 8
    mov edi, ecx
    call acpi_print_thermal             ; critical: always said
    add rsp, 8
    pop rcx
.zone_quiet:
    mov edi, POWER_THERMAL
    mov esi, ecx
.changed:
    mov rax, [rel acpi_power_fn]
    test rax, rax
    jz .handled
    call rax
.handled:
    mov eax, 1
    jmp .out
.none:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_print_battery, acpi_print_ac, acpi_print_thermal — one console line
; -----------------------------------------------------------------------------
acpi_print_battery:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    call acpi_battery_info
    mov rbx, rax
    lea rsi, [rel msg_pw_battery]
    call uart_print_str
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_pw_colon]
    call uart_print_str
    cmp dword [rbx + acpi_battery.present], 0
    jne .present
    lea rsi, [rel msg_pw_absent]
    call uart_print_str
    jmp .end
.present:
    mov eax, [rbx + acpi_battery.percent]
    cmp eax, ACPI_UNKNOWN
    je .state
    call uart_print_dec
    lea rsi, [rel msg_pw_percent]
    call uart_print_str
.state:
    mov eax, [rbx + acpi_battery.state]
    test eax, BAT_CHARGING
    jz .dis
    lea rsi, [rel msg_pw_charging]
    call uart_print_str
    jmp .end
.dis:
    test eax, BAT_DISCHARGING
    jz .end
    lea rsi, [rel msg_pw_discharging]
    call uart_print_str
.end:
    lea rsi, [rel msg_pw_crlf]
    call uart_print_str
    add rsp, 8
    pop r12
    pop rbx
    ret

acpi_print_ac:
    sub rsp, 8
    lea rsi, [rel msg_pw_ac]
    call uart_print_str
    lea rsi, [rel msg_pw_online]
    cmp dword [rel acpi_ac_online], 1
    je .say
    lea rsi, [rel msg_pw_offline]
.say:
    call uart_print_str
    lea rsi, [rel msg_pw_crlf]
    call uart_print_str
    add rsp, 8
    ret

acpi_print_thermal:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, edi
    call acpi_thermal_info
    mov rbx, rax
    lea rsi, [rel msg_pw_thermal]
    call uart_print_str
    mov eax, r12d
    call uart_print_dec
    lea rsi, [rel msg_pw_colon]
    call uart_print_str
    mov eax, [rbx + acpi_thermal.temp]
    cmp eax, ACPI_UNKNOWN
    je .crlf
    call acpi_print_tenths
    lea rsi, [rel msg_pw_degrees]
    call uart_print_str
    mov eax, [rbx + acpi_thermal.critical]
    cmp eax, ACPI_UNKNOWN
    je .over
    lea rsi, [rel msg_pw_crit]
    call uart_print_str
    mov eax, [rbx + acpi_thermal.critical]
    call acpi_print_tenths
    lea rsi, [rel msg_pw_close]
    call uart_print_str
.over:
    cmp dword [rbx + acpi_thermal.over], 0
    je .crlf
    lea rsi, [rel msg_pw_over]
    call uart_print_str
.crlf:
    lea rsi, [rel msg_pw_crlf]
    call uart_print_str
    add rsp, 8
    pop r12
    pop rbx
    ret

; EAX = tenths of a degree → whole degrees (rounded toward zero)
acpi_print_tenths:
    sub rsp, 8
    test eax, eax
    jns .positive
    lea rsi, [rel msg_pw_minus]
    call uart_print_str
    neg eax
.positive:
    cdq
    mov ecx, 10
    idiv ecx
    call uart_print_dec
    add rsp, 8
    ret

%endif ; LIB_IO_ACPI_AML_POWER_ASM
