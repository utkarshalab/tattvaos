%ifndef GUARD_UNET_CORE_L4_TCP_RACK_ASM
%define GUARD_UNET_CORE_L4_TCP_RACK_ASM
; =============================================================================
; Utkarsha OS — unet/core/l4/tcp_rack.asm
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

%include "lib/unet/unet.inc"

%define RACK_REORDERING_WINDOW_US  1000    ; 1ms reordering window
%define RACK_MIN_RTO_MS            200
%define RACK_MAX_RTO_MS            60000

%define TLP_INITIAL_RTO_MS         1000
%define TLP_MAX_PROBES             2

%define RACK_STATE_DISABLED        0
%define RACK_STATE_ACTIVE          1
%define RACK_STATE_RECOVERY        2

%define RACK_SENT_MAP_SIZE    64     ; Packets tracked per connection

%define RACK_EVENT_LOSS       1
%define RACK_EVENT_ECN        2

struc rack_packet_t
    .seq:                resd 1      ; Sequence number
    .end_seq:            resd 1      ; End sequence (seq + len)
    .xmit_time:          resq 1      ; Transmission time (mono_get_nanos)
    .sacked:             resb 1      ; SACKed flag
    .retransmitted:      resb 1      ; Retransmitted flag
    .tlp_probe:          resb 1      ; TLP probe flag
    .in_use:             resb 1      ; Slot holds an unacknowledged packet
    .pad:                resb 4
endstruc

struc rack_state_t
    .state:              resb 1      ; RACK state
    .enabled:            resb 1      ; RACK enabled
    .tlp_enabled:        resb 1      ; TLP enabled
    .tlp_probe_pending:  resb 1      ; A probe is out and not yet answered
    .reordering_window:  resd 1      ; Reordering window (us)

    .xmit_time:          resq 1      ; Latest packet transmission time (ns)
    .rack_rtt:           resd 1      ; RTT of the latest delivered packet (us)
    .rtt_seq:            resd 1      ; End sequence of that packet

    .tlp_count:          resb 1      ; Number of TLP probes sent
    .pad0:               resb 3
    .tlp_high_seq:       resd 1      ; Highest sequence probed by TLP
    .tlp_rto:            resd 1      ; Current TLP timeout (ticks)

    .recovery_start:     resd 1      ; Recovery start sequence
    .recovery_end:       resd 1      ; Recovery end sequence
    .recovery_point:     resd 1      ; Recovery point (snd_una at start)

    .reordering_fuzz:    resd 1      ; Reordering fuzz (us)
    .max_reordering:     resd 1      ; Max reordering observed (us)

    .dsack_seen:         resb 1      ; DSACK seen in current window
    .pad1:               resb 7

    .map:                resb RACK_SENT_MAP_SIZE * rack_packet_t_size
endstruc

section .text

global rack_init
global rack_destroy
global rack_update
global rack_on_ack
global rack_on_data_sent
global tlp_schedule_probe
global tlp_on_ack
global rack_cong_event
global rack_get_rtt

