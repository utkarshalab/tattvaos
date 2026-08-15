%ifndef GUARD_UNET_CORE_SYS_UNET_API_ASM
%define GUARD_UNET_CORE_SYS_UNET_API_ASM
; =============================================================================
; Tattva OS — unet/core/sys/unet_api.asm
; =============================================================================
; POSIX-shaped BSD socket API — the actual bodies behind unet_c_api.h's
; unet_socket/bind/connect/listen/accept/send/recv/close. Before this file,
; every one of those was declared in the C header and implemented nowhere:
; nothing outside unet/ had any way to actually use the stack.
;
; What's deliberately NOT here: this is a single-threaded, cooperatively-
; scheduled kernel (kernel/sched/fiber.asm) with no blocking/wakeup wiring
; into the socket layer yet, so connect()/accept()/recv() are non-blocking
; only — they return immediately with "not ready" rather than putting the
; calling fiber to sleep until data/a connection arrives. A caller that wants
; blocking behavior has to poll in a loop with fiber_yield, the same pattern
; kernel/entry/main.asm's heartbeat_fiber already uses for pacing.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define UNET_EPHEMERAL_PORT_BASE     49152
%define UNET_EPHEMERAL_PORT_MAX      65535

; Matches the layout callers build for unet_bind/unet_connect's `addr`
; parameter — this stack's own ABI for that opaque pointer, not the kernel
; POSIX layout: family and port are host order at the call boundary (this
; is a C-callable API, not wire data), everything gets converted to network
; order internally where the protocol layers need it.
struc unet_sockaddr_in
    .family:            resw 1      ; AF_INET
    .port:               resw 1      ; host order
    .addr:                resd 1      ; network order (already a raw IPv4 u32)
    .zero:                resb 8
endstruc

section .bss
alignb 4
unet_ephemeral_next: resd 1

section .text

global unet_socket
global unet_bind
global unet_connect
global unet_listen
global unet_accept
global unet_send
global unet_recv
global unet_close

align 64
unet_ephemeral_alloc_init:
    mov dword [unet_ephemeral_next], UNET_EPHEMERAL_PORT_BASE
    ret

; -----------------------------------------------------------------------------
; unet_socket — int unet_socket(int domain, int type, int protocol)
; -----------------------------------------------------------------------------
align 64
unet_socket:
    cmp dword [unet_ephemeral_next], 0
    jne .have_init
    call unet_ephemeral_alloc_init
.have_init:
    jmp socket_create

; -----------------------------------------------------------------------------
; unet_bind — int unet_bind(int sockfd, const void *addr, uint32_t addrlen)
; -----------------------------------------------------------------------------
align 64
unet_bind:
    push rbx
    push r12

    mov r12, rsi                    ; R12 = unet_sockaddr_in*
    cmp edx, unet_sockaddr_in_size
    jb .fail

    call socket_lookup
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = socket_t*

    movzx eax, word [r12 + unet_sockaddr_in.port]
    mov [rbx + socket_t.local_port], ax
    mov eax, [r12 + unet_sockaddr_in.addr]
    mov [rbx + socket_t.local_ip], eax

    cmp dword [rbx + socket_t.sock_type], UNET_SOCK_DGRAM
    jne .done

    movzx edi, word [rbx + socket_t.local_port]
    mov rsi, rbx
    call udp_bind
    test eax, eax
    jnz .fail
.done:
    xor eax, eax
    jmp .ret
.fail:
    mov eax, -1
.ret:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unet_connect — int unet_connect(int sockfd, const void *addr, uint32_t addrlen)
; UDP: just records the peer, no packets sent. TCP: sends the SYN and
; returns immediately (SYN_SENT) — see this file's header comment on
; blocking. A caller needs to unet_recv-poll (or check state, once something
; exposes it) until the handshake completes.
; -----------------------------------------------------------------------------
align 64
unet_connect:
    push rbx
    push r12
    push r13

    mov r12, rsi
    cmp edx, unet_sockaddr_in_size
    jb .fail

    call socket_lookup
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = socket_t*

    cmp word [rbx + socket_t.local_port], 0
    jne .have_local_port
    mov eax, [unet_ephemeral_next]
    mov [rbx + socket_t.local_port], ax
    inc dword [unet_ephemeral_next]
    cmp dword [unet_ephemeral_next], UNET_EPHEMERAL_PORT_MAX
    jbe .have_local_port
    mov dword [unet_ephemeral_next], UNET_EPHEMERAL_PORT_BASE
.have_local_port:
    cmp dword [rbx + socket_t.local_ip], 0
    jne .have_local_ip
    mov eax, [unet_local_ip]
    mov [rbx + socket_t.local_ip], eax
