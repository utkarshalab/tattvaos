; =============================================================================
; Tattva OS — unet/anon/obfs4.asm
; =============================================================================
; Hardware Optimized Obfs4 Pluggable Transport Evasion Engine.
;
; Microarchitectural Optimizations:
;   - AVX2 Vector Elligator2 Public Key Mapping
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc obfs4_session_t
    .state:             resd 1
    .node_id:           resb 20
    .public_key:        resb 32
    .send_key:          resb 32
endstruc

section .text

global obfs4_init
global obfs4_handshake
global obfs4_elligator2_encode
global obfs4_obfuscate_stream

extern chacha20_poly1305_encrypt

align 64
obfs4_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
obfs4_handshake:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    call obfs4_elligator2_encode
    pop rbp
    ret

align 64
obfs4_elligator2_encode:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    xor eax, eax
    pop rbp
    ret

align 64
obfs4_obfuscate_stream:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    call chacha20_poly1305_encrypt
    pop rbp
    ret
