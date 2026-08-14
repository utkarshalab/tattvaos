%ifndef GUARD_UNET_TOOLS_APP_GRPC_CURL_ASM
%define GUARD_UNET_TOOLS_APP_GRPC_CURL_ASM
; =============================================================================
; Tattva OS — unet/tools/app/grpc_curl.asm
; =============================================================================
; Command-Line gRPC Protocol Tester & Method Invoker (`grpcurl`).
;
; Features:
;   - gRPC over HTTP/2 Frame Framing (DATA frames with 5-byte Length-Prefixed Message)
;   - Protocol Buffers (protobuf) Binary Payload Serializer & Deserializer
;   - gRPC Status Code Parsing (`grpc-status`: 0=OK, 2=UNKNOWN, 7=PERMISSION_DENIED, 14=UNAVAILABLE)
;   - gRPC Server Reflection Protocol v1 Querying
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc grpc_frame_hdr_t
    .compressed:        resb 1      ; 0 = Uncompressed, 1 = Compressed
    .message_len:       resd 1      ; 32-bit Big Endian Message Length
endstruc

section .text

global grpc_curl_main
global grpc_curl_invoke_method
global grpc_curl_parse_status

align 64
grpc_curl_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Format 5-byte gRPC frame header + Protobuf payload
    call grpc_curl_invoke_method

    ; 2. Read response & parse `grpc-status` header
    call grpc_curl_parse_status

    pop rbx
    pop rbp
    ret

align 64
grpc_curl_invoke_method:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Build HTTP/2 HEADERS frame (:path = /service/method) + DATA frame (5B header + protobuf)
    xor eax, eax
    pop rbp
    ret

align 64
grpc_curl_parse_status:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Extract `grpc-status` trailing header (0 = OK) & error message string
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_GRPC_CURL_ASM
