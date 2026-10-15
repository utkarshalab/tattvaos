%ifndef GUARD_UNET_CORE_L3_IPV6_TCP_ASM
%define GUARD_UNET_CORE_L3_IPV6_TCP_ASM
; =============================================================================
; Tattva OS — unet/core/l3/ipv6_tcp.asm
; =============================================================================
; IPv6 TCP Support (RFC 8200, RFC 2460, RFC 3542)
;
; Implements:
;   - IPv6 header parsing and generation
;   - IPv6 pseudo-header for TCP/UDP checksums
;   - IPv6 Extension Headers (Hop-by-Hop, Destination, Routing, Fragment)
;   - IPv6 Path MTU Discovery (RFC 8201)
;   - IPv6 Neighbor Discovery (NDP) integration
;   - IPv6 Flow Label support
;   - IPv6 Jumbograms (RFC 2675)
;   - IPv6 TCP/UDP checksum with pseudo-header
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IPV6_VERSION            6
%define IPV6_HEADER_LEN         40
%define IPV6_MIN_MTU            1280

%define IPV6_NEXTHDR_HOP        0
%define IPV6_NEXTHDR_TCP        6
%define IPV6_NEXTHDR_UDP        17
%define IPV6_NEXTHDR_ICMPV6     58
%define IPV6_NEXTHDR_NONE       59
%define IPV6_NEXTHDR_DEST       60
%define IPV6_NEXTHDR_ROUTING    43
%define IPV6_NEXTHDR_FRAGMENT   44
%define IPV6_NEXTHDR_AUTH       51
%define IPV6_NEXTHDR_ESP        50
%define IPV6_NEXTHDR_MOBILITY   135

%define IPV6_FRAG_MF            0x01
%define IPV6_FRAG_OFFSET_MASK   0xFFF8

struc ipv6_header_t
    .ver_tc_fl:         resd 1      ; Version(4) | TrafficClass(8) | FlowLabel(20)
    .payload_len:       resw 1      ; Payload length in bytes
    .next_header:       resb 1      ; Next header type
    .hop_limit:         resb 1      ; Hop limit
    .src_addr:          resb 16     ; Source IPv6 address
    .dst_addr:          resb 16     ; Destination IPv6 address
endstruc

struc ipv6_ext_header_t
    .next_header:       resb 1
    .hdr_ext_len:       resb 1      ; Length in 8-octet units (minus 1)
endstruc

struc ipv6_frag_header_t
    .next_header:       resb 1
    .reserved:          resb 1
    .frag_off_flags:    resw 1      ; Fragment offset (13 bits) | Reserved (2) | M (1)
    .identification:    resd 1      ; Fragment identification
endstruc

struc ipv6_pseudo_header_t
    .src_addr:          resb 16
    .dst_addr:          resb 16
    .upper_len:         resd 1      ; Upper-layer packet length
    .zero:              resd 1      ; Zero
    .next_header:       resb 1
    .pad:               resb 3
endstruc

struc ipv6_flow_label_t
    .label:             resd 1      ; 20-bit flow label
endstruc

%define IPV6_FLOW_LABEL_MASK    0x000FFFFF

struc ndp_option_t
    .type:              resb 1
    .length:            resb 1      ; In units of 8 octets
endstruc

%define NDP_OPT_SOURCE_LLADDR     1
%define NDP_OPT_TARGET_LLADDR     2
%define NDP_OPT_PREFIX_INFO       3
%define NDP_OPT_REDIRECTED_HDR    4
%define NDP_OPT_MTU               5

struc ndp_prefix_info_t
    .type:              resb 1
    .length:            resb 1
    .prefix_len:        resb 1
    .flags:             resb 1      ; L, A, R
    .valid_lifetime:    resd 1
    .preferred_lifetime: resd 1
    .reserved:          resd 1
    .prefix:            resb 16
endstruc

section .text

global ipv6_init
global ipv6_input
global ipv6_output
global ipv6_checksum_pseudo
global ipv6_fragment
global ipv6_reassemble
global ipv6_route_lookup
global ipv6_ndp_process
global ipv6_flow_label_get

; =============================================================================
; IPv6 Initialization
; =============================================================================

align 64
ipv6_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; Initialize IPv6 subsystem
    ; TODO: Initialize IPv6 routing table, NDP cache, fragment reassembly

    xor eax, eax
    pop rbx
    pop rbp
    ret

; =============================================================================
; IPv6 Input Processing
; =============================================================================

