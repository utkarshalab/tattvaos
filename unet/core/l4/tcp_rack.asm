%ifndef GUARD_UNET_CORE_L4_TCP_RACK_ASM
%define GUARD_UNET_CORE_L4_TCP_RACK_ASM
; =============================================================================
; Tattva OS — unet/core/l4/tcp_rack.asm
; =============================================================================
; RACK (Recent ACKnowledgment) and TLP (Tail Loss Probe) — RFC 8960
;
; RACK: Uses per-packet transmission time and ACK information for loss detection
; TLP: Tail Loss Probe — sends probe packets to elicit ACKs for tail losses
;
; Together they provide faster and more accurate loss detection than
; traditional 3-DUPACK + RTO approach.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define RACK_REORDERING_WINDOW_US  1000    ; 1ms reordering window
%define RACK_MIN_RTO_MS            200
%define RACK_MAX_RTO_MS            60000

%define TLP_INITIAL_RTO_MS         1000
%define TLP_MAX_PROBES             2

%define RACK_STATE_DISABLED        0
%define RACK_STATE_ACTIVE          1
%define RACK_STATE_RECOVERY        2

struc rack_state_t
    .state:              resb 1      ; RACK state
    .enabled:            resb 1      ; RACK enabled
    .tlp_enabled:        resb 1      ; TLP enabled
    .reordering_window:  resd 1      ; Reordering window (us)

    .xmit_time:          resq 1      ; Latest packet transmission time
    .rack_rtt:           resd 1      ; RTT from RACK
    .rtt_seq:            resd 1      ; Sequence at which RTT measured

    .tlp_count:          resb 1      ; Number of TLP probes sent
    .tlp_high_seq:       resd 1      ; Highest sequence probed by TLP
    .tlp_timer:          resq 1      ; TLP timer entry
    .tlp_rto:            resd 1      ; Current TLP RTO

    .recovery_start:     resd 1      ; Recovery start sequence
    .recovery_end:       resd 1      ; Recovery end sequence
    .recovery_point:     resd 1      ; Recovery point (snd_una at start)

    .reordering_fuzz:    resd 1      ; Reordering fuzz (us)
    .max_reordering:     resd 1      ; Max reordering observed

    .dsack_seen:         resb 1      ; DSACK seen in current window
    .pad:                resb 7
endstruc

%define RACK_SENT_MAP_SIZE    64     ; Number of packets tracked

struc rack_packet_t
    .seq:                resd 1      ; Sequence number
    .end_seq:            resd 1      ; End sequence (seq + len)
    .xmit_time:          resq 1      ; Transmission timestamp (TSC)
    .sacked:             resb 1      ; SACKed flag
    .retransmitted:      resb 1      ; Retransmitted flag
    .tlp_probe:          resb 1      ; TLP probe flag
    .pad:                resb 5
endstruc

section .bss
alignb 64
rack_packet_map:     resb RACK_SENT_MAP_SIZE * rack_packet_t_size
rack_free_list:      resq RACK_SENT_MAP_SIZE

section .text

global rack_init
global rack_update
global rack_on_ack
global rack_on_data_sent
global rack_on_rto
global tlp_init
global tlp_schedule_probe
global tlp_on_ack
global rack_cong_event
global rack_get_rtt

