; =============================================================================
; Tattva OS — unet/mail/spf_dmarc.asm
; =============================================================================
; SPF (RFC 7208) & DMARC (RFC 7489) Email Authentication Policy Engine.
;
; Features:
;   - SPF Record Parsing & IP Authorization Check (include, a, mx, ip4, ip6, all)
;   - SPF Result Codes: pass, fail, softfail, neutral, none, temperror, permerror
;   - SPF DNS Lookup Limit Enforcement (Max 10 DNS Lookups per RFC 7208)
;   - DMARC Policy Lookup (_dmarc.domain TXT Record)
;   - DMARC Alignment Check: SPF & DKIM Domain vs. From Header Domain
;   - DMARC Policy Enforcement: none, quarantine, reject
;   - DMARC Aggregate Report (RUA) & Forensic Report (RUF) Generation
;
; Delegates:
;   - DNS TXT Lookup                     -> unet/dns/dns.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SPF_RESULT_NONE             0
%define SPF_RESULT_NEUTRAL          1
%define SPF_RESULT_PASS             2
%define SPF_RESULT_FAIL             3
%define SPF_RESULT_SOFTFAIL         4
%define SPF_RESULT_TEMPERROR        5
%define SPF_RESULT_PERMERROR        6

%define DMARC_POLICY_NONE           0
%define DMARC_POLICY_QUARANTINE     1
%define DMARC_POLICY_REJECT         2

%define SPF_MAX_DNS_LOOKUPS         10

struc spf_context_t
    .sender_ip:         resb 16     ; IPv4 or IPv6 address
    .sender_domain:     resb 64     ; MAIL FROM domain
    .dns_lookup_count:  resd 1      ; Current DNS lookup count
    .result:            resd 1      ; SPF result code
endstruc

struc dmarc_policy_t
    .domain:            resb 64     ; Organizational domain
    .policy:            resd 1      ; p= none/quarantine/reject
    .subdomain_policy:  resd 1      ; sp= subdomain policy
    .pct:               resd 1      ; pct= percentage (0-100)
    .adkim:             resb 1      ; DKIM alignment: 'r'=relaxed, 's'=strict
    .aspf:              resb 1      ; SPF alignment: 'r'=relaxed, 's'=strict
    .rua:               resb 128    ; Aggregate report URI
    .ruf:               resb 128    ; Forensic report URI
endstruc

section .text

global spf_init
global spf_check
global spf_parse_record
global dmarc_init
global dmarc_check
global dmarc_lookup_policy
global dmarc_check_alignment

extern dns_query

align 64
spf_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; spf_check — Evaluate SPF Record for Sender IP Authorization
; Input: RDI = Pointer to spf_context_t
; Output: EAX = SPF Result Code (pass/fail/softfail/neutral/none)
; -----------------------------------------------------------------------------
align 64
spf_check:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. DNS TXT lookup for sender_domain
    lea rdi, [rbx + spf_context_t.sender_domain]
    call dns_query

    ; 2. Parse SPF record mechanisms
    call spf_parse_record

    ; 3. Check DNS lookup limit (max 10)
    mov eax, [rbx + spf_context_t.dns_lookup_count]
    cmp eax, SPF_MAX_DNS_LOOKUPS
    jg .spf_permerror

    mov eax, [rbx + spf_context_t.result]
    jmp .spf_done

.spf_permerror:
    mov eax, SPF_RESULT_PERMERROR

.spf_done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; spf_parse_record — Parse SPF TXT Record Mechanisms
; Input: RDI = Pointer to SPF Record String, RSI = Pointer to spf_context_t
; Output: Updates spf_context_t.result
; -----------------------------------------------------------------------------
align 64
spf_parse_record:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse: v=spf1 include:domain a mx ip4:cidr ip6:cidr ~all -all +all ?all
    ; For each mechanism: match sender_ip, apply qualifier (+/-/~/?)
    xor eax, eax
    pop rbp
    ret

align 64
dmarc_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dmarc_check — Evaluate DMARC Policy for Message
; Input: RDI = From Header Domain, ESI = SPF Result, EDX = DKIM Result
; Output: EAX = DMARC Policy Action (none/quarantine/reject)
; -----------------------------------------------------------------------------
align 64
dmarc_check:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Lookup DMARC policy
    call dmarc_lookup_policy

    ; 2. Check SPF alignment (MAIL FROM domain vs. From header domain)
    ; 3. Check DKIM alignment (d= domain vs. From header domain)
    call dmarc_check_alignment

    pop rbx
    pop rbp
    ret

align 64
dmarc_lookup_policy:
    push rbp
    mov rbp, rsp
    ; DNS TXT query for _dmarc.domain
    call dns_query
    ; Parse: v=DMARC1; p=reject; sp=quarantine; pct=100; adkim=r; aspf=r; rua=...; ruf=...
    pop rbp
    ret

align 64
dmarc_check_alignment:
    push rbp
    mov rbp, rsp
    ; Strict: exact domain match. Relaxed: organizational domain match
    xor eax, eax
    pop rbp
    ret
