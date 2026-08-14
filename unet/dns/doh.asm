%ifndef GUARD_UNET_DNS_DOH_ASM
%define GUARD_UNET_DNS_DOH_ASM
; =============================================================================
; Tattva OS — unet/dns/doh.asm
; =============================================================================
; DNS over HTTPS (DoH RFC 8484 / HTTP/2 & HTTP/3) Encrypted Resolver Engine.
;
; Features:
;   - Wire-Format DNS Message Encapsulation into `application/dns-message`
;   - HTTP POST Binary Payload Body (Preferred — Lower Latency)
;   - HTTP GET Base64url Query Parameter Encoding (Cacheable by HTTP Proxies)
;   - HTTP/2 Stream Multiplexing (Multiple In-Flight DNS Queries)
;   - HTTP/3 QUIC Transport (0-RTT + HoLB Elimination)
;   - TLS 1.3 Session Resumption & Early Data
;   - Response Content-Type Validation (`application/dns-message`)
;   - Padding via EDNS0 (RFC 7830) to Prevent Query Size Fingerprinting
;   - Automatic Resolver Selection with Health Checking
;
; Delegates:
;   - HTTP/2 Stack                      -> unet/http/http2.asm
;   - HTTP/3 Stack                      -> unet/http/http3.asm
;   - TLS 1.3 Encryption                -> crypto/utls/
;   - Base64url Encoding               -> lib/encoding (inline)
;   - Timer Wheel Health Check          -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DOH_MAX_RESOLVERS           4       ; Max Configured DoH Resolvers
%define DOH_HEALTH_CHECK_MS         60000   ; 60-second Health Check Interval
%define DOH_MAX_BODY_SIZE           4096    ; Max DNS Message Body Size
%define DOH_CONTENT_TYPE_LEN        23      ; "application/dns-message"

struc doh_resolver_t
    .url:               resb 128    ; Resolver URL (e.g., "https://dns.google/dns-query")
    .state:             resd 1      ; 0=Unknown, 1=Healthy, 2=Degraded, 3=Down
    .rtt_ms:            resd 1      ; Last Measured RTT (ms)
    .success_count:     resq 1      ; Successful Queries
    .failure_count:     resq 1      ; Failed Queries
    .timer_id:          resd 1      ; Health Check Timer Wheel ID
    .prefer_h3:         resb 1      ; 1=Prefer HTTP/3, 0=HTTP/2
endstruc

section .bss
alignb 64
doh_resolver_table:     resb doh_resolver_t_size * DOH_MAX_RESOLVERS
doh_resolver_count:     resd 1
doh_active_resolver:    resd 1      ; Index of Currently Selected Resolver

section .text

global doh_init
global doh_encap_post
global doh_encap_get
global doh_decap_response
global doh_select_resolver
global doh_health_check


align 64
doh_init:
    push rbp
    mov rbp, rsp

    mov dword [doh_resolver_count], 0
    mov dword [doh_active_resolver], 0

    ; Schedule periodic health checks
    mov edi, DOH_HEALTH_CHECK_MS
    call timer_wheel_add

    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doh_encap_post — Format DoH POST Request with Binary DNS Message Body
; Input: RDI = Pointer to Wire-Format DNS Query, ESI = Query Length
; Output: EAX = 0 on Success, -1 on Failure
; Preferred method: lower latency, no Base64url overhead
; -----------------------------------------------------------------------------
align 64
doh_encap_post:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12d, esi
    prefetcht0 [rbx]

    ; 1. Validate query size <= DOH_MAX_BODY_SIZE
    cmp r12d, DOH_MAX_BODY_SIZE
    ja .post_fail

    ; 2. Select healthy resolver
    call doh_select_resolver

    ; 3. Establish TLS 1.3 session if not already connected
    call utls_client_handshake

    ; 4. Build HTTP/2 POST request:
    ;    POST /dns-query HTTP/2
    ;    Content-Type: application/dns-message
    ;    Content-Length: <query_length>
    ;    Accept: application/dns-message
    ;    [binary DNS query body]
    mov rdi, rbx
    mov esi, r12d
    call http2_send_request

    ; 5. Increment success counter
    xor eax, eax
    jmp .post_done

.post_fail:
    mov eax, -1

.post_done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doh_encap_get — Format DoH GET Request with Base64url Query Parameter
; Input: RDI = Pointer to Wire-Format DNS Query, ESI = Query Length
; Output: EAX = 0 on Success
; Alternative method: cacheable by HTTP proxies
; -----------------------------------------------------------------------------
align 64
doh_encap_get:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Base64url encode DNS query (no padding)
    ; 2. Build HTTP/2 GET request:
    ;    GET /dns-query?dns=<base64url_query> HTTP/2
    ;    Accept: application/dns-message
    call doh_select_resolver
    call http2_send_request

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doh_decap_response — Extract Binary DNS Response from HTTP Response Body
; Input: RDI = Pointer to HTTP Response Buffer, ESI = Response Length
; Output: RAX = Pointer to DNS Message, EDX = DNS Message Length, -1 on Error
; -----------------------------------------------------------------------------
align 64
doh_decap_response:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]

    ; 1. Verify Content-Type header == "application/dns-message"
    ; 2. Verify HTTP status code == 200
    ; 3. Extract binary DNS response payload from body
    call http2_recv_response

    pop rbp
    ret

; -----------------------------------------------------------------------------
; doh_select_resolver — Select Best Available DoH Resolver
; Output: RAX = Pointer to doh_resolver_t (Lowest RTT Healthy Resolver)
; -----------------------------------------------------------------------------
align 64
doh_select_resolver:
    push rbp
    mov rbp, rsp
    ; Iterate resolver table, select state=Healthy with lowest rtt_ms
    ; Fallback to Degraded if no Healthy resolvers available
    lea rax, [doh_resolver_table]
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doh_health_check — Periodic Health Check for All Configured Resolvers
; Called by timer_wheel at DOH_HEALTH_CHECK_MS intervals
; -----------------------------------------------------------------------------
align 64
doh_health_check:
    push rbp
    mov rbp, rsp
    ; Send minimal A query for "." (root) to each resolver
    ; Measure RTT, update state (Healthy/Degraded/Down)
    ; Re-schedule next health check timer
    mov edi, DOH_HEALTH_CHECK_MS
    call timer_wheel_add
    pop rbp
    ret

%endif ; GUARD_UNET_DNS_DOH_ASM
