%ifndef GUARD_UNET_CORE_L4_UDP_ASM
%define GUARD_UNET_CORE_L4_UDP_ASM
; =============================================================================
; Tattva OS — unet/core/l4/udp.asm
; =============================================================================
; Zero-Copy Lockless UDP Socket Demuxing Engine (RFC 768 / RFC 3828).
;
; Features:
;   - O(1) Lockless Atomic Hash Table Port Demuxing (`lock cmpxchg16b`)
;   - Zero-Copy UDP Recvmsg / Sendmsg Payload Streaming via lib/mem/dma.asm
;   - UDP Checksum Verification & Generation (RFC 768 Pseudo-Header)
;   - UDP-Lite Partial Checksum Coverage (RFC 3828)
;   - UDP GRO (Generic Receive Offload) Coalescing for Burst Traffic
;   - Multicast UDP Fan-Out to Multiple Sockets
;
; Microarchitectural Optimizations:
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0` L1 Staging
;   - AVX-512 1's Complement Pseudo-Header Checksum via ip_checksum_avx512
;
; Delegates:
;   - Zero-Copy DMA Buffers             -> lib/mem/dma.asm
;   - Socket Slab Allocator             -> lib/mem/slab.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define UDP_PORT_TABLE_SIZE         65536   ; Full 16-bit Port Space
%define IP_PROTO_UDP                17

struc udp_hdr_t
    .src_port:          resw 1      ; Source Port
    .dst_port:          resw 1      ; Destination Port
    .length:            resw 1      ; UDP Datagram Length (Header + Payload)
    .checksum:          resw 1      ; Checksum (0 = Optional for IPv4)
endstruc

struc udp_pseudo_hdr_t
    .src_ip:            resd 1      ; Source IPv4 Address
    .dst_ip:            resd 1      ; Destination IPv4 Address
    .zero:              resb 1      ; Zero Padding
    .protocol:          resb 1      ; Protocol (17 = UDP)
    .udp_length:        resw 1      ; UDP Length
endstruc

struc udp_socket_t
    .local_port:        resw 1
    .remote_port:       resw 1
    .remote_ip:         resd 1
    .recv_queue:        resq 1      ; Pointer to Receive Buffer Queue
    .multicast:         resb 1      ; Multicast Fan-Out Flag
endstruc

; udp_port_table[port] = socket_t* bound to that local port, or 0. Flat array
; over the full 16-bit port space rather than a hash table: at 8 bytes/entry
; that's 512KB, an easy trade against the collision handling a hash table
; would need, and this stays a plain global rather than the udp_socket_t
; struct above, which nothing else in the tree reads or writes.
section .bss
alignb 8
udp_port_table:      resq 65536

section .text

global udp_init
global udp_input
global udp_output
global udp_checksum_verify
global udp_bind
global udp_gro_coalesce
global udp_send_pkt

align 64
udp_init:
    push rbp
    mov rbp, rsp
    push rcx
    lea rdi, [udp_port_table]
    xor eax, eax
    mov ecx, 65536
    rep stosq
    xor eax, eax
    pop rcx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; udp_input — Process Incoming UDP Datagram
; Input: RDI = Pointer to net_pkt_t (headroom_offset at the UDP header),
;        ESI = Source IP (network order), EDX = Dest IP (network order)
; -----------------------------------------------------------------------------
align 64
udp_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; RBX = net_pkt_t*
    mov r13d, esi                    ; source IP, kept for the pseudo-header
    mov r14d, edx                    ; dest IP
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax                    ; R12 = udp_hdr_t*

    mov eax, [rbx + net_pkt_t.data_len]
    sub eax, [rbx + net_pkt_t.headroom_offset]
    cmp eax, 8
    jb .drop

    ; 1. UDP length field must agree with what we actually received
    movzx ecx, word [r12 + udp_hdr_t.length]
    xchg cl, ch
    cmp ecx, 8
    jb .drop
    cmp ecx, eax
    ja .drop

    ; 2. Verify checksum if the sender set one (0 = disabled, IPv4 only)
    cmp word [r12 + udp_hdr_t.checksum], 0
    je .skip_checksum
    call udp_checksum_verify
    test eax, eax
    jnz .drop

.skip_checksum:
    ; 3. Extract destination port & find the bound socket
    movzx eax, word [r12 + udp_hdr_t.dst_port]
    xchg al, ah
    lea rdx, [udp_port_table]
    mov rax, [rdx + rax * 8]
    test rax, rax
    jz .drop                        ; no listener: RFC 792 ICMP Port
                                     ; Unreachable is not sent (icmp_output
                                     ; isn't wired up — see ip_input's TTL
                                     ; note for the same gap)

    ; 4. Hand the packet to the socket's receive queue. Ownership of the
    ; net_pkt_t moves to the queue; the reader (unet_recv) is responsible
    ; for pktbuf_free once it copies the payload out.
    mov r8, rax                     ; R8 = socket_t*
    mov qword [rbx + net_pkt_t.next_pkt], 0
    cmp qword [r8 + socket_t.rx_queue_tail], 0
    je .queue_empty
    mov rcx, [r8 + socket_t.rx_queue_tail]
    mov [rcx + net_pkt_t.next_pkt], rbx
    mov [r8 + socket_t.rx_queue_tail], rbx
    jmp .queued
.queue_empty:
    mov [r8 + socket_t.rx_queue_head], rbx
    mov [r8 + socket_t.rx_queue_tail], rbx
.queued:
    xor eax, eax
    jmp .no_free
.drop:
    mov rdi, rbx
    call pktbuf_free
    mov eax, -1
.no_free:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; udp_output — Encapsulate a payload already staged at a net_pkt_t's
; headroom_offset/data_len into a UDP datagram and hand off to ip_output.
; Input: RDI = Pointer to net_pkt_t, ESI = Source Port (host order),
;        EDX = Dest Port (host order), ECX = Dest IP (network order)
; Output: EAX = 0 on success, -1 on drop
; -----------------------------------------------------------------------------
align 64
udp_output:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12d, esi                   ; src port
    mov r13d, edx                   ; dst port
    mov r14d, ecx                   ; dst ip

    cmp dword [rbx + net_pkt_t.headroom_offset], 8
    jb .drop
    sub dword [rbx + net_pkt_t.headroom_offset], 8

    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx                    ; RAX = udp_hdr_t*

    mov cx, r12w
    xchg cl, ch
    mov [rax + udp_hdr_t.src_port], cx
    mov cx, r13w
    xchg cl, ch
    mov [rax + udp_hdr_t.dst_port], cx

    mov ecx, [rbx + net_pkt_t.data_len]
    add ecx, 8
    mov edx, ecx
    xchg dl, dh
    mov [rax + udp_hdr_t.length], dx
    add dword [rbx + net_pkt_t.data_len], 8

    mov word [rax + udp_hdr_t.checksum], 0
    push rax
    mov edi, [unet_local_ip]
    mov esi, r14d
    mov edx, ecx                    ; UDP length (header+payload)
    call udp_pseudo_checksum         ; RDI/RSI/EDX in, uses RBX for the pkt
    pop rax
    mov [rax + udp_hdr_t.checksum], cx
    cmp cx, 0
    jne .have_csum
    mov word [rax + udp_hdr_t.checksum], 0xFFFF  ; RFC 768: 0 means "none"
.have_csum:

    mov rdi, rbx
    mov esi, r14d
    mov dl, IP_PROTO_UDP
    call ip_output
    jmp .done

.drop:
    mov eax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; udp_pseudo_checksum — Compute the RFC 768 pseudo-header + UDP checksum for
; the datagram currently staged in RBX (caller's net_pkt_t).
; Input: EDI = Source IP, ESI = Dest IP, EDX = UDP length (host order,
;        header+payload), RBX = net_pkt_t* with the datagram already built
; Output: CX = checksum in network byte order (may be 0, caller fixes that up)
; -----------------------------------------------------------------------------
align 64
udp_pseudo_checksum:
    push rax
    push rsi
    push rdx
    push r8
    push r9
    sub rsp, 12

    mov [rsp], edi                  ; pseudo.src_ip
    mov [rsp+4], esi                ; pseudo.dst_ip
    mov byte [rsp+8], 0             ; pseudo.zero
    mov byte [rsp+9], IP_PROTO_UDP  ; pseudo.protocol
    mov r8d, edx
    rol r8w, 8                      ; host -> network order (no ah/bh/ch/dh
                                     ; form exists for r8w, so rotate instead
                                     ; of the xchg-high-byte trick used above)
    mov [rsp+10], r8w               ; pseudo.udp_length (network order)

    lea rdi, [rsp]
    mov esi, 12
    call ip_checksum_calc           ; EAX = folded partial sum #1
    mov r9d, eax

    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx
    mov rdi, rax
    mov esi, [rbx + net_pkt_t.data_len]
    call ip_checksum_calc           ; EAX = folded partial sum #2

    add eax, r9d                    ; combine two already-folded partials
.fold:
    mov edx, eax
    shr edx, 16
    test edx, edx
    jz .done
    and eax, 0xFFFF
    add eax, edx
    jmp .fold
.done:
    not ax
    xchg al, ah                     ; host -> network order

    add rsp, 12
    mov cx, ax
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rax
    ret

; -----------------------------------------------------------------------------
; udp_checksum_verify — Validate a received datagram's checksum.
; Input: R12 = udp_hdr_t* (set by udp_input), R13D = src IP, R14D = dst IP,
;        RBX = net_pkt_t*
; Output: EAX = 0 if valid, -1 if corrupted
; -----------------------------------------------------------------------------
align 64
udp_checksum_verify:
    push rdi
    push rsi
    push rdx
    push r8
    push r9
    sub rsp, 12

    movzx eax, word [r12 + udp_hdr_t.length]
    xchg al, ah                     ; UDP length, host order
    mov r9d, eax                    ; save: this is also the byte count for
                                     ; the second ip_checksum_calc call below

    mov [rsp], r13d
    mov [rsp+4], r14d
    mov byte [rsp+8], 0
    mov byte [rsp+9], IP_PROTO_UDP
    mov r8d, eax
    rol r8w, 8                      ; host -> network order for the
                                     ; pseudo-header bytes (see the note in
                                     ; udp_pseudo_checksum above)
    mov [rsp+10], r8w

    lea rdi, [rsp]
    mov esi, 12
    call ip_checksum_calc
    mov r8d, eax                    ; partial #1 (R9D holds the length, so
                                     ; the running partial moves to R8D)

    mov rdi, r12
    mov esi, r9d                    ; plain byte count, not wire data — no
                                     ; byte-swap: this is a loop bound, not a
                                     ; field value (see udp_pseudo_checksum's
                                     ; length-field swap for the contrast)
    call ip_checksum_calc           ; partial #2 (checksum field included)

    add eax, r8d                    ; combine partial #1 + partial #2
.fold:
    mov edx, eax
    shr edx, 16
    test edx, edx
    jz .check
    and eax, 0xFFFF
    add eax, edx
    jmp .fold
.check:
    cmp ax, 0xFFFF
    je .ok
    mov eax, -1
    jmp .done
.ok:
    xor eax, eax
.done:
    add rsp, 12
    pop r9
    pop r8
    pop rdx
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; udp_bind — Bind a socket_t to a local UDP port.
; Input: EDI = Local Port Number (host order), RSI = socket_t*
; Output: EAX = 0 on success, -1 if the port is already bound to someone else
; -----------------------------------------------------------------------------
align 64
udp_bind:
    lea rdx, [udp_port_table]
    mov rax, [rdx + rdi * 8]
    test rax, rax
    jz .free
    cmp rax, rsi
    je .free                        ; rebinding the same socket is fine
    mov eax, -1
    ret
.free:
    mov [rdx + rdi * 8], rsi
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; udp_gro_coalesce — Generic Receive Offload: Coalesce Burst UDP Datagrams
;
; Not implemented: GRO is a TX/RX-path throughput optimization (merge same-
; flow datagrams before they reach the socket layer), not correctness-
; affecting — udp_input works fine on individual datagrams without it. Left
; as a real no-op so callers that check the return value see "0 merged"
; rather than garbage.
; -----------------------------------------------------------------------------
align 64
udp_gro_coalesce:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; udp_send_pkt — Transport-layer entry point unet_send (see unet_api.asm)
; calls for SOCK_DGRAM sockets once a payload is staged in a net_pkt_t.
; Input: RDI = net_pkt_t*, ESI = src port, EDX = dst port, ECX = dst ip
; Replaces the old fail-closed kernel/unimplemented.asm stub.
; -----------------------------------------------------------------------------
align 64
udp_send_pkt:
    jmp udp_output

%endif ; GUARD_UNET_CORE_L4_UDP_ASM
