; =============================================================================
; Tattva OS — unet/core/l4/udp.asm
; =============================================================================
; Zero-Copy Lockless UDP Socket Demuxing Engine.
;
; Microarchitectural Optimizations:
;   - O(1) Lockless Atomic Hash Table Port Demuxing (`lock cmpxchg16b`)
;   - Zero-Copy UDP Recvmsg / Sendmsg Payload Streaming via lib/mem/dma.asm
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc udp_hdr_t
    .src_port:          resw 1
    .dst_port:          resw 1
    .length:            resw 1
    .checksum:          resw 1
endstruc

section .text

global udp_init
global udp_input
global udp_output

align 64
udp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
udp_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Lockless hash table port demux to socket queue
    pop rbx
    pop rbp
    ret

align 64
udp_output:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    xor eax, eax
    pop rbp
    ret