.have_local_ip:

    movzx r13d, word [r12 + unet_sockaddr_in.port]
    mov eax, [r12 + unet_sockaddr_in.addr]
    mov [rbx + socket_t.remote_ip], eax
    mov [rbx + socket_t.remote_port], r13w

    cmp dword [rbx + socket_t.sock_type], UNET_SOCK_DGRAM
    jne .tcp

    movzx edi, word [rbx + socket_t.local_port]
    mov rsi, rbx
    call udp_bind
    mov dword [rbx + socket_t.state], TCP_STATE_ESTABLISHED  ; "connected" UDP
    jmp .ok

.tcp:
    mov edi, eax                    ; remote_ip (network order)
    mov esi, r13d                   ; remote_port (host order)
    mov rdx, rbx                    ; socket_t*
    call tcp_connect
    test rax, rax
    jz .fail
.ok:
    xor eax, eax
    jmp .ret
.fail:
    mov eax, -1
.ret:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unet_listen — int unet_listen(int sockfd, int backlog)
; backlog is accepted but not enforced as a hard cap — the accept queue is an
; unbounded intrusive list (see tcp_deliver_to_acceptor), not a fixed ring.
; -----------------------------------------------------------------------------
align 64
unet_listen:
    push rbx

    call socket_lookup
    test rax, rax
    jz .fail
    mov rbx, rax
    cmp word [rbx + socket_t.local_port], 0
    je .fail

    movzx edi, word [rbx + socket_t.local_port]
    mov rsi, rbx
    call tcp_listen
    test eax, eax
    jnz .fail

    xor eax, eax
    jmp .ret
.fail:
    mov eax, -1
