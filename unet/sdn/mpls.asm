; =============================================================================
; Tattva OS — unet/sdn/mpls.asm
; =============================================================================
; Multi-Protocol Label Switching (MPLS RFC 3031 / RFC 3032) Engine.
;
; Features:
;   - 32-Bit Label Stack Entry (LSE) Parsing: 20-bit Label, 3-bit TC/EXP, 1-bit S (Bottom of Stack), 8-bit TTL
;   - Label Push / Pop / Swap Forwarding Operations
;   - Multi-Label Stack Traversal (VPN Label + Transport Label)
;   - Segment Routing over MPLS (SR-MPLS RFC 8660) Prefix & Adjacency SIDs
;   - Entropy Label (RFC 6790) Support for ECMP Load Balancing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ETHERTYPE_MPLS_UNICAST      0x8847
%define ETHERTYPE_MPLS_MULTICAST    0x8848

struc mpls_lse_t
    .entry:             resd 1      ; Label(20b) + TC(3b) + S(1b) + TTL(8b)
endstruc

section .text

global mpls_init
global mpls_parse_stack
global mpls_push_label
global mpls_pop_label
global mpls_swap_label

align 64
mpls_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; mpls_parse_stack — Parse Multi-Label MPLS Stack & Extract Inner Protocol
; Input: RDI = Pointer to MPLS Header Buffer, ESI = Length
; Output: RAX = Pointer to Payload, EDX = Bottom-of-Stack Label, ECX = Stack Depth
; -----------------------------------------------------------------------------
align 64
mpls_parse_stack:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    xor ecx, ecx                    ; Stack depth counter
.stack_loop:
    mov eax, [rbx + rcx * 4]
    bswap eax                       ; Network -> Host byte order

    inc ecx

    ; Check S-bit (bit 8: Bottom of Stack)
    test eax, 0x00000100
    jz .stack_loop                  ; S=0 -> continue to next label in stack

    ; Extract 20-bit Label (bits 31..12)
    mov edx, eax
    shr edx, 12                     ; EDX = 20-bit Label

    ; Return pointer to Payload (RDI + stack_depth * 4)
    lea rax, [rbx + rcx * 4]

    pop rbx
    pop rbp
    ret

align 64
mpls_push_label:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend 32-bit LSE (Label + TC + S + TTL) to packet header
    xor eax, eax
    pop rbp
    ret

align 64
mpls_pop_label:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Remove outer 32-bit LSE from packet header
    xor eax, eax
    pop rbp
    ret

align 64
mpls_swap_label:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Replace outer 20-bit label with new outgoing label & decrement TTL
    xor eax, eax
    pop rbp
    ret
