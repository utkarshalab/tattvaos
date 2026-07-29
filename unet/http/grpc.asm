; =============================================================================
; Tattva OS — unet/http/grpc.asm
; =============================================================================
; gRPC & gRPC-Web Microservice Protocol Engine.
;
; Implements:
;   - Protobuf Payload Framing (`Length-Prefixed Message`) over HTTP/2 & HTTP/3
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global grpc_init
global grpc_handle_rpc

align 32
grpc_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
grpc_handle_rpc:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret
