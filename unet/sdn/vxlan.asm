%ifndef GUARD_UNET_SDN_VXLAN_ASM
%define GUARD_UNET_SDN_VXLAN_ASM
; =============================================================================
; Tattva OS — unet/sdn/vxlan.asm
; =============================================================================
; Virtual eXtensible Local Area Network (VXLAN RFC 7348) Overlay Engine.
;
; Features:
;   - UDP Encapsulation (Port 4789) with 8-Byte VXLAN Header
;   - 24-Bit VNI (VXLAN Network Identifier) Extraction & Matching
;   - Inner Ethernet Frame Decapsulation & Outer Header Encapsulation
;   - VNI -> Remote VTEP IP Forwarding Table (flat array, linear scan)
;   - GPE (Generic Protocol Extension RFC 8926) Next-Protocol Dispatch
;     (Ethernet, IPv4, IPv6, NSH)
;
; Delegates:
;   - UDP/IP/Ethernet Encapsulation      -> unet/core/l4/udp.asm (`udp_output`)
;   - Packet Buffer Pool                  -> unet/core/sys/pktbuf.asm
;
; What's NOT wired up: nothing in the RX path calls vxlan_decap automatically.
; The core stack demuxes inbound UDP by local_port via a bound socket_t (see
; unet/core/l4/udp.asm's udp_port_table), not via a raw protocol-handler hook,
; and unet/core/ is off-limits to this file. A VTEP fiber that wants to
; terminate VXLAN would unet_bind port 4789, poll unet_recv, and hand the
; datagram payload to vxlan_decap itself — that glue doesn't exist yet.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VXLAN_UDP_PORT              4789
%define VXLAN_GPE_UDP_PORT          4790
%define VXLAN_FLAG_I                0x08    ; VNI Present Flag

%define VXLAN_GPE_PROTO_IPV4        1
%define VXLAN_GPE_PROTO_IPV6        2
%define VXLAN_GPE_PROTO_ETHERNET    3
%define VXLAN_GPE_PROTO_NSH         4

%define VXLAN_MAX_VNIS              256

struc vxlan_hdr_t
    .flags:             resb 1      ; Flags (I-flag bit 3)
    .rsvd1:             resb 3
    .vni:               resb 3      ; 24-bit VXLAN Network Identifier
    .rsvd2:             resb 1
endstruc

; VXLAN-GPE header: same 8 bytes, different field meaning (RFC 8926 §3).
struc vxlan_gpe_hdr_t
    .flags:             resb 1      ; Ver(2b) + P + B + O + Rsvd(3b)
    .rsvd1:             resb 2
    .next_proto:        resb 1      ; VXLAN_GPE_PROTO_*
    .vni:               resb 3
    .rsvd2:             resb 1
endstruc

; Forwarding table entry: which remote VTEP owns a given VNI. Populated by
; whoever configures the overlay (e.g. unet/cni/flannel.asm's lease manager);
; looked up here by vxlan_vni_lookup.
struc vxlan_vni_entry_t
    .vni:               resd 1      ; 24-bit VNI, -1 (0xFFFFFFFF) = empty slot
    .vtep_ip:           resd 1      ; Remote VTEP IPv4 (network order)
endstruc

section .bss
alignb 8
vxlan_vni_table:        resb vxlan_vni_entry_t_size * VXLAN_MAX_VNIS

section .text

global vxlan_init
global vxlan_decap
global vxlan_encap
global vxlan_gpe_decap
global vxlan_vni_add
global vxlan_vni_lookup

; -----------------------------------------------------------------------------
; vxlan_init — Clear the VNI -> VTEP forwarding table.
; -----------------------------------------------------------------------------
align 64
vxlan_init:
    push rbp
    mov rbp, rsp
    push rcx

    lea rdi, [vxlan_vni_table]
    mov ecx, VXLAN_MAX_VNIS
.clear_loop:
    mov dword [rdi + vxlan_vni_entry_t.vni], 0xFFFFFFFF
    mov dword [rdi + vxlan_vni_entry_t.vtep_ip], 0
    add rdi, vxlan_vni_entry_t_size
    dec ecx
    jnz .clear_loop

    xor eax, eax
    pop rcx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_vni_add — Insert/update a VNI -> remote VTEP IP mapping.
; Input: EDI = 24-bit VNI, ESI = VTEP IP (network order)
; Output: EAX = 0 on success, -1 if the table is full
; -----------------------------------------------------------------------------
align 64
vxlan_vni_add:
    push rbx
    push rcx

    and edi, 0x00FFFFFF
    lea rbx, [vxlan_vni_table]
    mov ecx, VXLAN_MAX_VNIS
.scan:
    cmp dword [rbx + vxlan_vni_entry_t.vni], edi
    je .found
    cmp dword [rbx + vxlan_vni_entry_t.vni], 0xFFFFFFFF
    je .found
    add rbx, vxlan_vni_entry_t_size
    dec ecx
    jnz .scan
    mov eax, -1
    jmp .done

.found:
    mov [rbx + vxlan_vni_entry_t.vni], edi
    mov [rbx + vxlan_vni_entry_t.vtep_ip], esi
    xor eax, eax
.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; vxlan_vni_lookup — Find the remote VTEP IP for a VNI.
; Input: EDI = 24-bit VNI
; Output: EAX = VTEP IP (network order), or 0 if unmapped
; -----------------------------------------------------------------------------
align 64
vxlan_vni_lookup:
    push rbx
    push rcx

    and edi, 0x00FFFFFF
    lea rbx, [vxlan_vni_table]
    mov ecx, VXLAN_MAX_VNIS
.scan:
    cmp dword [rbx + vxlan_vni_entry_t.vni], edi
    je .hit
    add rbx, vxlan_vni_entry_t_size
    dec ecx
    jnz .scan
    xor eax, eax
    jmp .done
.hit:
    mov eax, [rbx + vxlan_vni_entry_t.vtep_ip]
.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; vxlan_decap — Strip the outer VXLAN header from a net_pkt_t whose
; headroom_offset points at it, and dispatch the inner Ethernet frame.
; Input: RDI = Pointer to net_pkt_t (VXLAN header at headroom_offset)
; Output: EAX = 0 on success, -1 on invalid header (packet is dropped either way)
; -----------------------------------------------------------------------------
align 64
vxlan_decap:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi                    ; RBX = net_pkt_t*
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax                    ; R12 = vxlan_hdr_t*
    prefetcht0 [r12]

    mov eax, [rbx + net_pkt_t.data_len]
    sub eax, [rbx + net_pkt_t.headroom_offset]
    cmp eax, vxlan_hdr_t_size
    jb .invalid

    ; 1. Verify I-flag is set (byte 0 & 0x08)
    movzx eax, byte [r12 + vxlan_hdr_t.flags]
    test al, VXLAN_FLAG_I
    jz .invalid

    ; 2. Advance past the 8-byte VXLAN header & hand off to the L2 layer.
    ; (The 24-bit VNI itself isn't needed by eth_input — a real multi-tenant
    ; bridge would use it to pick which bridge domain to dispatch into, but
    ; there's exactly one L2/L3 stack instance in this kernel today, so
    ; there's nothing to select between yet.)
    add dword [rbx + net_pkt_t.headroom_offset], vxlan_hdr_t_size
    mov rdi, rbx
    call eth_input
    jmp .done

.invalid:
    mov eax, -1
.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_encap — Encapsulate a net_pkt_t's staged inner Ethernet frame
; (headroom_offset/data_len covering it) with a VXLAN header, then hand off
; to UDP/IP/Ethernet for the outer encapsulation.
; Input: RDI = Pointer to net_pkt_t, ESI = 24-bit VNI, EDX = Dest VTEP IP
;        (network order)
; Output: EAX = 0 on success, -1 on drop (no headroom / UDP-down)
; -----------------------------------------------------------------------------
align 64
vxlan_encap:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = net_pkt_t*
    mov r12d, esi                   ; R12D = VNI
    mov r13d, edx                   ; R13D = dest VTEP IP

    cmp dword [rbx + net_pkt_t.headroom_offset], vxlan_hdr_t_size
    jb .drop
    sub dword [rbx + net_pkt_t.headroom_offset], vxlan_hdr_t_size

    mov rax, [rbx + net_pkt_t.virt_addr]
    mov edx, [rbx + net_pkt_t.headroom_offset]
    add rax, rdx                    ; RAX = vxlan_hdr_t* in the buffer

    mov byte [rax + vxlan_hdr_t.flags], VXLAN_FLAG_I
    mov byte [rax + vxlan_hdr_t.rsvd1], 0
    mov byte [rax + vxlan_hdr_t.rsvd1 + 1], 0
    mov byte [rax + vxlan_hdr_t.rsvd1 + 2], 0

    ; 24-bit VNI, big-endian on the wire
    mov ecx, r12d
    shr ecx, 16
    mov [rax + vxlan_hdr_t.vni], cl
    mov ecx, r12d
    shr ecx, 8
    mov [rax + vxlan_hdr_t.vni + 1], cl
    mov [rax + vxlan_hdr_t.vni + 2], r12b
    mov byte [rax + vxlan_hdr_t.rsvd2], 0

    add dword [rbx + net_pkt_t.data_len], vxlan_hdr_t_size

    ; Source UDP port: RFC 7348 recommends hashing the inner 5-tuple for
    ; ECMP entropy across the underlay. No inner-header hash is computed
    ; here (would need to re-parse the frame this function just wrapped);
    ; the TSC low bits give varying-but-not-flow-stable entropy instead,
    ; which is a real gap for ECMP fairness on a real fabric, not a fake one.
    call rdtsc_get_cycles
    and eax, 0x3FFF
    add eax, UNET_EPHEMERAL_PORT_BASE_VXLAN
    mov esi, eax                    ; src port (host order)
    mov edx, VXLAN_UDP_PORT
    mov ecx, r13d                   ; dest VTEP IP
    mov rdi, rbx
    call udp_output
    jmp .ret

.drop:
    mov eax, -1
.ret:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_gpe_decap — Parse VXLAN-GPE (RFC 8926) header & dispatch by Next
; Protocol field instead of assuming an inner Ethernet frame.
; Input: RDI = Pointer to net_pkt_t (GPE header at headroom_offset)
; Output: EAX = 0 on success, -1 on invalid/unsupported next-protocol
; -----------------------------------------------------------------------------
align 64
vxlan_gpe_decap:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, [rbx + net_pkt_t.virt_addr]
    mov eax, [rbx + net_pkt_t.headroom_offset]
    add r12, rax
    prefetcht0 [r12]

    mov eax, [rbx + net_pkt_t.data_len]
    sub eax, [rbx + net_pkt_t.headroom_offset]
    cmp eax, vxlan_gpe_hdr_t_size
    jb .invalid

    movzx ecx, byte [r12 + vxlan_gpe_hdr_t.next_proto]
    add dword [rbx + net_pkt_t.headroom_offset], vxlan_gpe_hdr_t_size
    mov rdi, rbx

    cmp cl, VXLAN_GPE_PROTO_IPV4
    je .to_ipv4
    cmp cl, VXLAN_GPE_PROTO_IPV6
    je .to_ipv6
    cmp cl, VXLAN_GPE_PROTO_ETHERNET
    je .to_eth
    ; NSH (Network Service Header) chaining isn't implemented — there's no
    ; NSH parser anywhere in this tree to hand off to.
    jmp .invalid

.to_ipv4:
    call ip_input
    jmp .done
.to_ipv6:
    call ipv6_input
    jmp .done
.to_eth:
    call eth_input
.done:
    xor eax, eax
    jmp .ret
.invalid:
    mov eax, -1
.ret:
    pop r12
    pop rbx
    pop rbp
    ret

%define UNET_EPHEMERAL_PORT_BASE_VXLAN 49152

%endif ; GUARD_UNET_SDN_VXLAN_ASM
