; UTM Enterprise - Command Line Interface
; Pure Assembly Implementation

%ifndef _UTM_CLI_ASM_
%define _UTM_ENTERPRISE_CLI_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .data
cli_usage:
    db "UTM Enterprise - Task Manager CLI", 10
    db "Usage: utm [command] [options]", 10, 10
    db "Commands:", 10
    db "  list              List all processes", 10
    db "  sample            Get system-wide sample", 10
    db "  top               Show top processes by CPU", 10
    db "  kill <pid>        Kill a process", 10
    db "  nice <pid> <val>  Change nice value", 10
    db "  flight start      Start flight recorder", 10
    db "  flight stop       Stop flight recorder", 10
    db "  metrics           Export Prometheus metrics", 10
    db "  version           Show version", 10
    db "  help              Show this help", 10, 0
cli_usage_len equ $ - cli_usage

cli_version:
    db "UTM Enterprise v1.0.0", 10
    db "Pure x86_64 Assembly Implementation", 10
    db "Built for UTM - Your Custom Assembly Operating System", 10, 0
cli_version_len equ $ - cli_version

cli_unknown_cmd:
    db "Unknown command: ", 0
cli_unknown_cmd_len equ $ - cli_unknown_cmd

cli_proc_header:
    db "PID    PPID    UID    CreateTick", 10
    db "--------------------------------------", 10, 0
cli_proc_header_len equ $ - cli_proc_header

cli_sys_header:
    db "UTM System Sample", 10
    db "=================", 10, 0
cli_sys_header_len equ $ - cli_sys_header

section .bss
cli_proc_buf:
    resb MAX_PROCESSES * PROC_IDENTITY_SIZE

cli_sys_buf:
    resb SYS_SAMPLE_SIZE

cli_metrics_buf:
    resb 65536

section .text

global _start
global cli_main

extern utm_term_write

_start:
    mov rdi, [rsp]
    lea rsi, [rsp + 8]
    call cli_main
    
    mov rax, 60
    xor rdi, rdi
    syscall

cli_main:
    cmp rdi, 1
    je .show_usage
    
    mov rdi, [rsi + 8]
    
    cmp dword [rdi], 0x7473696C
    jne .check_sample
    call cmd_list
    jmp .done
    
.check_sample:
    cmp dword [rdi], 0x706D6173
    jne .check_top
    call cmd_sample
    jmp .done
    
.check_top:
    cmp dword [rdi], 0x00706F74
    jne .check_kill
    call cmd_top
    jmp .done
    
.check_kill:
    cmp dword [rdi], 0x6C6C696B
    jne .check_nice
    call cmd_kill
    jmp .done
    
.check_nice:
    cmp dword [rdi], 0x6563696E
    jne .check_flight
    call cmd_nice
    jmp .done
    
.check_flight:
    cmp dword [rdi], 0x67696C66
    jne .check_metrics
    call cmd_flight
    jmp .done
    
.check_metrics:
    cmp dword [rdi], 0x7274656D
    jne .check_version
    call cmd_metrics
    jmp .done
    
.check_version:
    cmp dword [rdi], 0x73726576
    jne .show_usage
    call cmd_version
    jmp .done
    
.show_usage:
    mov rdi, cli_usage
    mov rsi, cli_usage_len
    call cli_write
    mov rax, 1
    jmp .done
    
.done:
    ret

cli_write:
    mov rax, 1
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, 1
    syscall
    ret

cmd_list:
    mov rdi, cli_proc_buf
    mov rsi, MAX_PROCESSES
    mov rax, SYS_UTM_GET_PROC_LIST
    syscall
    
    test rax, rax
    jl cmd_sample_error
    
    mov rdi, cli_proc_header
    mov rsi, cli_proc_header_len
    call cli_write
    
    mov rcx, rax
    mov rsi, cli_proc_buf
.list_loop:
    push rcx
    
    mov rdi, rsi
    add rdi, ProcessIdentity.pid
    mov rax, [rdi]
    call cli_print_u64
    
    mov rdi, sp_str
    call cli_write_str
    
    mov rdi, rsi
    add rdi, ProcessIdentity.ppid
    mov rax, [rdi]
    call cli_print_u64
    
    mov rdi, sp_str
    call cli_write_str
    
    mov rdi, rsi
    add rdi, ProcessIdentity.uid
    mov eax, [rdi]
    call cli_print_u32
    
    mov rdi, sp_str
    call cli_write_str
    
    mov rdi, rsi
    add rdi, ProcessIdentity.create_tick
    mov rax, [rdi]
    call cli_print_u64
    
    mov rdi, nl_str
    call cli_write_str
    
    add rsi, PROC_IDENTITY_SIZE
    pop rcx
    loop .list_loop
    ret

cmd_sample_error:
    mov rdi, err_str
    call cli_write_str
    mov rax, -1
    ret

cmd_sample:
    mov rdi, cli_sys_buf
    mov rax, SYS_UTM_GET_SYS_SAMPLE
    syscall
    
    test rax, rax
    jl cmd_sample_error
    
    mov rdi, cli_sys_header
    mov rsi, cli_sys_header_len
    call cli_write
    
    mov rdi, ts_str
    call cli_write_str
    mov rdi, cli_sys_buf
    add rdi, SystemSample.timestamp_ns
    mov rax, [rdi]
    call cli_print_u64
    mov rdi, nl_str
    call cli_write_str
    
    mov rdi, cpu_str
    call cli_write_str
    mov rdi, cli_sys_buf
    add rdi, SystemSample.cpu_total_percent
    mov eax, [rdi]
    mov edx, eax
    shr edx, 2
    call cli_print_u32
    mov rdi, dot_str
    call cli_write_str
    mov eax, edx
    and eax, 3
    imul eax, 25
    call cli_print_u32
    mov rdi, pct_str
    call cli_write_str
    
    mov rdi, mem_str
    call cli_write_str
    mov rdi, cli_sys_buf
    add rdi, SystemSample.mem_used
    mov rax, [rdi]
    call cli_print_u64
    mov rdi, bytes_str
    call cli_write_str
    
    mov rdi, pwr_str
    call cli_write_str
    mov rdi, cli_sys_buf
    add rdi, SystemSample.pkg_power_uv
    mov rax, [rdi]
    call cli_print_u64
    mov rdi, uw_str
    call cli_write_str
    
    ret

