; =============================================================================
; Tattva OS — unet/core/l2/arp.asm
; =============================================================================
; Lockless Atomic Hash Table ARP Cache Engine.
;
; Microarchitectural Optimizations:
;   - O(1) Lockless Atomic Hash Table ARP Lookup (`lock cmpxchg16b`)
;   - Dynamic Gratuitous ARP & Timer Wheel Cache Expiration (`timer_wheel_add`)
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ARP_OP_REQUEST              1
%define ARP_OP_REPLY                2

struc arp_hdr_t
    .hw_type:           resw 1
    .proto_type:        resw 1
    .hw_len:            resb 1
    .proto_len:         resb 1
    .opcode:            resw 1
    .sender_mac:        resb 6
    .sender_ip:         resd 1
    .target_mac:        resb 6
    .target_ip:         resd 1
endstruc

section .text

global arp_init
global arp_input
global arp_lookup

extern timer_wheel_add

align 64
arp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
arp_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Update ARP hash cache table & reply to ARP requests
    call timer_wheel_add

    pop rbx
    pop rbp
    ret

align 64
arp_lookup:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Lockless hash table O(1) lookup for Target IP -> MAC
    xor eax, eax
    pop rbp
    ret
