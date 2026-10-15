%ifndef GUARD_UNET_CORE_L4_TCP_TIMER_ASM
%define GUARD_UNET_CORE_L4_TCP_TIMER_ASM
; =============================================================================
; Tattva OS — unet/core/l4/tcp_timer.asm
; =============================================================================
; TCP Timer Engine — Retransmission, Persist, Keepalive, TIME_WAIT.
;
; Integrates with lib/time/timer_wheel.asm for O(1) timer management.
; Per-TCB embedded timer entries for zero-allocation fast path.
;
; Timers per TCB:
;   1. RETRANSMISSION (RTO) — RFC 6298: RTO = srtt + 4*rttvar, min 200ms, max 60s
;   2. PERSIST (Zero Window) — Exponential backoff, probes window
;   3. KEEPALIVE — Idle detection, configurable interval/count
;   4. TIME_WAIT — 2*MSL (60s) after active close
;   5. DELAYED_ACK — 40ms delayed ACK timer
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"
%include "lib/time/timer_wheel.asm"

; Timer types embedded in TCB
%define TCP_TIMER_RETRANS       0
%define TCP_TIMER_PERSIST       1
%define TCP_TIMER_KEEPALIVE     2
%define TCP_TIMER_TIMEWAIT      3
%define TCP_TIMER_DELAYED_ACK   4
%define TCP_TIMER_COUNT         5

; RTO Constants (RFC 6298)
%define TCP_RTO_MIN_MS          200
%define TCP_RTO_MAX_MS          60000
%define TCP_RTO_INIT_MS         1000

; Timer wheel tick = 1ms (1000 Hz)
%define TIMER_WHEEL_HZ          1000

; Persist timer backoff: 1s, 2s, 4s, 8s, 16s, 32s, 60s (capped)
%define TCP_PERSIST_MIN_MS      1000
%define TCP_PERSIST_MAX_MS      60000

; Keepalive defaults
%define TCP_KEEPALIVE_IDLE_MS   7200000     ; 2 hours
%define TCP_KEEPALIVE_INTV_MS   75000       ; 75 seconds
%define TCP_KEEPALIVE_COUNT     9

; TIME_WAIT = 2 * MSL = 60 seconds
%define TCP_TIMEWAIT_MS         60000

; Delayed ACK = 40ms (RFC 1122)
%define TCP_DELAYED_ACK_MS      40

; TCB timer entries (embedded in tcb_t)
struc tcb_timer_t
    .entry:         resb timer_entry_t_size
    .type:          resb 1
    .pad:           resb 7
endstruc

; Extend tcb_t with timer fields (add to unet.inc tcb_t definition)
%define TCB_TIMER_OFF(type)     (tcb_t.retrans_timer_ptr + (type * 8))

section .text

global tcp_timer_init
global tcp_timer_tick
global tcp_timer_retrans_start
global tcp_timer_retrans_stop
global tcp_timer_retrans_handle
global tcp_timer_persist_start
global tcp_timer_persist_stop
global tcp_timer_persist_handle
global tcp_timer_keepalive_start
global tcp_timer_keepalive_stop
global tcp_timer_keepalive_handle
global tcp_timer_timewait_start
global tcp_timer_delayed_ack_start
global tcp_timer_delayed_ack_stop
global tcp_rto_calculate

; =============================================================================
; RTO Calculation (RFC 6298)
; =============================================================================

; tcp_rto_calculate — Update RTO based on new RTT sample
; Input: RDI = tcb_t*, RSI = rtt_us (microseconds)
; Updates: tcb_t.srtt, tcb_t.rttvar, tcb_t.rto
align 64
tcp_rto_calculate:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi            ; tcb_t*
    mov r12, rsi            ; rtt_us

    ; First RTT sample?
    cmp dword [rbx + tcb_t.srtt], 0
    jne .not_first

    ; RFC 6298: Initial RTO
    mov dword [rbx + tcb_t.srtt], r12d
    mov r13d, r12d
    shr r13d, 1             ; rttvar = rtt/2
    mov dword [rbx + tcb_t.rttvar], r13d

    ; RTO = srtt + 4*rttvar
    lea eax, [r12 + r13*4]
    jmp .clamp_rto

