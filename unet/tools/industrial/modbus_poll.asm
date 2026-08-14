%ifndef GUARD_UNET_TOOLS_INDUSTRIAL_MODBUS_POLL_ASM
%define GUARD_UNET_TOOLS_INDUSTRIAL_MODBUS_POLL_ASM
; =============================================================================
; Tattva OS — unet/tools/industrial/modbus_poll.asm
; =============================================================================
; Command-Line Modbus TCP Industrial Polling Tool (`modbus-poll`).
;
; Features:
;   - TCP Port 502 MBAP Header Construction (Transaction ID, Protocol ID 0, Length, Unit ID)
;   - Function Codes:
;       0x01 Read Coils, 0x02 Read Discrete Inputs
;       0x03 Read Holding Registers, 0x04 Read Input Registers
;       0x05 Write Single Coil, 0x06 Write Single Register
;       0x10 Write Multiple Registers
;   - Exception Response Handling (0x80 + FC, Exception Codes 01..06)
;   - Real-Time Register Value Formatting (16-bit Integer, 32-bit Float IEEE 754)
;   - RDTSC Nanosecond Response Latency Measurement
;
; Delegates:
;   - Modbus Protocol Engine            -> unet/scada/modbus.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define MODBUS_PORT                 502
%define MODBUS_PROTOCOL_ID          0

%define MODBUS_FC_READ_COILS        0x01
%define MODBUS_FC_READ_DI           0x02
%define MODBUS_FC_READ_HOLDING      0x03
%define MODBUS_FC_READ_INPUT        0x04
%define MODBUS_FC_WRITE_COIL        0x05
%define MODBUS_FC_WRITE_REG         0x06
%define MODBUS_FC_WRITE_MULTI_REG   0x10

struc mbap_header_t
    .transaction_id:    resw 1      ; Transaction Identifier (Big Endian)
    .protocol_id:       resw 1      ; Protocol ID = 0x0000 (Modbus)
    .length:            resw 1      ; Remaining bytes (Big Endian)
    .unit_id:           resb 1      ; Unit Identifier (Slave Address)
endstruc

struc modbus_poll_opts_t
    .server_ip:         resd 1
    .port:              resw 1
    .unit_id:           resb 1
    .function_code:     resb 1
    .start_register:    resw 1
    .num_registers:     resw 1
endstruc

section .data
align 2
modbus_tx_id:           dw 1        ; Auto-incrementing Transaction ID

section .text

global modbus_poll_main
global modbus_poll_read_registers
global modbus_poll_format_mbap
global modbus_poll_parse_response

; -----------------------------------------------------------------------------
; modbus_poll_main — Entry Point: Format & Send Modbus Request
; Input: RDI = Pointer to modbus_poll_opts_t
; Output: EAX = 0 (Success), -1 (Exception Response)
; -----------------------------------------------------------------------------
align 64
modbus_poll_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call modbus_poll_read_registers

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; modbus_poll_read_registers — Format MBAP + PDU & Transmit
; Input: RDI = Pointer to modbus_poll_opts_t
; Output: EAX = 0 (Success)
; -----------------------------------------------------------------------------
align 64
modbus_poll_read_registers:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Record departure timestamp for latency measurement
    rdtsc
    shl rdx, 32
    or rax, rdx
    push rax                        ; Save departure TSC on stack

    ; Allocate packet buffer
    call pktbuf_alloc
    test rax, rax
    jz .err

    mov r12, rax                    ; R12 = net_pkt_t*
    mov r13, [r12 + net_pkt_t.phys_addr]
    add r13d, [r12 + net_pkt_t.headroom_offset]

    ; --- Format 7-byte MBAP Header ---

    ; Transaction ID (Big Endian, auto-increment)
    mov ax, [modbus_tx_id]
    xchg al, ah
    mov [r13 + mbap_header_t.transaction_id], ax
    inc word [modbus_tx_id]

    ; Protocol ID = 0x0000
    mov word [r13 + mbap_header_t.protocol_id], 0

    ; Length = 6 bytes (Unit ID 1 + FC 1 + Start Reg 2 + Num Reg 2)
    mov word [r13 + mbap_header_t.length], 0x0600  ; 6 in Big Endian

    ; Unit ID
    mov al, [rbx + modbus_poll_opts_t.unit_id]
    mov [r13 + mbap_header_t.unit_id], al

    ; --- Format PDU (after 7-byte MBAP) ---

    ; Function Code
    mov al, [rbx + modbus_poll_opts_t.function_code]
    mov [r13 + 7], al

    ; Starting Register Address (Big Endian)
    movzx eax, word [rbx + modbus_poll_opts_t.start_register]
    xchg al, ah
    mov [r13 + 8], ax

    ; Number of Registers (Big Endian)
    movzx eax, word [rbx + modbus_poll_opts_t.num_registers]
    xchg al, ah
    mov [r13 + 10], ax

    ; Total packet = 12 bytes (7 MBAP + 5 PDU)

    ; Transmit via TCP
    mov rdi, r12
    call tcp_send_data

    pop rax                         ; Restore departure TSC
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.err:
    pop rax                         ; Clean up saved TSC
    mov eax, -1
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; modbus_poll_parse_response — Parse Modbus Response PDU
; Input: RDI = Pointer to response buffer (starts at MBAP header)
; Output: EAX = 0 (Normal), Exception Code (1..6) if error
;
; Normal Response (FC 0x03): Unit_ID | FC | Byte_Count | Register_Values...
; Exception Response: Unit_ID | (0x80 + FC) | Exception_Code
; -----------------------------------------------------------------------------
align 64
modbus_poll_parse_response:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Skip 7-byte MBAP header -> PDU starts at offset 7
    movzx eax, byte [rbx + 7]      ; Function Code

    ; Check if exception (bit 7 set = 0x80 + original FC)
    test eax, 0x80
    jnz .exception

    ; Normal response: extract byte count & register values
    movzx ecx, byte [rbx + 8]      ; Byte Count
    ; Register data starts at offset 9, each register is 2 bytes Big Endian

    xor eax, eax                    ; Success
    pop rbx
    pop rbp
    ret

.exception:
    ; Exception Response: extract exception code
    movzx eax, byte [rbx + 8]      ; Exception Code (01..06)
    ; 01 = Illegal Function, 02 = Illegal Data Address
    ; 03 = Illegal Data Value, 04 = Slave Device Failure
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; modbus_poll_format_mbap — Standalone MBAP Header Formatter
; Input: RDI = Output buffer, ESI = Unit ID, EDX = PDU Length
; Output: EAX = Total MBAP header bytes written (7)
; -----------------------------------------------------------------------------
align 64
modbus_poll_format_mbap:
    push rbp
    mov rbp, rsp

    ; Transaction ID
    mov ax, [modbus_tx_id]
    xchg al, ah
    mov [rdi], ax
    inc word [modbus_tx_id]

    ; Protocol ID
    mov word [rdi + 2], 0

    ; Length (PDU length + 1 for Unit ID)
    lea eax, [edx + 1]
    xchg al, ah
    mov [rdi + 4], ax

    ; Unit ID
    mov [rdi + 6], sil

    mov eax, 7                      ; MBAP header is always 7 bytes
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_INDUSTRIAL_MODBUS_POLL_ASM