.ret:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unet_accept — int unet_accept(int sockfd, void *addr, uint32_t *addrlen)
; Non-blocking: returns -1 immediately if no handshake has completed yet.
; addr/addrlen are accepted for API compatibility but not filled in — a
; caller that needs the peer's address today has to read it back off the fd
; some other way (nothing exposes socket_t fields to callers yet).
; -----------------------------------------------------------------------------
align 64
unet_accept:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                    ; addr out (unused, see above)
    mov r13, rdx                    ; addrlen* out (unused, see above)

    call socket_lookup
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = listener socket_t*

    mov r14, [rbx + socket_t.rx_queue_head]
    test r14, r14
    jz .fail                        ; nothing pending

    ; Pop one tcb_t off the accept queue (chained via tcb_t.sock_ptr — see
    ; tcp_deliver_to_acceptor's comment on why that field is reused here).
    mov rcx, [r14 + tcb_t.sock_ptr]
    mov [rbx + socket_t.rx_queue_head], rcx
    test rcx, rcx
    jnz .not_last
    mov qword [rbx + socket_t.rx_queue_tail], 0
.not_last:

    mov edi, AF_INET
    mov esi, UNET_SOCK_STREAM
    xor edx, edx
    call socket_create
    cmp eax, -1
    je .fail
    mov r15d, eax                   ; R15 = new fd

    mov edi, r15d
    call socket_lookup
    test rax, rax
    jz .fail                        ; shouldn't happen: just created above
    mov rbx, rax                    ; RBX = new socket_t*

    mov [rbx + socket_t.tcb_ptr], r14
    mov [r14 + tcb_t.sock_ptr], rbx
    mov eax, [r14 + tcb_t.remote_ip]
    mov [rbx + socket_t.remote_ip], eax
    mov ax, [r14 + tcb_t.remote_port]
    mov [rbx + socket_t.remote_port], ax
    mov eax, [r14 + tcb_t.local_ip]
    mov [rbx + socket_t.local_ip], eax
    mov ax, [r14 + tcb_t.local_port]
    mov [rbx + socket_t.local_port], ax
    mov dword [rbx + socket_t.state], TCP_STATE_ESTABLISHED

    mov eax, r15d
    jmp .ret
.fail:
    mov eax, -1
.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unet_send — int64_t unet_send(int sockfd, const void *buf, size_t len, int flags)
; -----------------------------------------------------------------------------
align 64
unet_send:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rsi                    ; buf
    mov r13, rdx                    ; len

    call socket_lookup
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = socket_t*

    cmp dword [rbx + socket_t.sock_type], UNET_SOCK_DGRAM
    je .udp
    cmp dword [rbx + socket_t.sock_type], UNET_SOCK_STREAM
    je .tcp
    jmp .fail

.udp:
    mov r14d, PKTBUF_HEADROOM
    sub r14d, 8                     ; header space udp_output will reserve
    cmp r13, r14
    jbe .udp_fits
    mov r13, r14                    ; truncate to what one packet can carry —
                                     ; no fragmentation of oversized sends
.udp_fits:
    call pktbuf_alloc
    test rax, rax
    jz .fail
    mov r14, rax                    ; R14 = net_pkt_t*

    mov rdi, [r14 + net_pkt_t.virt_addr]
    mov eax, [r14 + net_pkt_t.headroom_offset]
    add rdi, rax
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb
    mov [r14 + net_pkt_t.data_len], r13d

    movzx esi, word [rbx + socket_t.local_port]
    movzx edx, word [rbx + socket_t.remote_port]
    mov ecx, [rbx + socket_t.remote_ip]
    mov rdi, r14
    call udp_send_pkt
    test eax, eax
    jnz .fail
    mov rax, r13
    jmp .ret

.tcp:
    mov r14d, PKTBUF_HEADROOM
    sub r14d, 20
    cmp r13, r14
    jbe .tcp_fits
    mov r13, r14
.tcp_fits:
    call pktbuf_alloc
    test rax, rax
    jz .fail
    mov r14, rax

    cmp dword [r14 + net_pkt_t.headroom_offset], 20
    jb .tcp_no_room
    sub dword [r14 + net_pkt_t.headroom_offset], 20

    mov rdi, [r14 + net_pkt_t.virt_addr]
    mov eax, [r14 + net_pkt_t.headroom_offset]
    add rdi, rax
    add rdi, 20                     ; past the TCP header space just reserved
    mov rsi, r12
    mov rcx, r13
    cld
    rep movsb

    mov eax, r13d
    add eax, 20
    mov [r14 + net_pkt_t.data_len], eax

    mov rdi, r14
    mov rsi, [rbx + socket_t.tcb_ptr]
    test rsi, rsi
    jz .tcp_no_room
    call tcp_send_data
    mov rax, r13
    jmp .ret
.tcp_no_room:
    mov rdi, r14
    call pktbuf_free
.fail:
    mov rax, -1
.ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unet_recv — int64_t unet_recv(int sockfd, void *buf, size_t len, int flags)
; Non-blocking: returns -1 immediately if the socket's receive queue is
; empty. Whatever's queued is delivered whole or not at all — a datagram/
; segment larger than the caller's buffer is truncated to fit, the rest of
; that one queued net_pkt_t is dropped rather than held for a second read.
; -----------------------------------------------------------------------------
align 64
unet_recv:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rsi                    ; buf
    mov r13, rdx                    ; len

    call socket_lookup
    test rax, rax
    jz .fail
    mov rbx, rax                    ; RBX = socket_t*

    mov r14, [rbx + socket_t.rx_queue_head]
    test r14, r14
    jz .fail

    mov rcx, [r14 + net_pkt_t.next_pkt]
    mov [rbx + socket_t.rx_queue_head], rcx
    test rcx, rcx
    jnz .not_last
    mov qword [rbx + socket_t.rx_queue_tail], 0
.not_last:

    mov eax, [r14 + net_pkt_t.data_len]
    sub eax, [r14 + net_pkt_t.headroom_offset]  ; L4 header + payload

    cmp dword [rbx + socket_t.sock_type], UNET_SOCK_DGRAM
    jne .tcp_hdr
    sub eax, 8
    mov rdx, 8
    jmp .have_hdr_len
.tcp_hdr:
    sub eax, 20
    mov rdx, 20
.have_hdr_len:
    test eax, eax
    jns .len_ok
    xor eax, eax                    ; malformed/short — treat as empty payload
.len_ok:
    mov rsi, r13
    cmp rax, rsi
    jbe .copy_len_ok
    mov rax, rsi                    ; truncate to the caller's buffer
.copy_len_ok:
    mov rsi, [r14 + net_pkt_t.virt_addr]
    add rsi, [r14 + net_pkt_t.headroom_offset]
    add rsi, rdx                    ; past the L4 header
    mov rdi, r12
    mov rcx, rax
    push rax
    cld
    rep movsb
    pop rax

    push rax
    mov rdi, r14
    call pktbuf_free
    pop rax
    jmp .ret
.fail:
    mov rax, -1
.ret:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unet_close — int unet_close(int sockfd)
; Not declared in unet/include/unet_c_api.h historically — added there
; alongside this implementation, since a socket API with no way to close a
; socket isn't usable.
; -----------------------------------------------------------------------------
align 64
unet_close:
    push rbx

    mov ebx, edi
    call socket_lookup
    test rax, rax
    jz .done

    cmp dword [rax + socket_t.sock_type], UNET_SOCK_STREAM
    jne .no_tcp
    mov rdi, [rax + socket_t.tcb_ptr]
    test rdi, rdi
    jz .no_tcp
    call tcp_close
.no_tcp:
    mov edi, ebx
    call socket_close

.done:
    xor eax, eax
    pop rbx
    ret

%endif ; GUARD_UNET_CORE_SYS_UNET_API_ASM