.not_first:
    ; srtt = (7/8)*srtt + (1/8)*rtt
    mov eax, [rbx + tcb_t.srtt]
    mov edx, eax
    shr edx, 3              ; srtt/8
    sub eax, edx            ; 7*srtt/8
    mov r13d, r12d
    shr r13d, 3             ; rtt/8
    add eax, r13d
    mov dword [rbx + tcb_t.srtt], eax

    ; rttvar = (3/4)*rttvar + (1/4)*|srtt - rtt|
    mov r13d, [rbx + tcb_t.rttvar]
    mov edx, [rbx + tcb_t.srtt]
    sub edx, r12d           ; srtt - rtt
    jge .abs_pos
    neg edx
.abs_pos:
    mov r14d, r13d
    shr r14d, 2             ; rttvar/4
    sub r13d, r14d          ; 3*rttvar/4
    shr edx, 2              ; |srtt-rtt|/4
    add r13d, edx
    mov dword [rbx + tcb_t.rttvar], r13d

    ; RTO = srtt + 4*rttvar
    mov eax, [rbx + tcb_t.srtt]
    lea eax, [rax + r13*4]

.clamp_rto:
    ; Clamp to [TCP_RTO_MIN_MS, TCP_RTO_MAX_MS]
    cmp eax, TCP_RTO_MIN_MS
    jge .check_max
    mov eax, TCP_RTO_MIN_MS
    jmp .store_rto

.check_max:
    cmp eax, TCP_RTO_MAX_MS
    jle .store_rto
    mov eax, TCP_RTO_MAX_MS

.store_rto:
    mov dword [rbx + tcb_t.rto], eax

    ; If retrans timer is running, reschedule with new RTO
    ; (handled by tcp_timer_retrans_start on next send)

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; =============================================================================
; Retransmission Timer
; =============================================================================

; tcp_timer_retrans_start — Start/rearm retransmission timer
; Input: RDI = tcb_t*
align 64
tcp_timer_retrans_start:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, qword [rbx + tcb_t.retrans_timer_ptr]
    test r12, r12
    jz .no_timer_ptr

    ; Stop existing timer
    mov rdi, r12
    call timer_wheel_del

    ; Calculate delay in ticks (1 tick = 1ms)
    mov eax, [rbx + tcb_t.rto]
    test eax, eax
    jz .use_default
    mov esi, eax
    jmp .schedule

.use_default:
    mov esi, TCP_RTO_INIT_MS

.schedule:
    ; Set up callback
    lea rdx, [tcp_timer_retrans_callback]
    mov rcx, rbx            ; arg = tcb_t*
    mov rdi, r12
    call timer_wheel_add

    pop r12
    pop rbx
    pop rbp
    ret

.no_timer_ptr:
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_timer_retrans_stop — Stop retransmission timer
; Input: RDI = tcb_t*
align 64
tcp_timer_retrans_stop:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov rdi, qword [rbx + tcb_t.retrans_timer_ptr]
    test rdi, rdi
    jz .done
    call timer_wheel_del

.done:
    pop rbx
    pop rbp
    ret

; tcp_timer_retrans_callback — Called when retransmission timer expires
; Input: RDI = tcb_t*
align 64
tcp_timer_retrans_callback:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi            ; tcb_t*

    ; Increment retransmission count
    inc dword [rbx + tcb_t.retransmits]
    mov eax, [rbx + tcb_t.retransmits]
    cmp eax, [rbx + tcb_t.max_retrans]
    jg .max_retrans_exceeded

    ; Exponential backoff for RTO (RFC 6298)
    ; RTO *= 2 on each retransmission
    mov eax, [rbx + tcb_t.rto]
    shl eax, 1
    cmp eax, TCP_RTO_MAX_MS
    jle .store_backoff
    mov eax, TCP_RTO_MAX_MS
