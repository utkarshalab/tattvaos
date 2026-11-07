; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/ec.asm
; =============================================================================
; The ACPI embedded controller (PNP0C09): a small microcontroller with 256
; bytes of registers firmware reads for the lid, battery, fans and hotkeys,
; reached through a data port and a command/status port.
;
;   acpi_ec_init           find it: _CRS ports (data first, then command),
;                          _GPE for its event
;   acpi_ec_region         the handler for AML's EmbeddedControl regions
;   acpi_ec_query_all      on its GPE: query (0x84) until nothing is left,
;                          running _Qxx for each query value
;
; Protocol: wait for the input buffer to empty before every write, for the
; output buffer to fill before every read; read = 0x80, address, data;
; write = 0x81, address, data. Every wait is bounded; a stuck controller
; fails the access (AML_EIO-like -AML_EBUDGET) instead of hanging.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_EC_ASM
%define LIB_IO_ACPI_AML_EC_ASM

%define EC_OBF              (1 << 0)
%define EC_IBF              (1 << 1)
%define EC_SCI_EVT          (1 << 5)
%define EC_CMD_READ         0x80
%define EC_CMD_WRITE        0x81
%define EC_CMD_QUERY        0x84
%define EC_SPIN             100000      ; status reads per wait
%define EC_MAX_QUERIES      32          ; per GPE

section .bss
alignb 8
global acpi_ec_node
acpi_ec_node:       resq 1
global acpi_ec_ready
acpi_ec_ready:      resd 1
global acpi_ec_data
acpi_ec_data:       resd 1
global acpi_ec_cmd
acpi_ec_cmd:        resd 1
global acpi_ec_gpe
acpi_ec_gpe:        resd 1
global acpi_ec_timeouts
acpi_ec_timeouts:   resd 1
global acpi_ec_queries
acpi_ec_queries:    resd 1
acpi_ec_res:        resb aml_res_size
acpi_ec_off:        resd 1
alignb 8
acpi_ec_value:      resb aml_value_size

section .rodata
acpi_ec_id:         db "PNP0C09", 0
msg_acpi_ec:        db "ACPI: embedded controller, ports ", 0
msg_acpi_ec_gpe:    db ", GPE ", 0
msg_acpi_ec_crlf:   db 0x0D, 0x0A, 0

section .text

; -----------------------------------------------------------------------------
; acpi_ec_wait — wait for the input buffer to empty (ESI = 0) or the output
;                buffer to fill (ESI = 1)
; Output: CF = 1 on timeout
; -----------------------------------------------------------------------------
acpi_ec_wait:
    push rbx
    push r12
    sub rsp, 8
    mov r12d, esi
    mov ebx, EC_SPIN
.poll:
    mov edi, [rel acpi_ec_cmd]
    mov esi, 8
    call acpi_in
    test r12d, r12d
    jnz .obf
    test eax, EC_IBF
    jz .ok
    jmp .again
.obf:
    test eax, EC_OBF
    jnz .ok
.again:
    dec ebx
    jnz .poll
    inc dword [rel acpi_ec_timeouts]
    stc
    jmp .out
.ok:
    clc
.out:
    lea rsp, [rsp + 8]
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ec_send — write a byte (EDX) to the command (ESI = 1) or data port
; Output: CF = 1 on timeout
; -----------------------------------------------------------------------------
acpi_ec_send:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edx
    mov r12d, esi
    xor esi, esi
    call acpi_ec_wait
    jc .out
    mov edi, [rel acpi_ec_data]
    test r12d, r12d
    jz .port
    mov edi, [rel acpi_ec_cmd]
.port:
    mov edx, ebx
    mov esi, 8
    call acpi_out
    clc
.out:
    lea rsp, [rsp + 8]
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ec_receive — read the data port once the output buffer is full
; Output: EAX = byte, CF = 1 on timeout
; -----------------------------------------------------------------------------
acpi_ec_receive:
    sub rsp, 8
    mov esi, 1
    call acpi_ec_wait
    jc .out
    mov edi, [rel acpi_ec_data]
    mov esi, 8
    call acpi_in
    movzx eax, al
    clc
.out:
    lea rsp, [rsp + 8]
    ret

; -----------------------------------------------------------------------------
; acpi_ec_read — EDI = register → EAX = 0 with EDX = byte, or -AML_EBUDGET
; acpi_ec_write — EDI = register, ESI = byte → EAX
; -----------------------------------------------------------------------------
global acpi_ec_read
acpi_ec_read:
    push rbx
    mov ebx, edi
    mov esi, 1
    mov edx, EC_CMD_READ
    call acpi_ec_send
    jc .fail
    xor esi, esi
    mov edx, ebx
    call acpi_ec_send
    jc .fail
    call acpi_ec_receive
    jc .fail
    mov edx, eax
    xor eax, eax
    pop rbx
    ret
.fail:
    mov eax, -AML_EBUDGET
    pop rbx
    ret

global acpi_ec_write
acpi_ec_write:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov esi, 1
    mov edx, EC_CMD_WRITE
    call acpi_ec_send
    jc .fail
    xor esi, esi
    mov edx, ebx
    call acpi_ec_send
    jc .fail
    xor esi, esi
    mov edx, r12d
    call acpi_ec_send
    jc .fail
    xor eax, eax
    jmp .out