; =============================================================================
; rack_init — Initialize RACK state
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
rack_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi

    ; Allocate RACK state
    lea rdi, [rack_state_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .fail
    mov qword [rbx + tcb_t.rack_ptr], rax
    mov rbx, rax

    ; Initialize RACK state
    mov byte [rbx + rack_state_t.state], RACK_STATE_ACTIVE
    mov byte [rbx + rack_state_t.enabled], 1
    mov byte [rbx + rack_state_t.tlp_enabled], 1
    mov dword [rbx + rack_state_t.reordering_window], RACK_REORDERING_WINDOW_US
    mov dword [rbx + rack_state_t.tlp_rto], TLP_INITIAL_RTO_MS
    mov dword [rbx + rack_state_t.reordering_fuzz], 1000  ; 1ms

    ; Initialize packet map
    lea rdi, [rack_packet_map]
    xor eax, eax
    mov rcx, RACK_SENT_MAP_SIZE
    rep stosq

    ; Initialize free list
    lea rdi, [rack_free_list]
    mov rcx, RACK_SENT_MAP_SIZE
    xor rax, rax
    mov rbx, rack_packet_map
.init_loop:
    mov [rdi], rbx
    add rbx, rack_packet_t_size
    add rdi, 8
    loop .init_loop

    xor eax, eax
    jmp .done

.fail:
    mov eax, -1
.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; rack_on_data_sent — Record packet transmission time
; Input: RDI = tcb_t*, RSI = sequence, RDX = end sequence, RCX = length
; -----------------------------------------------------------------------------
align 64
rack_on_data_sent:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx

    mov rbx, qword [rbx + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    ; Find free slot in packet map
    mov r12, rack_packet_map
    mov rcx, RACK_SENT_MAP_SIZE
.find_slot:
    cmp qword [r12], 0
    jz .found
    add r12, rack_packet_t_size
    dec rcx
    jnz .find_slot
    jmp .done  ; Map full

.found:
    ; Record packet
    mov [r12 + rack_packet_t.seq], r12d
    mov [r12 + rack_packet_t.end_seq], r13d
    call rdtsc_get_cycles
    mov [r12 + rack_packet_t.xmit_time], rax
    mov byte [r12 + rack_packet_t.sacked], 0
    mov byte [r12 + rack_packet_t.retransmitted], 0
    mov byte [r12 + rack_packet_t.tlp_probe], 0

    ; Update latest xmit time
    mov [rbx + rack_state_t.xmit_time], rax

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; rack_on_ack — Process incoming ACK for RACK
; Input: RDI = tcb_t*, RSI = ack_seq, RDX = sack_blocks, RCX = sack_count
; -----------------------------------------------------------------------------
align 64
rack_on_ack:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; tcb_t*
    mov r12d, esi           ; ack_seq
    mov r13, rdx            ; sack_blocks pointer
    mov r14d, ecx           ; sack_count

    mov rbx, qword [rbx + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    ; Update RACK RTT if this ACK advances snd_una
    cmp r12d, [rbx + tcb_t.snd_una]
    jbe .no_rtt_update

    ; Calculate RTT for this ACK
    ; Find packet with seq == ack_seq - 1 (the packet being ACKed)
    mov r13, rack_packet_map
    mov rcx, RACK_SENT_MAP_SIZE
.find_packet:
    cmp dword [rax + rack_packet_t.end_seq], r12d
    je .found_packet
    add rax, rack_packet_t_size
    dec rcx
    jnz .find_packet
    jmp .no_rtt_update

.found_packet:
    ; Calculate RTT
    call rdtsc_get_cycles
    sub rax, [rax + rack_packet_t.xmit_time]
    ; Convert to microseconds (assume 3GHz)
    mov rcx, 3000
    div rcx
    mov [rbx + rack_state_t.rack_rtt], eax
    mov [rbx + rack_state_t.rtt_seq], r12d

    ; Mark packet as SACKed/ACKed
    mov byte [rax + rack_packet_t.sacked], 1

    ; Update reordering window
    ; If packet was retransmitted and now ACKed, update reordering window
    test byte [rax + rack_packet_t.retransmitted], 1
    jz .no_reorder
    mov eax, [rbx + rack_state_t.rack_rtt]
    cmp eax, [rbx + rack_state_t.reordering_fuzz]
    cmova [rbx + rack_state_t.reordering_fuzz], eax
    cmp eax, [rbx + rack_state_t.max_reordering]
    cmova [rbx + rack_state_t.max_reordering], eax

.no_reorder:
    ; Check if we should exit recovery
    cmp r12d, [rbx + rack_state_t.recovery_end]
    jb .in_recovery
    ; Exit recovery
    mov byte [rbx + rack_state_t.state], RACK_STATE_ACTIVE
    and byte [rbx + tcb_t.flags], ~TCBF_FAST_RECOVERY

.in_recovery:
    ; Process SACK blocks
    test r14d, r14d
    jz .no_sack
    mov r15, r13
    mov r14d, ecx
.process_sack_loop:
    ; Process each SACK block
    mov eax, [r15]
    bswap eax
    mov r15d, eax
    mov eax, [r15 + 4]
    bswap eax
    ; Mark range as SACKed
    add r15, 8
    dec r14d
    jnz .process_sack_loop

.no_sack:
    ; Check for DSACK
    ; If SACK block acknowledges already SACKed data -> DSACK
    ; Update reordering window

.no_sack:
.no_rtt_update:
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; rack_update — Periodic RACK update (called from timer)
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
rack_update:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov rbx, qword [rbx + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    ; Check if any unacked packets have exceeded RACK timeout
    ; RACK timeout = RTT + reordering_window
    mov eax, [rbx + rack_state_t.rack_rtt]
    add eax, [rbx + rack_state_t.reordering_window]
    ; TODO: Check packets in map against timeout

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; rack_cong_event — Handle congestion event
; Input: RDI = tcb_t*, RSI = event type
; -----------------------------------------------------------------------------
align 64
rack_cong_event:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12d, esi

    mov rbx, qword [rbx + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    cmp r12d, 1  ; LOSS
    je .loss
    cmp r12d, 2  ; ECN
    je .ecn

.loss:
    ; Enter RACK recovery
    mov byte [rbx + rack_state_t.state], RACK_STATE_RECOVERY
    mov eax, [rbx + tcb_t.snd_nxt]
    mov [rbx + rack_state_t.recovery_end], eax
    mov eax, [rbx + tcb_t.snd_una]
    mov [rbx + rack_state_t.recovery_point], eax
    jmp .done

.ecn:
    ; ECN mark treated as congestion signal
    mov byte [rbx + rack_state_t.state], RACK_STATE_RECOVERY
    jmp .loss  ; Same as loss for now

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; TLP (Tail Loss Probe) Functions
; =============================================================================

; tlp_schedule_probe — Schedule TLP probe timer
; Input: RDI = tcb_t*
align 64
tlp_schedule_probe:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov rbx, qword [rbx + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    cmp byte [rbx + rack_state_t.tlp_enabled], 0
    je .done

    ; Check if already have pending TLP
    cmp byte [rbx + rack_state_t.tlp_count], 0
    jne .done

    ; Schedule TLP timer
    ; RTO = srtt + 4*rttvar (from TCP timer)
    mov eax, [rbx + tcb_t.rto]
    test eax, eax
    jz .use_default
    mov esi, eax
    jmp .schedule

.use_default:
    mov esi, TLP_INITIAL_RTO_MS

.schedule:
    mov edi, [rdi + tcb_t.tlp_timer_ptr]
    lea rdx, [tlp_timer_callback]
    mov rcx, rdi
    call timer_wheel_add

    inc byte [rbx + rack_state_t.tlp_count]

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; tlp_timer_callback — Called when TLP timer fires
align 64
tlp_timer_callback:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi        ; tcb_t*
    mov rbx, qword [rbx + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    ; Send TLP probe (retransmit last segment)
    ; Check probe count
    cmp byte [rbx + rack_state_t.tlp_count], TLP_MAX_PROBES
    jge .max_probes

    ; Retransmit last unacked segment
    mov rdi, [rdi + tcb_t.tlp_retrans_ptr]
    test rdi, rdi
    jz .done

    ; Mark as TLP probe
    ; Send segment
    call tcp_retransmit_head

    ; Double RTO for next probe
    mov eax, [rbx + rack_state_t.tlp_rto]
    shl eax, 1
    cmp eax, RACK_MAX_RTO_MS
    jle .set_rto
    mov eax, RACK_MAX_RTO_MS
.set_rto:
    mov [rbx + rack_state_t.tlp_rto], eax

    inc byte [rbx + rack_state_t.tlp_count]
    mov byte [rbx + rack_state_t.tlp_probe_pending], 1

    ; Reschedule
    mov edi, [rdi + tcb_t.tlp_timer_ptr]
    mov esi, [rbx + rack_state_t.tlp_rto]
    lea rdx, [tlp_timer_callback]
    mov rcx, rdi
    call timer_wheel_add

    jmp .done

.max_probes:
    ; Max probes reached - fallback to RTO
    call tcp_timer_retrans_callback

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; tlp_on_ack — Process ACK for TLP
align 64
tlp_on_ack:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov rbx, qword [rbx + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    ; If ACK acknowledges data beyond TLP probe, cancel TLP
    ; Check if ack_seq > tlp_high_seq
    mov eax, [rsi]  ; ack_seq from caller context
    cmp eax, [rbx + rack_state_t.tlp_high_seq]
    jbe .done

    ; Cancel TLP timer
    mov rdi, [rdi + tcb_t.tlp_timer_ptr]
    call timer_wheel_del

    mov byte [rbx + rack_state_t.tlp_count], 0
    mov byte [rbx + rack_state_t.tlp_probe_pending], 0

.done:
    pop r12
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_RACK_ASM