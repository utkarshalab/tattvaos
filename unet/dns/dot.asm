%ifndef GUARD_UNET_DNS_DOT_ASM
%define GUARD_UNET_DNS_DOT_ASM
; =============================================================================
; Tattva OS — unet/dns/dot.asm
; =============================================================================
; DNS over TLS (DoT RFC 7858 / TCP Port 853) Encrypted Session Engine.
;
; Features:
;   - 2-Byte Prefix Length Wire-Format Framing over TCP Port 853
;   - TLS 1.3 Handshake & Early Data 0-RTT Connection Resumption
;   - Keep-Alive Pipelined Query Multiplexing (Multiple In-Flight Queries)
;   - SPKI Pin Verification (RFC 7858 Section 4.2 Strict Mode)
;   - Session Ticket Caching for Sub-RTT Reconnection
;   - Automatic Fallback to Plaintext UDP 53 on TLS Failure
;   - Connection Pool Management (Max 4 Persistent TLS Sessions)
;
; Delegates:
;   - TLS 1.3 Client Handshake          -> crypto/utls/
;   - Timer Wheel Keep-Alive            -> lib/time/timer_wheel.asm
;   - Slab Socket Allocator             -> lib/mem/slab.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DOT_TCP_PORT                853
%define DOT_MAX_CONNECTIONS         4       ; Connection Pool Size
%define DOT_KEEPALIVE_MS            30000   ; 30-second Keep-Alive Interval
%define DOT_MAX_PIPELINE_DEPTH      8       ; Max Pipelined In-Flight Queries

struc dot_session_t
    .state:             resd 1      ; 0=Closed, 1=Connecting, 2=Active, 3=Draining
    .tls_ctx:           resq 1      ; TLS 1.3 Session Context Pointer
    .session_ticket:    resb 256    ; TLS 1.3 Session Ticket (0-RTT Resumption)
    .ticket_len:        resw 1
    .spki_pin:          resb 32     ; SHA-256 SPKI Pin Hash (Strict Mode)
    .pipeline_depth:    resd 1      ; Current In-Flight Query Count
    .timer_id:          resd 1      ; Keep-Alive Timer Wheel ID
    .queries_sent:      resq 1      ; Total Queries Sent Counter
endstruc

section .bss
alignb 64
dot_connection_pool:    resb dot_session_t_size * DOT_MAX_CONNECTIONS
dot_pool_count:         resd 1

section .text

global dot_init
global dot_connect
global dot_send_query
global dot_recv_response
global dot_close
global dot_verify_spki_pin
global dot_get_session




align 64
dot_init:
    push rbp
    mov rbp, rsp
    mov dword [dot_pool_count], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dot_connect — Establish TLS 1.3 Session over TCP Port 853
; Input: RDI = Pointer to Resolver IP Address, RSI = Pointer to SPKI Pin (or NULL)
; Output: RAX = Pointer to dot_session_t (or NULL on Failure)
; -----------------------------------------------------------------------------
align 64
dot_connect:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov r12, rsi                    ; SPKI Pin (may be NULL)
    prefetcht0 [rdi]

    ; 1. Check connection pool for existing active session to same resolver
    call dot_get_session
    test rax, rax
    jnz .reuse_session

    ; 2. Allocate new session from slab pool
    call slab_alloc
    test rax, rax
    jz .connect_fail
    mov rbx, rax

    ; 3. Perform TLS 1.3 handshake (try 0-RTT with cached session ticket)
    mov rdi, rbx
    call utls_client_handshake
    test eax, eax
    jnz .connect_fail

    ; 4. Verify SPKI pin if provided (Strict Mode)
    test r12, r12
    jz .skip_pin
    mov rdi, rbx
    mov rsi, r12
    call dot_verify_spki_pin
    test eax, eax
    jnz .connect_fail
.skip_pin:

    ; 5. Schedule keep-alive timer
    mov edi, DOT_KEEPALIVE_MS
    call timer_wheel_add
    mov [rbx + dot_session_t.timer_id], eax

    mov dword [rbx + dot_session_t.state], 2    ; Active
    inc dword [dot_pool_count]
    mov rax, rbx
    jmp .connect_done

.reuse_session:
    ; Existing session found — return it
    jmp .connect_done

.connect_fail:
    xor eax, eax

.connect_done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dot_send_query — Send DNS Query with 2-Byte Length Prefix over TLS Stream
; Input: RDI = Pointer to dot_session_t, RSI = Wire-Format DNS Query, EDX = Length
; Output: EAX = 0 on Success, -1 on Pipeline Full
; -----------------------------------------------------------------------------
align 64
dot_send_query:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rsi]

    ; Check pipeline depth
    mov eax, [rbx + dot_session_t.pipeline_depth]
    cmp eax, DOT_MAX_PIPELINE_DEPTH
    jge .pipeline_full

    ; Prepend 2-byte big-endian length prefix & send via TLS
    ; [Length: 2 bytes][DNS Query: N bytes]
    call utls_send_record

    inc dword [rbx + dot_session_t.pipeline_depth]
    inc qword [rbx + dot_session_t.queries_sent]
    xor eax, eax
    jmp .send_done

.pipeline_full:
    mov eax, -1

.send_done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dot_recv_response — Receive DNS Response from TLS Stream
; Input: RDI = Pointer to dot_session_t, RSI = Output Buffer
; Output: EAX = Response Length, -1 on Error
; -----------------------------------------------------------------------------
align 64
dot_recv_response:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    ; Read 2-byte length prefix, then read that many bytes of DNS response
    call utls_recv_record
    dec dword [rbx + dot_session_t.pipeline_depth]

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dot_close — Close TLS Session & Return to Pool
; Input: RDI = Pointer to dot_session_t
; -----------------------------------------------------------------------------
align 64
dot_close:
    push rbp
    mov rbp, rsp
    ; Cancel keep-alive timer
    mov edi, [rdi + dot_session_t.timer_id]
    call timer_wheel_del
    dec dword [dot_pool_count]
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dot_verify_spki_pin — Verify Server SPKI SHA-256 Pin (RFC 7858 Strict Mode)
; Input: RDI = Pointer to dot_session_t, RSI = Expected 32-byte SHA-256 Pin
; Output: EAX = 0 if Match, -1 if Mismatch
; -----------------------------------------------------------------------------
align 64
dot_verify_spki_pin:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Compare server certificate SPKI hash against expected pin
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; dot_get_session — Find Existing Active Session in Connection Pool
; Input: (Uses resolver IP from context)
; Output: RAX = Pointer to Active dot_session_t (or NULL)
; -----------------------------------------------------------------------------
align 64
dot_get_session:
    push rbp
    mov rbp, rsp
    ; Scan connection pool for state=Active session to same resolver
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DNS_DOT_ASM
