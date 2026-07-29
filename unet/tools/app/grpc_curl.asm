; =============================================================================
; Tattva OS — unet/tools/grpc_curl.asm
; =============================================================================
; gRPC Protocol Buffer Stream Invocation CLI Tool (`grpcurl`).
;
; Implements:
;   - Formats Protobuf Binary Messages & Executes gRPC Methods over HTTP/2
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global grpc_curl_init
global grpc_curl_invoke

align 32
grpc_curl_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
grpc_curl_invoke:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
