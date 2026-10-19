; UTM Enterprise - REST API Server
; Pure Assembly Implementation

%ifndef _UTM_API_ASM_
%define _UTM_ENTERPRISE_API_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .data
api_port equ 9090

api_listening:
    db "UTM Enterprise API server listening on port 9090", 10, 0
api_listening_len equ $ - api_listening

api_404:
    db "HTTP/1.1 404 Not Found", 10
    db "Content-Length: 0", 10
    db "Connection: close", 10, 10, 0
api_404_len equ $ - api_404

api_200_header:
    db "HTTP/1.1 200 OK", 10
    db "Content-Type: text/plain", 10
    db "Connection: close", 10, 0
api_200_header_len equ $ - api_200_header

api_json_header:
    db "HTTP/1.1 200 OK", 10
    db "Content-Type: application/json", 10
    db "Connection: close", 10, 0
api_json_header_len equ $ - api_json_header

section .bss
api_server_fd:
    resq 1
api_client_fd:
    resq 1
api_buf:
    resb 65536
api_sys_sample:
    resb SYS_SAMPLE_SIZE

section .text

global _start
global api_main

extern utm_term_write

_start:
    call api_main
    
    mov rax, 60
    xor rdi, rdi
    syscall

api_main:
    mov rax, 1
    mov rdi, 1
    mov rsi, api_listening
    mov rdx, api_listening_len
    syscall
    
    mov rax, 41
    mov rdi, 2
    mov rsi, 1
    mov rdx, 0
    syscall
    
    test rax, rax
    js .socket_error
    mov [api_server_fd], rax
    
    mov rax, 16
    mov rdi, [api_server_fd]
    mov rsi, 1
    mov rdx, 2
    mov r10, 1
    mov r8, 4
    syscall
    
    mov rax, 42
    mov rdi, [api_server_fd]
    mov rsi, api_sockaddr
    mov rdx, 16
    syscall
    
    test rax, rax
    js .bind_error
    
    mov rax, 43
    mov rdi, [api_server_fd]
    mov rsi, 1000
    syscall
    
    test rax, rax
    js .listen_error
    
.accept_loop:
    mov rax, 44
    mov rdi, [api_server_fd]
    mov rsi, 0
    mov rdx, 0
    syscall
    
    test rax, rax
    js .accept_error
    mov [api_client_fd], rax
    
    call api_handle_request
    
    mov rax, 6
    mov rdi, [api_client_fd]
    syscall
    
    jmp .accept_loop
    
.socket_error:
    mov rax, 1
    ret
.bind_error:
    mov rax, 2
    ret
.listen_error:
    mov rax, 3
    ret
.accept_error:
    jmp .accept_loop

api_handle_request:
    mov rax, 0
    mov rdi, [api_client_fd]
    mov rsi, api_buf
    mov rdx, 65535
    syscall
    
    test rax, rax
    jle .done
    
    mov rsi, api_buf
    mov rdi, metrics_path
    call api_starts_with
    test rax, rax
    jnz .serve_metrics
    
    mov rdi, sample_path
    call api_starts_with
    test rax, rax
    jnz .serve_sample
    
    jmp .serve_404
    
.serve_metrics:
    mov rdi, api_sys_sample
    mov rax, SYS_UTM_GET_SYS_SAMPLE
    syscall
    
    call api_build_prometheus
    jmp .send_response
    
.serve_sample:
    mov rdi, api_sys_sample
    mov rax, SYS_UTM_GET_SYS_SAMPLE
    syscall
    
    call api_build_json
    jmp .send_response
    
.serve_404:
    mov rdi, api_client_fd
    mov rsi, api_404
    mov rdx, api_404_len
    call api_write_client
    jmp .done
    
.send_response:
    mov rdi, api_client_fd
    mov rsi, api_200_header
    mov rdx, api_200_header_len
    call api_write_client
    
    mov rdi, api_client_fd
    mov rsi, api_buf
    mov rdx, [api_response_len]
    call api_write_client
    
.done:
    ret

api_build_prometheus:
    mov rdi, api_buf
    
    mov rsi, prom_header
    call api_strcpy
    
    mov rsi, prom_cpu_total
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.cpu_total_percent
    mov eax, [rdi]
    call api_format_percent
    call api_strcat_newline
    
    mov rsi, prom_cpu_user
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.cpu_user_percent
    mov eax, [rdi]
    call api_format_percent
    call api_strcat_newline
    
    mov rsi, prom_cpu_kernel
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.cpu_kernel_percent
    mov eax, [rdi]
    call api_format_percent
    call api_strcat_newline
    
    mov rsi, prom_mem_used
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.mem_used
    mov rax, [rdi]
    call api_format_u64
    call api_strcat_newline
    
    mov rsi, prom_mem_total
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.mem_total
    mov rax, [rdi]
    call api_format_u64
    call api_strcat_newline
    
    mov rsi, prom_pkg_power
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.pkg_power_uv
    mov rax, [rdi]
    call api_format_u64
    call api_strcat_newline
    
    mov rsi, prom_thermal
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.thermal_pressure
    movzx eax, byte [rdi]
    call api_format_u32
    call api_strcat_newline
    
    mov rsi, api_buf
    sub rdi, rsi
    mov [api_response_len], rdi
    ret

