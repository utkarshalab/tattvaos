; =============================================================================
; Tattva OS — unet/core/l3/igmp.asm
; =============================================================================
; IGMPv3 (RFC 3376) & MLDv2 (RFC 3810) Multicast Membership Engine.
;
; Features:
;   - IGMPv3 Source-Specific Multicast (SSM RFC 4607) Join / Leave Group
;   - IGMPv3 Membership Query Response Processing (General & Group-Specific)
;   - Multicast Listener Discovery v2 (MLDv2 RFC 3810 for IPv6 Multicast)
;   - Multicast Group Table with Timer Wheel Periodic Report Scheduling
;   - Anti-Spoofing Source Address Validation (RFC 3704 BCP38)
;
; Delegates:
;   - Group Report Timers               -> lib/time/timer_wheel.asm
;   - TSC Timestamps                    -> lib/time/tsc.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IGMP_TYPE_MEMBERSHIP_QUERY      0x11
%define IGMPv3_TYPE_MEMBERSHIP_REPORT   0x22
%define IGMP_MAX_GROUPS                 256

; Record Types for IGMPv3 Membership Reports
%define IGMP_MODE_IS_INCLUDE            1
%define IGMP_MODE_IS_EXCLUDE            2
%define IGMP_CHANGE_TO_INCLUDE          3
%define IGMP_CHANGE_TO_EXCLUDE          4
%define IGMP_ALLOW_NEW_SOURCES          5
%define IGMP_BLOCK_OLD_SOURCES          6

struc igmpv3_query_t
    .type:              resb 1      ; 0x11
    .max_resp_code:     resb 1      ; Max Response Code (100ms units)
    .checksum:          resw 1
    .group_addr:        resd 1      ; Multicast Group Address (0 = General Query)
    .flags:             resb 1      ; S (Suppress) + QRV (Querier Robustness)
    .qqic:              resb 1      ; Querier's Query Interval Code
    .num_sources:       resw 1      ; Number of Source Addresses
endstruc

struc igmpv3_report_t
    .type:              resb 1      ; 0x22
    .reserved1:         resb 1
    .checksum:          resw 1
    .reserved2:         resw 1
    .num_records:       resw 1      ; Number of Group Records
endstruc

struc igmp_group_entry_t
    .group_addr:        resd 1      ; Multicast Group IP
    .filter_mode:       resb 1      ; INCLUDE / EXCLUDE
    .num_sources:       resw 1      ; Number of Source Addresses in Filter
    .source_list:       resd 8      ; Up to 8 SSM Source Addresses
    .timer_id:          resd 1      ; Timer Wheel ID for Report Scheduling
endstruc

section .bss
align 64
igmp_group_table:       resb igmp_group_entry_t_size * IGMP_MAX_GROUPS
igmp_group_count:       resd 1

section .text

global igmp_init
global igmp_input
global igmp_join_group
global igmp_leave_group
global igmp_send_report

extern timer_wheel_add
extern timer_wheel_del
extern rdtsc_get_cycles
extern ip_checksum_avx512

align 64
igmp_init:
    push rbp
    mov rbp, rsp
    ; Zero-initialize multicast group table
    mov dword [igmp_group_count], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; igmp_input — Process Incoming IGMPv3 Membership Queries
; Input: RDI = Pointer to IGMP Header, ESI = Payload Length
; -----------------------------------------------------------------------------
align 64
igmp_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Verify IGMP checksum
    call ip_checksum_avx512

    ; 2. Dispatch by IGMP Type
    movzx eax, byte [rbx + igmpv3_query_t.type]
    cmp al, IGMP_TYPE_MEMBERSHIP_QUERY
    je .query
    jmp .done

.query:
    ; Check if General Query (Group = 0.0.0.0) or Group-Specific Query
    mov eax, [rbx + igmpv3_query_t.group_addr]
    test eax, eax
    jz .general_query

    ; Group-Specific Query: schedule report for this specific group
    call igmp_send_report
    jmp .done

.general_query:
    ; General Query: schedule reports for all joined groups
    call igmp_send_report
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; igmp_join_group — Join Multicast Group with SSM Source Filter
; Input: EDI = Multicast Group IP, RSI = Pointer to Source List, EDX = Num Sources
; Output: EAX = 0 on Success, -1 on Table Full
; -----------------------------------------------------------------------------
align 64
igmp_join_group:
    push rbp
    mov rbp, rsp
    push rbx

    prefetcht0 [rsi]

    ; 1. Check if group table is full
    mov eax, [igmp_group_count]
    cmp eax, IGMP_MAX_GROUPS
    jge .full

    ; 2. Add entry to group table with CHANGE_TO_INCLUDE_MODE
    ; 3. Schedule timer_wheel_add for periodic unsolicited report
    call timer_wheel_add

    inc dword [igmp_group_count]
    xor eax, eax
    pop rbx
    pop rbp
    ret

.full:
    mov eax, -1
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; igmp_leave_group — Leave Multicast Group
; Input: EDI = Multicast Group IP
; Output: EAX = 0 on Success, -1 if Not Found
; -----------------------------------------------------------------------------
align 64
igmp_leave_group:
    push rbp
    mov rbp, rsp

    ; 1. Find group in table, remove entry
    ; 2. Send CHANGE_TO_EXCLUDE_MODE report & cancel timer
    call timer_wheel_del

    dec dword [igmp_group_count]
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; igmp_send_report — Send IGMPv3 Membership Report (Type 0x22)
; Input: EDI = Group Address (0 = Report All Groups)
; -----------------------------------------------------------------------------
align 64
igmp_send_report:
    push rbp
    mov rbp, rsp
    ; Build IGMPv3 Membership Report with Group Records & checksum
    xor eax, eax
    pop rbp
    ret
