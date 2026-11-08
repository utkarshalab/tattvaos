; =============================================================================
; Utkarsha OS — lib/ubt/kernel.asm — Bluetooth in the kernel
; =============================================================================
;   ubt_kernel_init     before usb_kernel_init: the USB driver registered,
;                       adapters said on the console, ubt_service run from
;                       the USB poll, the monotonic clock for L2CAP's
;                       timeouts
;
; An adapter's line comes after its device's USB line (the USB glue calls
; usb_k_after_device_fn once that line is out).
; =============================================================================

%ifndef LIB_UBT_KERNEL_ASM
%define LIB_UBT_KERNEL_ASM

section .bss
alignb 8
ubt_k_pending:      resq UBT_MAX_ADAPTERS
ubt_k_pending_n:    resd 1

section .rodata
msg_bt:             db "BT: hci", 0
msg_bt_up:          db " up: HCI ", 0
msg_bt_maker:       db ", manufacturer ", 0
msg_bt_addr:        db ", address ", 0
msg_bt_le:          db ", LE", 0
msg_bt_fw:          db " needs its MediaTek firmware patch; nothing can load it at boot yet", 0
msg_bt_failed:      db " did not come up: command 0x", 0
msg_bt_status:      db ", status ", 0
msg_bt_silent:      db ", no answer", 0
msg_bt_gone:        db " gone", 0
msg_bt_colon:       db ":", 0
msg_bt_crlf:        db 0x0D, 0x0A, 0
; HCI version numbers → Core specification versions
msg_bt_versions:    db "1.0b", 0, "1.1", 0, 0, "1.2", 0, 0, "2.0", 0, 0, "2.1", 0, 0
                    db "3.0", 0, 0, "4.0", 0, 0, "4.1", 0, 0, "4.2", 0, 0, "5.0", 0, 0
                    db "5.1", 0, 0, "5.2", 0, 0, "5.3", 0, 0, "5.4", 0, 0, "6.0", 0, 0
                    db "6.1", 0, 0, "?", 0, 0, 0, 0
%define UBT_K_VERSIONS 17

section .text

global ubt_kernel_init
ubt_kernel_init:
    sub rsp, 8
    mov dword [rel ubt_k_pending_n], 0
    lea rax, [rel ubt_kernel_say]
    mov [rel ubt_adapter_fn], rax
    lea rax, [rel ubt_kernel_flush]
    mov [rel usb_k_after_device_fn], rax
    lea rax, [rel ubt_service]
    mov [rel usb_k_service_fn], rax
    lea rax, [rel ubt_kernel_clock]
    mov [rel ubt_clock_fn], rax         ; L2CAP's and SMP's timeouts
    lea rax, [rel ubt_kernel_random]
    mov [rel ubt_random_fn], rax        ; SMP's keys and nonces
    call ubt_init
    add rsp, 8
    ret

; ubt_kernel_clock — ubt_clock_fn: RAX = milliseconds of the monotonic clock
ubt_kernel_clock:
    sub rsp, 8
    call mono_get_nanos
    add rsp, 8
    xor edx, edx
    mov ecx, 1000000
    div rcx
    ret

; ubt_kernel_random — ubt_random_fn: RDI = buffer, ESI = length → EAX = 0
; when urand filled all of it
ubt_kernel_random:
    push rsi
    mov esi, esi
    call urand_get_bytes
    pop rsi
    cmp rax, rsi
    jne .failed
    xor eax, eax
    ret
.failed:
    mov eax, -1
    ret

; ubt_kernel_say — ubt_adapter_fn: RDI = adapter. A gone one is said now;
; the others after their device's line
ubt_kernel_say:
    ; this machine has a screen and a keyboard, and keeps its bonds
    mov byte [rdi + ubt_adapter.io_cap], 4
    mov byte [rdi + ubt_adapter.bondable], 1
    cmp dword [rdi + ubt_adapter.state], UBT_GONE
    je ubt_kernel_line
    mov eax, [rel ubt_k_pending_n]
    cmp eax, UBT_MAX_ADAPTERS
    jae ubt_kernel_line
    lea rcx, [rel ubt_k_pending]
    mov [rcx + rax * 8], rdi
    inc dword [rel ubt_k_pending_n]
    ret

; ubt_kernel_flush — usb_k_after_device_fn: the lines waiting
ubt_kernel_flush:
    push rbx
    xor ebx, ebx
.next:
    cmp ebx, [rel ubt_k_pending_n]
    jae .out
    lea rax, [rel ubt_k_pending]
    mov rdi, [rax + rbx * 8]
    inc ebx
    call ubt_kernel_line
    jmp .next
.out:
    mov dword [rel ubt_k_pending_n], 0
    pop rbx
    ret

; ubt_k_hex — EAX as ECX hex digits (lib/usb/kernel.asm's printer)
ubt_k_hex:
    jmp usb_k_hex

; ubt_kernel_line — RDI = adapter: one line about it
ubt_kernel_line:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    lea rsi, [rel msg_bt]
    call uart_print_str
    mov eax, [rbx + ubt_adapter.index]
    call uart_print_dec
    mov eax, [rbx + ubt_adapter.state]
    cmp eax, UBT_UP
    je .up
    cmp eax, UBT_NEED_FIRMWARE
    je .firmware
    cmp eax, UBT_GONE
    je .gone
    ; failed
    lea rsi, [rel msg_bt_failed]
    call uart_print_str
    mov eax, [rbx + ubt_adapter.failed_op]
    mov ecx, 4
    call ubt_k_hex
    mov eax, [rbx + ubt_adapter.failed_status]
    test eax, eax
    js .silent
    lea rsi, [rel msg_bt_status]
    call uart_print_str
    mov eax, [rbx + ubt_adapter.failed_status]
    call uart_print_dec
    jmp .end
.silent:
    lea rsi, [rel msg_bt_silent]
    call uart_print_str
    jmp .end
.firmware:
    lea rsi, [rel msg_bt_fw]
    call uart_print_str
    jmp .end
.gone:
    lea rsi, [rel msg_bt_gone]
    call uart_print_str
    jmp .end
.up:
    lea rsi, [rel msg_bt_up]
    call uart_print_str
    movzx eax, byte [rbx + ubt_adapter.hci_version]
    cmp eax, UBT_K_VERSIONS - 1
    jbe .version
    mov eax, UBT_K_VERSIONS - 1
.version:
    lea rsi, [rel msg_bt_versions]
    lea rsi, [rsi + rax * 4]
    lea rsi, [rsi + rax]                ; five bytes each
    call uart_print_str
    lea rsi, [rel msg_bt_maker]
    call uart_print_str
    movzx eax, word [rbx + ubt_adapter.manufacturer]
    call uart_print_dec
    lea rsi, [rel msg_bt_addr]
    call uart_print_str
    ; the address, most significant byte first
    mov r12d, 5
.byte:
    movzx eax, byte [rbx + ubt_adapter.bdaddr + r12]
    mov ecx, 2
    call ubt_k_hex
    test r12d, r12d
    jz .addr_done
    lea rsi, [rel msg_bt_colon]
    call uart_print_str
    dec r12d
    jmp .byte
.addr_done:
    cmp byte [rbx + ubt_adapter.le], 0
    je .end
    lea rsi, [rel msg_bt_le]
    call uart_print_str
.end:
    lea rsi, [rel msg_bt_crlf]
    call uart_print_str
    add rsp, 8
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_KERNEL_ASM
