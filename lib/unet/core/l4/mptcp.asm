%ifndef GUARD_UNET_CORE_L4_MPTCP_ASM
%define GUARD_UNET_CORE_L4_MPTCP_ASM
; =============================================================================
; Utkarsha OS — unet/core/l4/mptcp.asm
; =============================================================================
; Multipath TCP (MPTCP) RFC 8684 Implementation
;
; Features:
;   - MP_CAPABLE: Connection establishment with key exchange
;   - MP_JOIN: Subflow addition with HMAC-SHA256 authentication
;   - DSS (Data Sequence Signal): Cross-subflow data sequencing
;   - Subflow management: Creation, join, teardown
;   - Scheduler: Round-robin, lowest-RTT, backup paths
;   - Congestion control coupling (LIA/OLIA/BALIA)
;   - Fast fallback to regular TCP
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"

%define MPTCP_KIND                  30
%define MPTCP_SUB_CAPABLE           0x0
%define MPTCP_SUB_JOIN              0x1
%define MPTCP_SUB_DSS               0x2
%define MPTCP_SUB_ADD_ADDR          0x3
%define MPTCP_SUB_REMOVE_ADDR       0x4
%define MPTCP_SUB_PRIO              0x5
%define MPTCP_SUB_FAST_CLOSE        0x6

%define MPTCP_FLAG_C                0x01  ; Checksum required
%define MPTCP_FLAG_H                0x02  ; HMAC included
%define MPTCP_SUBTYPE_MASK          0x0F

%define MPTCP_HMAC_SHA256           1
%define MPTCP_KEY_LEN               32

struc mptcp_conn_t
    .token:             resq 1      ; Connection token (8 bytes)
    .loc_key:           resq 1      ; Local 64-bit key
    .rem_key:           resq 1      ; Remote 64-bit key
    .loc_id:            resb 1      ; Local address ID
    .rem_id:            resb 1      ; Remote address ID
    .state:             resb 1      ; Connection state
    .flags:             resb 1      ; Connection flags
    .csum_req:          resb 1      ; Checksum required
    .pad0:              resb 1
    .subflows:          resq 8      ; Array of subflow TCB pointers
    .num_subflows:      resd 1
    .max_subflows:      resd 1
    .dss_enabled:       resb 1      ; DSS option enabled
    .checksum_enabled:  resb 1      ; Checksum option enabled
    .scheduler:         resb 1      ; Scheduler algorithm
    .backup_mode:       resb 1      ; Backup path mode
    .pad1:              resw 1
    .rr_index:          resd 1      ; Round-robin scheduler position
    .dss_snd_nxt:       resq 1      ; DSS send next (64-bit)
    .dss_rcv_nxt:       resq 1      ; DSS receive next (64-bit)
    .subflow_seq_map:   resq 1      ; Subflow sequence mapping
endstruc

%define MPTCP_STATE_CLOSED        0
%define MPTCP_STATE_ESTABLISHED   1
%define MPTCP_STATE_CLOSING       2

%define MPTCP_SCHED_RR            0   ; Round Robin
%define MPTCP_SCHED_LOW_RTT       1   ; Lowest RTT
%define MPTCP_SCHED_BLEST         2   ; BLEST scheduler
%define MPTCP_SCHED_BINDER        3   ; Binder (programmable)

%define MPTCP_MAX_SUBFLOWS        8
%define MPTCP_MAX_TOKEN_LEN       8

struc mptcp_subflow_t
    .tcb_ptr:           resq 1      ; Pointer to subflow TCB
    .local_addr:        resq 2      ; Local IPv6 address (128-bit)
    .remote_addr:       resq 2      ; Remote IPv6 address
    .local_port:        resw 1
    .remote_port:       resw 1
    .local_id:          resb 1
    .remote_id:         resb 1
    .state:             resb 1      ; Subflow state
    .flags:             resb 1      ; Backup, etc.
    .backup:            resb 1
    .pad:               resb 1
    .rtt_us:            resd 1      ; Smoothed RTT
    .cwnd:              resd 1      ; Subflow cwnd
    .ssthresh:          resd 1
    .last_ack:          resd 1
endstruc

