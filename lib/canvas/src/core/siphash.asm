; ============================================================================
; SipHash-2-4 — Keyed Hash for Capability Tokens
; ============================================================================
; v0 .. v3 live in r8 .. r11; the message word in rax. Leaf functions: no
; callee-saved registers touched.

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

%macro SIPROUND 0
    add r8, r9
    rol r9, 13
    xor r9, r8
    rol r8, 32
    add r10, r11
    rol r11, 16
    xor r11, r10
    add r8, r11
    rol r11, 21
    xor r11, r8
    add r10, r9
    rol r9, 17
    xor r9, r10
    rol r10, 32
%endmacro

; one message word rax into the state: v3 ^= m, two rounds, v0 ^= m
%macro SIPWORD 0
    xor r11, rax
    SIPROUND
    SIPROUND
    xor r8, rax
%endmacro

; ---------------------------------------------------------------------------
; siphash24
;   SipHash-2-4
;   IN:  rdi = data ptr, rsi = length, rdx = key ptr (16 bytes)
;   OUT: rax = 64-bit hash
; ---------------------------------------------------------------------------
global siphash24
siphash24:
    mov r8, 0x736f6d6570736575          ; "somepseu" ^ k0
    mov r9, 0x646f72616e646f6d          ; "dorandom" ^ k1
    mov r10, 0x6c7967656e657261         ; "lygenera" ^ k0
    mov r11, 0x7465646279746573         ; "tedbytes" ^ k1
    mov rax, [rdx]
    xor r8, rax
    xor r10, rax
    mov rax, [rdx + 8]
    xor r9, rax
    xor r11, rax

    mov rcx, rsi
    shr rcx, 3                          ; full 8-byte words
    jz .tail
.word:
    mov rax, [rdi]
    SIPWORD
    add rdi, 8
    dec rcx
    jnz .word

.tail:
    ; the last word: the 0 .. 7 bytes left, little endian, length in the top byte
    mov rcx, rsi
    and ecx, 7
    xor eax, eax
.byte:
    test ecx, ecx
    jz .last
    dec ecx
    shl rax, 8
    movzx edx, byte [rdi + rcx]
    or rax, rdx
    jmp .byte
.last:
    mov rdx, rsi
    shl rdx, 56
    or rax, rdx
    SIPWORD

    xor r10, 0xff
    SIPROUND
    SIPROUND
    SIPROUND
    SIPROUND
    mov rax, r8
    xor rax, r9
    xor rax, r10
    xor rax, r11
    ret

; ---------------------------------------------------------------------------
; siphash24_verify
;   Verify SipHash matches expected
;   IN:  rdi = data, rsi = len, rdx = key, rcx = expected_hash
;   OUT: rax = 1 if match, 0 if not
; ---------------------------------------------------------------------------
global siphash24_verify
siphash24_verify:
    push rbx
    mov rbx, rcx
    call siphash24
    xor ecx, ecx
    cmp rax, rbx
    sete cl
    mov eax, ecx
    pop rbx
    ret

section .data
global siphash_version
siphash_version: dq 0x010100
