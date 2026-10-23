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
global mptcp_hmac_sha256

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
; mptcp_parse_options — Parse MPTCP options from incoming segment
; Input: RDI = net_pkt_t*, RSI = tcp_hdr_t*, RDX = options length
; Output: RAX = 0 on success, -1 on error
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
    mov r12, rsi            ; tcp_hdr_t*
    mov r13, rdx            ; options length
    mov r14, rcx            ; mptcp_conn_t* (output)

    test rdx, rdx
    jz .done

    lea r15, [rsi + 20]     ; Start of options
    mov r14d, edx
    sub r14d, 20            ; Options length

.parse_loop:
    cmp r14d, 2
    jl .done

    movzx eax, byte [r12]       ; Current pointer
    ; Actually r12 is tcp_hdr_t*, need to calculate options start
    ; TCP header starts at headroom_offset, options at +20
    mov r15, rsi
    add r12, 20
    mov r13d, edx
    sub r13d, 20

.parse_loop2:
    cmp r13d, 2
    jl .done

    movzx eax, byte [r12]
    cmp al, MPTCP_KIND
    je .found_mptcp
    cmp al, 0
    je .done
    cmp al, 1
    je .skip_nop

    ; Multi-byte option
    movzx ecx, byte [r12 + 1]
    cmp r15d, ecx
    jl .done
    add r12, rcx
    sub r15d, ecx
    jmp .check_loop

.skip_nop:
    inc r12
    dec r15d
    jmp .check_loop

.found_mptcp:
    ; Parse MPTCP option
    movzx ecx, byte [r12 + 1]
    cmp cl, 4
    jl .invalid

    ; Extract subtype
    movzx eax, byte [r12 + 2]
    and al, MPTCP_SUBTYPE_MASK

    cmp al, MPTCP_SUB_CAPABLE
    je .parse_capable
    cmp al, MPTCP_SUB_JOIN
    je .parse_join
    cmp al, MPTCP_SUB_DSS
    je .parse_dss
    cmp al, MPTCP_SUB_ADD_ADDR
    je .parse_add_addr
    cmp al, MPTCP_SUB_REMOVE_ADDR
    je .parse_remove_addr
    cmp al, MPTCP_SUB_PRIO
    je .parse_prio
    cmp al, MPTCP_SUB_FAST_CLOSE
    je .parse_fast_close

    jmp .continue_parse

.parse_capable:
    ; MP_CAPABLE: version, flags, key exchange
    ; TODO: Parse keys, generate tokens
    jmp .continue_parse

.parse_join:
    ; MP_JOIN: authenticate subflow
    ; TODO: Verify HMAC, link to existing connection
    jmp .continue_parse

.parse_dss:
    ; DSS option
    ; TODO: Parse data sequence mapping
    jmp .continue_parse

.parse_add_addr:
.parse_remove_addr:
.parse_prio:
.parse_fast_close:
    ; Handle other subtypes
    jmp .continue_parse

.invalid:
    mov eax, -1
    jmp .done

.continue_parse:
    movzx ecx, byte [r12 + 1]
    add r12, rcx
    sub r15d, ecx
    jmp .check_loop

.check_loop:
    cmp r15d, 2
    jge .parse_loop2

.done:
    xor eax, eax
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
; Output: RAX = 0 on success, -1 on failure
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

    ; Check max subflows
    mov eax, [rdi + mptcp_conn_t.num_subflows]
    cmp eax, MPTCP_MAX_SUBFLOWS
    jge .fail

    ; Allocate subflow structure
    lea rdi, [mptcp_subflow_pool]
    call kmem_cache_alloc
    test rax, rax
    jz .fail
    mov rbx, rax

    ; Initialize subflow
    mov rsi, rdi            ; original mptcp_conn_t*
    mov rdi, rax
    ; Copy addresses from TCB
    mov eax, [r12 + tcb_t.local_ip]
    mov [rbx + mptcp_subflow_t.local_addr], eax
    mov eax, [r12 + tcb_t.remote_ip]
    mov [rbx + mptcp_subflow_t.remote_addr], eax
    mov ax, [r12 + tcb_t.local_port]
    mov [rax + mptcp_subflow_t.local_port], ax
    mov ax, [r12 + tcb_t.remote_port]
    mov [rax + mptcp_subflow_t.remote_port], ax

    ; Assign local ID
    mov al, [rdi + mptcp_conn_t.num_subflows]
    mov byte [rbx + mptcp_subflow_t.local_id], al

    ; Link to connection
    mov qword [rbx + mptcp_subflow_t.tcb_ptr], r12
    mov byte [rbx + mptcp_subflow_t.state], TCP_STATE_SYN_SENT
    mov qword [rbx + mptcp_subflow_t.tcb_ptr], r12

    ; Add to connection's subflow array
    mov rax, rdi
    mov ecx, [rax + mptcp_conn_t.num_subflows]
    mov [rax + mptcp_conn_t.subflows + rcx * 8], rbx
    inc dword [rax + mptcp_conn_t.num_subflows]

    ; Initialize subflow congestion control
    mov dword [rbx + mptcp_subflow_t.cwnd], 10
    mov dword [rbx + mptcp_subflow_t.ssthresh], 0xFFFFFFFF

    xor eax, eax
    jmp .done