struc mptcp_dss_t
    .data_seq:          resq 1      ; Data sequence number (64-bit)
    .data_len:          resd 1      ; Data length
    .flags:             resb 1      ; FIN, RESET, etc.
    .subtype:           resb 1      ; DSS subtype
    .pad:               resw 1
endstruc

%define DSS_FLAG_FIN        0x01
%define DSS_FLAG_RESET      0x02
%define DSS_FLAG_MAPPED     0x04

struc mptcp_hmac_ctx_t
    .key:               resb 32
    .key_len:           resb 1
    .pad:               resb 7
endstruc

section .bss
alignb 64
global mptcp_conn_pool
mptcp_conn_pool:        resb kmem_cache_t_size
global mptcp_subflow_pool
mptcp_subflow_pool:     resb kmem_cache_t_size
global mptcp_hmac_ctx
mptcp_hmac_ctx:         resb mptcp_hmac_ctx_t_size

section .data
mptcp_conn_cache_name:  db "mptcp_conn", 0
mptcp_subflow_cache_name: db "mptcp_subflow", 0

section .text

global mptcp_init
global mptcp_parse_options
global mptcp_add_subflow
global mptcp_remove_subflow
global mptcp_send_dss
global mptcp_process_dss
global mptcp_schedule_subflow
global mptcp_congestion_control

; =============================================================================
; mptcp_init — Initialize MPTCP subsystem
; -----------------------------------------------------------------------------
align 64
mptcp_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; Create connection pool
    lea rdi, [mptcp_conn_pool]
    lea rsi, [mptcp_conn_cache_name]
    mov rdx, mptcp_conn_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    ; Create subflow pool
    lea rdi, [mptcp_subflow_pool]
    lea rsi, [mptcp_subflow_cache_name]
    mov rdx, mptcp_subflow_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    ; Initialize HMAC context
    mov byte [mptcp_hmac_ctx + mptcp_hmac_ctx_t.key_len], 32
    call rdtsc_get_cycles
    mov qword [mptcp_hmac_ctx + mptcp_hmac_ctx_t.key], rax
    mov qword [mptcp_hmac_ctx + mptcp_hmac_ctx_t.key + 8], rdx

    xor eax, eax
    pop rbx
    pop rbp
    ret

; =============================================================================
; mptcp_parse_options — Walk the TCP options of a segment and dispatch the
; MPTCP (kind 30) ones by subtype.
; Input: RDI = net_pkt_t*, RSI = tcp_hdr_t*, RDX = TCP header length in bytes
;        (data offset * 4, so options are RDX - 20 bytes), RCX = mptcp_conn_t*
;        (0 while the connection is not yet known)
; Output: EAX = 0 on success, -1 on a malformed option
; -----------------------------------------------------------------------------
align 64
mptcp_parse_options:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; net_pkt_t*
    mov r14, rcx            ; mptcp_conn_t* (may be 0)
    lea r12, [rsi + 20]     ; R12 = current option
    lea r13, [rsi + rdx]    ; R13 = end of options
    cmp edx, 20
    jbe .ok                 ; no options

.parse_loop:
    cmp r12, r13
    jae .ok
    movzx eax, byte [r12]
    test al, al
    jz .ok                  ; End of Option List
    cmp al, 1
    je .skip_nop

    ; Every other option has a length byte, covering kind and length
    lea rcx, [r12 + 2]
    cmp rcx, r13
    ja .invalid
    movzx r15d, byte [r12 + 1]
    cmp r15d, 2
    jb .invalid
    lea rcx, [r12 + r15]
    cmp rcx, r13
    ja .invalid

    cmp al, MPTCP_KIND
    jne .next_option

    ; MPTCP option: kind, length, subtype (high nibble) | version/flags
    cmp r15d, 4
    jb .invalid
    movzx eax, byte [r12 + 2]
    shr eax, 4

    cmp al, MPTCP_SUB_CAPABLE
    je .parse_capable
    cmp al, MPTCP_SUB_JOIN
    je .parse_join
    cmp al, MPTCP_SUB_DSS
    je .parse_dss
    jmp .next_option        ; ADD_ADDR, REMOVE_ADDR, MP_PRIO, MP_FASTCLOSE

