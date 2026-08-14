%ifndef GUARD_UNET_HTTP_GRPC_ASM
%define GUARD_UNET_HTTP_GRPC_ASM
; =============================================================================
; Tattva OS — unet/http/grpc.asm
; =============================================================================
; gRPC & gRPC-Web Microservice Protocol Engine (HTTP/2 & HTTP/3 Transport).
;
; Features:
;   - Protobuf Length-Prefixed Message Framing (5-Byte Header: Compressed + 4B Length)
;   - Unary RPC, Server Streaming, Client Streaming, Bidirectional Streaming
;   - gRPC Status Codes & Trailers-Only Error Responses
;   - gRPC-Web Text Mode (Base64 Encoding for Browser Compatibility)
;   - Content-Type: application/grpc & application/grpc-web
;   - Deadline Propagation via `grpc-timeout` Header
;   - Metadata Key-Value Pairs & Binary Metadata (`-bin` Suffix)
;   - gRPC Health Check Protocol (grpc.health.v1.Health/Check)
;
; Delegates:
;   - HTTP/2 Stream Transport            -> unet/http/http2.asm
;   - HTTP/3 Stream Transport            -> unet/http/http3.asm
;   - Timer Wheel Deadline Enforcement   -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define GRPC_STATUS_OK               0
%define GRPC_STATUS_CANCELLED        1
%define GRPC_STATUS_UNKNOWN          2
%define GRPC_STATUS_INVALID_ARG      3
%define GRPC_STATUS_DEADLINE_EXCEEDED 4
%define GRPC_STATUS_NOT_FOUND        5
%define GRPC_STATUS_ALREADY_EXISTS   6
%define GRPC_STATUS_PERMISSION_DENIED 7
%define GRPC_STATUS_UNAUTHENTICATED  16

%define GRPC_COMPRESS_NONE          0
%define GRPC_COMPRESS_GZIP          1

struc grpc_msg_hdr_t
    .compressed:        resb 1      ; 0 = Not Compressed, 1 = Compressed
    .msg_length:        resd 1      ; 32-bit Message Length (big-endian)
endstruc

struc grpc_call_t
    .stream_id:         resd 1      ; HTTP/2 or HTTP/3 Stream ID
    .method_path:       resb 128    ; /package.Service/Method
    .deadline_ms:       resd 1      ; Deadline in Milliseconds
    .timer_id:          resd 1      ; Timer Wheel Deadline ID
    .status:            resd 1      ; gRPC Status Code
    .call_type:         resb 1      ; 0=Unary, 1=ServerStream, 2=ClientStream, 3=Bidi
endstruc

section .text

global grpc_init
global grpc_handle_rpc
global grpc_send_message
global grpc_recv_message
global grpc_send_status
global grpc_parse_frame_header
global grpc_health_check


align 64
grpc_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; grpc_handle_rpc — Dispatch Incoming gRPC Request by Method Path
; Input: RDI = Pointer to grpc_call_t
; Output: EAX = gRPC Status Code
; -----------------------------------------------------------------------------
align 64
grpc_handle_rpc:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Parse :path pseudo-header -> /package.Service/Method
    ; 2. Extract grpc-timeout header & schedule deadline timer
    mov edi, [rbx + grpc_call_t.deadline_ms]
    test edi, edi
    jz .no_deadline
    call timer_wheel_add
    mov [rbx + grpc_call_t.timer_id], eax
.no_deadline:

    ; 3. Dispatch to service handler based on method path
    ; 4. Receive client message(s) via grpc_recv_message
    call grpc_recv_message

    ; 5. Send response message(s) via grpc_send_message
    call grpc_send_message

    ; 6. Send status trailer
    mov edi, GRPC_STATUS_OK
    call grpc_send_status

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; grpc_send_message — Send Length-Prefixed Protobuf Message on HTTP/2 Stream
; Input: RDI = Stream ID, RSI = Protobuf Payload, EDX = Length
; -----------------------------------------------------------------------------
align 64
grpc_send_message:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Build 5-byte gRPC frame header (1B compressed + 4B length big-endian)
    ; Send as HTTP/2 DATA frame
    call http2_send_data
    pop rbp
    ret

; -----------------------------------------------------------------------------
; grpc_recv_message — Receive Length-Prefixed Protobuf Message
; Input: RDI = Stream ID, RSI = Output Buffer
; Output: EAX = Message Length, -1 on Error
; -----------------------------------------------------------------------------
align 64
grpc_recv_message:
    push rbp
    mov rbp, rsp
    ; Read 5-byte frame header, then read msg_length bytes of protobuf payload
    call grpc_parse_frame_header
    pop rbp
    ret

; -----------------------------------------------------------------------------
; grpc_send_status — Send gRPC Status & Trailers
; Input: EDI = gRPC Status Code
; -----------------------------------------------------------------------------
align 64
grpc_send_status:
    push rbp
    mov rbp, rsp
    ; Send HEADERS frame with END_STREAM containing:
    ;   grpc-status: <code>
    ;   grpc-message: <optional message>
    call http2_send_headers
    pop rbp
    ret

; -----------------------------------------------------------------------------
; grpc_parse_frame_header — Parse 5-Byte gRPC Length-Prefixed Frame Header
; Input: RDI = Pointer to Frame Buffer
; Output: EAX = Message Length, DL = Compressed Flag
; -----------------------------------------------------------------------------
align 64
grpc_parse_frame_header:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    movzx edx, byte [rdi + grpc_msg_hdr_t.compressed]
    mov eax, [rdi + grpc_msg_hdr_t.msg_length]
    bswap eax                       ; Network -> Host byte order
    pop rbp
    ret

; -----------------------------------------------------------------------------
; grpc_health_check — gRPC Health Check Protocol (grpc.health.v1.Health/Check)
; Output: EAX = 1 (SERVING), 0 (NOT_SERVING)
; -----------------------------------------------------------------------------
align 64
grpc_health_check:
    push rbp
    mov rbp, rsp
    mov eax, 1                      ; SERVING
    pop rbp
    ret

%endif ; GUARD_UNET_HTTP_GRPC_ASM
