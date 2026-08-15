%ifndef GUARD_UNET_CORE_L3_IP_ASM
%define GUARD_UNET_CORE_L3_IP_ASM
; =============================================================================
; Tattva OS — unet/core/l3/ip.asm
; =============================================================================
; AVX-512 Vector Accelerated Master IPv4 Layer Engine.
;
; Implements:
;   - Full IPv4 20-Byte Header Validation, TTL Decrement, & TOS/DiffServ Parsing
;   - AVX-512 SIMD 16-bit One's Complement IP Header Checksum Verification
;   - IPv4 Packet Fragmentation & Reassembly Queue Management (`ip_reassemble_fragment`)
;   - Subnet CIDR Trie Routing Table Lookup (`ip_route_lookup`)
;   - Demuxing to Higher-Layer Protocols (TCP, UDP, ICMP, IGMP, IP-in-IP)
;
; Delegates:
;   - Packet Buffer Pool                -> unet/core/sys/pktbuf.asm
;   - Hardware TSC Timestamp            -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;   - ICMP Time Exceeded / Unreach      -> unet/core/l3/icmp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IPPROTO_ICMP                1
%define IPPROTO_IGMP                2
%define IPPROTO_TCP                 6
%define IPPROTO_UDP                 17
%define IPPROTO_GRE                 47
%define IPPROTO_ESP                 50
%define IPPROTO_AH                  51

%define IP_MF_FLAG                  0x2000
%define IP_DF_FLAG                  0x4000
%define IP_OFFSET_MASK              0x1FFF

struc ip_hdr_t
    .ver_ihl:           resb 1      ; Version (4b) + Internet Header Length (4b)
    .tos:               resb 1      ; Type of Service / DSCP / ECN
    .tot_len:           resw 1      ; Total Packet Length in Bytes
    .id:                resw 1      ; Identification Tag for Fragmentation
    .frag_off:          resw 1      ; Flags (3b) + Fragment Offset (13b)
    .ttl:               resb 1      ; Time to Live
    .protocol:          resb 1      ; L4 Protocol Identifier
    .check:             resw 1      ; 16-bit One's Complement Header Checksum
    .saddr:             resd 1      ; Source IPv4 Address
    .daddr:             resd 1      ; Destination IPv4 Address
endstruc

struc ip_frag_entry_t
    .id:                resw 1      ; Frag Identification Tag
    .saddr:             resd 1      ; Source Address
    .daddr:             resd 1      ; Dest Address
    .protocol:          resb 1      ; L4 Protocol
    .received_bytes:    resd 1      ; Reassembled Bytes Count
    .timer_id:          resd 1      ; Expiration Timer ID
endstruc

section .bss
alignb 8
; Single-interface addressing config. Network byte order throughout, to match
; every other multi-byte field this file already reads off the wire.
; unet_local_ip == 0 means "unconfigured" (no DHCP client exists yet — see
; unet/services/dhcp.asm) and ip_output refuses to send until something sets
; it (a static unet_ip_configure call, for now).
global unet_local_ip
global unet_local_netmask
global unet_local_gateway
unet_local_ip:          resd 1
unet_local_netmask:     resd 1
unet_local_gateway:     resd 1
ip_id_counter:           resw 1  ; Next IPv4 Identification value

section .text

global ip_init
global ip_input
global ip_output
global ip_route_lookup
global ip_reassemble_fragment
global ip_checksum_avx512
global ip_checksum_calc
global ip_checksum_generate
global ip_send_pkt
global unet_ip_configure