; =============================================================================
; rack_init — Allocate and initialize the RACK state of a connection
; Input: RDI = tcb_t*
; Output: EAX = 0, or -1 if out of memory (tcb_t.rack_ptr stays 0)
; -----------------------------------------------------------------------------
align 64
rack_init:
    push rbx
    push r12
    sub rsp, 8

    mov rbx, rdi
    mov qword [rbx + tcb_t.rack_ptr], 0
    mov qword [rbx + tcb_t.tlp_timer_ptr], 0
    mov qword [rbx + tcb_t.tlp_retrans_ptr], 0

    lea rdi, [rack_state_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .fail
    mov r12, rax

    ; Zero the whole state, packet map included
    mov rdi, r12
    xor eax, eax
    mov ecx, rack_state_t_size
    rep stosb

    mov byte [r12 + rack_state_t.state], RACK_STATE_ACTIVE
    mov byte [r12 + rack_state_t.enabled], 1
    mov byte [r12 + rack_state_t.tlp_enabled], 1
    mov dword [r12 + rack_state_t.reordering_window], RACK_REORDERING_WINDOW_US
    mov dword [r12 + rack_state_t.tlp_rto], TLP_INITIAL_RTO_MS
    mov dword [r12 + rack_state_t.reordering_fuzz], 1000  ; 1ms

    ; Timer entry for the tail loss probe; without one, TLP stays off
    lea rdi, [timer_entry_cache]
    call kmem_cache_alloc
    mov [rbx + tcb_t.tlp_timer_ptr], rax
    test rax, rax
    jnz .have_timer
    mov byte [r12 + rack_state_t.tlp_enabled], 0
.have_timer:

    mov [rbx + tcb_t.rack_ptr], r12
    xor eax, eax
    jmp .done

.fail:
    mov eax, -1
.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; =============================================================================
; rack_destroy — Stop the TLP timer and free the RACK state of a connection
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
rack_destroy:
    push rbx
    mov rbx, rdi

    mov rdi, [rbx + tcb_t.tlp_timer_ptr]
    test rdi, rdi
    jz .no_timer
    call timer_wheel_del            ; -1 if it was not armed; nothing to undo
    lea rdi, [timer_entry_cache]
    mov rsi, [rbx + tcb_t.tlp_timer_ptr]
    call kmem_cache_free
    mov qword [rbx + tcb_t.tlp_timer_ptr], 0
.no_timer:

    mov rsi, [rbx + tcb_t.rack_ptr]
    test rsi, rsi
    jz .done
    lea rdi, [rack_state_cache]
    call kmem_cache_free
    mov qword [rbx + tcb_t.rack_ptr], 0
.done:
    pop rbx
    ret

; =============================================================================
; rack_on_data_sent — Record packet transmission time
; Input: RDI = tcb_t*, ESI = sequence, EDX = end sequence
; Output: EAX = 0, or -1 if the map is full (the packet is not tracked)
; -----------------------------------------------------------------------------
align 64
rack_on_data_sent:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8

    mov r12d, esi
    mov r13d, edx
    mov rbx, [rdi + tcb_t.rack_ptr]
    test rbx, rbx
    jz .full

    ; Find a free slot
    lea r14, [rbx + rack_state_t.map]
    mov ecx, RACK_SENT_MAP_SIZE
.find_slot:
    cmp byte [r14 + rack_packet_t.in_use], 0
    je .found
    add r14, rack_packet_t_size
    dec ecx
    jnz .find_slot
    jmp .full

.found:
    call mono_get_nanos
    mov [r14 + rack_packet_t.seq], r12d
    mov [r14 + rack_packet_t.end_seq], r13d
    mov [r14 + rack_packet_t.xmit_time], rax
    mov byte [r14 + rack_packet_t.sacked], 0
    mov byte [r14 + rack_packet_t.retransmitted], 0
    mov byte [r14 + rack_packet_t.tlp_probe], 0
    mov byte [r14 + rack_packet_t.in_use], 1

    mov [rbx + rack_state_t.xmit_time], rax
    mov [rbx + rack_state_t.tlp_high_seq], r13d
    xor eax, eax
    jmp .done

.full:
    mov eax, -1
.done:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; =============================================================================
; rack_on_ack — Process incoming ACK for RACK
; Input: RDI = tcb_t*, ESI = ack_seq, RDX = SACK blocks (pairs of big-endian
;        start/end sequence numbers), ECX = SACK block count
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
    sub rsp, 8

    mov r15, rdi            ; tcb_t*
    mov r12d, esi           ; ack_seq
    mov r13, rdx            ; SACK blocks
    mov r14d, ecx           ; SACK block count

    mov rbx, [r15 + tcb_t.rack_ptr]
    test rbx, rbx
    jz .done

    call mono_get_nanos
    mov [rsp], rax          ; now

    ; Packets wholly below ack_seq are delivered: take RTT samples, free them
    lea rdi, [rbx + rack_state_t.map]
    mov ecx, RACK_SENT_MAP_SIZE
.ack_loop:
    cmp byte [rdi + rack_packet_t.in_use], 0
    je .ack_next
    mov eax, r12d
    sub eax, [rdi + rack_packet_t.end_seq]
    js .ack_next            ; end_seq after ack_seq (mod 2^32): not yet acked

    mov rax, [rsp]
    sub rax, [rdi + rack_packet_t.xmit_time]
    xor edx, edx
    mov r8d, 1000
    div r8                  ; RAX = RTT in us
    cmp byte [rdi + rack_packet_t.retransmitted], 0
    jne .reordered
    mov [rbx + rack_state_t.rack_rtt], eax
    mov r8d, [rdi + rack_packet_t.end_seq]
    mov [rbx + rack_state_t.rtt_seq], r8d
    jmp .release
.reordered:
    ; A retransmitted packet was delivered: the original was likely only
    ; reordered, so widen the tolerance (no RTT sample: it is ambiguous)
    cmp eax, [rbx + rack_state_t.reordering_fuzz]
    jbe .fuzz_ok
    mov [rbx + rack_state_t.reordering_fuzz], eax
.fuzz_ok:
    cmp eax, [rbx + rack_state_t.max_reordering]
    jbe .release
    mov [rbx + rack_state_t.max_reordering], eax
.release:
    mov byte [rdi + rack_packet_t.in_use], 0
.ack_next:
    add rdi, rack_packet_t_size
    dec ecx
    jnz .ack_loop

    ; Mark packets inside each SACK block
.sack_loop:
    test r14d, r14d
    jz .sack_done
    mov r8d, [r13]
    bswap r8d               ; block start
    mov r9d, [r13 + 4]
    bswap r9d               ; block end
    lea rdi, [rbx + rack_state_t.map]
    mov ecx, RACK_SENT_MAP_SIZE
.mark_loop:
    cmp byte [rdi + rack_packet_t.in_use], 0
    je .mark_next
    mov eax, [rdi + rack_packet_t.seq]
    sub eax, r8d
    js .mark_next           ; starts before the block
    mov eax, r9d
    sub eax, [rdi + rack_packet_t.end_seq]
    js .mark_next           ; ends after the block
    mov byte [rdi + rack_packet_t.sacked], 1
.mark_next:
    add rdi, rack_packet_t_size
    dec ecx
    jnz .mark_loop
    add r13, 8
    dec r14d
    jmp .sack_loop
.sack_done:

    ; Leave recovery once everything outstanding at its start is acked
    cmp byte [rbx + rack_state_t.state], RACK_STATE_RECOVERY
    jne .tlp
    mov eax, r12d
    sub eax, [rbx + rack_state_t.recovery_end]
    js .tlp
    mov byte [rbx + rack_state_t.state], RACK_STATE_ACTIVE
    and dword [r15 + tcb_t.flags], ~TCBF_FAST_RECOVERY

.tlp:
    mov rdi, r15
    mov esi, r12d
    call tlp_on_ack

.done:
    add rsp, 8
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
; Output: EAX = number of tracked packets RACK now considers lost
;
; A packet is lost when it is neither acked nor SACKed and was sent more
; than RTT + reordering window before the most recently delivered one.
; -----------------------------------------------------------------------------
align 64
rack_update:
    mov rdx, [rdi + tcb_t.rack_ptr]
    xor eax, eax
    test rdx, rdx
    jz .done

    ; Deadline in ns: latest delivered xmit time - (rtt + window) us
    mov ecx, [rdx + rack_state_t.rack_rtt]
    add ecx, [rdx + rack_state_t.reordering_window]
    imul rcx, rcx, 1000
    mov r8, [rdx + rack_state_t.xmit_time]
    sub r8, rcx

    lea rdi, [rdx + rack_state_t.map]
    mov ecx, RACK_SENT_MAP_SIZE
.scan:
    cmp byte [rdi + rack_packet_t.in_use], 0
    je .next
    cmp byte [rdi + rack_packet_t.sacked], 0
    jne .next
    cmp [rdi + rack_packet_t.xmit_time], r8
    jge .next
    inc eax
.next:
    add rdi, rack_packet_t_size
    dec ecx
    jnz .scan
.done:
    ret

; =============================================================================
; rack_cong_event — Handle congestion event
; Input: RDI = tcb_t*, ESI = event type (RACK_EVENT_LOSS / RACK_EVENT_ECN)
; -----------------------------------------------------------------------------
align 64
rack_cong_event:
    mov rdx, [rdi + tcb_t.rack_ptr]
    test rdx, rdx
    jz .done
    cmp esi, RACK_EVENT_LOSS
    je .recovery
    cmp esi, RACK_EVENT_ECN
    jne .done               ; unknown event: no change

.recovery:
    ; Enter recovery until everything sent so far is acknowledged
    mov byte [rdx + rack_state_t.state], RACK_STATE_RECOVERY
    mov eax, [rdi + tcb_t.snd_una]
    mov [rdx + rack_state_t.recovery_start], eax
    mov [rdx + rack_state_t.recovery_point], eax
    mov eax, [rdi + tcb_t.snd_nxt]
    mov [rdx + rack_state_t.recovery_end], eax
    or dword [rdi + tcb_t.flags], TCBF_FAST_RECOVERY
.done:
    ret

; =============================================================================
; rack_get_rtt — RTT of the most recently delivered packet
; Input: RDI = tcb_t*
; Output: EAX = RTT in us, 0 if RACK is off or has no sample yet
; -----------------------------------------------------------------------------
align 64
rack_get_rtt:
    xor eax, eax
    mov rdx, [rdi + tcb_t.rack_ptr]
    test rdx, rdx
    jz .done
    mov eax, [rdx + rack_state_t.rack_rtt]
.done:
    ret

; =============================================================================
; TLP (Tail Loss Probe) Functions
; =============================================================================

; tlp_schedule_probe — Arm the TLP timer
; Input: RDI = tcb_t*
; Output: EAX = 0 if armed, -1 if TLP is off or a probe is already pending
align 64
tlp_schedule_probe:
    push rbx
    mov rbx, rdi

    mov rdx, [rbx + tcb_t.rack_ptr]
    test rdx, rdx
    jz .off
    cmp byte [rdx + rack_state_t.tlp_enabled], 0
    je .off
    cmp byte [rdx + rack_state_t.tlp_count], 0
    jne .off

    ; Timeout: the connection's RTO, else the initial TLP timeout
    mov esi, [rbx + tcb_t.rto]
    test esi, esi
    jnz .have_rto
    mov esi, TLP_INITIAL_RTO_MS
.have_rto:
    mov [rdx + rack_state_t.tlp_rto], esi
    inc byte [rdx + rack_state_t.tlp_count]

    mov rdi, [rbx + tcb_t.tlp_timer_ptr]
    lea rdx, [tlp_timer_callback]
    mov rcx, rbx
    call timer_wheel_add
    jmp .done

.off:
    mov eax, -1
.done:
    pop rbx
    ret

; tlp_timer_callback — Called when the TLP timer fires
; Input: RDI = tcb_t* (the callback argument)
align 64
tlp_timer_callback:
    push rbx
    push r12
    sub rsp, 8

    mov rbx, rdi
    mov r12, [rbx + tcb_t.rack_ptr]
    test r12, r12
    jz .done

    cmp byte [r12 + rack_state_t.tlp_count], TLP_MAX_PROBES
    ja .max_probes

    ; Probe: retransmit the head of the retransmission queue
    mov rdi, rbx
    call tcp_retransmit_head
    mov byte [r12 + rack_state_t.tlp_probe_pending], 1

    ; Back off and re-arm for the next probe
    mov eax, [r12 + rack_state_t.tlp_rto]
    shl eax, 1
    cmp eax, RACK_MAX_RTO_MS
    jbe .set_rto
    mov eax, RACK_MAX_RTO_MS
.set_rto:
    mov [r12 + rack_state_t.tlp_rto], eax
    inc byte [r12 + rack_state_t.tlp_count]

    mov rdi, [rbx + tcb_t.tlp_timer_ptr]
    mov esi, eax
    lea rdx, [tlp_timer_callback]
    mov rcx, rbx
    call timer_wheel_add
    jmp .done

.max_probes:
    ; Probes exhausted: hand over to the retransmission timeout
    mov rdi, rbx
    call tcp_timer_retrans_callback

.done:
    add rsp, 8
    pop r12
    pop rbx
    ret

; tlp_on_ack — Cancel the probe once an ACK covers what it probed
; Input: RDI = tcb_t*, ESI = ack_seq
align 64
tlp_on_ack:
    push rbx
    mov rbx, rdi

    mov rdx, [rbx + tcb_t.rack_ptr]
    test rdx, rdx
    jz .done
    cmp byte [rdx + rack_state_t.tlp_count], 0
    je .done
    mov eax, esi
    sub eax, [rdx + rack_state_t.tlp_high_seq]
    js .done                ; not past the probed data yet

    mov byte [rdx + rack_state_t.tlp_count], 0
    mov byte [rdx + rack_state_t.tlp_probe_pending], 0
    mov rdi, [rbx + tcb_t.tlp_timer_ptr]
    test rdi, rdi
    jz .done
    call timer_wheel_del    ; -1 if already fired; nothing to undo

.done:
    pop rbx
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_RACK_ASM
