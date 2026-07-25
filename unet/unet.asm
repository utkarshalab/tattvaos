; =============================================================================
; Tattva OS — unet/unet.asm
; =============================================================================
; Master unet (Unikernel Network Stack Engine) Dispatcher API (`unet_init`,
; `unet_poll`, `unet_shutdown`).
;
; Single-pass NASM included subsystem handler linking all unet sub-modules.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "unet/unet.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

; -----------------------------------------------------------------------------
; unet Child Subsystem NASM Includes
; -----------------------------------------------------------------------------
%include "unet/mem/pktbuf.asm"
%include "unet/core/eth.asm"
%include "unet/core/arp.asm"
%include "unet/core/ip.asm"
%include "unet/core/udp.asm"
%include "unet/core/tcp.asm"
%include "unet/socket/socket.asm"
%include "unet/http/http1.asm"
%include "unet/drivers/e1000.asm"

section .text

global unet_init
global unet_poll
global unet_shutdown

; -----------------------------------------------------------------------------
; unet_init — Initialize Network Stack Subsystem
; -----------------------------------------------------------------------------
align 32
unet_init:
    push rbp
    mov rbp, rsp

    call pktbuf_init
    call arp_init
    call socket_init
    call e1000_init

    mov eax, 0                      ; Success
    pop rbp
    ret

; -----------------------------------------------------------------------------
; unet_poll — Main zero-copy packet rx/tx polling loop
; -----------------------------------------------------------------------------
align 32
unet_poll:
    push rbp
    mov rbp, rsp
    push rbx

    call e1000_receive_packet
    test rax, rax
    jz .poll_done

    mov rdi, rax
    call eth_parse
    test eax, eax
    jz .poll_done

    cmp ax, UNET_ETH_TYPE_IPV4
    je .handle_ipv4
    cmp ax, UNET_ETH_TYPE_ARP
    je .handle_arp
    jmp .poll_done

.handle_ipv4:
    call ip_parse
    jmp .poll_done

.handle_arp:
    call arp_process_packet
    jmp .poll_done

.poll_done:
    mov eax, 0
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; unet_shutdown — Shutdown Network Subsystem
; -----------------------------------------------------------------------------
align 32
unet_shutdown:
    mov eax, 0                      ; Success
    ret