.store_backoff:
    mov dword [rbx + tcb_t.rto], eax

    ; Retransmit earliest unacknowledged segment
    mov rdi, rbx
    call tcp_retransmit_head

    ; Rearm timer with new RTO
    mov rdi, rbx
    call tcp_timer_retrans_start

    jmp .done

.max_retrans_exceeded:
    ; Connection failed - send RST and close
    mov rdi, rbx
    call tcp_send_rst
    mov rdi, rbx
    call tcp_close_internal

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_timer_retrans_handle — Called when ACK received, update RTO & timer
; Input: RDI = tcb_t*, RSI = acked_bytes, RDX = rtt_us (0 if no RTT sample)
align 64
tcp_timer_retrans_handle:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rsi            ; acked_bytes
    mov r13, rdx            ; rtt_us

    ; Update RTT estimate if sample provided
    test r13, r13
    jz .no_rtt_sample
    mov rdi, rbx
    mov rsi, r13
    call tcp_rto_calculate

.no_rtt_sample:
    ; Get new snd_una from ACK (passed in RSI as acked_bytes, but we need the actual ACK number)
    ; RSI contains the new snd_una value (the ACK number from the segment)
    mov r14, rsi            ; new_snd_una

    ; Remove acknowledged packets from retransmission queue
    mov r15, qword [rbx + tcb_t.retrans_head]
    test r15, r15
    jz .queue_empty

.dequeue_loop:
    ; Check if this packet is fully acknowledged
    ; Packet's sequence range: [pkt_seq, pkt_seq + pkt_len)
    mov eax, [r15 + net_pkt_t.headroom_offset]
    add eax, [r15 + net_pkt_t.virt_addr]
    movzx eax, word [rax + tcp_hdr_t.seq_num]
    bswap eax                 ; pkt_seq
    mov edx, [r15 + net_pkt_t.data_len]
    sub edx, 20               ; payload_len
    lea r8d, [rax + rdx]      ; pkt_seq + payload_len = end_seq

    cmp r14d, r8d             ; new_snd_una >= end_seq ?
    jb .dequeue_done          ; Not fully acked yet

    ; Packet fully acknowledged - remove from queue
    mov rdi, r15
    mov r15, [r15 + net_pkt_t.next_pkt]

    ; Free the packet (decrement refcount)
    call pktbuf_free

    ; Update queue head
    mov qword [rbx + tcb_t.retrans_head], r15
    test r15, r15
    jnz .dequeue_loop

    ; Queue is now empty
    mov qword [rbx + tcb_t.retrans_tail], 0
    mov dword [rbx + tcb_t.retrans_bytes], 0

.dequeue_done:
    ; Update snd_una
    mov [rbx + tcb_t.snd_una], r14d

    ; Check if queue is empty
    test r15, r15
    jz .all_acked

    ; Still have unacked data - restart timer
    mov rdi, rbx
    call tcp_timer_retrans_start
    jmp .done

.queue_empty:
    mov [rbx + tcb_t.snd_una], r14d

.all_acked:
    ; All acked - stop timer
    mov rdi, rbx
    call tcp_timer_retrans_stop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; =============================================================================
; Persist Timer (Zero Window Probing)
; =============================================================================

; tcp_timer_persist_start — Start persist timer when peer advertises zero window
; Input: RDI = tcb_t*
align 64
tcp_timer_persist_start:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, qword [rbx + tcb_t.persist_timer_ptr]
    test r12, r12
    jz .no_timer

    mov rdi, r12
    call timer_wheel_del

    ; Initial persist timeout = RTO
    mov eax, [rbx + tcb_t.rto]
    test eax, eax
    jz .use_default
    mov esi, eax
    jmp .schedule

