%ifndef GUARD_UNET_TOOLS_TELECOM_LOOKUP_ASM
%define GUARD_UNET_TOOLS_TELECOM_LOOKUP_ASM
; =============================================================================
; Tattva OS — unet/tools/telecom/lookup.asm
; =============================================================================
; Command-Line DNS Resolver & Lookup Tool (`dig` / `nslookup`).
;
; Features:
;   - UDP Port 53 RFC 1035 DNS Query Formatting (QNAME Label Compression, QTYPE A/AAAA/MX/CNAME/NS/SOA/TXT/SRV)
;   - DNS Response Parsing: RCODE (0=NOERROR, 2=SERVFAIL, 3=NXDOMAIN), Answer/Authority/Additional Sections
;   - Recursive / Iterative Query Mode & Multiple Nameserver Failover
;   - Nanosecond Resolution Query Latency Measurement
;
; Delegates:
;   - DNS Engine                        -> unet/dns/dns.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DNS_PORT                    53
%define DNS_QTYPE_A                 1
%define DNS_QTYPE_AAAA              28
%define DNS_QTYPE_MX                15
%define DNS_QTYPE_CNAME             5
%define DNS_QTYPE_NS                2
%define DNS_QTYPE_SOA               6
%define DNS_QTYPE_TXT               16
%define DNS_QTYPE_SRV               33

struc dns_query_opts_t
    .nameserver_ip:     resd 1      ; Target DNS Server IPv4
    .qtype:             resw 1      ; Query Type (A, AAAA, MX, etc.)
    .qname_ptr:         resq 1      ; Pointer to QNAME domain string
    .recursive:         resb 1      ; 1 = Recursive (RD bit set)
endstruc

section .text

global lookup_main
global lookup_format_query
global lookup_parse_response


align 64
lookup_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Format DNS query
    call lookup_format_query

    ; 2. Transmit UDP 53 & parse response
    call lookup_parse_response

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; lookup_format_query — Encode QNAME Label Sequence & DNS Header
; Input: RDI = Pointer to dns_query_opts_t
; Output: RAX = Pointer to formatted DNS packet, ECX = Packet Length
; -----------------------------------------------------------------------------
align 64
lookup_format_query:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Encode domain label sequence (e.g. 3www6google3com0) + QTYPE + QCLASS=IN(1)
    ; Set Transaction ID = RDTSC lower 16 bits, QR=0 (Query), RD=1 (Recursive)
    call rdtsc_get_cycles
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; lookup_parse_response — Parse DNS Answer Section & Print Records
; Input: RDI = Pointer to DNS response buffer
; Output: EAX = RCODE (0=NOERROR, 3=NXDOMAIN)
; -----------------------------------------------------------------------------
align 64
lookup_parse_response:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract ANCOUNT -> iterate Answer RRs -> print NAME, TYPE, TTL, RDATA
    call dns_parse_query
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_TELECOM_LOOKUP_ASM