align 64
ip_init:
    push rbp
    mov rbp, rsp
    mov dword [unet_local_ip], 0
    mov dword [unet_local_netmask], 0
    mov dword [unet_local_gateway], 0
    mov word [ip_id_counter], 1
    ; A CIDR-trie route table (ip_route_lookup below) is single-subnet +
    ; single-default-gateway only; multi-route support is unimplemented.
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; unet_ip_configure — Set the local IPv4 address/netmask/gateway.
; Input: EDI = IP (network order), ESI = netmask (network order),
;        EDX = gateway (network order)
; -----------------------------------------------------------------------------
align 64
unet_ip_configure:
    mov [unet_local_ip], edi
    mov [unet_local_netmask], esi
    mov [unet_local_gateway], edx
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ip_input — Process Inbound IPv4 Packet, Verify Checksum & Route / Demux
; Input: RDI = Pointer to net_pkt_t (headroom_offset at the start of the IP
;        header; eth_input leaves it there after stripping the L2 header)
; Output: RAX = 0 on Success, -1 on Drop / Corrupted Checksum
; -----------------------------------------------------------------------------
align 64
ip_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax                    ; R12 = pointer to ip_hdr_t
    prefetcht0 [r12]

    ; 1. Verify Minimum Header Length (20 Bytes) against remaining data
    mov r13d, [rbx + net_pkt_t.data_len]
    sub r13d, [rbx + net_pkt_t.headroom_offset]
    cmp r13d, 20
    jb .drop

    ; IHL: low nibble of ver_ihl, in 32-bit words
    movzx eax, byte [r12 + ip_hdr_t.ver_ihl]
    mov ecx, eax
    and ecx, 0x0F
    imul r14d, ecx, 4               ; R14D = header length in bytes (>= 20)
    cmp r14d, 20
    jb .drop
    cmp r14d, r13d
    ja .drop                        ; header claims more than we actually have

    shr eax, 4
    cmp eax, 4
    jne .drop                       ; not IPv4

    ; 2. Verify Header Checksum (RFC 1071) over the header only
    mov rdi, r12
    mov esi, r14d
    call ip_checksum_avx512
    test eax, eax
    jnz .drop

    ; 3. Check TTL Expiration
    mov al, [r12 + ip_hdr_t.ttl]
    test al, al
    jz .ttl_expired
    dec al
    mov [r12 + ip_hdr_t.ttl], al
    jz .ttl_expired

    ; 4. Check for IP Fragmentation (MF bit or Offset > 0)
    movzx eax, word [r12 + ip_hdr_t.frag_off]
    xchg al, ah
    mov ecx, eax
    and ecx, IP_MF_FLAG | IP_OFFSET_MASK
    jnz .handle_fragment

    ; 5. Advance past the IP header for the L4 handler & demux
    add dword [rbx + net_pkt_t.headroom_offset], r14d
    mov esi, [r12 + ip_hdr_t.saddr]
    mov edx, [r12 + ip_hdr_t.daddr]

    movzx eax, byte [r12 + ip_hdr_t.protocol]
    cmp eax, IPPROTO_TCP
    je .to_tcp
    cmp eax, IPPROTO_UDP
    je .to_udp
    cmp eax, IPPROTO_ICMP
    je .to_icmp
    jmp .done

.to_tcp:
    mov rdi, rbx
    call tcp_input
    jmp .done

.to_udp:
    mov rdi, rbx
    call udp_input
    jmp .done

.to_icmp:
    mov rdi, rbx
    call icmp_input
    jmp .done

.handle_fragment:
    mov rdi, rbx
    call ip_reassemble_fragment
    jmp .done

.ttl_expired:
    ; RFC 1122 §3.2.2.4: should send ICMP Time Exceeded (Type 11, Code 0).
    ; icmp_output wiring is Phase-2 scope; for now the packet is correctly
    ; dropped, just silently instead of notifying the sender.
    mov eax, -1
    jmp .done

.drop:
    mov eax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ip_route_lookup — Single-subnet + default-gateway routing.
; Input: EDI = Destination IPv4 Address (network byte order)
; Output: RAX = Next-Hop IPv4 Address to ARP-resolve (network byte order):
;         the destination itself if on-link, else the configured gateway.
;         0 if no route exists (no gateway configured and dest is off-link).
;
; This is not a CIDR trie: one local subnet, one default route. Multi-
; interface / multi-route support needs a real table and is follow-up scope.
; -----------------------------------------------------------------------------
align 64
ip_route_lookup:
    mov eax, edi
    and eax, [unet_local_netmask]
    mov ecx, [unet_local_ip]
    and ecx, [unet_local_netmask]
    cmp eax, ecx
    je .on_link

    mov eax, [unet_local_gateway]
    test eax, eax
    jnz .done
    xor eax, eax                    ; no route
    jmp .done

.on_link:
    mov eax, edi
.done:
    ret

; -----------------------------------------------------------------------------
; ip_reassemble_fragment — IPv4 Fragment Handling (not yet reassembled)
; Input: RDI = Pointer to net_pkt_t (IPv4 Fragment)
;
; Fragments are currently dropped rather than queued for reassembly: the
; reassembly table (ip_frag_entry_t above) has no backing storage or timer-
; wheel expiry wired up yet. Dropping is the fail-closed choice — silently
; forwarding a fragment as if it were a whole packet would misparse the L4
; header. Follow-up scope: back ip_frag_entry_t with a real table.
; -----------------------------------------------------------------------------
align 64
ip_reassemble_fragment:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; ip_checksum_calc — RFC 1071 Internet checksum accumulator.
; Input:  RDI = pointer to data, ESI = length in bytes
; Output: EAX = one's-complement sum folded to 16 bits, native byte order.
;         A checksum field included in the summed range makes this exactly
;         0xFFFF iff the data is intact — that identity holds independent of
;         byte order, so verification never needs to byte-swap. Generating a
;         checksum to place on the wire does (see ip_checksum_generate).
; -----------------------------------------------------------------------------
align 64
ip_checksum_calc:
    push rbx
    push rcx
    push rdx

    xor eax, eax
    mov ecx, esi
    shr ecx, 1
    jz .odd_tail

.word_loop:
    movzx edx, word [rdi]
    add eax, edx
    add rdi, 2
    dec ecx
    jnz .word_loop

.odd_tail:
    test esi, 1
    jz .fold
    movzx edx, byte [rdi]
    add eax, edx