cmd_top:
    jmp cmd_list

cmd_kill:
    mov rdi, [rsi + 16]
    call cli_parse_u64
    mov rdi, rax
    mov rsi, 15
    mov rax, SYS_UTM_PROC_KILL
    syscall
    
    test rax, rax
    jl cmd_kill_error
    
    mov rdi, killed_str
    call cli_write_str
    mov rdi, [rsi + 16]
    call cli_write_str
    mov rdi, nl_str
    call cli_write_str
    ret

cmd_kill_error:
    mov rdi, err_str
    call cli_write_str
    mov rax, -1
    ret

cmd_nice:
    mov rdi, [rsi + 16]
    call cli_parse_u64
    mov r10, rax
    
    mov rdi, [rsi + 24]
    call cli_parse_u64
    mov rsi, rax
    
    mov rdi, r10
    mov rax, SYS_UTM_PROC_NICE
    syscall
    
    test rax, rax
    jl cmd_nice_error
    ret

cmd_nice_error:
    mov rdi, err_str
    call cli_write_str
    mov rax, -1
    ret

cmd_flight:
    mov rdi, [rsi + 16]
    cmp dword [rdi], 0x74726173
    jne .flight_stop
    
    mov rax, SYS_UTM_FLIGHT_START
    mov rdi, 1
    syscall
    test rax, rax
    jl cmd_flight_error
    mov rdi, flight_started_str
    call cli_write_str
    ret

.flight_stop:
    mov rax, SYS_UTM_FLIGHT_STOP
    syscall
    test rax, rax
    jl cmd_flight_error
    mov rdi, flight_stopped_str
    call cli_write_str
    ret

cmd_flight_error:
    mov rdi, err_str
    call cli_write_str
    mov rax, -1
    ret

cmd_metrics:
    mov rdi, cli_metrics_buf
    mov rax, SYS_UTM_METRICS_EXPORT
    mov rsi, 0
    syscall
    
    test rax, rax
    jl cmd_metrics_error
    
    mov rdi, cli_metrics_buf
    mov rsi, rax
    call cli_write
    ret

cmd_metrics_error:
    mov rdi, err_str
    call cli_write_str
    mov rax, -1
    ret

cmd_version:
    mov rdi, cli_version
    mov rsi, cli_version_len
    call cli_write
    ret

cli_print_u64:
    push rax
    push rbx
    push rcx
    push rdi
    
    mov rbx, 10
    mov rcx, 0
    
.conv_loop:
    xor rdx, rdx
    div rbx
    push rdx
    inc rcx
    test rax, rax
    jnz .conv_loop
    
.print_loop:
    pop rax
    add al, '0'
    mov [rsp], al
    mov rax, 1
    mov rdx, 1
    mov rsi, rsp
    mov rdi, 1
    syscall
    pop rax
    loop .print_loop
    
    pop rdi
    pop rcx
    pop rbx
    pop rax
    ret

cli_print_u32:
    push rax
    push rbx
    push rcx
    push rdi
    
    mov ebx, 10
    mov ecx, 0
    
.conv_loop32:
    xor edx, edx
    div ebx
    push rdx
    inc rcx
    test rax, rax
    jnz .conv_loop32
    
.print_loop32:
    pop rax
    add al, '0'
    mov [rsp], al
    mov rax, 1
    mov rdx, 1
    mov rsi, rsp
    mov rdi, 1
    syscall
    pop rax
    loop .print_loop32
    
    pop rdi
    pop rcx
    pop rbx
    pop rax
    ret

cli_write_str:
    push rdi
    call cli_strlen
    pop rdi
    mov rsi, rax
    call cli_write
    ret

cli_strlen:
    xor rax, rax
.strlen_loop:
    cmp byte [rdi + rax], 0
    je .strlen_done
    inc rax
    jmp .strlen_loop
.strlen_done:
    ret

cli_parse_u64:
    xor rax, rax
    xor rbx, rbx
.parse_loop:
    mov bl, [rdi]
    cmp bl, 0
    je .parse_done
    cmp bl, '0'
    jl .parse_done
    cmp bl, '9'
    jg .parse_done
    mov rcx, rax
    shl rax, 3
    add rax, rcx
    add rax, rcx
    sub bl, '0'
    add rax, rbx
    inc rdi
    jmp .parse_loop
.parse_done:
    ret

section .data
sp_str:       db "    ", 0
nl_str:       db 10, 0
dot_str:      db ".", 0
pct_str:      db "%", 10, 0
ts_str:       db "Timestamp: ", 0
cpu_str:      db "CPU Total: ", 0
mem_str:      db "Memory Used: ", 0
bytes_str:    db " bytes", 10, 0
pwr_str:      db "Package Power: ", 0
uw_str:       db " uW", 10, 0
err_str:      db "Error", 10, 0
killed_str:   db "Process ", 0
flight_started_str: db "Flight recorder started", 10, 0
flight_stopped_str: db "Flight recorder stopped", 10, 0

%endif