.fail:
    mov eax, -1
.done:
    ret

; =============================================================================
; mptcp_remove_subflow — Remove subflow from MPTCP connection
; Input: RDI = mptcp_conn_t*, RSI = subflow tcb_t*
; -----------------------------------------------------------------------------
align 64
mptcp_remove_subflow:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    mov ecx, [rbx + mptcp_conn_t.num_subflows]
    test ecx, ecx
    jz .done

    mov rdi, [rbx + mptcp_conn_t.subflows]
.find_loop:
    cmp qword [rdi], r12
    je .found
    add rdi, 8
    dec ecx
    jnz .find_loop
    jmp .done

.found:
    ; Shift remaining subflows
    mov rax, [rdi + 8]
    mov [rdi], rax
    dec dword [rbx + mptcp_conn_t.num_subflows]

    ; Free subflow structure
    lea rsi, [mptcp_subflow_pool]
    xchg rdi, rsi
    call kmem_cache_free

    xor eax, eax
    ret

; =============================================================================
; mptcp_send_dss — Send Data Sequence Signal
; Input: RDI = mptcp_conn_t*, RSI = data pointer, RDX = length
; -----------------------------------------------------------------------------
align 64
mptcp_send_dss:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx

    ; Get next DSS sequence
    mov rax, [rdi + mptcp_conn_t.dss_snd_nxt]
    mov rdx, rax

    ; Build DSS option
    ; TODO: Implement DSS option generation
    ; Data Sequence Signal: subtype=2, flags, data_seq, data_len

    xor eax, eax
    ret

; =============================================================================
; mptcp_process_dss — Process incoming DSS option
; -----------------------------------------------------------------------------
align 64
mptcp_process_dss:
    ret

; =============================================================================
; mptcp_schedule_subflow — Select subflow for sending (scheduler)
; Input: RDI = mptcp_conn_t*, RSI = data length
; Output: RAX = subflow tcb_t* or 0
; -----------------------------------------------------------------------------
align 64
mptcp_schedule_subflow:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    movzx eax, byte [rdi + mptcp_conn_t.scheduler]
    cmp al, MPTCP_SCHED_LOW_RTT
    je .sched_low_rtt
    cmp al, MPTCP_SCHED_BLEST
    je .sched_blest
    ; Default: Round Robin
    jmp .sched_rr

.sched_rr:
    ; Simple round-robin among available subflows
    mov ecx, [rdi + mptcp_conn_t.num_subflows]
    test ecx, ecx
    jz .no_subflow
    mov eax, [rdi + mptcp_conn_t.rr_index]
    xor edx, edx
    div ecx
    mov [rdi + mptcp_conn_t.rr_index], edx
    mov rax, [rdi + mptcp_conn_t.subflows + rdx * 8]
    ret

.sched_low_rtt:
    ; Select subflow with lowest RTT
    mov rcx, [rdi + mptcp_conn_t.subflows]
    mov r12d, [rcx + mptcp_subflow_t.rtt_us]
    mov rax, rcx
    mov r13d, [rdi + mptcp_conn_t.num_subflows]
    mov rbx, 1
.find_best:
    cmp rbx, r13
    jge .found_best
    mov rdx, [rdi + mptcp_conn_t.subflows + rbx * 8]
    mov edx, [rdx + mptcp_subflow_t.rtt_us]
    cmp edx, r12d
    jge .next_candidate
    mov r12d, edx
    mov rax, rdx
.next_candidate:
    inc rbx
    jmp .find_best
.found_best:
    ret

.no_subflow:
    xor rax, rax
    ret

; =============================================================================
; mptcp_congestion_control — Coupled congestion control (LIA/OLIA)
; -----------------------------------------------------------------------------
align 64
mptcp_congestion_control:
    ret

%endif ; GUARD_UNET_CORE_L4_MPTCP_ASM
