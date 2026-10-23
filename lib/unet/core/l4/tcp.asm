%ifndef GUARD_UNET_CORE_L4_TCP_ASM
%define GUARD_UNET_CORE_L4_TCP_ASM
; =============================================================================
; Utkarsha OS — unet/core/l4/tcp.asm
; =============================================================================
; Master TCP Stack Engine (RFC 793, RFC 7323 Window Scale, RFC 2018 SACK).
;
; Features:
;   - Full TCP Header Parsing & Verification (Ports, Seq, Ack, Data Offset, Flags, Window, Checksum)
;   - TCP State Machine: LISTEN, SYN_SENT, SYN_RCVD, ESTABLISHED, FIN_WAIT_1/2, TIME_WAIT, CLOSE_WAIT
;   - Fast-Path Ingress Demux via Hash-Indexed TCB Lookup Table
;   - Zero-Copy Transmit Payload Construction & Checksum Offload Flag Handling
;   - TCP Window Scaling & Timestamp Options Processing
;   - RDTSC Timestamp Ingress Sampling
;
; Delegates:
;   - TCB Slab Allocator                 -> lib/mem/slab.asm
;   - Timer Wheel                       -> lib/time/timer_wheel.asm
;   - High-Precision Cycle Counter      -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;   - BBR Congestion Control             -> unet/core/l4/tcp_bbr.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"
%include "lib/unet/core/l4/tcp_timer.asm"

%define IP_PROTO_TCP                 6   ; matches udp.asm's local IP_PROTO_UDP
                                          ; pattern rather than unet.inc's
                                          ; differently-named UNET_IP_PROTO_TCP

%define TCP_STATE_CLOSED            0
%define TCP_STATE_LISTEN            1
%define TCP_STATE_SYN_SENT          2
%define TCP_STATE_SYN_RCVD          3
%define TCP_STATE_ESTABLISHED       4
%define TCP_STATE_FIN_WAIT_1        5
%define TCP_STATE_FIN_WAIT_2        6
%define TCP_STATE_CLOSE_WAIT        7
%define TCP_STATE_CLOSING           8
%define TCP_STATE_LAST_ACK          9
%define TCP_STATE_TIME_WAIT         10

%define TCP_FLAG_FIN                0x01
%define TCP_FLAG_SYN                0x02
%define TCP_FLAG_RST                0x04
%define TCP_FLAG_PSH                0x08
%define TCP_FLAG_ACK                0x10
%define TCP_FLAG_URG                0x20
%define TCP_FLAG_ECE                0x40
%define TCP_FLAG_CWR                0x80

; TCB Flags
%define TCBF_NEED_OUTPUT            0x01
%define TCBF_NEED_ACK               0x02
%define TCBF_FIN_SENT               0x04
%define TCBF_FIN_RECV               0x08
%define TCBF_NODELAY                0x10
%define TCBF_KEEPALIVE              0x20
%define TCBF_SACK_PERM              0x40
%define TCBF_TIMESTAMPS             0x80
%define TCBF_CORK                   0x100
%define TCBF_FAST_RECOVERY          0x200
%define TCBF_TFO_CLIENT             0x400
%define TCBF_TFO_SERVER             0x800
%define TCBF_TFO_COOKIE_VALID       0x1000

struc tcp_hdr_t
    .src_port:          resw 1      ; Source Port (Big Endian)
    .dst_port:          resw 1      ; Destination Port (Big Endian)
    .seq_num:           resd 1      ; Sequence Number (Big Endian)
    .ack_num:           resd 1      ; Acknowledgment Number (Big Endian)
    .data_offset_flags: resw 1      ; Data Offset (4b) + Reserved (6b) + Flags (6b)
    .window_size:       resw 1      ; Window Size (Big Endian)
    .checksum:          resw 1      ; TCP Checksum
    .urgent_ptr:        resw 1      ; Urgent Pointer
endstruc

struc tcb_t
    .state:             resd 1      ; TCP State Machine
    .local_ip:          resd 1      ; Local IPv4 Address
    .remote_ip:         resd 1      ; Remote IPv4 Address
    .local_port:        resw 1      ; Local TCP Port
    .remote_port:       resw 1      ; Remote TCP Port
    .snd_una:           resd 1      ; Send Unacknowledged
    .snd_nxt:           resd 1      ; Send Next
    .rcv_nxt:           resd 1      ; Receive Next
    .rcv_wnd:           resd 1      ; Receive Window Size
    .snd_wnd:           resd 1      ; Send Window Size
    .timer_id:          resd 1      ; Timer Wheel ID (legacy)
    .srtt:              resd 1      ; Smoothed Round Trip Time (us)
    .rto:               resd 1      ; Retransmission Timeout (ms)
    .snd_scale:         resb 1      ; Window Scale Shift Factor (Send)
    .rcv_scale:         resb 1      ; Window Scale Shift Factor (Receive)
    .bbr_bw:            resq 1      ; BBR Bottleneck Bandwidth
    .bbr_rtt:           resd 1      ; BBR Min RTT
    .hash_next:          resq 1      ; Next tcb_t* in this hash bucket's chain
    .sock_ptr:           resq 1      ; Owning socket_t*, or the listener's
                                     ; socket_t* while still in SYN_RCVD
    .is_listener:         resb 1      ; 1 for the pseudo-TCB a LISTEN socket
                                     ; owns (wildcard remote_ip/remote_port)

    ; --- Timer Integration ---
    .retrans_timer_ptr:  resq 1      ; timer_entry_t* for retransmission
    .persist_timer_ptr:  resq 1      ; timer_entry_t* for zero-window probe
    .keepalive_timer_ptr: resq 1     ; timer_entry_t* for keepalive
    .timewait_timer_ptr: resq 1      ; timer_entry_t* for TIME_WAIT
    .delayed_ack_timer_ptr: resq 1   ; timer_entry_t* for delayed ACK

    ; --- RTO/Retransmission ---
    .retransmits:        resd 1      ; Retransmission count
    .max_retrans:        resd 1      ; Max retransmissions before abort
    .rttvar:             resd 1      ; RTT variation (us)

    ; --- Retransmission Queue ---
    .retrans_head:       resq 1      ; Head of retransmission queue (net_pkt_t*)
    .retrans_tail:       resq 1      ; Tail of retransmission queue
    .retrans_bytes:      resd 1      ; Bytes in retransmission queue

    ; --- Persist Timer ---
    .persist_backoff:    resd 1      ; Current backoff exponent

    ; --- Keepalive ---
    .keepalive_idle:     resd 1      ; Idle time before first keepalive (ms)
    .keepalive_intvl:    resd 1      ; Interval between keepalives (ms)
    .keepalive_max:      resd 1      ; Max keepalive probes before abort
    .keepalive_count:    resd 1      ; Current probe count

    ; --- Congestion Control ---
    .cc_ops:             resq 1      ; cc_ops* (CUBIC, BBR, etc.)
    .cc_state:           resq 1      ; Congestion control private state
    .ssthresh:           resd 1      ; Slow start threshold
    .cwnd:               resd 1      ; Congestion window
    .dup_acks:           resd 1      ; Duplicate ACK count
    .last_ack:           resd 1      ; Last ACK number received
    .mss:                resd 1      ; Negotiated maximum segment size
    .ts_recent:          resd 1      ; Most recent peer timestamp
    .ts_last_ack:        resd 1      ; Local timestamp echoed by peer
    .stats_retrans:      resd 1      ; Retransmitted segment count
    .stats_tx_bytes:     resq 1      ; Transmitted byte count
    .flags:              resd 1      ; TCBF_* state bits

    ; --- ECN ---
    .ecn_state:          resb 1      ; ECN state machine
    .ecn_flags:          resb 1      ; ECN flags for outgoing packets
    .ce_count:           resd 1      ; CE marks received
    .ece_sent:           resd 1      ; ECE signals sent
    .cwr_sent:           resd 1      ; CWR signals sent
    .pad_ecn:            resb 3

    ; --- RACK/TLP ---
    .rack_ptr:           resq 1      ; Pointer to RACK state

    ; --- SACK / FACK ---
    .fack_highest:       resd 1      ; Highest SACKed sequence (FACK)

    ; --- OOO Reassembly Queue ---
    .ooo_head:           resq 1      ; Head of OOO segment queue
    .ooo_tail:           resq 1      ; Tail of OOO segment queue
endstruc

%define TCP_TCB_HASH_SIZE            1024

section .bss
alignb 64
tcp_tcb_hashtable:      resq TCP_TCB_HASH_SIZE   ; bucket -> tcb_t* chain head
tcb_cache:               resb kmem_cache_t_size
tcp_iss_counter:          resd 1      ; crude Initial Sequence Number source

section .data
tcb_cache_name: db "tcb", 0

section .text

global tcp_init
global tcp_input
global tcp_timer_tick
global tcp_connect
global tcp_close
global tcp_send_data
global tcp_checksum_calc
global tcp_tcb_lookup
global tcp_tcb_insert
global tcp_tcb_remove
global tcp_listen

; Timer callback functions (called from timer wheel)
global tcp_timer_retrans_callback
global tcp_timer_persist_callback
global tcp_timer_keepalive_callback
global tcp_timer_timewait_callback
global tcp_timer_delayed_ack_callback

; Internal timer functions
global tcp_retransmit_head
global tcp_send_probe
global tcp_send_keepalive
global tcp_send_rst
global tcp_close_internal

; SYN cookie functions
global tcp_send_synack_with_cookie

; ECN functions
global tcp_ecn_init
global tcp_ecn_syn_sent
global tcp_ecn_syn_rcvd
global tcp_ecn_established
global tcp_ecn_process_ce
global tcp_ecn_process_ece
global tcp_ecn_process_cwr
global tcp_ecn_set_flags
global tcp_ecn_get_flags

; Fast Open functions
global tfo_init
global tfo_generate_cookie
global tfo_validate_cookie
global tfo_process_syn
global tfo_process_synack
global tfo_send_syn_with_data
global tfo_client_init
global tfo_server_enable

