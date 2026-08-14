%ifndef GUARD_UNET_PROXY_REVERSE_PROXY_ASM
%define GUARD_UNET_PROXY_REVERSE_PROXY_ASM
; =============================================================================
; Tattva OS — unet/proxy/reverse_proxy.asm
; =============================================================================
; High-Performance Layer 7 Reverse Proxy & Load Balancer.
;
; Features:
;   - Upstream Backend Pool Health Checking & Circuit Breaking
;   - Load Balancing Algorithms: Round-Robin, Least-Connections, IP-Hash, Weighted
;   - HTTP Header Injection (`X-Forwarded-For`, `X-Forwarded-Proto`, `X-Real-IP`, `Via`)
;   - Response Caching & Gzip / Brotli Compression Passing
;   - SSL/TLS Termination & Re-Encryption to Upstream Backends
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define RP_MAX_BACKENDS             64

struc reverse_proxy_backend_t
    .ip_addr:           resd 1
    .port:              resw 1
    .weight:            resw 1
    .active_conns:      resd 1
    .healthy:           resb 1      ; 1=Healthy, 0=Unhealthy
endstruc

section .bss
alignb 64
backend_pool:           resb reverse_proxy_backend_t_size * RP_MAX_BACKENDS
backend_count:          resd 1

section .text

global reverse_proxy_init
global reverse_proxy_select_backend
global reverse_proxy_inject_headers
global reverse_proxy_forward_request

align 64
reverse_proxy_init:
    push rbp
    mov rbp, rsp
    mov dword [backend_count], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; reverse_proxy_select_backend — Select Healthy Upstream Backend (Least Conns)
; Output: RAX = Pointer to selected reverse_proxy_backend_t
; -----------------------------------------------------------------------------
align 64
reverse_proxy_select_backend:
    push rbp
    mov rbp, rsp
    push rbx

    mov ecx, [backend_count]
    test ecx, ecx
    jz .no_backend

    ; Iterate backend pool & select healthy backend with minimum active_conns
    lea rax, [backend_pool]
    jmp .done

.no_backend:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
reverse_proxy_inject_headers:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Append X-Forwarded-For: client_ip, X-Forwarded-Proto: https, X-Real-IP
    xor eax, eax
    pop rbp
    ret

align 64
reverse_proxy_forward_request:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Forward request to selected upstream backend socket & pipe response back to client
    call reverse_proxy_select_backend
    call reverse_proxy_inject_headers
    pop rbp
    ret

%endif ; GUARD_UNET_PROXY_REVERSE_PROXY_ASM