.parse_capable:
    ; TODO: MP_CAPABLE — parse keys, derive the connection token
    jmp .next_option

.parse_join:
    ; TODO: MP_JOIN — verify the HMAC, link the subflow to its connection
    jmp .next_option

.parse_dss:
    test r14, r14
    jz .next_option
    mov rdi, r14
    mov rsi, r12
    call mptcp_process_dss
    jmp .next_option

.skip_nop:
    inc r12
    jmp .parse_loop

.next_option:
    add r12, r15
    jmp .parse_loop

.invalid:
    mov eax, -1
    jmp .done
.ok:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; mptcp_add_subflow — Add new subflow to MPTCP connection
; Input: RDI = mptcp_conn_t*, RSI = subflow tcb_t*
; Output: EAX = 0 on success, -1 on failure (connection full / out of memory)
; -----------------------------------------------------------------------------
align 64
mptcp_add_subflow:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi            ; mptcp_conn_t*
    mov r12, rsi            ; tcb_t* (subflow)

    cmp dword [rbx + mptcp_conn_t.num_subflows], MPTCP_MAX_SUBFLOWS
    jae .fail

    lea rdi, [mptcp_subflow_pool]
    call kmem_cache_alloc
    test rax, rax
    jz .fail
    mov r13, rax            ; R13 = mptcp_subflow_t*

    ; Addresses: the TCB is IPv4, stored in the low 32 bits of each 128-bit field
    xor eax, eax
    mov [r13 + mptcp_subflow_t.local_addr], rax
    mov [r13 + mptcp_subflow_t.local_addr + 8], rax
    mov [r13 + mptcp_subflow_t.remote_addr], rax
    mov [r13 + mptcp_subflow_t.remote_addr + 8], rax
    mov eax, [r12 + tcb_t.local_ip]
    mov [r13 + mptcp_subflow_t.local_addr], eax
    mov eax, [r12 + tcb_t.remote_ip]
    mov [r13 + mptcp_subflow_t.remote_addr], eax
    mov ax, [r12 + tcb_t.local_port]
    mov [r13 + mptcp_subflow_t.local_port], ax
    mov ax, [r12 + tcb_t.remote_port]
    mov [r13 + mptcp_subflow_t.remote_port], ax

    mov eax, [rbx + mptcp_conn_t.num_subflows]
    mov [r13 + mptcp_subflow_t.local_id], al
    mov byte [r13 + mptcp_subflow_t.remote_id], 0
    mov [r13 + mptcp_subflow_t.tcb_ptr], r12
    mov byte [r13 + mptcp_subflow_t.state], TCP_STATE_SYN_SENT
    mov byte [r13 + mptcp_subflow_t.flags], 0
    mov byte [r13 + mptcp_subflow_t.backup], 0

    ; Per-subflow congestion state starts from the TCB's
    mov ecx, [r12 + tcb_t.srtt]
    mov [r13 + mptcp_subflow_t.rtt_us], ecx
    mov dword [r13 + mptcp_subflow_t.cwnd], 10
    mov dword [r13 + mptcp_subflow_t.ssthresh], 0xFFFFFFFF
    mov dword [r13 + mptcp_subflow_t.last_ack], 0

    ; Append to the connection's subflow array
    mov [rbx + mptcp_conn_t.subflows + rax * 8], r13
    inc dword [rbx + mptcp_conn_t.num_subflows]

    xor eax, eax
    jmp .done
.fail:
    mov eax, -1
.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; mptcp_remove_subflow — Remove subflow from MPTCP connection
; Input: RDI = mptcp_conn_t*, RSI = subflow tcb_t*
; Output: EAX = 0 if removed, -1 if the TCB is not a subflow of the connection
; -----------------------------------------------------------------------------
align 64
mptcp_remove_subflow:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    ; Find the slot whose subflow wraps this TCB
    mov ecx, [rbx + mptcp_conn_t.num_subflows]
    xor edx, edx
.find_loop:
    cmp edx, ecx
    jae .not_found
    mov rax, [rbx + mptcp_conn_t.subflows + rdx * 8]
    cmp [rax + mptcp_subflow_t.tcb_ptr], r12
    je .found
    inc edx
    jmp .find_loop

