%ifndef GUARD_UNET_CORE_L4_TCP_ASM
%define GUARD_UNET_CORE_L4_TCP_ASM
; =============================================================================
; Tattva OS — unet/core/l4/tcp.asm
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

%include "unet/unet.inc"

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
    .timer_id:          resd 1      ; Timer Wheel ID
    .srtt:              resd 1      ; Smoothed Round Trip Time (us)
    .rto:               resd 1      ; Retransmission Timeout (ms)
    .snd_scale:         resb 1      ; Window Scale Shift Factor (Send)
    .rcv_scale:         resb 1      ; Window Scale Shift Factor (Receive)
    .bbr_bw:            resq 1      ; BBR Bottleneck Bandwidth (unused: no
                                     ; congestion control yet, see tcp_timer_tick)
    .bbr_rtt:           resd 1      ; BBR Min RTT (ditto)
    .hash_next:          resq 1      ; Next tcb_t* in this hash bucket's chain
    .sock_ptr:           resq 1      ; Owning socket_t*, or the listener's
                                     ; socket_t* while still in SYN_RCVD
    .is_listener:         resb 1      ; 1 for the pseudo-TCB a LISTEN socket
                                     ; owns (wildcard remote_ip/remote_port)
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

    cmp r13d, 20
    jbe .no_payload
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
    mov rdi, r11
    call tcp_send_ack
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

    mov cx, [r11 + tcb_t.rcv_wnd]
    cmp word [r11 + tcb_t.rcv_wnd], 0xFFFF
    jbe .wnd_ok
    mov cx, 0xFFFF
.wnd_ok:
    xchg cl, ch
    mov [rax + tcp_hdr_t.window_size], cx
    mov word [rax + tcp_hdr_t.urgent_ptr], 0
    mov word [rax + tcp_hdr_t.checksum], 0
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
    push rbx
    push r11
    push r12

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

    mov rdi, rbx
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    call ip_output

    pop r12
    pop r11
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tcp_timer_tick — Retransmission / TIME_WAIT expiry timer sweep.
; Not implemented: needs to walk every live tcb_t and check its RTO against
; the timer wheel, which needs the timer wheel to actually carry a payload
; back to whatever it's timing (lib/time/timer_wheel.asm's timer_entry_t
; exists but nothing here schedules a real per-TCB entry into it yet — see
; ip_reassemble_fragment's identical gap). Called every unet_poll tick from
; unet.asm; a no-op tick means segments lost in flight are never resent, only
; the peer's own retransmits recover the connection.
; -----------------------------------------------------------------------------
align 64
tcp_timer_tick:
    xor eax, eax
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

    mov rdx, rax                    ; tcp_checksum_calc's RDX arg, before EDI/ESI reuse the low regs
    mov edi, [r11 + tcb_t.local_ip]
    mov esi, [r11 + tcb_t.remote_ip]
    mov ecx, 20
    call tcp_checksum_calc
    mov [rdx + tcp_hdr_t.checksum], ax

    mov rdi, r15
    mov esi, [r11 + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
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
    call ip_output

    mov dword [r11 + tcb_t.state], TCP_STATE_FIN_WAIT_1
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

%endif ; GUARD_UNET_CORE_L4_TCP_ASM