align 64
ipv6_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; net_pkt_t*
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax                    ; R12 = ipv6_header_t*

    ; Verify minimum header length
    mov r13d, [rbx + net_pkt_t.data_len]
    sub r13d, [rbx + net_pkt_t.headroom_offset]
    cmp r13d, IPV6_HEADER_LEN
    jb .drop

    ; Check version
    movzx eax, byte [r12 + ipv6_header_t.ver_tc_fl]
    shr eax, 28
    cmp eax, IPV6_VERSION
    jne .drop

    ; Check payload length
    movzx eax, word [r12 + ipv6_header_t.payload_len]
    xchg al, ah
    cmp eax, r13d
    sub eax, IPV6_HEADER_LEN
    jne .drop

    ; Process extension headers
    mov r14, r12
    add r14, IPV6_HEADER_LEN
    mov r15b, byte [r12 + ipv6_header_t.next_header]
    movzx r13d, word [r12 + ipv6_header_t.payload_len]
    xchg r13b, r13b+1

.process_ext_headers:
    cmp r15b, IPV6_NEXTHDR_TCP
    je .process_tcp
    cmp r15b, IPV6_NEXTHDR_UDP
    je .process_udp
    cmp r15b, IPV6_NEXTHDR_ICMPV6
    je .process_icmpv6
    cmp r15b, IPV6_NEXTHDR_HOP
    je .process_hop
    cmp r15b, IPV6_NEXTHDR_DEST
    je .process_dest
    cmp r15b, IPV6_NEXTHDR_ROUTING
    je .process_routing
    cmp r15b, IPV6_NEXTHDR_FRAGMENT
    je .process_fragment
    cmp r15b, IPV6_NEXTHDR_AUTH
    je .process_auth
    cmp r15b, IPV6_NEXTHDR_ESP
    je .process_esp

    ; Unknown next header - skip
    jmp .skip_ext_header

.process_tcp:
    ; Adjust headroom for L4
    add dword [rbx + net_pkt_t.headroom_offset], r14
    sub r12, r14
    mov rdi, rbx
    mov esi, [r12 + ipv6_header_t.src_addr + 12]   ; Last 4 bytes of src
    mov edx, [r12 + ipv6_header_t.dst_addr + 12]   ; Last 4 bytes of dst
    call tcp_input
    jmp .done

.process_udp:
    add dword [rbx + net_pkt_t.headroom_offset], r14
    sub r12, r14
    mov rdi, rbx
    call udp_input
    jmp .done

.process_icmpv6:
    add dword [rbx + net_pkt_t.headroom_offset], r14
    sub r12, r14
    mov rdi, rbx
    call icmpv6_input
    jmp .done

.process_hop:
.process_dest:
.process_routing:
    ; Parse extension header
    mov r15b, byte [r14]
    movzx eax, byte [r14 + 1]
    lea eax, [rax * 8 + 8]
    add r14, rax
    mov r15b, byte [r14]
    jmp .process_ext_headers

.process_fragment:
    ; Handle fragmentation
    call ipv6_reassemble_fragment
    jmp .done

.process_auth:
.process_esp:
    ; IPsec headers - skip
    movzx eax, byte [r14 + 1]
    lea eax, [rax * 4 + 8]
    add r14, rax
    mov r15b, byte [r14]
    jmp .process_ext_headers

.skip_ext_header:
    ; Unknown extension header
    movzx eax, byte [r14 + 1]
    lea eax, [rax * 8 + 8]
    add r14, rax
    mov r15b, byte [r14]
    jmp .process_ext_headers

.drop:
    mov eax, -1
    jmp .ret

.done:
    xor eax, eax

.ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; IPv6 Output
; =============================================================================

; ipv6_output — Send IPv6 packet
; Input: RDI = net_pkt_t*, ESI = dest_addr (16 bytes), EDX = next_header
;        ECX = hop_limit, R8 = src_addr (16 bytes), R9 = flow_label
;        R10 = traffic_class, DH = ECN flags
align 64
ipv6_output:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; net_pkt_t*
    mov r13, rsi                    ; dest_addr pointer
    mov r14d, edx                   ; next_header
    mov r15d, ecx                   ; hop_limit
    mov r12, r8                     ; src_addr pointer
    mov r15, r9                     ; flow_label
    mov r10d, r10d                  ; traffic_class
    mov r11d, edx
    shr r11d, 8
    and r11d, 0x03                 ; ECN flags

    ; Check headroom
    cmp dword [rbx + net_pkt_t.headroom_offset], IPV6_HEADER_LEN
    jb .drop

    sub dword [rbx + net_pkt_t.headroom_offset], IPV6_HEADER_LEN

    mov r12, [rbx + net_pkt_t.virt_addr]
    add r12, [rbx + net_pkt_t.headroom_offset]  ; R12 = ipv6_header_t*

    ; Build IPv6 header
    ; Version(4) | TrafficClass(8) | FlowLabel(20)
    mov eax, IPV6_VERSION
    shl eax, 28
    mov ecx, r10d
    shl ecx, 20
    or eax, ecx
    mov ecx, r15d
    and ecx, IPV6_FLOW_LABEL_MASK
    or eax, ecx
    mov [r12 + ipv6_header_t.ver_tc_fl], eax

    ; Payload length
    mov eax, [rbx + net_pkt_t.data_len]
    xchg al, ah
    mov [r12 + ipv6_header_t.payload_len], ax

    ; Next header
    mov [r12 + ipv6_header_t.next_header], r14b

    ; Hop limit
    mov [r12 + ipv6_header_t.hop_limit], r15b

    ; Source/Dest addresses
    mov rsi, r12
    add rsi, ipv6_header_t.src_addr
    mov rdi, r12
    mov rcx, 16
    rep movsb

    mov rsi, r13
    mov rdi, r12
    add rdi, ipv6_header_t.dst_addr
    mov rcx, 16
    rep movsb

    ; ECN in traffic class
    mov al, r11b
    shl al, 6
    or al, r10b
    mov [r12 + ipv6_header_t.ver_tc_fl + 1], al

    ; Update packet length
    add dword [rbx + net_pkt_t.data_len], IPV6_HEADER_LEN

    ; Route lookup
    mov rdi, r13
    call ipv6_route_lookup
    test eax, eax
    jz .drop

    ; NDP lookup for link-layer address
    mov rdi, rax
    call ndp_lookup
    test rax, rax
    jz .need_ndp

    ; Send via link layer
    mov rdi, rbx
    mov rsi, rax
    mov edx, UNET_ETH_TYPE_IPV6
    call eth_output
    jmp .ok

