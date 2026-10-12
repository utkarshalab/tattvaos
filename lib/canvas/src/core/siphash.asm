; ============================================================================
; SipHash-2-4 — Keyed Hash for Capability Tokens
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

%define SIPROUND \
    vaddq   v0, v0, v1 ;\
    vrotl   v1, v1, 13 ;\
    vxorq   v1, v1, v0 ;\
    vrotl   v0, v0, 32 ;\
    vaddq   v2, v2, v3 ;\
    vrotl   v3, v3, 16 ;\
    vxorq   v3, v3, v2 ;\
    vaddq   v0, v0, v3 ;\
    vrotl   v3, v3, 21 ;\
    vxorq   v3, v3, v0 ;\
    vaddq   v2, v2, v1 ;\
    vrotl   v1, v1, 17 ;\
    vxorq   v1, v1, v2 ;\
    vrotl   v2, v2, 32

; ---------------------------------------------------------------------------
; siphash24
;   SipHash-2-4
;   IN:  rdi = data ptr, rsi = length, rdx = key ptr (16 bytes)
;   OUT: rax = 64-bit hash
; ---------------------------------------------------------------------------
global siphash24
siphash24:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Load key (k0, k1)
    mov rax, [r13]
    mov rdx, [r13 + 8]

    ; Initialize state
    mov r14, 0x736f6d6570736575  ; "somepseu"
    mov r15, 0x646f72616e646f6d  ; "dorandom"
    xor r14, rax
    xor r15, rdx

    mov r8, r14    ; v0
    mov r9, r15    ; v1
    mov r10, r14   ; v2
    xor r10, r15   ; v3 = v2 ^ k1

    ; Process full 8-byte blocks
    mov rcx, r12
    shr rcx, 3
    test rcx, rcx
    jz .final

.block_loop:
    mov r11, [rbx]
    xor r11, r10
    add r8, r11
    ; SIPROUND x2
    ; Round 1
    add r8, r9
    rol r9, 13
    xor r9, r8
    rol r8, 32
    add r10, r15
    rol r15, 16
    xor r15, r10
    add r8, r15
    rol r15, 21
    xor r15, r8
    add r10, r9
    rol r9, 17
    xor r9, r10
    rol r10, 32
    ; Round 2
    add r8, r9
    rol r9, 13
    xor r9, r8
    rol r8, 32
    add r10, r15
    rol r15, 16
    xor r15, r10
    add r8, r15
    rol r15, 21
    xor r15, r8
    add r10, r9
    rol r9, 17
    xor r9, r10
    rol r10, 32

    add rbx, 8
    dec rcx
    jnz .block_loop

.final:
    ; Remaining bytes
    mov rcx, r12
    and rcx, 7
    test rcx, rcx
    jz .last

    mov r11, 0
    mov rdx, rbx
.rem_loop:
    movzx rax, byte [rdx]
    shl rax, cl
    or r11, rax
    inc rdx
    dec rcx
    jnz .rem_loop

    shl r11, 56
    xor r11, 0x80
    xor r10, r11

    ; SIPROUND x2
    add r8, r9
    rol r9, 13
    xor r9, r8
    rol r8, 32
    add r10, r15
    rol r15, 16
    xor r15, r10
    add r8, r15
    rol r15, 21
    xor r15, r8
    add r10, r9
    rol r9, 17
    xor r9, r10
    rol r10, 32

    add r8, r9
    rol r9, 13
    xor r9, r8
    rol r8, 32
    add r10, r15
    rol r15, 16
    xor r15, r10
    add r8, r15
    rol r15, 21
    xor r15, r8
    add r10, r9
    rol r9, 17
    xor r9, r10
    rol r10, 32

.last:
    xor r10, r12
    xor r8, r10
    xor r9, r15
    add r8, r9
    rol r9, 13
    xor r9, r8
    rol r8, 32
    add r10, r15
    rol r15, 16
    xor r15, r10
    add r8, r15
    rol r15, 21
    xor r15, r8
    add r10, r9
    rol r9, 17
    xor r9, r10
    rol r10, 32

    ; Finalization
    xor r15, 0xee
    add r10, r15
    rol r15, 16
    xor r15, r10
    add r8, r15
    rol r15, 21
    xor r15, r8
    add r10, r9
    rol r9, 17
    xor r9, r10
    rol r10, 32

    ; Output v0 ^ v1 ^ v2 ^ v3
    xor r8, r9
    xor r8, r10
    xor r8, r15
    mov rax, r8

    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; siphash24_verify
;   Verify SipHash matches expected
;   IN:  rdi = data, rsi = len, rdx = key, rcx = expected_hash
;   OUT: rax = 1 if match, 0 if not
; ---------------------------------------------------------------------------
global siphash24_verify
siphash24_verify:
    PROLOGUE_SAVE rbx
    mov rbx, rcx
    call siphash24
    cmp rax, rbx
    sete al
    movzx rax, al
    EPILOGUE_RESTORE rbx
    ret

section .data
global siphash_version
siphash_version: dq 0x010000