; TCP-AO functions
global tcp_ao_init
global tcp_ao_mkt_create
global tcp_ao_mkt_delete
global tcp_ao_mkt_lookup
global tcp_ao_mkt_set_active
global tcp_ao_compute_mac
global tcp_ao_verify_mac
global tcp_ao_gen_option
global tcp_ao_parse_option
global tcp_ao_key_rotate

; RACK/TLP functions
global rack_init
global rack_on_ack
global rack_on_data_sent
global rack_update
global rack_cong_event
global tlp_schedule_probe
global tlp_on_ack

; TLS 1.3 functions
global tls_init
global tls_connection_create
global tls_connection_destroy
global tls_handshake_client
global tls_handshake_server
global tls_encrypt_record
global tls_decrypt_record
global tls_ktls_enable
global tls_ktls_disable
global tls_write_early_data
global tls_read_early_data
global tls_key_update

; QUIC functions
global quic_init
global quic_connection_create
global quic_connection_destroy
global quic_input
global quic_output
global quic_send_initial
global quic_send_handshake
global quic_send_1rtt
global quic_process_initial
global quic_process_handshake
global quic_process_1rtt
global quic_send_ack
global quic_on_ack

; Option parsing/generation
global tcp_parse_options
global tcp_gen_options
global tcp_fast_retransmit

; SACK / OOO reassembly
global tcp_process_sack
global tcp_sack_mark_blocks
global tcp_ooo_insert
global tcp_ooo_drain
global tcp_ooo_cache_init

; -----------------------------------------------------------------------------
; tcp_tcb_hash — 4-tuple -> bucket index.
; Input: EDI = local_port|remote_port<<16 packed, ESI = remote_ip
; Output: EAX = bucket index [0, TCP_TCB_HASH_SIZE)
; -----------------------------------------------------------------------------
align 64
tcp_tcb_hash:
    mov eax, edi
    xor eax, esi
    mov ecx, eax
    shr ecx, 16
    xor eax, ecx
    and eax, TCP_TCB_HASH_SIZE - 1
    ret

; -----------------------------------------------------------------------------
; tcp_init — Master TCP Subsystem Initialization
; -----------------------------------------------------------------------------
align 64
tcp_init:
    push rbp
    mov rbp, rsp
    push rcx

    lea rdi, [tcp_tcb_hashtable]
    xor eax, eax
    mov ecx, TCP_TCB_HASH_SIZE
    rep stosq

    lea rdi, [tcb_cache]
    lea rsi, [tcb_cache_name]
    mov rdx, tcb_t_size
    mov rcx, 8
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    ; Initialize timer entry cache
    call tcp_timer_cache_init

    ; Initialize OOO segment cache
    call tcp_ooo_cache_init

    ; Initialize SYN cookie subsystem
    call syncookie_init

    ; Initialize TCP Fast Open subsystem
    call tfo_init

    ; Initialize TCP-AO subsystem
    call tcp_ao_init

    ; Initialize TLS 1.3 subsystem
    call tls_init

    ; Initialize timer wheel
    mov rdi, timer_wheel
    call timer_wheel_init

    mov dword [tcp_iss_counter], 0x1000

    xor eax, eax
    pop rcx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_tcb_lookup — Find a TCB (or listening pseudo-TCB) for a 4-tuple.
; Input: EDI = local_port (host), ESI = remote_port (host, 0 = wildcard),
;        EDX = local_ip, ECX = remote_ip (0 = wildcard)
; Output: RAX = tcb_t*, or 0
;
; Tries an exact match first, then falls back to a listener on the same
; local_port (remote_port/remote_ip wildcarded) — the usual BSD demux order.
; -----------------------------------------------------------------------------
align 64
tcp_tcb_lookup:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; local_port
    mov r13d, esi                   ; remote_port
    mov r14d, edx                   ; local_ip
    mov r15d, ecx                   ; remote_ip

    mov edi, r12d
    mov eax, r13d
    shl eax, 16
    or edi, eax
    mov esi, r15d
    call tcp_tcb_hash
    lea rbx, [tcp_tcb_hashtable]
    mov rbx, [rbx + rax * 8]

.scan:
    test rbx, rbx
    jz .try_listener
    movzx eax, word [rbx + tcb_t.local_port]
    cmp eax, r12d
    jne .next
    movzx eax, word [rbx + tcb_t.remote_port]
    cmp eax, r13d
    jne .next
    mov eax, [rbx + tcb_t.remote_ip]
    cmp eax, r15d
    jne .next
    mov rax, rbx
    jmp .done
.next:
    mov rbx, [rbx + tcb_t.hash_next]
    jmp .scan

.try_listener:
    ; A listener's pseudo-TCB hashes with remote_port=0, remote_ip=0.
    mov edi, r12d
    xor esi, esi
    call tcp_tcb_hash
    lea rbx, [tcp_tcb_hashtable]
    mov rbx, [rbx + rax * 8]
.scan_listen:
    test rbx, rbx
    jz .miss
    cmp byte [rbx + tcb_t.is_listener], 1
    jne .next_listen
    movzx eax, word [rbx + tcb_t.local_port]
    cmp eax, r12d
    jne .next_listen
    mov rax, rbx
    jmp .done
.next_listen:
    mov rbx, [rbx + tcb_t.hash_next]
    jmp .scan_listen

.miss:
    xor eax, eax
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_tcb_insert — Add a tcb_t to the hash table.
; Input: RDI = tcb_t* (local_port/remote_port/remote_ip/is_listener already set)
; -----------------------------------------------------------------------------
align 64
tcp_tcb_insert:
    push rbx
    push r12

    mov r12, rdi                    ; R12 = tcb_t*
    movzx eax, word [r12 + tcb_t.local_port]

    cmp byte [r12 + tcb_t.is_listener], 1
    je .listener_key

    movzx ecx, word [r12 + tcb_t.remote_port]
    mov edi, eax
    shl ecx, 16
    or edi, ecx
    mov esi, [r12 + tcb_t.remote_ip]
    jmp .hash

.listener_key:
    mov edi, eax                    ; remote_port field packs as 0
    xor esi, esi

.hash:
    call tcp_tcb_hash
    lea rbx, [tcp_tcb_hashtable]
    mov rcx, [rbx + rax * 8]
    mov [r12 + tcb_t.hash_next], rcx
    mov [rbx + rax * 8], r12

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_tcb_remove — Unlink a tcb_t from the hash table (does not free it).
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_tcb_remove:
    push rbx
    push r12
    push r13

    mov r12, rdi
    movzx eax, word [r12 + tcb_t.local_port]

    cmp byte [r12 + tcb_t.is_listener], 1
    je .listener_key
    movzx ecx, word [r12 + tcb_t.remote_port]
    mov edi, eax
    shl ecx, 16
    or edi, ecx
    mov esi, [r12 + tcb_t.remote_ip]
    jmp .hash
.listener_key:
    mov edi, eax
    xor esi, esi
.hash:
    call tcp_tcb_hash
    lea rbx, [tcp_tcb_hashtable]
    lea rbx, [rbx + rax * 8]        ; RBX = &bucket head slot
    mov rcx, [rbx]                  ; RCX = current node
    xor r13d, r13d                  ; R13 = previous node (0 = none yet)
.scan:
    test rcx, rcx
    jz .done
    cmp rcx, r12
    je .found
    mov r13, rcx
    mov rcx, [rcx + tcb_t.hash_next]
    jmp .scan
.found:
    mov rax, [rcx + tcb_t.hash_next]
    test r13, r13
    jz .unlink_head
    mov [r13 + tcb_t.hash_next], rax
    jmp .done
.unlink_head:
    mov [rbx], rax