api_build_json:
    mov rdi, api_buf
    
    mov rsi, json_start
    call api_strcpy
    
    mov rsi, json_timestamp
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.timestamp_ns
    mov rax, [rdi]
    call api_format_u64
    call api_strcat_comma
    
    mov rsi, json_cpu_total
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.cpu_total_percent
    mov eax, [rdi]
    call api_format_u32
    call api_strcat_comma
    
    mov rsi, json_mem_used
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.mem_used
    mov rax, [rdi]
    call api_format_u64
    call api_strcat_comma
    
    mov rsi, json_pkg_power
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.pkg_power_uv
    mov rax, [rdi]
    call api_format_u64
    call api_strcat_comma
    
    mov rsi, json_thermal
    call api_strcpy
    mov rdi, api_sys_sample
    add rdi, SystemSample.thermal_pressure
    movzx eax, byte [rdi]
    call api_format_u32
    
    mov rsi, json_end
    call api_strcpy
    
    mov rsi, api_buf
    sub rdi, rsi
    mov [api_response_len], rdi
    ret

api_write_client:
    mov rax, 1
    syscall
    ret

api_starts_with:
    push rdi
    push rsi
.loop:
    mov al, [rdi]
    test al, al
    jz .match
    mov bl, [rsi]
    cmp al, bl
    jne .no_match
    inc rdi
    inc rsi
    jmp .loop
.match:
    mov rax, 1
    pop rsi
    pop rdi
    ret
.no_match:
    xor rax, rax
    pop rsi
    pop rdi
    ret

api_strcpy:
    push rdi
.loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .done
    inc rdi
    inc rsi
    jmp .loop
.done:
    pop rdi
    ret

api_strcat_newline:
    mov byte [rdi], 10
    inc rdi
    ret

api_strcat_comma:
    mov byte [rdi], 44
    inc rdi
    ret

api_format_u64:
    push rax
    push rbx
    push rcx
    push rdi
    
    mov rbx, 10
    mov rcx, 0
    
.conv:
    xor rdx, rdx
    div rbx
    push rdx
    inc rcx
    test rax, rax
    jnz .conv
    
.print:
    pop rax
    add al, '0'
    mov [rdi], al
    inc rdi
    loop .print
    
    pop rdi
    pop rcx
    pop rbx
    pop rax
    ret

api_format_u32:
    push rax
    push rbx
    push rcx
    push rdi
    
    mov ebx, 10
    mov ecx, 0
    
.conv32:
    xor edx, edx
    div ebx
    push rdx
    inc rcx
    test rax, rax
    jnz .conv32
    
.print32:
    pop rax
    add al, '0'
    mov [rdi], al
    inc rdi
    loop .print32
    
    pop rdi
    pop rcx
    pop rbx
    pop rax
    ret

api_format_percent:
    push rax
    push rbx
    push rcx
    push rdx
    push rdi
    
    mov ebx, 100
    xor rdx, rdx
    div ebx
    
    call api_format_u32
    
    mov byte [rdi], '.'
    inc rdi
    
    mov eax, edx
    mov ebx, 10
    xor rdx, rdx
    div ebx
    add al, '0'
    mov [rdi], al
    inc rdi
    
    mov eax, edx
    add al, '0'
    mov [rdi], al
    inc rdi
    
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

section .rodata
metrics_path:
    db "GET /metrics", 0
sample_path:
    db "GET /api/v1/sample", 0

prom_header:
    db "# HELP utm_cpu_percent CPU utilization percentage", 10
    db "# TYPE utm_cpu_percent gauge", 10
    db 'utm_cpu_percent{type="total"} ', 0
prom_cpu_total:
    db 'utm_cpu_percent{type="user"} ', 0
prom_cpu_user:
    db 'utm_cpu_percent{type="kernel"} ', 0
prom_cpu_kernel:
    db "# HELP utm_mem_used_bytes Memory used in bytes", 10
    db "# TYPE utm_mem_used_bytes gauge", 10
    db "utm_mem_used_bytes ", 0
prom_mem_used:
    db "# HELP utm_mem_total_bytes Memory total in bytes", 10
    db "# TYPE utm_mem_total_bytes gauge", 10
    db "utm_mem_total_bytes ", 0
prom_mem_total:
    db "# HELP utm_energy_package_microwatts Package power in microwatts", 10
    db "# TYPE utm_energy_package_microwatts gauge", 10
    db "utm_energy_package_microwatts ", 0
prom_pkg_power:
    db "# HELP utm_thermal_pressure Thermal pressure level (0-4)", 10
    db "# TYPE utm_thermal_pressure gauge", 10
    db "utm_thermal_pressure ", 0
prom_thermal:

json_start:
    db "{", 0
json_timestamp:
    db '"timestamp_ns":', 0
json_cpu_total:
    db ',"cpu_total_percent":', 0
json_mem_used:
    db ',"mem_used":', 0
json_pkg_power:
    db ',"pkg_power_uv":', 0
json_thermal:
    db ',"thermal_pressure":', 0
json_end:
    db "}", 10, 0

section .bss
api_response_len:
    resq 1

section .data
api_sockaddr:
    dw 2
    dw 0x3532
    dd 0
    dd 0
    dd 0
    dd 0

%endif