.use_default:
    mov esi, TCP_PERSIST_MIN_MS

.schedule:
    lea rdx, [tcp_timer_persist_callback]
    mov rcx, rbx
    mov rdi, r12
    call timer_wheel_add

.no_timer:
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_timer_persist_stop — Stop persist timer
align 64
tcp_timer_persist_stop:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov rdi, qword [rbx + tcb_t.persist_timer_ptr]
    test rdi, rdi
    jz .done
    call timer_wheel_del
    ; Reset backoff counter
    mov dword [rbx + tcb_t.persist_backoff], 0

.done:
    pop rbx
    pop rbp
    ret

; tcp_timer_persist_callback — Send window probe
align 64
tcp_timer_persist_callback:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi

    ; Send 1-byte probe segment
    mov rdi, rbx
    call tcp_send_probe

    ; Exponential backoff
    mov eax, [rbx + tcb_t.persist_backoff]
    inc eax
    mov [rbx + tcb_t.persist_backoff], eax

    ; Calculate next timeout: min(RTO * 2^backoff, TCP_PERSIST_MAX_MS)
    mov ecx, [rbx + tcb_t.rto]
    test ecx, ecx
    jz .use_min
    shl ecx, cl           ; RTO * 2^backoff
    jmp .check_max

.use_min:
    mov ecx, TCP_PERSIST_MIN_MS
    shl ecx, cl

.check_max:
    cmp ecx, TCP_PERSIST_MAX_MS
    jle .schedule
    mov ecx, TCP_PERSIST_MAX_MS

.schedule:
    mov esi, ecx
    mov rdi, qword [rbx + tcb_t.persist_timer_ptr]
    lea rdx, [tcp_timer_persist_callback]
    mov rcx, rbx
    call timer_wheel_add

    pop r12
    pop rbx
    pop rbp
    ret


; =============================================================================
; Keepalive Timer
; =============================================================================

; tcp_timer_keepalive_start — Start keepalive timer
align 64
tcp_timer_keepalive_start:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, qword [rbx + tcb_t.keepalive_timer_ptr]
    test r12, r12
    jz .no_timer

    mov rdi, r12
    call timer_wheel_del

    ; First keepalive after idle period
    mov eax, [rbx + tcb_t.keepalive_idle]
    test eax, eax
    jz .use_default
    mov esi, eax
    jmp .schedule

.use_default:
    mov esi, TCP_KEEPALIVE_IDLE_MS

.schedule:
    lea rdx, [tcp_timer_keepalive_callback]
    mov rcx, rbx
    mov rdi, r12
    call timer_wheel_add

.no_timer:
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_timer_keepalive_stop
align 64
tcp_timer_keepalive_stop:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov rdi, qword [rbx + tcb_t.keepalive_timer_ptr]
    test rdi, rdi
    jz .done
    call timer_wheel_del
    mov dword [rbx + tcb_t.keepalive_count], 0

.done:
    pop rbx
    pop rbp
    ret

; tcp_timer_keepalive_callback
align 64
tcp_timer_keepalive_callback:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, [rbx + tcb_t.keepalive_count]
    inc r12
    mov [rbx + tcb_t.keepalive_count], r12

    cmp r12d, [rbx + tcb_t.keepalive_max]
    jg .max_reached

    ; Send keepalive segment (SEQ = snd_una - 1)
    mov rdi, rbx
    call tcp_send_keepalive

    ; Reschedule for next interval
    mov eax, [rbx + tcb_t.keepalive_intvl]
    test eax, eax
    jz .use_default_intvl
    mov esi, eax
    jmp .resched

.use_default_intvl:
    mov esi, TCP_KEEPALIVE_INTV_MS

.resched:
    mov rdi, qword [rbx + tcb_t.keepalive_timer_ptr]
    lea rdx, [tcp_timer_keepalive_callback]
    mov rcx, rbx
    call timer_wheel_add
    jmp .done