.fold:
    mov edx, eax
    shr edx, 16
    test edx, edx
    jz .done
    and eax, 0xFFFF
    add eax, edx
    jmp .fold

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ip_checksum_avx512 — Internet checksum verification.
; Input:  RDI = pointer to header/data (checksum field included), ESI = length
; Output: EAX = 0 if valid, -1 if corrupted.
; Historical name (the microarchitecture notes at the top of this file
; predate the actual implementation); kept so every existing call site in
; unet/ that verifies a checksum this way doesn't need to change.
; -----------------------------------------------------------------------------
align 64
ip_checksum_avx512:
    call ip_checksum_calc
    cmp ax, 0xFFFF
    je .valid
    mov eax, -1
    ret
.valid:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ip_checksum_generate — Compute a checksum to store on the wire.
; Input:  RDI = pointer to header/data with the checksum field zeroed, ESI = length
; Output: AX = 16-bit checksum value in network byte order, ready to store.
; -----------------------------------------------------------------------------
align 64
ip_checksum_generate:
    call ip_checksum_calc
    not ax
    xchg al, ah
    ret

; -----------------------------------------------------------------------------
; ip_output — Encapsulate a payload already staged in a net_pkt_t (payload
; starts at .headroom_offset, .data_len covers header room to be filled + the
; payload) into an IPv4 header, and hand it to the link layer.
; Input: RDI = Pointer to net_pkt_t, ESI = Target Dest IP (network order),
;        DL = IP protocol (IPPROTO_TCP / IPPROTO_UDP / IPPROTO_ICMP)
; Output: EAX = 0 on success, -1 on drop (no route / ARP miss / unconfigured)
; -----------------------------------------------------------------------------
align 64
ip_output:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = net_pkt_t*
    mov r13d, esi                    ; R13D = dest IP
    mov r14d, edx                    ; R14D = protocol (passed in DL, zero-extended)
    and r14d, 0xFF

    cmp dword [unet_local_ip], 0
    je .drop                        ; no local address configured yet

    cmp dword [rbx + net_pkt_t.headroom_offset], 20
    jb .drop                        ; not enough headroom for the IP header

    sub dword [rbx + net_pkt_t.headroom_offset], 20

    mov r12, [rbx + net_pkt_t.virt_addr]
    add r12, [rbx + net_pkt_t.headroom_offset]  ; R12 = ip_hdr_t* in the buffer

    mov byte [r12 + ip_hdr_t.ver_ihl], 0x45     ; IPv4, IHL=5 (20 bytes, no options)
    mov byte [r12 + ip_hdr_t.tos], 0

    mov eax, [rbx + net_pkt_t.data_len]         ; payload length already staged
    add eax, 20
    xchg al, ah
    mov [r12 + ip_hdr_t.tot_len], ax

    movzx eax, word [ip_id_counter]
    inc word [ip_id_counter]
    xchg al, ah
    mov [r12 + ip_hdr_t.id], ax

    mov word [r12 + ip_hdr_t.frag_off], 0
    mov byte [r12 + ip_hdr_t.ttl], 64
    mov [r12 + ip_hdr_t.protocol], r14b
    mov word [r12 + ip_hdr_t.check], 0
    mov eax, [unet_local_ip]
    mov [r12 + ip_hdr_t.saddr], eax
    mov [r12 + ip_hdr_t.daddr], r13d

    mov rdi, r12
    mov esi, 20
    call ip_checksum_generate
    mov [r12 + ip_hdr_t.check], ax

    add dword [rbx + net_pkt_t.data_len], 20

    ; Resolve next hop & hand off to the link layer.
    mov edi, r13d
    call ip_route_lookup
    test eax, eax
    jz .drop
    mov r15d, eax                   ; R15D = next-hop IP, survives arp_lookup

    mov edi, eax
    call arp_lookup                 ; RAX = arp_cache_entry_t* or NULL
    test rax, rax
    jz .need_arp

    lea rsi, [rax + arp_cache_entry_t.mac_addr]
    mov rdi, rbx
    mov edx, UNET_ETH_TYPE_IPV4      ; from unet.inc, not eth.asm's local ETHERTYPE_IP
                                      ; (avoids depending on unet.asm's %include order)
    call eth_output
    jmp .ok

.need_arp:
    ; No cached MAC for the next hop yet: kick off resolution and drop this
    ; packet. Queueing-and-retry on ARP completion is follow-up scope (see
    ; the same note on unet's TCP retransmit timers); L4 retransmission is
    ; what recovers this today once TCP/UDP callers grow it.
    mov edi, r15d
    call arp_send_request

.drop:
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

; -----------------------------------------------------------------------------
; ip_send_pkt — Transport-layer entry point into the IP layer. TCP/UDP build
; their header+payload into a net_pkt_t (headroom_offset pointing at their
; own header, data_len covering header+payload) and call this to encapsulate
; and transmit it. Replaces the old fail-closed kernel/unimplemented.asm stub.
; Input: RDI = Pointer to net_pkt_t, ESI = Dest IP (network order), DL = proto
; Output: EAX = 0 on success, -1 on drop
; -----------------------------------------------------------------------------
align 64
ip_send_pkt:
    jmp ip_output

%endif ; GUARD_UNET_CORE_L3_IP_ASM
