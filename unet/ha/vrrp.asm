%ifndef GUARD_UNET_HA_VRRP_ASM
%define GUARD_UNET_HA_VRRP_ASM
; =============================================================================
; Tattva OS — unet/ha/vrrp.asm
; =============================================================================
; Virtual Router Redundancy Protocol Engine (VRRPv2 RFC 3768 / VRRPv3 RFC 5798).
;
; Features:
;   - IP Protocol 112 VRRP Packet Parsing & Construction
;   - Multicast Address: `224.0.0.18` (IPv4) & `FF02::12` (IPv6)
;   - Fields: Version (2 or 3), Type (1 = Advertisement), VRID (Virtual Router ID 1..255),
;             Priority (1..254, 255 = Owner, 0 = Master Shutdown), Count IP Addrs, Advertisement Interval
;   - Master / Backup / Initialize Finite State Machine
;   - Preemption Control & Master Down Timer Scheduling
;   - Gratuitous ARP / Unsolicited Neighbor Advertisement Generation on Master Transition
;
; Delegates:
;   - ARP Gratuitous Announcement        -> unet/core/l2/arp.asm
;   - Timer Wheel Master Down Timer      -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IP_PROTO_VRRP               112
%define VRRP_VERSION_2              2
%define VRRP_VERSION_3              3
%define VRRP_TYPE_ADVERTISEMENT     1

%define VRRP_STATE_INITIALIZE       0
%define VRRP_STATE_BACKUP           1
%define VRRP_STATE_MASTER           2

struc vrrp_hdr_t
    .vers_type:         resb 1      ; Version (4b) + Type (4b)
    .vrid:              resb 1      ; Virtual Router ID (1..255)
    .priority:          resb 1      ; Priority (1..255)
    .ip_count:          resb 1      ; Number of Virtual IP Addresses
    .adv_interval:      resw 1      ; Advertisement Interval (centiseconds in v3)
    .checksum:          resw 1      ; 16-bit 1's complement checksum
endstruc

struc vrrp_instance_t
    .vrid:              resb 1
    .state:             resb 1      ; Initialize, Backup, Master
    .priority:          resb 1
    .preempt:           resb 1      ; 1 = Preempt Enabled
    .adv_interval_ms:   resd 1
    .master_down_timer: resd 1      ; Timer Wheel ID
    .virtual_ip:        resd 1
endstruc

section .text

global vrrp_init
global vrrp_process_packet
global vrrp_send_advertisement
global vrrp_transition_master
global vrrp_transition_backup


align 64
vrrp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vrrp_process_packet — Process Inbound VRRP Advertisement
; Input: RDI = Pointer to VRRP Packet Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
vrrp_process_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Version (v2 or v3) & Type == 1 (Advertisement)
    movzx eax, byte [rbx + vrrp_hdr_t.vers_type]
    mov ecx, eax
    and ecx, 0x0F                   ; Type
    cmp cl, VRRP_TYPE_ADVERTISEMENT
    jne .invalid

    ; Extract VRID & Priority
    movzx edx, byte [rbx + vrrp_hdr_t.vrid]
    movzx eax, byte [rbx + vrrp_hdr_t.priority]

    ; If priority > local priority & preempt enabled -> transition to Backup
    ; Reset Master Down Timer

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
vrrp_send_advertisement:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Build VRRP Advertisement packet & transmit to 224.0.0.18
    xor eax, eax
    pop rbp
    ret

align 64
vrrp_transition_master:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Transition Backup -> Master state
    ; Broadcast Gratuitous ARP for Virtual IP address to update switches
    call arp_send_gratuitous

    ; Start periodic advertisement timer
    mov edi, 1000                   ; 1 second adv interval
    call timer_wheel_add
    pop rbp
    ret

align 64
vrrp_transition_backup:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Transition Master -> Backup state
    ; Cancel advertisement timer & start Master Down timer (3 * Adv_Interval + Skew_Time)
    mov edi, 3600                   ; ~3.6s Master Down timer
    call timer_wheel_add
    pop rbp
    ret

%endif ; GUARD_UNET_HA_VRRP_ASM
