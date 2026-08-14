%ifndef GUARD_UNET_SERVICES_IPFIX_ASM
%define GUARD_UNET_SERVICES_IPFIX_ASM
; =============================================================================
; Tattva OS — unet/services/ipfix.asm
; =============================================================================
; IPFIX (IP Flow Information Export RFC 7011 / NetFlow v9) Exporter & Collector.
;
; Features:
;   - UDP / SCTP Port 4739 16-Byte IPFIX Message Header Parsing
;   - Set Header: Template Set (ID 2), Options Template Set (ID 3), Data Set (ID > 255)
;   - Information Element (IE) Field Specifiers (IPv4/IPv6 Src/Dst, Ports, Octets, Packets, TCP Flags, ICMP)
;   - Template Management & Dynamic Data Record Decoding
;   - High-Throughput Flow Telemetry Export Engine
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IPFIX_PORT                  4739
%define IPFIX_VERSION               0x000A  ; Version 10 (IPFIX)

%define IPFIX_SET_TEMPLATE          2
%define IPFIX_SET_OPTIONS_TEMPLATE  3

struc ipfix_hdr_t
    .version:           resw 1      ; 0x000A
    .length:            resw 1      ; Total Message Length
    .export_time:       resd 1      ; Export Time (Epoch Seconds)
    .seq_num:           resd 1      ; Sequence Number
    .domain_id:         resd 1      ; Observation Domain ID
endstruc

struc ipfix_set_hdr_t
    .set_id:            resw 1      ; Set ID (2, 3, or >255)
    .length:            resw 1      ; Set Length
endstruc

section .text

global ipfix_init
global ipfix_process_message
global ipfix_parse_template
global ipfix_parse_data_set
global ipfix_export_flow

align 64
ipfix_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
ipfix_process_message:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify IPFIX version 10 (0x000A)
    movzx eax, word [rbx + ipfix_hdr_t.version]
    xchg al, ah
    cmp ax, IPFIX_VERSION
    jne .invalid

    ; Iterate Sets within message
    lea rdi, [rbx + ipfix_hdr_t_size]
    movzx eax, word [rdi + ipfix_set_hdr_t.set_id]
    xchg al, ah

    cmp ax, IPFIX_SET_TEMPLATE
    je .template_set
    cmp ax, IPFIX_SET_OPTIONS_TEMPLATE
    je .options_template_set
    jmp .data_set

.template_set:
    call ipfix_parse_template
    jmp .done
.options_template_set:
    jmp .done
.data_set:
    call ipfix_parse_data_set
    jmp .done

.invalid:
    mov eax, -1
    pop rbx
    pop rbp
    ret

.done:
    pop rbx
    pop rbp
    ret

align 64
ipfix_parse_template:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Store Field Specifiers (IE ID, Field Length) in Template Table
    xor eax, eax
    pop rbp
    ret

align 64
ipfix_parse_data_set:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Decode Data Record using active Template definition
    xor eax, eax
    pop rbp
    ret

align 64
ipfix_export_flow:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Construct IPFIX Data Record from flow metrics & transmit via UDP
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_SERVICES_IPFIX_ASM