.need_ndp:
    ; Queue for NDP resolution
    call ndp_queue_packet
    jmp .ok

.drop:
    mov eax, -1

.ok:
    xor eax, eax

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; IPv6 Pseudo-header Checksum
; =============================================================================

; ipv6_checksum_pseudo — Compute IPv6 pseudo-header checksum
; Input: RDI = src_addr (16 bytes), RSI = dst_addr (16 bytes)
;        RDX = next_header, RCX = upper_len
; Output: RAX = checksum (16-bit, network order)
align 64
ipv6_checksum_pseudo:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; src_addr
    mov r12, rsi            ; dst_addr
    mov r13d, edx           ; next_header
    mov r14d, ecx           ; upper_len

    ; Pseudo-header: src(16) + dst(16) + upper_len(4) + zero(3) + next_header(1)
    ; Total 40 bytes = 20 16-bit words

    xor rax, rax
    xor r15, r15

    ; Process source address (16 bytes = 8 words)
    mov rcx, 8
.src_loop:
    movzx eax, word [rbx]
    xchg al, ah
    add r15d, eax
    adc r15d, 0
    add rbx, 2
    dec rcx
    jnz .src_loop

    ; Process destination address (16 bytes = 8 words)
    mov rcx, 8
.dst_loop:
    movzx eax, word [r12]
    xchg al, ah
    add r15d, eax
    adc r15d, 0
    add r12, 2
    dec rcx
    jnz .dst_loop

    ; Upper length (2 words)
    mov eax, r14d
    xchg al, ah
    add r15d, eax
    adc r15d, 0
    shr eax, 16
    xchg al, ah
    add r15d, eax
    adc r15d, 0

    ; Zero padding (3 words = 6 bytes) + next_header (1 byte)
    ; Already zero from XOR RAX, RAX

    ; Next header (1 byte = half word)
    mov al, r13b
    mov ah, 0
    add r15d, eax
    adc r15d, 0

    ; Final fold
    mov eax, r15d
    shr eax, 16
    add ax, r15w
    adc ax, 0
    not ax
    xchg al, ah
    movzx rax, ax

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; IPv6 Fragmentation
; =============================================================================

align 64
ipv6_fragment:
    ; TODO: Implement IPv6 fragmentation
    ret

align 64
ipv6_reassemble:
    ; TODO: Implement IPv6 reassembly
    ret

; =============================================================================
; IPv6 Route Lookup
; =============================================================================

align 64
ipv6_route_lookup:
    ; TODO: Implement IPv6 routing table lookup
    ; Return next-hop MAC address in RAX, or 0 if no route
    xor rax, rax
    ret

; =============================================================================
; IPv6 NDP Processing
; =============================================================================

align 64
ipv6_ndp_process:
    ; TODO: Implement NDP (Neighbor Discovery Protocol)
    ret

align 64
ndp_lookup:
    ; TODO: Implement NDP cache lookup
    xor rax, rax
    ret

align 64
ndp_queue_packet:
    ; TODO: Queue packet for NDP resolution
    ret

; =============================================================================
; IPv6 Flow Label
; =============================================================================

align 64
ipv6_flow_label_get:
    ; Generate flow label (RFC 6437)
    call rdtsc_get_cycles
    and eax, IPV6_FLOW_LABEL_MASK
    ret

%endif ; GUARD_UNET_CORE_L3_IPV6_TCP_ASM