.found:
    ; Close the gap: shift the later slots down by one
    mov rsi, rax            ; RSI = subflow to free
    dec ecx                 ; ECX = new count
.shift:
    cmp edx, ecx
    jae .shifted
    mov rax, [rbx + mptcp_conn_t.subflows + rdx * 8 + 8]
    mov [rbx + mptcp_conn_t.subflows + rdx * 8], rax
    inc edx
    jmp .shift
.shifted:
    mov qword [rbx + mptcp_conn_t.subflows + rcx * 8], 0
    mov [rbx + mptcp_conn_t.num_subflows], ecx

    lea rdi, [mptcp_subflow_pool]
    call kmem_cache_free

    xor eax, eax
    jmp .done
.not_found:
    mov eax, -1
.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; mptcp_send_dss — Send Data Sequence Signal
; Input: RDI = mptcp_conn_t*, RSI = data pointer, RDX = length
; Output: EAX = 0
; -----------------------------------------------------------------------------
align 64
mptcp_send_dss:
    ; TODO: Build the DSS option (subtype 2: flags, data_seq, subflow_seq,
    ; data_len) for the next mapping. Only the connection-level sequence is
    ; advanced here.
    add [rdi + mptcp_conn_t.dss_snd_nxt], rdx
    xor eax, eax
    ret

; =============================================================================
; mptcp_process_dss — Process incoming DSS option
; Input: RDI = mptcp_conn_t*, RSI = pointer to the DSS option
; Output: EAX = 0
; -----------------------------------------------------------------------------
align 64
mptcp_process_dss:
    ; TODO: Parse the data sequence mapping and DATA_ACK
    xor eax, eax
    ret

; =============================================================================
; mptcp_schedule_subflow — Select subflow for sending (scheduler)
; Input: RDI = mptcp_conn_t*, RSI = data length
; Output: RAX = subflow tcb_t* or 0
; -----------------------------------------------------------------------------
align 64
mptcp_schedule_subflow:
    mov ecx, [rdi + mptcp_conn_t.num_subflows]
    test ecx, ecx
    jz .no_subflow

    movzx eax, byte [rdi + mptcp_conn_t.scheduler]
    cmp al, MPTCP_SCHED_LOW_RTT
    je .sched_low_rtt
    cmp al, MPTCP_SCHED_BLEST
    je .sched_low_rtt       ; TODO: BLEST; lowest RTT until it exists

    ; Default: round robin over the subflows
    mov eax, [rdi + mptcp_conn_t.rr_index]
    xor edx, edx
    div ecx                 ; EDX = rr_index % num_subflows
    lea eax, [rdx + 1]
    mov [rdi + mptcp_conn_t.rr_index], eax
    mov rax, [rdi + mptcp_conn_t.subflows + rdx * 8]
    mov rax, [rax + mptcp_subflow_t.tcb_ptr]
    ret

.sched_low_rtt:
    ; Subflow with the lowest smoothed RTT
    mov rax, [rdi + mptcp_conn_t.subflows]
    mov r8d, [rax + mptcp_subflow_t.rtt_us]
    mov edx, 1
.find_best:
    cmp edx, ecx
    jae .found_best
    mov r9, [rdi + mptcp_conn_t.subflows + rdx * 8]
    cmp [r9 + mptcp_subflow_t.rtt_us], r8d
    jae .next_candidate
    mov r8d, [r9 + mptcp_subflow_t.rtt_us]
    mov rax, r9
.next_candidate:
    inc edx
    jmp .find_best
.found_best:
    mov rax, [rax + mptcp_subflow_t.tcb_ptr]
    ret

.no_subflow:
    xor eax, eax
    ret

; =============================================================================
; mptcp_congestion_control — Coupled congestion control (LIA/OLIA)
; Input: RDI = mptcp_conn_t*
; -----------------------------------------------------------------------------
align 64
mptcp_congestion_control:
    ; TODO: Couple the subflow windows (RFC 6356 LIA)
    ret

%endif ; GUARD_UNET_CORE_L4_MPTCP_ASM