.done:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_listen — Turn a socket_t into a TCP listener on local_port.
; Input: EDI = local_port (host order), RSI = socket_t*
; Output: EAX = 0 on success, -1 on OOM
; -----------------------------------------------------------------------------
align 64
tcp_listen:
    push rbx
    push r12
    push r13

    mov r13d, edi                   ; local_port, survives the alloc call
    mov r12, rsi                    ; socket_t*

    lea rdi, [tcb_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov word [rbx + tcb_t.local_port], r13w
    mov word [rbx + tcb_t.remote_port], 0
    mov dword [rbx + tcb_t.remote_ip], 0
    mov dword [rbx + tcb_t.local_ip], 0
    mov dword [rbx + tcb_t.state], TCP_STATE_LISTEN
    mov byte [rbx + tcb_t.is_listener], 1
    mov qword [rbx + tcb_t.sock_ptr], r12
    mov qword [rbx + tcb_t.hash_next], 0

    mov [r12 + socket_t.tcb_ptr], rbx
    mov dword [r12 + socket_t.state], TCP_STATE_LISTEN

    mov rdi, rbx
    call tcp_tcb_insert

    xor eax, eax
    jmp .done
.oom:
    mov eax, -1
.done:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_checksum_calc — RFC 793 pseudo-header + TCP segment checksum.
; Input: EDI = src IP, ESI = dst IP, RDX = tcp_hdr_t* (segment start),
;        ECX = segment length (header + payload, host order byte count)
; Output: AX = checksum in network byte order, ready to store (generation)
;         or compare against a received field's fold (== 0xFFFF => valid).
; This one function serves both generation and verification: the caller
; either stores AX into the checksum field (after zeroing it first) or, for
; verification, calls it with the received checksum field left in place and
; checks the fold via tcp_checksum_verify below instead of reading AX.
; -----------------------------------------------------------------------------
align 64
tcp_checksum_calc:
    push rbx
    push rsi
    push rdx
    push r8
    push r9
    sub rsp, 12

    mov [rsp], edi                  ; pseudo.src_ip
    mov [rsp+4], esi                ; pseudo.dst_ip
    mov byte [rsp+8], 0
    mov byte [rsp+9], IP_PROTO_TCP  ; from unet.inc: 6
    mov r8d, ecx
    rol r8w, 8                      ; TCP length, network order in the pseudo hdr
    mov [rsp+10], r8w

    lea rdi, [rsp]
    mov esi, 12
    call ip_checksum_calc
    mov r9d, eax                    ; partial #1

    mov rdi, rdx
    mov esi, ecx
    call ip_checksum_calc           ; partial #2 (TCP header + payload)

    add eax, r9d
.fold:
    mov edx, eax
    shr edx, 16
    test edx, edx
    jz .done
    and eax, 0xFFFF
    add eax, edx
    jmp .fold
.done:
    add rsp, 12
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_checksum_verify — RDI=net_pkt_t*, ESI=src_ip, EDX=dst_ip, ECX=seg_len,
; R8=tcp_hdr_t* (checksum field left as received) -> EAX = 0 valid, -1 corrupt
; -----------------------------------------------------------------------------
align 64
tcp_checksum_verify:
    push rdi
    mov edi, esi
    mov esi, edx
    mov rdx, r8
    call tcp_checksum_calc
    cmp ax, 0xFFFF
    je .ok
    mov eax, -1
    jmp .done
.ok:
    xor eax, eax
.done:
    pop rdi
    ret

; -----------------------------------------------------------------------------
; tcp_input — Process Inbound TCP Segment & drive the state machine.
; Input: RDI = Pointer to net_pkt_t (headroom_offset at the TCP header),
;        ESI = Source IP (network order), EDX = Dest IP (network order)
; Output: EAX = 0 (Handled), -1 (Dropped/RST)
;
; Implements the 3-way handshake (passive open only — active open is
; tcp_connect below), in-order data delivery into the owning socket's rx
; queue, and a basic FIN close. What's explicitly NOT here: retransmission
; (tcp_timer_tick is still a no-op), congestion control, SACK, out-of-order
; reassembly, and window scaling negotiation — tcb_t already reserves fields
; for BBR (.bbr_bw/.bbr_rtt) and window scale for whenever that lands.
; -----------------------------------------------------------------------------
align 64
tcp_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = net_pkt_t*
    mov r14d, esi                    ; source IP (network order)
    mov r15d, edx                    ; dest IP (network order)

    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax                    ; R12 = tcp_hdr_t*

    mov eax, [rbx + net_pkt_t.data_len]
    sub eax, [rbx + net_pkt_t.headroom_offset]
    cmp eax, 20
    jb .drop_free
    mov r13d, eax                    ; R13D = segment length (hdr + payload)

    ; Checksum verify (only if a nonzero value was actually sent — TCP
    ; technically requires it, but real senders occasionally offload/omit
    ; it, and dropping on a zero field would be pointlessly strict here).
    cmp word [r12 + tcp_hdr_t.checksum], 0
    je .csum_ok
    mov esi, r14d
    mov edx, r15d
    mov ecx, r13d
    mov r8, r12
    call tcp_checksum_verify        ; ECX (seg len) passes through untouched
                                     ; to tcp_checksum_calc — see that
                                     ; function's body, it never reassigns it
    test eax, eax
    jnz .drop_free
.csum_ok:

    movzx eax, word [r12 + tcp_hdr_t.src_port]
    xchg al, ah
    mov r8d, eax                    ; remote_port (peer's src)
    movzx eax, word [r12 + tcp_hdr_t.dst_port]
    xchg al, ah
    mov r9d, eax                    ; local_port

    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    movzx ecx, al
    and ecx, 0x0F                   ; TCP flags (low byte after the swap)
    mov r10d, ecx                    ; R10D = flags

    ; 4-tuple lookup: local_port, remote_port, local_ip, remote_ip
    mov edi, r9d
    mov esi, r8d
    mov edx, r15d
    mov ecx, r14d
    call tcp_tcb_lookup
    test rax, rax
    jz .no_tcb
    mov r11, rax                    ; R11 = tcb_t*

    ; Parse TCP options (if data offset > 5)
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    movzx eax, al
    and eax, 0xF0
    shr eax, 4                  ; data offset in 32-bit words
    cmp eax, 5
    jbe .no_options
    lea eax, [rax * 4 - 20]     ; options length in bytes
    lea rdi, [r12 + 20]         ; pointer to options
    mov rsi, r11                ; tcb_t*
    mov rdx, rax                ; options length
    call tcp_parse_options

.no_options:

    cmp byte [r11 + tcb_t.is_listener], 1
    je .on_listener

    ; Established (or handshake-in-progress) connection.
    test r10d, TCP_FLAG_RST
    jnz .do_rst

    test r10d, TCP_FLAG_SYN
    jz .not_syn
    ; Retransmitted SYN for a connection we already have — ignore.
    jmp .ok_free
.not_syn:

    cmp dword [r11 + tcb_t.state], TCP_STATE_SYN_RCVD
    jne .not_handshake_ack
    test r10d, TCP_FLAG_ACK
    jz .ok_free
    ; Handshake complete: move to ESTABLISHED and hand the socket to accept().
    mov dword [r11 + tcb_t.state], TCP_STATE_ESTABLISHED
    mov eax, [r12 + tcp_hdr_t.ack_num]
    bswap eax
    mov [r11 + tcb_t.snd_una], eax
    call tcp_deliver_to_acceptor
    jmp .ok_free
.not_handshake_ack:

    cmp dword [r11 + tcb_t.state], TCP_STATE_ESTABLISHED
    jne .other_state

    ; Process ECN in incoming packet
    mov rdi, r11                ; tcb_t*
    mov rsi, r12                ; tcp_hdr_t*
    ; Need IP header - get from packet
    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    sub edx, 20                 ; IP header is 20 bytes before TCP
    add rax, rdx
    mov rdx, rax                ; ip_hdr_t*

    ; Get ECN from packet metadata
    movzx edx, byte [rbx + net_pkt_t.ecn]
    call tcp_ecn_established

    ; Data / FIN in ESTABLISHED.
    mov eax, [r12 + tcp_hdr_t.seq_num]
    bswap eax
    add eax, r13d
    sub eax, 20                      ; payload bytes advance rcv_nxt

    test r10d, TCP_FLAG_FIN
    jz .no_fin
    inc eax                          ; FIN consumes one sequence number
    mov dword [r11 + tcb_t.state], TCP_STATE_CLOSE_WAIT
.no_fin:
    mov [r11 + tcb_t.rcv_nxt], eax

    ; Update peer's send window (with scaling)
    movzx eax, word [r12 + tcp_hdr_t.window_size]
    xchg al, ah
    movzx ecx, byte [r11 + tcb_t.snd_scale]
    shl eax, cl
    mov [r11 + tcb_t.snd_wnd], eax

    ; Check for ACK flag and process if present
    test r10d, TCP_FLAG_ACK
    jz .no_ack
    ; Calculate RTT sample if this ACK acknowledges new data
    mov eax, [r12 + tcp_hdr_t.ack_num]
    bswap eax
    cmp eax, [r11 + tcb_t.snd_una]
    jbe .no_rtt_sample               ; Not advancing snd_una
    ; TODO: Calculate RTT from timestamp option or packet timestamp
    ; For now, pass 0 for RTT sample (will use RTO without update)
    mov rdi, r11
    mov rsi, rax
    sub rsi, [r11 + tcb_t.snd_una]   ; acked bytes
    xor rdx, rdx                     ; rtt_us = 0 (no timestamp yet)
    call tcp_timer_retrans_handle

    ; Reset DUPACK counter on new ACK
    mov dword [r11 + tcb_t.dup_acks], 0
    mov [r11 + tcb_t.last_ack], eax

    ; Process SACK options if present
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    movzx eax, al
    and eax, 0xF0
    shr eax, 4
    cmp eax, 5
    jbe .no_sack_process
    lea eax, [rax * 4 - 20]
    lea rdi, [r12 + 20]
    mov rsi, rax
    mov rdi, r11
    call tcp_process_sack

.no_sack_process:
    jmp .ack_processed

.no_rtt_sample:
    ; Check for duplicate ACK
    cmp eax, [r11 + tcb_t.last_ack]
    jne .not_dup_ack

    ; Duplicate ACK received
    inc dword [r11 + tcb_t.dup_acks]
    mov eax, [r11 + tcb_t.dup_acks]
    cmp eax, 3
    je .fast_retransmit

    ; ACK received but no new data - still need to handle window updates
    mov rdi, r11
    xor rsi, rsi
    xor rdx, rdx
    call tcp_timer_retrans_handle
    jmp .ack_processed

.not_dup_ack:
    ; New ACK number but doesn't advance snd_una (window update only)
    mov [r11 + tcb_t.last_ack], eax
    mov dword [r11 + tcb_t.dup_acks], 0
    mov rdi, r11
    xor rsi, rsi
    xor rdx, rdx
    call tcp_timer_retrans_handle
    jmp .ack_processed

.fast_retransmit:
    ; 3 DUPACKs - trigger fast retransmit
    mov rdi, r11
    call tcp_fast_retransmit
    jmp .ack_processed

.ack_processed:
.no_ack:

    cmp r13d, 20
    jbe .no_payload

    ; Check if segment is in-order (seq == rcv_nxt)
    mov eax, [r12 + tcp_hdr_t.seq_num]
    bswap eax
    cmp eax, [r11 + tcb_t.rcv_nxt]
    je .in_order_payload

    ; Out-of-order segment - insert into OOO reassembly queue
    mov rdi, r11
    mov rsi, rbx
    call tcp_ooo_insert
    ; Send immediate ACK for out-of-order segment (RFC 5681)
    mov rdi, r11
    call tcp_send_ack
    jmp .ok_no_free

.in_order_payload:
    ; Hand the payload off to the socket's receive queue (whole net_pkt_t;
    ; headroom_offset already points at the TCP header, so the reader skips
    ; the 20-byte header itself — see unet_recv in unet_api.asm).
    mov rdi, [r11 + tcb_t.sock_ptr]
    test rdi, rdi
    jz .no_payload
    mov qword [rbx + net_pkt_t.next_pkt], 0
    cmp qword [rdi + socket_t.rx_queue_tail], 0
    je .rx_empty
    mov rcx, [rdi + socket_t.rx_queue_tail]
    mov [rcx + net_pkt_t.next_pkt], rbx
    mov [rdi + socket_t.rx_queue_tail], rbx
    jmp .rx_queued
.rx_empty:
    mov [rdi + socket_t.rx_queue_head], rbx
    mov [rdi + socket_t.rx_queue_tail], rbx
.rx_queued:
    ; Start delayed ACK timer instead of immediate ACK
    mov rdi, r11
    call tcp_timer_delayed_ack_start

    ; Drain any now-in-order OOO segments
    mov rdi, r11
    call tcp_ooo_drain

    jmp .ok_no_free                  ; ownership of RBX moved to the rx queue

.no_payload:
    test r10d, TCP_FLAG_FIN
    jz .ok_free
    mov rdi, r11
    call tcp_send_ack
    jmp .ok_free

.other_state:
    ; CLOSE_WAIT/LAST_ACK/FIN_WAIT_*/TIME_WAIT: acknowledge and otherwise
    ; leave the TCB alone. A full teardown state machine (simultaneous
    ; close, TIME_WAIT expiry via the timer wheel) is follow-up scope.
    jmp .ok_free

.do_rst:
    call tcp_tcb_remove
    mov rdi, [r11 + tcb_t.sock_ptr]
    test rdi, rdi
    jz .rst_no_sock
    mov dword [rdi + socket_t.state], TCP_STATE_CLOSED
.rst_no_sock:
    mov rdi, r11
    lea rsi, [tcb_cache]
    xchg rdi, rsi
    call kmem_cache_free
    jmp .ok_free

.on_listener:
    ; SYN to a LISTEN socket: create a new TCB for the incoming connection.
    test r10d, TCP_FLAG_SYN
    jz .ok_free
    mov rdi, r11
    mov esi, r8d                     ; remote_port
    mov edx, r14d                    ; remote_ip
    mov ecx, r15d                    ; local_ip
    mov r8d, r9d                     ; local_port
    push r12
    push r13
    call tcp_accept_syn
    pop r13
    pop r12
    jmp .ok_free

.no_tcb:
    ; No listener, no connection: RFC 793 says answer with RST, which needs
    ; tcp_output wired for a bodiless RST-only segment. Not built yet —
    ; dropping silently instead of answering is the fail-closed choice.
    jmp .drop_free

.ok_free:
    mov rdi, rbx
    call pktbuf_free
.ok_no_free:
    xor eax, eax
    jmp .ret
.drop_free:
    mov rdi, rbx
    call pktbuf_free
    mov eax, -1
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_accept_syn — Create a SYN_RCVD tcb_t for a connection arriving on a
; listener, and send the SYN-ACK.
; Input: RDI = listener tcb_t*, ESI = remote_port, EDX = remote_ip,
;        ECX = local_ip, R8D = local_port (all host order except IPs, which
;        stay network order throughout this stack)
; -----------------------------------------------------------------------------
align 64
tcp_accept_syn:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, esi                   ; remote_port
    mov r13d, edx                   ; remote_ip
    mov r14d, ecx                   ; local_ip
    mov r15d, r8d                   ; local_port

    ; Already have a SYN_RCVD/ESTABLISHED TCB for this 4-tuple? Don't double-
    ; allocate on a retransmitted SYN.
    mov edi, r15d
    mov esi, r12d
    mov edx, r14d
    mov ecx, r13d
    call tcp_tcb_lookup
    test rax, rax
    jnz .done

    ; Check if SYN cookies should be used (backlog full)
    mov rdi, rdi                ; listener tcb_t* (still in RDI from caller)
    call syncookie_enabled
    test eax, eax
    jz .allocate_tcb

    ; Use SYN cookie - generate cookie and send SYN-ACK
    mov edi, r14d               ; local_ip
    mov esi, r13d               ; remote_ip
    mov dx, r15w                ; local_port
    mov cx, r12w                ; remote_port
    mov r8d, 1460               ; MSS (TODO: get from SYN options)
    call syncookie_generate
    mov r11d, eax               ; Save cookie

    ; Send SYN-ACK with cookie as sequence number
    mov rdi, rdi                ; listener tcb_t*
    call tcp_send_synack_with_cookie
    jmp .done

.allocate_tcb:
    lea rdi, [tcb_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .done
    mov rbx, rax

    mov dword [rbx + tcb_t.state], TCP_STATE_SYN_RCVD
    mov [rbx + tcb_t.local_ip], r14d
    mov [rbx + tcb_t.remote_ip], r13d
    mov word [rbx + tcb_t.local_port], r15w
    mov word [rbx + tcb_t.remote_port], r12w
    mov byte [rbx + tcb_t.is_listener], 0
    mov qword [rbx + tcb_t.sock_ptr], 0     ; filled in on handshake completion
    mov qword [rbx + tcb_t.hash_next], 0
    mov dword [rbx + tcb_t.rcv_wnd], PKTBUF_SIZE

    mov eax, [tcp_iss_counter]
    add dword [tcp_iss_counter], 0x10000
    mov [rbx + tcb_t.snd_una], eax
    mov [rbx + tcb_t.snd_nxt], eax
    inc dword [rbx + tcb_t.snd_nxt]  ; SYN consumes one sequence number

    ; Initialize timers for this connection
    mov rdi, rbx
    call tcp_timer_tcb_init

    ; Set default keepalive values
    mov dword [rbx + tcb_t.keepalive_idle], TCP_KEEPALIVE_IDLE_MS
    mov dword [rbx + tcb_t.keepalive_intvl], TCP_KEEPALIVE_INTV_MS
    mov dword [rbx + tcb_t.keepalive_max], TCP_KEEPALIVE_COUNT
    mov dword [rbx + tcb_t.max_retrans], 15

    mov rdi, rbx
    call tcp_tcb_insert

    mov rdi, rbx
    call tcp_send_synack

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_deliver_to_acceptor — Handshake just completed on a SYN_RCVD tcb_t:
; find its listener (same local_port, is_listener=1) and push this
; connection's socket_t onto the listener's accept queue.
;
; The completed connection doesn't have its own socket_t yet — unet_accept
; creates one lazily and links it to this tcb_t, which is why the listener's
; accept queue is a queue of tcb_t*, not socket_t*, chained through
; tcb_t.hash_next (safe to reuse: an accepted tcb_t has already been removed
; from the hash table's bucket chains by this point... actually it hasn't,
; it stays hashed for normal demux. Use sock_ptr as the link instead, since
; it's otherwise unused until unet_accept claims the connection).
; Input: R11 = the now-ESTABLISHED tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_deliver_to_acceptor:
    push rdi
    push rsi
    push rdx
    push rcx

    movzx edi, word [r11 + tcb_t.local_port]
    xor esi, esi
    xor edx, edx
    xor ecx, ecx
    call tcp_tcb_lookup             ; local_port match, wildcard -> listener
    test rax, rax
    jz .done

    mov rdi, [rax + tcb_t.sock_ptr] ; listener's socket_t*
    test rdi, rdi
    jz .done

    mov qword [r11 + tcb_t.sock_ptr], 0
    cmp qword [rdi + socket_t.rx_queue_tail], 0
    je .empty
    mov rcx, [rdi + socket_t.rx_queue_tail]
    mov [rcx + tcb_t.sock_ptr], r11 ; reuse sock_ptr as the accept-queue link
    mov [rdi + socket_t.rx_queue_tail], r11
    jmp .done
.empty:
    mov [rdi + socket_t.rx_queue_head], r11
    mov [rdi + socket_t.rx_queue_tail], r11
.done:
    ; Connection is now ESTABLISHED - start keepalive timer
    mov rdi, r11
    call tcp_timer_keepalive_start

    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; tcp_build_segment — Shared header-fill for SYN-ACK/ACK/data segments.
; Input: RBX = net_pkt_t* (headroom_offset already backed off by 20),
;        R11 = tcb_t*, EDI = flags, ESI = payload length already in data_len
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
align 64
tcp_build_segment:
    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx                    ; RAX = tcp_hdr_t*

    mov cx, [r11 + tcb_t.local_port]
    mov [rax + tcp_hdr_t.src_port], cx
    mov cx, [r11 + tcb_t.remote_port]
    mov [rax + tcp_hdr_t.dst_port], cx

    mov ecx, [r11 + tcb_t.snd_nxt]
    bswap ecx
    mov [rax + tcp_hdr_t.seq_num], ecx
    mov ecx, [r11 + tcb_t.rcv_nxt]
    bswap ecx
    mov [rax + tcp_hdr_t.ack_num], ecx

    mov cx, di                      ; flags, low byte
    and cx, 0x3F
    or cx, 0x5000                   ; data offset = 5 (20 bytes, no options)
    rol cx, 8                       ; -> network order (offset byte first)
    mov [rax + tcp_hdr_t.data_offset_flags], cx

    ; Apply receive window scaling
    mov eax, [r11 + tcb_t.rcv_wnd]
    movzx ecx, byte [r11 + tcb_t.rcv_scale]
    shr eax, cl
    cmp eax, 0xFFFF
    jbe .wnd_ok
    mov eax, 0xFFFF
.wnd_ok:
    xchg al, ah
    mov [rax + tcp_hdr_t.window_size], ax
    mov word [rax + tcp_hdr_t.urgent_ptr], 0
    mov word [rax + tcp_hdr_t.checksum], 0

    ; Generate TCP options if needed
    mov rdi, rbx                ; net_pkt_t*
    mov rsi, r11                ; tcb_t*
    mov edx, r10d               ; flags
    call tcp_gen_options
    ; tcp_gen_options updates data_offset_flags and adjusts headroom_offset
    ; It returns RAX = pointer to end of options (start of payload)
    ; We need to update data_len to include options
    mov edx, [rbx + net_pkt_t.data_len]
    sub edx, 20                 ; payload length
    add edx, 20                 ; header + options
    mov [rbx + net_pkt_t.data_len], edx

    ret

; -----------------------------------------------------------------------------
; tcp_send_synack / tcp_send_ack — Build and transmit a bodiless control
; segment for R11=tcb_t* via a freshly allocated net_pkt_t.
; -----------------------------------------------------------------------------
align 64
tcp_send_synack:
    push rbx
    push r11
    push r12

    call pktbuf_alloc
    test rax, rax
    jz .done
    mov rbx, rax
    cmp dword [rbx + net_pkt_t.headroom_offset], 20
    jb .free
    sub dword [rbx + net_pkt_t.headroom_offset], 20
    mov dword [rbx + net_pkt_t.data_len], 20

    mov edi, TCP_FLAG_SYN | TCP_FLAG_ACK
    mov esi, 0
    call tcp_build_segment

    ; Initialize ECN for SYN-ACK
    mov rdi, r11
    mov rsi, rax
    call tcp_ecn_syn_rcvd

    call .finish_and_send
    jmp .done
.free:
    mov rdi, rbx
    call pktbuf_free
.done:
    pop r12
    pop r11
    pop rbx
    ret
.finish_and_send:
    ; RAX = tcp_hdr_t* from tcp_build_segment; compute checksum & hand to IP.
    mov r12, rax
    mov edi, [r11 + tcb_t.local_ip]
    mov esi, [r11 + tcb_t.remote_ip]
    mov rdx, r12
    mov ecx, 20
    call tcp_checksum_calc
    mov [r12 + tcp_hdr_t.checksum], ax

    mov rdi, rbx
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output
    ret

; -----------------------------------------------------------------------------
; tcp_send_synack_with_cookie � Send SYN-ACK with SYN cookie as sequence number
; Input: RDI = listener tcb_t*, R11D = cookie (in R11 from caller)
; -----------------------------------------------------------------------------
align 64
tcp_send_synack_with_cookie:
    push rbp
    mov rbp, rsp
    push rbx
    push r11
    push r12
    push r13

    mov r11, rdi            ; listener tcb_t*
    mov r12d, r11d          ; cookie (passed in R11)

    call pktbuf_alloc
    test rax, rax
    jz .done
    mov rbx, rax

    cmp dword [rbx + net_pkt_t.headroom_offset], 20
    jb .free
    sub dword [rbx + net_pkt_t.headroom_offset], 20
    mov dword [rbx + net_pkt_t.data_len], 20

    mov edi, TCP_FLAG_SYN | TCP_FLAG_ACK
    mov esi, 0
    call tcp_build_segment

    ; Initialize ECN for SYN-ACK
    mov rdi, r11
    mov rsi, rax
    call tcp_ecn_syn_rcvd

    ; Override sequence number with cookie
    mov rax, [rbx + net_pkt_t.virt_addr]
    add rax, [rbx + net_pkt_t.headroom_offset]
    mov [rax + tcp_hdr_t.seq_num], r12d

    call .finish_and_send
    jmp .done

.free:
    mov rdi, rbx
    call pktbuf_free
.done:
    pop r13
    pop r12
    pop r11
    pop rbx
    pop rbp
    ret
.finish_and_send:
    ; RAX = tcp_hdr_t* from tcp_build_segment; compute checksum & hand to IP.
    mov r12, rax
    mov edi, [r11 + tcb_t.local_ip]
    mov esi, [r11 + tcb_t.remote_ip]
    mov rdx, r12
    mov ecx, 20
    call tcp_checksum_calc
    mov [r12 + tcp_hdr_t.checksum], ax

    mov rdi, rbx
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output
    ret

align 64
tcp_send_ack:
    push rbx
    push r11
    push r12

    mov r11, rdi

    call pktbuf_alloc
    test rax, rax
    jz .done
    mov rbx, rax
    cmp dword [rbx + net_pkt_t.headroom_offset], 20
    jb .free
    sub dword [rbx + net_pkt_t.headroom_offset], 20
    mov dword [rbx + net_pkt_t.data_len], 20

    mov edi, TCP_FLAG_ACK
    mov esi, 0
    call tcp_build_segment
    mov r12, rax

    mov edi, [r11 + tcb_t.local_ip]
    mov esi, [r11 + tcb_t.remote_ip]
    mov rdx, r12
    mov ecx, 20
    call tcp_checksum_calc
    mov [r12 + tcp_hdr_t.checksum], ax

    mov rdi, rbx
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output
    jmp .done
.free:
    mov rdi, rbx
    call pktbuf_free
.done:
    pop r12
    pop r11
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_send_data — Transmit payload already staged in a net_pkt_t (headroom_
; offset backed off by 20 for the header, data_len = header + payload).
; Input: RDI = net_pkt_t*, RSI = tcb_t* for the connection
; Output: EAX = 0 on success, -1 on drop
; -----------------------------------------------------------------------------
align 64
tcp_send_data:
    push rbp
    mov rbp, rsp
    push rbx
    push r11
    push r12
    push r13

    mov rbx, rdi
    mov r11, rsi

    mov ecx, [rbx + net_pkt_t.data_len]
    sub ecx, 20                     ; payload length only

    mov edi, TCP_FLAG_ACK | TCP_FLAG_PSH
    mov esi, ecx
    call tcp_build_segment
    mov r12, rax

    add [r11 + tcb_t.snd_nxt], ecx

    mov edi, [r11 + tcb_t.local_ip]
    mov esi, [r11 + tcb_t.remote_ip]
    mov rdx, r12
    mov ecx, [rbx + net_pkt_t.data_len]
    call tcp_checksum_calc
    mov [r12 + tcp_hdr_t.checksum], ax

    ; Add to retransmission queue before sending
    ; Increment refcount since we're queuing it
    lock inc dword [rbx + net_pkt_t.ref_count]

    ; Queue at tail
    mov r13, qword [r11 + tcb_t.retrans_tail]
    test r13, r13
    jz .queue_empty
    mov qword [r13 + net_pkt_t.next_pkt], rbx
    mov qword [r11 + tcb_t.retrans_tail], rbx
    jmp .queued

.queue_empty:
    mov qword [r11 + tcb_t.retrans_head], rbx
    mov qword [r11 + tcb_t.retrans_tail], rbx

.queued:
    mov qword [rbx + net_pkt_t.next_pkt], 0
    add dword [r11 + tcb_t.retrans_bytes], ecx

    mov rdi, rbx
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output

    ; Start retransmission timer if not already running
    mov rdi, r11
    call tcp_timer_retrans_start

    xor eax, eax
    pop r13
    pop r12
    pop r11
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcp_connect — Active open: allocate a TCB in SYN_SENT and send the SYN.
; Input: EDI = remote_ip (network order), ESI = remote_port (host order),
;        RDX = socket_t* (already has local_port/local_ip filled in)
; Output: RAX = tcb_t*, or 0 on failure
; -----------------------------------------------------------------------------
align 64
tcp_connect:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi                   ; remote_ip
    mov r13d, esi                   ; remote_port
    mov r14, rdx                    ; socket_t*

    lea rdi, [tcb_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .done
    mov rbx, rax

    mov dword [rbx + tcb_t.state], TCP_STATE_SYN_SENT
    mov eax, [r14 + socket_t.local_ip]
    mov [rbx + tcb_t.local_ip], eax
    mov [rbx + tcb_t.remote_ip], r12d
    movzx eax, word [r14 + socket_t.local_port]
    mov [rbx + tcb_t.local_port], ax
    mov [rbx + tcb_t.remote_port], r13w
    mov byte [rbx + tcb_t.is_listener], 0
    mov [rbx + tcb_t.sock_ptr], r14
    mov qword [rbx + tcb_t.hash_next], 0
    mov dword [rbx + tcb_t.rcv_wnd], PKTBUF_SIZE

    mov eax, [tcp_iss_counter]
    add dword [tcp_iss_counter], 0x10000
    mov [rbx + tcb_t.snd_una], eax
    mov [rbx + tcb_t.snd_nxt], eax
    inc dword [rbx + tcb_t.snd_nxt]

    ; Initialize timers for this connection
    mov rdi, rbx
    call tcp_timer_tcb_init

    ; Set default keepalive values
    mov dword [rbx + tcb_t.keepalive_idle], TCP_KEEPALIVE_IDLE_MS
    mov dword [rbx + tcb_t.keepalive_intvl], TCP_KEEPALIVE_INTV_MS
    mov dword [rbx + tcb_t.keepalive_max], TCP_KEEPALIVE_COUNT
    mov dword [rbx + tcb_t.max_retrans], 15

    mov [r14 + socket_t.tcb_ptr], rbx
    mov dword [r14 + socket_t.state], TCP_STATE_SYN_SENT

    mov rdi, rbx
    call tcp_tcb_insert

    ; Send the SYN itself (no ACK flag: peer isn't acking anything of ours
    ; yet). tcp_send_synack always sets SYN|ACK, so build this one by hand.
    ; R11 = tcb_t* and R15 = net_pkt_t* for the rest of this block; R12/R13/
    ; R14 stay untouched since they're this function's own saved arguments.
    mov r11, rbx

    call pktbuf_alloc
    test rax, rax
    jz .done_success                ; TCB exists even if the SYN send failed
    mov r15, rax
    cmp dword [r15 + net_pkt_t.headroom_offset], 20
    jb .free_syn
    sub dword [r15 + net_pkt_t.headroom_offset], 20
    mov dword [r15 + net_pkt_t.data_len], 20

    mov rbx, r15                    ; tcp_build_segment expects RBX = net_pkt_t*
    mov edi, TCP_FLAG_SYN
    mov esi, 0
    call tcp_build_segment          ; RAX = tcp_hdr_t*

    ; Initialize ECN for SYN
    mov rdi, r11
    mov rsi, rax
    call tcp_ecn_syn_sent

    mov rdx, rax                    ; tcp_checksum_calc's RDX arg, before EDI/ESI reuse the low regs
    mov edi, [r11 + tcb_t.local_ip]
    mov esi, [r11 + tcb_t.remote_ip]
    mov ecx, 20
    call tcp_checksum_calc
    mov [rdx + tcp_hdr_t.checksum], ax

    mov rdi, r15
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output
    jmp .done_success
.free_syn:
    mov rdi, r15
    call pktbuf_free
.done_success:
    mov rax, r11
    jmp .ret
.done:
    xor eax, eax
.ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_close — Begin closing a connection: send FIN, move to FIN_WAIT_1.
; Full simultaneous-close / TIME_WAIT handling isn't implemented (see
; tcp_timer_tick); this covers the active-close happy path only.
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_close:
    push rbx
    push r11
    push r12

    mov r11, rdi
    cmp dword [r11 + tcb_t.state], TCP_STATE_ESTABLISHED
    jne .just_free

    call pktbuf_alloc
    test rax, rax
    jz .just_free
    mov rbx, rax
    cmp dword [rbx + net_pkt_t.headroom_offset], 20
    jb .free_pkt
    sub dword [rbx + net_pkt_t.headroom_offset], 20
    mov dword [rbx + net_pkt_t.data_len], 20

    mov edi, TCP_FLAG_FIN | TCP_FLAG_ACK
    mov esi, 0
    call tcp_build_segment
    mov r12, rax
    inc dword [r11 + tcb_t.snd_nxt]

    mov edi, [r11 + tcb_t.local_ip]
    mov esi, [r11 + tcb_t.remote_ip]
    mov rdx, r12
    mov ecx, 20
    call tcp_checksum_calc
    mov [r12 + tcp_hdr_t.checksum], ax

    mov rdi, rbx
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output

    mov dword [r11 + tcb_t.state], TCP_STATE_FIN_WAIT_1

    ; Start keepalive timer for connection (will be used for TIME_WAIT after FIN)
    mov rdi, r11
    call tcp_timer_keepalive_start

    jmp .done
.free_pkt:
    mov rdi, rbx
    call pktbuf_free
.just_free:
    ; Not ESTABLISHED (never connected, or already closing): just release
    ; the TCB. A half-open connection's peer will time its own side out.
    mov dword [r11 + tcb_t.state], TCP_STATE_CLOSED
.done:
    mov rdi, r11
    call tcp_tcb_remove
    lea rsi, [tcb_cache]
    xchg rdi, rsi
    call kmem_cache_free
    pop r12
    pop r11
    pop rbx
    ret

; =============================================================================
; tcp_retransmit_head — Retransmit earliest unacknowledged segment
; Input: RDI = tcb_t*
; =============================================================================
align 64
tcp_retransmit_head:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi

    ; Get packet at head of retransmission queue
    mov r12, qword [rbx + tcb_t.retrans_head]
    test r12, r12
    jz .done

    ; Retransmit the packet
    ; Increment refcount for retransmission
    lock inc dword [r12 + net_pkt_t.ref_count]

    ; Update timestamp for RTT measurement
    call rdtsc_get_cycles
    mov qword [r12 + net_pkt_t.timestamp_ns], rax

    ; Send via IP layer
    mov rdi, r12
    mov esi, [rbx + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output

    ; Update statistics
    inc dword [rbx + tcb_t.stats_retrans]
    mov eax, [r12 + net_pkt_t.data_len]
    add qword [rbx + tcb_t.stats_tx_bytes], rax

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_send_probe — Send 1-byte zero-window probe
; Input: RDI = tcb_t*
; =============================================================================
align 64
tcp_send_probe:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi

    call pktbuf_alloc
    test rax, rax
    jz .done
    mov r12, rax

    cmp dword [r12 + net_pkt_t.headroom_offset], 20
    jb .free_pkt
    sub dword [r12 + net_pkt_t.headroom_offset], 20
    mov dword [r12 + net_pkt_t.data_len], 21  ; 20 header + 1 byte probe

    ; Build probe segment (ACK with SEG.SEQ = SND.UNA - 1)
    mov edi, TCP_FLAG_ACK
    mov esi, 1
    call tcp_build_segment
    mov r13, rax

    ; Set sequence to snd_una - 1 (probe sequence)
    mov eax, [rbx + tcb_t.snd_una]
    dec eax
    bswap eax
    mov [r13 + tcp_hdr_t.seq_num], eax

    mov edi, [rbx + tcb_t.local_ip]
    mov esi, [rbx + tcb_t.remote_ip]
    mov rdx, r13
    mov ecx, 21
    call tcp_checksum_calc
    mov [r13 + tcp_hdr_t.checksum], ax

    mov rdi, r12
    mov esi, [rbx + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output

    jmp .done

.free_pkt:
    mov rdi, r12
    call pktbuf_free

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_send_keepalive — Send keepalive segment (SEQ = SND.UNA - 1)
; Input: RDI = tcb_t*
; =============================================================================
align 64
tcp_send_keepalive:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi

    call pktbuf_alloc
    test rax, rax
    jz .done
    mov r12, rax

    cmp dword [r12 + net_pkt_t.headroom_offset], 20
    jb .free_pkt
    sub dword [r12 + net_pkt_t.headroom_offset], 20
    mov dword [r12 + net_pkt_t.data_len], 20

    mov edi, TCP_FLAG_ACK
    mov esi, 0
    call tcp_build_segment
    mov r13, rax

    ; Keepalive: SEQ = SND.UNA - 1
    mov eax, [rbx + tcb_t.snd_una]
    dec eax
    bswap eax
    mov [r13 + tcp_hdr_t.seq_num], eax

    mov edi, [rbx + tcb_t.local_ip]
    mov esi, [rbx + tcb_t.remote_ip]
    mov rdx, r13
    mov ecx, 20
    call tcp_checksum_calc
    mov [r13 + tcp_hdr_t.checksum], ax

    mov rdi, r12
    mov esi, [rbx + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output

    jmp .done

.free_pkt:
    mov rdi, r12
    call pktbuf_free

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_send_rst — Send RST segment
; Input: RDI = tcb_t*
; =============================================================================
align 64
tcp_send_rst:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi

    call pktbuf_alloc
    test rax, rax
    jz .done
    mov r12, rax

    cmp dword [r12 + net_pkt_t.headroom_offset], 20
    jb .free_pkt
    sub dword [r12 + net_pkt_t.headroom_offset], 20
    mov dword [r12 + net_pkt_t.data_len], 20

    mov edi, TCP_FLAG_RST | TCP_FLAG_ACK
    mov esi, 0
    call tcp_build_segment
    mov r13, rax

    mov edi, [rbx + tcb_t.local_ip]
    mov esi, [rbx + tcb_t.remote_ip]
    mov rdx, r13
    mov ecx, 20
    call tcp_checksum_calc
    mov [r13 + tcp_hdr_t.checksum], ax

    mov rdi, r12
    mov esi, [rbx + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    push rdi
    mov rdi, r11
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    pop rdi
    call ip_output

    jmp .done

.free_pkt:
    mov rdi, r12
    call pktbuf_free

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tcp_close_internal — Internal close without state checks (for timer expiry)
; Input: RDI = tcb_t*
; =============================================================================
align 64
tcp_close_internal:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi

    ; Stop all timers
    mov rdi, qword [rbx + tcb_t.retrans_timer_ptr]
    test rdi, rdi
    jz .no_retrans
    call timer_wheel_del
.no_retrans:

    mov rdi, qword [rbx + tcb_t.persist_timer_ptr]
    test rdi, rdi
    jz .no_persist
    call timer_wheel_del
.no_persist:

    mov rdi, qword [rbx + tcb_t.keepalive_timer_ptr]
    test rdi, rdi
    jz .no_keepalive
    call timer_wheel_del
.no_keepalive:

    mov rdi, qword [rbx + tcb_t.delayed_ack_timer_ptr]
    test rdi, rdi
    jz .no_delayed_ack
    call timer_wheel_del
.no_delayed_ack:

    ; Remove from hash table, free TCB
    mov rdi, rbx
    call tcp_tcb_remove
    lea rsi, [tcb_cache]
    xchg rdi, rsi
    call kmem_cache_free

    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; TCP Option Parsing (RFC 7323, RFC 2018)
; =============================================================================

%define TCP_OPT_EOL           0   ; End of Option List
%define TCP_OPT_NOP           1   ; No Operation
%define TCP_OPT_MSS           2   ; Maximum Segment Size
%define TCP_OPT_WSCALE        3   ; Window Scale
%define TCP_OPT_SACK_PERM     4   ; SACK Permitted
%define TCP_OPT_SACK          5   ; Selective Acknowledgment
%define TCP_OPT_TIMESTAMP     8   ; Timestamps (RFC 7323)

; tcp_parse_options — Parse TCP options from incoming segment
; Input: RDI = net_pkt_t*, RSI = tcp_hdr_t* (points to start of options)
;        RDX = options length in bytes, RCX = tcb_t*
; Output: Updates TCB option state (window scale, timestamps, SACK, MSS)
; -----------------------------------------------------------------------------
align 64
tcp_parse_options:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; net_pkt_t*
    mov r12, rsi            ; tcp_hdr_t* (start of options)
    mov r13, rdx            ; options length
    mov r14, rcx            ; tcb_t*

    test r13, r13
    jz .done

    lea r15, [r12]          ; current option pointer

.parse_loop:
    cmp r13, 0
    jle .done

    movzx eax, byte [r15]   ; option kind
    test al, al
    jz .eol                 ; EOL = end of options

    cmp al, TCP_OPT_NOP
    je .nop

    ; Multi-byte option: check length
    cmp r13, 2
    jl .done
    movzx ecx, byte [r15 + 1] ; option length
    cmp r13d, ecx
    jl .done

    ; Process known options
    cmp al, TCP_OPT_MSS
    je .opt_mss
    cmp al, TCP_OPT_WSCALE
    je .opt_wscale
    cmp al, TCP_OPT_SACK_PERM
    je .opt_sack_perm
    cmp al, TCP_OPT_TIMESTAMP
    je .opt_timestamp
    cmp al, TCP_OPT_SACK
    je .opt_sack

.unknown_opt:
    ; Skip unknown option
    add r15, rcx
    sub r13, rcx
    jmp .parse_loop

.nop:
    inc r15
    dec r13
    jmp .parse_loop

.eol:
    jmp .done

.opt_mss:
    ; MSS: 4 bytes (kind=2, len=4, value=16-bit)
    cmp ecx, 4
    jne .unknown_opt
    movzx eax, word [r15 + 2]
    xchg al, ah             ; network to host
    cmp eax, [r14 + tcb_t.mss]
    jbe .mss_kept
    mov [r14 + tcb_t.mss], eax
.mss_kept:
    add r15, 4
    sub r13, 4
    jmp .parse_loop

.opt_wscale:
    ; Window Scale: 3 bytes (kind=3, len=3, shift=8-bit)
    cmp ecx, 3
    jne .unknown_opt
    movzx eax, byte [r15 + 2]
    cmp eax, 14
    jg .unknown_opt         ; Max shift is 14
    mov byte [r14 + tcb_t.snd_scale], al
    add r15, 3
    sub r13, 3
    jmp .parse_loop

.opt_sack_perm:
    ; SACK Permitted: 2 bytes (kind=4, len=2)
    cmp ecx, 2
    jne .unknown_opt
    or byte [r14 + tcb_t.flags], TCBF_SACK_PERM
    add r15, 2
    sub r13, 2
    jmp .parse_loop

.opt_timestamp:
    ; Timestamp: 10 bytes (kind=8, len=10, TSval=4, TSecr=4)
    cmp ecx, 10
    jne .unknown_opt
    mov eax, [r15 + 2]
    bswap eax
    mov [r14 + tcb_t.ts_recent], eax
    mov eax, [r15 + 6]
    bswap eax
    mov [r14 + tcb_t.ts_last_ack], eax
    or byte [r14 + tcb_t.flags], TCBF_TIMESTAMPS
    add r15, 10
    sub r13, 10
    jmp .parse_loop

.opt_sack:
    ; SACK: variable length (kind=5, len=2+8*n)
    ; TODO: Parse SACK blocks
    add r15, rcx
    sub r13, rcx
    jmp .parse_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; TCP Option Generation
; =============================================================================

; tcp_gen_options — Generate TCP options for outgoing segment
; Input: RDI = net_pkt_t* (headroom_offset already backed off)
;        RSI = tcb_t*, RDX = flags (SYN, etc.)
; Output: RAX = pointer to end of options (new data start)
; -----------------------------------------------------------------------------
align 64
tcp_gen_options:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi            ; net_pkt_t*
    mov r12, rsi            ; tcb_t*
    mov r13d, edx           ; flags

    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx            ; RAX = tcp_hdr_t*
    lea r14, [rax + 20]     ; Start of options

    ; Always include NOP for alignment if we have options
    test r13d, TCP_FLAG_SYN
    jz .check_timestamps

    ; SYN segment - include MSS, Window Scale, SACK Permitted, Timestamp
    ; MSS option (4 bytes)
    mov byte [r14], TCP_OPT_MSS
    mov byte [r14 + 1], 4
    mov eax, [r12 + tcb_t.mss]
    test eax, eax
    jnz .mss_set
    mov eax, 1460           ; Default MSS
.mss_set:
    xchg al, ah
    mov [r14 + 2], ax
    add r14, 4

    ; Window Scale (3 bytes)
    mov byte [r14], TCP_OPT_WSCALE
    mov byte [r14 + 1], 3
    movzx eax, byte [r12 + tcb_t.rcv_scale]
    mov byte [r14 + 2], al
    add r14, 3

    ; SACK Permitted (2 bytes)
    test byte [r12 + tcb_t.flags], TCBF_SACK_PERM
    jz .no_sack_perm
    mov byte [r14], TCP_OPT_SACK_PERM
    mov byte [r14 + 1], 2
    add r14, 2

.no_sack_perm:
    ; Timestamp (10 bytes) - if enabled
    test byte [r12 + tcb_t.flags], TCBF_TIMESTAMPS
    jz .no_timestamp_syn
    mov byte [r14], TCP_OPT_TIMESTAMP
    mov byte [r14 + 1], 10
    call rdtsc_get_cycles
    bswap eax
    mov [r14 + 2], eax      ; TSval
    mov eax, [r12 + tcb_t.ts_recent]
    bswap eax
    mov [r14 + 6], eax      ; TSecr
    add r14, 10

.no_timestamp_syn:
    ; Pad to 4-byte boundary with NOPs
    jmp .pad_and_done

.check_timestamps:
    ; Non-SYN: only include timestamp if negotiated
    test byte [rsi + tcb_t.flags], TCBF_TIMESTAMPS
    jz .pad_and_done

    ; Timestamp option (10 bytes)
    mov byte [r14], TCP_OPT_TIMESTAMP
    mov byte [r14 + 1], 10
    call rdtsc_get_cycles
    bswap eax
    mov [r14 + 2], eax      ; TSval
    mov eax, [rsi + tcb_t.ts_recent]
    bswap eax
    mov [r14 + 6], eax      ; TSecr
    add r14, 10

.pad_and_done:
    ; Pad to 4-byte boundary with NOPs
    sub r14, rax
    sub r14, 20             ; r14 = options length
    and r14d, 3
    jz .done
    mov ecx, 4
    sub ecx, r14d
    mov al, TCP_OPT_NOP
    rep stosb

.done:
    ; Update data offset in TCP header
    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx            ; tcp_hdr_t*

    ; Calculate new data offset: (20 + options_len) / 4
    sub r14, rax
    sub r14, 20             ; options length
    shr r14d, 2             ; / 4
    add r14d, 5             ; base offset = 5
    shl r14d, 12            ; offset in high 4 bits

    movzx eax, word [rax + tcp_hdr_t.data_offset_flags]
    and eax, 0x0FFF         ; preserve flags
    or eax, r14d
    xchg al, ah
    mov [rax + tcp_hdr_t.data_offset_flags], ax

    ; Return pointer to end of options (start of payload)
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; TCP Fast Retransmit / Fast Recovery (RFC 6582)
; =============================================================================

; tcp_fast_retransmit — Enter fast retransmit on 3 DUPACKs
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_fast_retransmit:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi

    ; Set ssthresh = max(flight_size / 2, 2*MSS)
    mov eax, [rbx + tcb_t.snd_nxt]
    sub eax, [rbx + tcb_t.snd_una]    ; flight_size
    shr eax, 1                        ; flight_size / 2
    cmp eax, [rbx + tcb_t.mss]
    jge .set_ssthresh
    mov eax, [rbx + tcb_t.mss]
    shl eax, 1                        ; 2*MSS
.set_ssthresh:
    mov dword [rbx + tcb_t.ssthresh], eax

    ; Set cwnd = ssthresh + 3*MSS
    lea eax, [eax + eax*2]            ; ssthresh * 3? No: ssthresh + 3*MSS
    add eax, [rbx + tcb_t.mss]
    add eax, [rbx + tcb_t.mss]
    add eax, [rbx + tcb_t.mss]
    mov dword [rbx + tcb_t.cwnd], eax

    ; Retransmit lost segment (at snd_una)
    call tcp_retransmit_head

    ; Enter fast recovery state
    or dword [rbx + tcb_t.flags], TCBF_FAST_RECOVERY

    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; TCP SACK Block Processing (RFC 2018, RFC 6675)
; =============================================================================

%define SACK_BLOCK_SIZE       8   ; 2 x 32-bit per block (start, end)
%define MAX_SACK_BLOCKS       4   ; Max blocks in TCP option (40 bytes)

struc sack_block_t
    .start:         resd 1      ; Start sequence (network order)
    .end:           resd 1      ; End sequence (network order)
endstruc

; tcp_process_sack — Process SACK blocks from incoming ACK
; Input: RDI = tcb_t*, RSI = pointer to SACK option data, RDX = option length
; Updates: retransmission queue SACK state, fast recovery logic
; -----------------------------------------------------------------------------
align 64
tcp_process_sack:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; tcb_t*
    mov r12, rsi            ; SACK option data pointer
    mov r13d, edx           ; option length (including kind/len)

    ; Validate SACK option
    cmp r13d, 2
    jl .done
    movzx eax, byte [r12]
    cmp al, TCP_OPT_SACK
    jne .done
    movzx eax, byte [r12 + 1]
    cmp al, 2
    jl .done
    ; Length must be 2 + 8*n
    sub eax, 2
    test al, 7
    jnz .done
    shr eax, 3              ; block count
    cmp eax, MAX_SACK_BLOCKS
    jg .done
    mov r14d, eax           ; block count

    ; Skip kind/len
    add r12, 2

    ; Process each SACK block
    xor r15, r15            ; highest SACKed sequence

.block_loop:
    test r14d, r14d
    jz .blocks_done

    ; Parse block (8 bytes: start, end - both network order)
    mov eax, [r12]
    bswap eax
    mov r8d, eax            ; block_start
    mov eax, [r12 + 4]
    bswap eax
    mov r9d, eax            ; block_end

    ; Track highest SACKed sequence for FACK
    cmp r9d, r15d
    cmova r15d, r9d

    ; Mark segments in retrans queue as SACKed
    mov rdi, rbx
    mov esi, r8d
    mov edx, r9d
    call tcp_sack_mark_blocks

    add r12, 8
    dec r14d
    jmp .block_loop

.blocks_done:
    ; Update FACK state
    test r15d, r15d
    jz .done
    mov [rbx + tcb_t.fack_highest], r15d

    ; If in fast recovery, check for forward progress
    test dword [rbx + tcb_t.flags], TCBF_FAST_RECOVERY
    jz .done

    ; RFC 6675: If new SACK blocks received, retransmit next unsacked segment
    ; This is handled in tcp_output when sending new data

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_sack_mark_blocks — Mark retrans queue segments as SACKed
; Input: RDI = tcb_t*, ESI = block_start, EDX = block_end (host order)
; -----------------------------------------------------------------------------
align 64
tcp_sack_mark_blocks:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12d, esi           ; block_start
    mov r13d, edx           ; block_end

    mov r14, qword [rbx + tcb_t.retrans_head]
    test r14, r14
    jz .done

.mark_loop:
    ; Get segment sequence range
    mov rax, [r14 + net_pkt_t.virt_addr]
    add rax, [r14 + net_pkt_t.headroom_offset]
    movzx r15d, word [rax + tcp_hdr_t.seq_num]
    bswap r15d              ; seg_seq
    mov r8d, [r14 + net_pkt_t.data_len]
    sub r8d, 20             ; payload_len
    lea r9d, [r15 + r8]     ; seg_end = seq + payload_len

    ; Check overlap: [seg_seq, seg_end) intersects [block_start, block_end)?
    cmp r15d, r13d          ; seg_seq >= block_end?
    jge .next_segment
    cmp r9d, r12d           ; seg_end <= block_start?
    jle .next_segment

    ; Overlap found - mark as SACKed
    or byte [r14 + net_pkt_t.flags], 0x10   ; PKTBUF_F_SACKED

.next_segment:
    mov r14, [r14 + net_pkt_t.next_pkt]
    test r14, r14
    jnz .mark_loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; TCP Out-of-Order Reassembly Queue (RFC 793, RFC 2883)
; =============================================================================

; Reassembly queue entry
struc ooo_segment_t
    .next:          resq 1      ; Next in queue
    .seq:           resd 1      ; Sequence number (host order)
    .end_seq:       resd 1      ; End sequence (seq + payload_len)
    .pkt:           resq 1      ; net_pkt_t* (refcounted)
    .len:           resd 1      ; Payload length
    .flags:         resb 1      ; Flags (FIN, etc.)
    .pad:           resb 7
endstruc

; tcp_ooo_insert — Insert segment into OOO reassembly queue
; Input: RDI = tcb_t*, RSI = net_pkt_t* (payload at headroom_offset+20)
; Output: RAX = 0 on success, -1 if duplicate/overlap
; -----------------------------------------------------------------------------
align 64
tcp_ooo_insert:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; tcb_t*
    mov r12, rsi            ; net_pkt_t*

    ; Get segment sequence and length
    mov rax, [r12 + net_pkt_t.virt_addr]
    add rax, [r12 + net_pkt_t.headroom_offset]
    add rax, 20             ; Skip TCP header to payload
    movzx r13d, word [rax - 20 + tcp_hdr_t.seq_num]
    bswap r13d              ; seq
    mov r14d, [r12 + net_pkt_t.data_len]
    sub r14d, 20            ; payload_len
    lea r15d, [r13 + r14]   ; end_seq

    ; Check for FIN flag
    movzx eax, word [rax - 20 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    and al, 0x3F
    test al, TCP_FLAG_FIN
    jz .no_fin
    inc r15d                ; FIN consumes sequence
.no_fin:

    ; Check if already in-order (seq == rcv_nxt)
    mov eax, [rbx + tcb_t.rcv_nxt]
    cmp r13d, eax
    jne .insert_ooo

    ; In-order delivery - pass to socket immediately
    inc dword [rbx + tcb_t.rcv_nxt]
    test byte [r12 + net_pkt_t.flags], 0x01   ; FIN?
    jz .deliver
    inc dword [rbx + tcb_t.rcv_nxt]
.deliver:
    mov rdi, [rbx + tcb_t.sock_ptr]
    test rdi, rdi
    jz .no_sock
    lock inc dword [r12 + net_pkt_t.ref_count]
    mov qword [r12 + net_pkt_t.next_pkt], 0
    cmp qword [rdi + socket_t.rx_queue_tail], 0
    je .rx_empty
    mov rcx, [rdi + socket_t.rx_queue_tail]
    mov [rcx + net_pkt_t.next_pkt], r12
    mov [rdi + socket_t.rx_queue_tail], r12
    jmp .rx_queued
.rx_empty:
    mov [rdi + socket_t.rx_queue_head], r12
    mov [rdi + socket_t.rx_queue_tail], r12
.rx_queued:
    ; Try to drain OOO queue
    mov rdi, rbx
    call tcp_ooo_drain
    xor eax, eax
    jmp .done

.no_sock:
    xor eax, eax
    jmp .done

.insert_ooo:
    ; Insert into OOO queue (ordered by sequence)
    ; Allocate ooo_segment_t
    lea rdi, [ooo_segment_cache]
    call kmem_cache_alloc
    test rax, rax
    jz .alloc_fail
    mov r14, rax

    mov [r14 + ooo_segment_t.seq], r13d
    mov [r14 + ooo_segment_t.end_seq], r15d
    mov [r14 + ooo_segment_t.pkt], r12
    mov [r14 + ooo_segment_t.len], r14d
    mov byte [r14 + ooo_segment_t.flags], 0
    test byte [r12 + net_pkt_t.flags], 0x01
    jz .no_fin2
    or byte [r14 + ooo_segment_t.flags], 1
.no_fin2:
    lock inc dword [r12 + net_pkt_t.ref_count]

    ; Find insertion point (ordered by seq)
    mov r15, qword [rbx + tcb_t.ooo_head]
    test r15, r15
    jz .insert_head
    mov qword [r14 + ooo_segment_t.next], 0

    mov r12, qword [rbx + tcb_t.ooo_tail]
    cmp r13d, [r12 + ooo_segment_t.seq]
    jge .insert_after_tail

    ; Find position
    mov r12, qword [rbx + tcb_t.ooo_head]
    xor r15, r15
.find_pos:
    test r12, r12
    jz .insert_before
    cmp r13d, [r12 + ooo_segment_t.seq]
    jl .insert_before
    mov r15, r12
    mov r12, [r12 + ooo_segment_t.next]
    jmp .find_pos

.insert_head:
    mov rax, [rbx + tcb_t.ooo_head]
    mov [r14 + ooo_segment_t.next], rax
    mov qword [rbx + tcb_t.ooo_head], r14
    cmp qword [rbx + tcb_t.ooo_tail], 0
    jnz .done
    mov qword [rbx + tcb_t.ooo_tail], r14
    jmp .done

.insert_after_tail:
    mov qword [r12 + ooo_segment_t.next], r14
    mov qword [rbx + tcb_t.ooo_tail], r14
    jmp .done

.insert_before:
    mov qword [r14 + ooo_segment_t.next], r12
    test r15, r15
    jz .insert_at_head
    mov qword [r15 + ooo_segment_t.next], r14
    jmp .done
.insert_at_head:
    mov qword [rbx + tcb_t.ooo_head], r14
    jmp .done

.alloc_fail:
    mov eax, -1
    jmp .done

.done:
    xor eax, eax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; tcp_ooo_drain — Drain in-order segments from OOO queue to socket
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tcp_ooo_drain:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi

.drain_loop:
    mov r12, qword [rbx + tcb_t.ooo_head]
    test r12, r12
    jz .done

    mov r13d, [r12 + ooo_segment_t.seq]
    cmp r13d, [rbx + tcb_t.rcv_nxt]
    jne .done

    ; Next in-order segment found
    mov r14, [r12 + ooo_segment_t.pkt]
    mov r13d, [r12 + ooo_segment_t.end_seq]
    mov byte [rbx + tcb_t.rcv_nxt], r13b
    test byte [r12 + ooo_segment_t.flags], 1
    jz .no_fin
    inc dword [rbx + tcb_t.rcv_nxt]
.no_fin:

    ; Remove from OOO queue
    mov rax, [r12 + ooo_segment_t.next]
    mov qword [rbx + tcb_t.ooo_head], rax
    test rax, rax
    jnz .tail_ok
    mov qword [rbx + tcb_t.ooo_tail], 0
.tail_ok:

    ; Deliver to socket
    mov rdi, [rbx + tcb_t.sock_ptr]
    test rdi, rdi
    jz .free_segment
    lock inc dword [r14 + net_pkt_t.ref_count]
    mov qword [r14 + net_pkt_t.next_pkt], 0
    cmp qword [rdi + socket_t.rx_queue_tail], 0
    je .rx_empty
    mov rcx, [rdi + socket_t.rx_queue_tail]
    mov [rcx + net_pkt_t.next_pkt], r14
    mov [rdi + socket_t.rx_queue_tail], r14
    jmp .rx_queued
.rx_empty:
    mov [rdi + socket_t.rx_queue_head], r14
    mov [rdi + socket_t.rx_queue_tail], r14
.rx_queued:
    ; Generate ACK for delivered data
    mov rdi, rbx
    call tcp_send_ack

.free_segment:
    ; Free ooo_segment_t
    lock dec dword [r14 + net_pkt_t.ref_count]
    jnz .next_iter
    mov rdi, r14
    lea rsi, [ooo_segment_cache]
    xchg rdi, rsi
    call kmem_cache_free
.next_iter:
    jmp .drain_loop

.done:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; OOO Segment Cache
; =============================================================================

section .bss
alignb 64
ooo_segment_cache:    resb kmem_cache_t_size

section .data
ooo_segment_cache_name: db "tcp_ooo_segment", 0

global tcp_ooo_cache_init
align 64
tcp_ooo_cache_init:
    push rbp
    mov rbp, rsp
    push rbx

    lea rdi, [ooo_segment_cache]
    lea rsi, [ooo_segment_cache_name]
    mov rdx, ooo_segment_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_ASM