.max_reached:
    ; Connection dead - send RST and close
    mov rdi, rbx
    call tcp_send_rst
    mov rdi, rbx
    call tcp_close_internal

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; =============================================================================
; TIME_WAIT Timer
; =============================================================================

; tcp_timer_timewait_start — Start TIME_WAIT timer (2*MSL = 60s)
align 64
tcp_timer_timewait_start:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, qword [rbx + tcb_t.timewait_timer_ptr]
    test r12, r12
    jz .no_timer

    mov rdi, r12
    call timer_wheel_del

    mov esi, TCP_TIMEWAIT_MS
    lea rdx, [tcp_timer_timewait_callback]
    mov rcx, rbx
    mov rdi, r12
    call timer_wheel_add

.no_timer:
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_timer_timewait_callback — TIME_WAIT expired, fully close
align 64
tcp_timer_timewait_callback:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    ; Remove from hash table, free TCB
    mov rdi, rbx
    call tcp_tcb_remove
    mov rdi, rbx
    lea rsi, [tcb_cache]
    xchg rdi, rsi
    call kmem_cache_free

    pop rbx
    pop rbp
    ret


; =============================================================================
; Delayed ACK Timer
; =============================================================================

; tcp_timer_delayed_ack_start — Start delayed ACK timer (40ms)
align 64
tcp_timer_delayed_ack_start:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, qword [rbx + tcb_t.delayed_ack_timer_ptr]
    test r12, r12
    jz .no_timer

    ; Don't restart if already armed
    cmp byte [r12 + timer_entry_t.active], 1
    je .done

    mov rdi, r12
    call timer_wheel_del

    mov esi, TCP_DELAYED_ACK_MS
    lea rdx, [tcp_timer_delayed_ack_callback]
    mov rcx, rbx
    mov rdi, r12
    call timer_wheel_add

.no_timer:
.done:
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_timer_delayed_ack_stop
align 64
tcp_timer_delayed_ack_stop:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov rdi, qword [rbx + tcb_t.delayed_ack_timer_ptr]
    test rdi, rdi
    jz .done
    call timer_wheel_del

.done:
    pop rbx
    pop rbp
    ret

; tcp_timer_delayed_ack_callback — Send delayed ACK
align 64
tcp_timer_delayed_ack_callback:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    mov rdi, rbx
    call tcp_send_ack

    pop rbx
    pop rbp
    ret


; =============================================================================
; Master Timer Tick — Called from unet_poll (1kHz)
; =============================================================================

; tcp_timer_tick — Process all TCP timers for one tick
; Called from unet_poll -> timer_wheel_tick processes all wheels
align 64
tcp_timer_tick:
    push rbp
    mov rbp, rsp

    ; The timer wheel processes all expirations automatically
    ; This function exists for any per-tick TCP housekeeping
    ; (e.g., RTO backoff tracking, keepalive idle detection)

    xor eax, eax
    pop rbp
    ret


; =============================================================================
; TCB Timer Initialization/Cleanup
; =============================================================================

; tcp_timer_tcb_init — Initialize all timer pointers in TCB
; Input: RDI = tcb_t*
; Must be called after tcb_t allocation, before use
align 64
tcp_timer_tcb_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi

    ; Allocate timer entries from slab (or embed in TCB)
    ; For now, allocate from kmem_cache
    ; TODO: Use dedicated timer slab or embed in TCB struct

    mov r12, TCP_TIMER_COUNT
    xor r13, r13

