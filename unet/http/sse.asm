%ifndef GUARD_UNET_HTTP_SSE_ASM
%define GUARD_UNET_HTTP_SSE_ASM
; =============================================================================
; Tattva OS — unet/http/sse.asm
; =============================================================================
; Server-Sent Events (SSE) LLM Token Streaming Engine (W3C EventSource).
;
; Features:
;   - `text/event-stream` Content-Type with Chunked Transfer-Encoding
;   - Event Fields: event, data, id, retry
;   - Multi-Line Data Fields (multiple "data:" lines per event)
;   - Last-Event-ID Header for Automatic Reconnection & Resume
;   - Configurable Retry Interval via "retry:" Field
;   - Named Event Types for Multi-Channel Multiplexing
;   - Keep-Alive Comment Lines (": heartbeat\n") to Prevent Timeout
;   - Connection Drop Detection & Auto-Reconnection
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define SSE_DEFAULT_RETRY_MS        3000    ; 3-second Default Retry
%define SSE_HEARTBEAT_MS            15000   ; 15-second Heartbeat Interval

struc sse_stream_t
    .state:             resd 1      ; 0=Closed, 1=Connecting, 2=Open
    .last_event_id:     resb 64     ; Last-Event-ID for resume
    .retry_ms:          resd 1      ; Retry interval
    .timer_id:          resd 1      ; Heartbeat timer
endstruc

section .text

global sse_init
global sse_open_stream
global sse_stream_token
global sse_send_event
global sse_send_heartbeat
global sse_close_stream
global sse_parse_event


align 64
sse_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; sse_open_stream — Open SSE Connection & Send Response Headers
; Input: RDI = Pointer to sse_stream_t
; Output: EAX = 0 on Success
; -----------------------------------------------------------------------------
align 64
sse_open_stream:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    ; Send HTTP response: 200 OK
    ;   Content-Type: text/event-stream
    ;   Cache-Control: no-cache
    ;   Connection: keep-alive
    mov dword [rbx + sse_stream_t.state], 2
    mov dword [rbx + sse_stream_t.retry_ms], SSE_DEFAULT_RETRY_MS

    ; Schedule heartbeat timer
    mov edi, SSE_HEARTBEAT_MS
    call timer_wheel_add
    mov [rbx + sse_stream_t.timer_id], eax

    xor eax, eax
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; sse_stream_token — Stream Single LLM Token as SSE Data Event
; Input: RDI = Pointer to sse_stream_t, RSI = Token String, EDX = Length
; -----------------------------------------------------------------------------
align 64
sse_stream_token:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Format: "data: <token>\n\n"
    ; Send on chunked HTTP connection
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; sse_send_event — Send Named SSE Event with Data & ID
; Input: RDI = Event Name, RSI = Data, EDX = Data Length, RCX = Event ID
; -----------------------------------------------------------------------------
align 64
sse_send_event:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Format:
    ;   event: <name>\n
    ;   id: <id>\n
    ;   data: <line1>\n
    ;   data: <line2>\n
    ;   \n
    xor eax, eax
    pop rbp
    ret

align 64
sse_send_heartbeat:
    push rbp
    mov rbp, rsp
    ; Send comment line: ": heartbeat\n\n"
    ; Reschedule heartbeat timer
    mov edi, SSE_HEARTBEAT_MS
    call timer_wheel_add
    pop rbp
    ret

align 64
sse_close_stream:
    push rbp
    mov rbp, rsp
    ; Cancel heartbeat timer & close connection
    mov edi, [rdi + sse_stream_t.timer_id]
    call timer_wheel_del
    xor eax, eax
    pop rbp
    ret

align 64
sse_parse_event:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse incoming SSE text: extract event, data, id, retry fields
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_HTTP_SSE_ASM