.fail:
    mov eax, -AML_EBUDGET
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ec_region — EmbeddedControl regions: RDI = space (3), RSI = register,
;                  EDX = width (8 to 64, a byte at a time, little-endian),
;                  ECX = 1 write, R8 = u64*
; -----------------------------------------------------------------------------
global acpi_ec_region
acpi_ec_region:
    push rbx
    push r12
    push r13
    push r14
    push r15
    cmp dword [rel acpi_ec_ready], 0
    je .unsupported
    mov r12, rsi                        ; register
    mov r13d, edx
    shr r13d, 3                         ; bytes
    mov r14d, ecx
    mov r15, r8
    lea rax, [r12 + r13]
    cmp rax, 256
    ja .unsupported
    test r14d, r14d
    jnz .write
    mov qword [r15], 0
    xor ebx, ebx
.read:
    cmp ebx, r13d
    jae .ok
    lea edi, [r12 + rbx]
    call acpi_ec_read
    test eax, eax
    jnz .out
    mov [r15 + rbx], dl
    inc ebx
    jmp .read
.write:
    xor ebx, ebx
.wbyte:
    cmp ebx, r13d
    jae .ok
    lea edi, [r12 + rbx]
    movzx esi, byte [r15 + rbx]
    call acpi_ec_write
    test eax, eax
    jnz .out
    inc ebx
    jmp .wbyte
.ok:
    xor eax, eax
    jmp .out
.unsupported:
    mov eax, -AML_EUNSUPPORTED
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ec_init — find the embedded controller
; Output: EAX = 0 when found and usable
; -----------------------------------------------------------------------------
global acpi_ec_init
acpi_ec_init:
    push rbx
    push r12
    sub rsp, 8
    mov dword [rel acpi_ec_ready], 0
    lea rdi, [rel acpi_ec_id]
    xor esi, esi
    call aml_find_device
    test rax, rax
    jz .none
    mov [rel acpi_ec_node], rax
    ; ports: the first two I/O descriptors
    mov rdi, rax
    lea rsi, [rel acpi_ec_value]
    call aml_get_crs
    test eax, eax
    jnz .none
    mov dword [rel acpi_ec_data], 0
    mov dword [rel acpi_ec_cmd], 0
    mov dword [rel acpi_ec_off], 0
.res:
    mov rdi, [rel acpi_ec_value + aml_value.data]
    mov esi, [rel acpi_ec_value + aml_value.len]
    lea rdx, [rel acpi_ec_off]
    lea rcx, [rel acpi_ec_res]
    call aml_res_next
    cmp eax, 1
    jne .res_done
    movzx eax, byte [rel acpi_ec_res + aml_res.kind]
    cmp eax, AML_RES_IO
    je .port
    cmp eax, AML_RES_FIXED_IO
    jne .res
.port:
    mov rax, [rel acpi_ec_res + aml_res.base]
    cmp dword [rel acpi_ec_data], 0
    jne .cmd
    mov [rel acpi_ec_data], eax
    jmp .res
.cmd:
    cmp dword [rel acpi_ec_cmd], 0
    jne .res
    mov [rel acpi_ec_cmd], eax
    jmp .res
.res_done:
    cmp dword [rel acpi_ec_data], 0
    je .none
    cmp dword [rel acpi_ec_cmd], 0
    je .none
    ; its GPE
    mov dword [rel acpi_ec_gpe], -1
    mov rdi, [rel acpi_ec_node]
    mov esi, AML_SEG('_','G','P','E')
    lea rdx, [rel acpi_ec_value]
    call aml_eval_child_of
    test eax, eax
    jnz .gpe_done
    cmp byte [rel acpi_ec_value + aml_value.type], AML_T_INTEGER
    jne .gpe_done
    mov rax, [rel acpi_ec_value + aml_value.data]
    cmp rax, 255
    ja .gpe_done
    mov [rel acpi_ec_gpe], eax
.gpe_done:
    mov dword [rel acpi_ec_ready], 1
    lea rsi, [rel msg_acpi_ec]
    call uart_print_str
    mov eax, [rel acpi_ec_data]
    call uart_print_hex64
    lea rsi, [rel msg_acpi_ec_gpe]
    call uart_print_str
    mov eax, [rel acpi_ec_gpe]
    call uart_print_dec
    lea rsi, [rel msg_acpi_ec_crlf]
    call uart_print_str
    xor eax, eax
    jmp .out
.none:
    mov eax, -1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; acpi_ec_query_all — the EC's GPE: query until it has nothing left, running
;                     _Qxx for each value
; Output: EAX = queries run
; -----------------------------------------------------------------------------
global acpi_ec_query_all
acpi_ec_query_all:
    push rbx
    push r12
    sub rsp, 8
    xor ebx, ebx
.next:
    cmp ebx, EC_MAX_QUERIES
    jae .done
    mov esi, 1
    mov edx, EC_CMD_QUERY
    call acpi_ec_send
    jc .done
    call acpi_ec_receive
    jc .done
    test eax, eax
    jz .done                            ; nothing pending
    mov r12d, eax
    inc ebx
    inc dword [rel acpi_ec_queries]
    ; _Qxx, two upper-case hex digits
    mov edi, r12d
    mov esi, 'Q'
    call acpi_gpe_seg
    mov rdi, [rel acpi_ec_node]
    mov esi, eax
    lea rdx, [rel acpi_ec_value]
    call aml_eval_child_of
    jmp .next
.done:
    mov eax, ebx
    add rsp, 8
    pop r12
    pop rbx
    ret

%endif ; LIB_IO_ACPI_AML_EC_ASM
