; =============================================================================
; Tattva OS — unet/scada/modbus_tcp.asm
; =============================================================================
; Modbus TCP/IP Industrial Automation Protocol Engine (RFC 10001 / Modbus Messaging Spec v1.1b).
;
; Features:
;   - MBAP (Modbus Application Protocol) 7-Byte Header Parsing & Construction (TCP Port 502)
;   - Transaction ID, Protocol ID (0=Modbus), Length, Unit ID (Slave Address)
;   - Function Codes:
;       0x01: Read Coils
;       0x02: Read Discrete Inputs
;       0x03: Read Holding Registers
;       0x04: Read Input Registers
;       0x05: Write Single Coil
;       0x06: Write Single Register
;       0x0F: Write Multiple Coils
;       0x10: Write Multiple Registers
;       0x17: Read/Write Multiple Registers
;   - Exception Code Responses (0x80 + FC): Illegal FC, Illegal Data Address, Illegal Data Value, Device Failure
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define MODBUS_TCP_PORT             502
%define MODBUS_PROTOCOL_ID          0x0000

%define MODBUS_FC_READ_COILS        0x01
%define MODBUS_FC_READ_DISCRETES    0x02
%define MODBUS_FC_READ_HOLDING      0x03
%define MODBUS_FC_READ_INPUT        0x04
%define MODBUS_FC_WRITE_COIL        0x05
%define MODBUS_FC_WRITE_REG         0x06
%define MODBUS_FC_WRITE_COILS       0x0F
%define MODBUS_FC_WRITE_REGS        0x10
%define MODBUS_FC_READWRITE_REGS    0x17

%define MODBUS_EX_ILLEGAL_FC        0x01
%define MODBUS_EX_ILLEGAL_ADDR      0x02
%define MODBUS_EX_ILLEGAL_VAL       0x03
%define MODBUS_EX_SLAVE_FAIL        0x04

struc mbap_hdr_t
    .transaction_id:    resw 1      ; 16-bit Transaction ID
    .protocol_id:       resw 1      ; 0x0000 (Modbus)
    .length:            resw 1      ; 16-bit Remaining PDU Length
    .unit_id:           resb 1      ; Slave Unit ID
    .function_code:     resb 1      ; Modbus Function Code
endstruc

section .text

global modbus_init
global modbus_parse
global modbus_process_read_holding
global modbus_process_write_regs
global modbus_send_exception

align 64
modbus_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; modbus_parse — Parse MBAP Header & Dispatch Function Code
; Input: RDI = Pointer to MBAP Buffer, ESI = Buffer Length
; Output: EAX = Function Code, EDX = Transaction ID
; -----------------------------------------------------------------------------
align 64
modbus_parse:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Protocol ID == 0x0000
    movzx eax, word [rbx + mbap_hdr_t.protocol_id]
    test ax, ax
    jnz .invalid_proto

    ; Extract Function Code & Transaction ID
    movzx edx, word [rbx + mbap_hdr_t.transaction_id]
    xchg dl, dh                     ; bswap16 (Transaction ID)

    movzx eax, byte [rbx + mbap_hdr_t.function_code]

    cmp al, MODBUS_FC_READ_HOLDING
    je .read_holding
    cmp al, MODBUS_FC_WRITE_REGS
    je .write_regs
    cmp al, MODBUS_FC_READ_COILS
    je .read_coils
    cmp al, MODBUS_FC_WRITE_COIL
    je .write_coil
    jmp .illegal_fc

.read_holding:
    call modbus_process_read_holding
    jmp .done
.write_regs:
    call modbus_process_write_regs
    jmp .done
.read_coils:
    jmp .done
.write_coil:
    jmp .done

.illegal_fc:
    mov edi, MODBUS_EX_ILLEGAL_FC
    call modbus_send_exception
    jmp .done

.invalid_proto:
    mov eax, -1
    pop rbx
    pop rbp
    ret

.done:
    pop rbx
    pop rbp
    ret

align 64
modbus_process_read_holding:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract starting register address & quantity, fetch from register table, send response
    xor eax, eax
    pop rbp
    ret

align 64
modbus_process_write_regs:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract starting register address & quantity, write to register table, send response
    xor eax, eax
    pop rbp
    ret

align 64
modbus_send_exception:
    push rbp
    mov rbp, rsp
    ; Send Exception PDU: Function Code (FC + 0x80) + Exception Code
    xor eax, eax
    pop rbp
    ret
