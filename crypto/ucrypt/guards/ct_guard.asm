; =============================================================================
; Tattva OS — crypto/ucrypt/guards/ct_guard.asm
; =============================================================================
; Constant-Time Side-Channel Protection Guard (Bleichenbacher / Lucky 13 Defense).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

; Included from ucrypt.asm, storage/uxfs/uxfs.asm and storage/uxfs/vfs/clone.asm.
; Without this guard the single-unit kernel build redefines every label here.
%ifndef UCRYPT_CT_GUARD_ASM
%define UCRYPT_CT_GUARD_ASM

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ucrypt_ct_memcmp — Constant-Time Memory Comparison (Zero Branching)
; Input:  RDI = Buffer A Pointer
;         RSI = Buffer B Pointer
;         RDX = Comparison Length in Bytes
; Output: RAX = 0 if identical, Non-Zero if mismatch
; -----------------------------------------------------------------------------
ucrypt_ct_memcmp:
    push rbx
    push rcx
    push rsi
    push rdi

    xor rax, rax                    ; Accumulator
    xor rcx, rcx

.cmp_loop:
    cmp rcx, rdx
    jae .done

    mov bl, [rdi + rcx]
    xor bl, [rsi + rcx]
    movzx rbx, bl
    or rax, rbx                     ; Accumulate diff bits without branching

    inc rcx
    jmp .cmp_loop

.done:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ucrypt_ct_select — Constant-Time Conditional Select (CMOV / XOR)
; Input:  RDI = Condition Mask (0x0000000000000000 or 0xFFFFFFFFFFFFFFFF)
;         RSI = Value A
;         RDX = Value B
; Output: RAX = (Condition & A) | (~Condition & B)
; -----------------------------------------------------------------------------
ucrypt_ct_select:
    mov rax, rsi
    and rax, rdi
    not rdi
    and rdx, rdi
    or rax, rdx
    ret

%endif ; UCRYPT_CT_GUARD_ASM
