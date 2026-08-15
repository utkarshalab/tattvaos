; =============================================================================
; Tattva OS — lib/ulog/ratelimit/ratelimit_hash.asm
; =============================================================================
; A cheap bucket signature over (module_id, msg_ptr). msg_ptr is always a
; static string literal's address in this tree — never heap or stack — so
; hashing the pointer value itself is a valid, stable signature; no need to
; hash message content.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RATELIMIT_RATELIMIT_HASH_ASM
%define LIB_ULOG_RATELIMIT_RATELIMIT_HASH_ASM

[BITS 64]

%define RATELIMIT_BUCKETS  256

section .text

; -----------------------------------------------------------------------------
; ratelimit_hash — Input: RDI = module_id, RSI = msg_ptr
; Output: RAX = bucket index in [0, RATELIMIT_BUCKETS)
; -----------------------------------------------------------------------------
global ratelimit_hash
ratelimit_hash:
    mov rax, rsi
    shr rax, 3                       ; drop low alignment bits, they don't vary
    movzx ecx, di
    xor rax, rcx
    ; imul's 3-operand immediate form sign-extends a 32-bit immediate, and
    ; 2654435761 (0x9E3779B1) has its top bit set — sign-extending it would
    ; silently multiply by the wrong 64-bit value. `mov r32, imm32` zero-
    ; extends instead, so load it that way first.
    mov ecx, 2654435761              ; Knuth multiplicative hash constant
    imul rax, rcx
    and rax, (RATELIMIT_BUCKETS - 1)
    ret

%endif ; LIB_ULOG_RATELIMIT_RATELIMIT_HASH_ASM
