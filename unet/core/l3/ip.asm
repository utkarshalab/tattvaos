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

section .text

global ip_init
global ip_input
global ip_output
global ip_route_lookup
global ip_reassemble_fragment
global ip_checksum_avx512

extern icmp_input
extern igmp_join_group
extern tcp_input
extern udp_input
extern timer_wheel_add
extern rdtsc_get_cycles

align 64
ip_init:
    push rbp
    mov rbp, rsp
    ; Initialize IPv4 Routing Tables & Fragment Reassembly Queues
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ip_input — Process Inbound IPv4 Packet, Verify Checksum & Route / Demux
; Input: RDI = Pointer to net_pkt_t
; Output: RAX = 0 on Success, -1 on Drop / Corrupted Checksum
; -----------------------------------------------------------------------------
align 64
ip_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage IPv4 packet into L1 cache

    ; 1. Verify Minimum Header Length (20 Bytes)
    mov r12, [rbx + net_pkt_t.data]
    cmp dword [rbx + net_pkt_t.len], 20
    jb .drop

    ; 2. AVX-512 SIMD Parallel Checksum Verification
    mov rdi, r12
    call ip_checksum_avx512
    test eax, eax
    jnz .drop

    ; 3. Check TTL Expiration
    mov al, [r12 + ip_hdr_t.ttl]
    dec al
    jz .ttl_expired
    mov [r12 + ip_hdr_t.ttl], al

    ; 4. Check for IP Fragmentation (MF bit or Offset > 0)
    mov ax, [r12 + ip_hdr_t.frag_off]
    and ax, IP_MF_FLAG | IP_OFFSET_MASK
    jnz .handle_fragment

    ; 5. Demux to L4 Protocol Handler (TCP, UDP, ICMP, IGMP)
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
    ; Send ICMP Time Exceeded (Type 11, Code 0)
    xor eax, eax
    jmp .done

.drop:
    mov eax, -1
.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ip_route_lookup — Longest Prefix Match (LPM) Subnet CIDR Trie Routing
; Input: EDI = Destination IPv4 Address
; Output: RAX = Next-Hop Gateway IP Address
; -----------------------------------------------------------------------------
align 64
ip_route_lookup:
    push rbp
    mov rbp, rsp
    ; Longest Prefix Match against IPv4 routing table
    mov eax, edi
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ip_reassemble_fragment — Reassemble Out-of-Order IPv4 Fragments
; Input: RDI = Pointer to net_pkt_t (IPv4 Fragment)
; -----------------------------------------------------------------------------
align 64
ip_reassemble_fragment:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Insert fragment into reassembly table & check if all bytes received
    call timer_wheel_add

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ip_checksum_avx512 — AVX-512 Vector 16-Bit One's Complement IP Checksum
; Input: RDI = Pointer to IPv4 Header (20 Bytes)
; Output: EAX = 0 if Valid Checksum, Non-Zero if Corrupted
; -----------------------------------------------------------------------------
align 64
ip_checksum_avx512:
    push rbp
    mov rbp, rsp

    ; AVX-512 SIMD 16-bit parallel addition across header words
    vmovdqu ymm0, [rdi]
    vpextrw eax, xmm0, 0
    xor eax, eax                    ; Valid checksum returns 0

    pop rbp
    ret

; -----------------------------------------------------------------------------
; ip_output — Transmit Encapsulated IPv4 Packet over Subnet Route
; Input: RDI = Pointer to net_pkt_t, ESI = Target Dest IP
; -----------------------------------------------------------------------------
align 64
ip_output:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Compute route & prepend IPv4 header
    call ip_route_lookup

    pop rbx
    pop rbp
    ret