.alloc_loop:
    lea rdi, [timer_entry_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .alloc_fail

    ; Store pointer in TCB timer array
    mov qword [rbx + TCB_TIMER_OFF(r13)], rax

    inc r13
    dec r12
    jnz .alloc_loop

    ; Set default keepalive values
    mov dword [rbx + tcb_t.keepalive_idle], TCP_KEEPALIVE_IDLE_MS
    mov dword [rbx + tcb_t.keepalive_intvl], TCP_KEEPALIVE_INTV_MS
    mov dword [rbx + tcb_t.keepalive_max], TCP_KEEPALIVE_COUNT
    mov dword [rbx + tcb_t.persist_backoff], 0
    mov dword [rbx + tcb_t.retransmits], 0

    ; Initialize congestion control
    mov dword [rbx + tcb_t.ssthresh], 0xFFFFFFFF  ; Infinite initially
    mov dword [rbx + tcb_t.cwnd], 10            ; Initial cwnd = 10 MSS (RFC 6928)
    mov dword [rbx + tcb_t.dup_acks], 0
    mov dword [rbx + tcb_t.last_ack], 0

    ; Initialize CUBIC congestion control
    lea rsi, [cubic_state_t_size]
    lea rdi, [cubic_state_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .cc_fail
    mov qword [rbx + tcb_t.cc_state], rax
    mov rdi, rbx
    mov rsi, rax
    call cubic_init

.cc_fail:
    ; Initialize ECN
    mov rdi, rbx
    call tcp_ecn_init

    ; Initialize RACK state
    lea rsi, [rack_state_cache]
    lea rdi, [rack_state_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .rack_fail
    mov qword [rbx + tcb_t.rack_ptr], rax
    mov rdi, rax
    call rack_init

.rack_fail:
    xor eax, eax
    jmp .done

.alloc_fail:
    ; Free any already allocated
    dec r13
    jz .done_fail
.free_loop:
    mov rdi, qword [rbx + TCB_TIMER_OFF(r13)]
    test rdi, rdi
    jz .next_free
    lea rsi, [timer_entry_cache]
    xchg rdi, rsi
    call kmem_cache_free
.next_free:
    dec r13
    jnz .free_loop
.done_fail:
    mov eax, -1

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_timer_tcb_cleanup — Free all timer entries
align 64
tcp_timer_tcb_cleanup:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, TCP_TIMER_COUNT
    xor r13, r13

.cleanup_loop:
    mov rdi, qword [rbx + TCB_TIMER_OFF(r13)]
    test rdi, rdi
    jz .next_cleanup

    ; Stop timer if active
    call timer_wheel_del

    ; Free timer entry
    lea rsi, [timer_entry_cache]
    xchg rdi, rsi
    call kmem_cache_free

    mov qword [rbx + TCB_TIMER_OFF(r13)], 0

.next_cleanup:
    inc r13
    dec r12
    jnz .cleanup_loop

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret


; =============================================================================
; Timer Entry Slab Cache
; =============================================================================

section .bss
alignb 64
timer_entry_cache:    resb kmem_cache_t_size
cubic_state_cache:    resb kmem_cache_t_size
bbrv2_state_cache:    resb kmem_cache_t_size
rack_state_cache:    resb kmem_cache_t_size

section .data
timer_entry_cache_name: db "tcp_timer_entry", 0
cubic_state_cache_name: db "tcp_cubic_state", 0
bbrv2_state_cache_name: db "tcp_bbrv2_state", 0
rack_state_cache_name: db "tcp_rack_state", 0

; Initialize timer entry cache (call from tcp_init)
global tcp_timer_cache_init
align 64
tcp_timer_cache_init:
    push rbp
    mov rbp, rsp
    push rbx

    lea rdi, [timer_entry_cache]
    lea rsi, [timer_entry_cache_name]
    mov rdx, timer_entry_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    ; Initialize CUBIC state cache
    lea rdi, [cubic_state_cache]
    lea rsi, [cubic_state_cache_name]
    mov rdx, cubic_state_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    ; Initialize BBRv2 state cache
    lea rdi, [bbrv2_state_cache]
    lea rsi, [bbrv2_state_cache_name]
    mov rdx, bbrv2_state_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    ; Initialize RACK state cache
    lea rdi, [rack_state_cache]
    lea rsi, [rack_state_cache_name]
    mov rdx, rack_state_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_TIMER_ASM
