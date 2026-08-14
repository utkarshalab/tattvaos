%ifndef GUARD_CRYPTO_USIGN_ECDSA_BN256_ASM
%define GUARD_CRYPTO_USIGN_ECDSA_BN256_ASM
; =============================================================================
; Tattva OS — crypto/usign/ecdsa/bn256.asm
; =============================================================================
; 256-bit modular arithmetic for a general modulus.
;
; Implements:
;   - Schoolbook multiply to 512 bits (`bn256_mul_512`)
;   - Barrett reduction (`bn256_barrett`)
;   - Modular add, subtract, multiply, exponentiation, inversion
;   - Comparison and range tests
;
; ECDSA works modulo TWO different numbers: the field prime p, for coordinates,
; and the group order n, for scalars. They are close in size but not equal, and
; mixing them up produces a verifier that accepts forged signatures while still
; passing every valid-signature test. Every routine here therefore takes the
; modulus explicitly — there is no ambient "the" modulus to get wrong.
;
; Reduction is Barrett's rather than the Solinas form specific to P-256. The
; Solinas reduction is faster but expands into nine signed partial sums with
; several correction cases, and a single mis-signed term produces answers that
; are wrong only for rare inputs. Barrett is uniform, has no special cases, and
; costs two multiplications — irrelevant for a verifier that runs occasionally.
;
; NOT CONSTANT TIME. Everything here operates on public values: signatures,
; message hashes and public keys. Signing must not use this code.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

section .text

global bn256_mul_512
global bn256_barrett
global bn256_mulmod
global bn256_addmod
global bn256_submod
global bn256_powmod
global bn256_invmod
global bn256_is_zero
global bn256_is_zero_mask
global bn256_cmov
global bn256_cmp
global bn256_copy

; -----------------------------------------------------------------------------
; bn256_is_zero_mask — RDI = value. Returns RAX = all ones when zero, else 0.
;
; The branch-free counterpart of bn256_is_zero, for code that must not reveal
; which case it took. The OR-then-compare produces the answer without ever
; testing a limb individually.
; -----------------------------------------------------------------------------
align 32
bn256_is_zero_mask:
    mov rax, [rdi]
    or rax, [rdi + 8]
    or rax, [rdi + 16]
    or rax, [rdi + 24]
    ; RAX is zero exactly when every limb was. Turn that into a full mask:
    ; NEG sets the carry flag iff the value was nonzero.
    neg rax
    sbb rax, rax                    ; nonzero -> -1, zero -> 0
    not rax                         ; zero -> -1, nonzero -> 0
    ret

; -----------------------------------------------------------------------------
; bn256_cmov — RDI = r, RSI = a, RDX = mask.
;
; r = a when the mask is all ones, unchanged when it is zero. The mask must be
; 0 or ~0; a 0/1 flag would AND away all but the low bit.
; -----------------------------------------------------------------------------
align 32
bn256_cmov:
%assign i 0
%rep 4
    mov rax, [rsi + i*8]
    and rax, rdx
    mov rcx, [rdi + i*8]
    mov r8, rdx
    not r8
    and rcx, r8
    or rax, rcx
    mov [rdi + i*8], rax
%assign i i+1
%endrep
    ret

; -----------------------------------------------------------------------------
; bn256_copy — RDI = destination, RSI = source. Four limbs.
; -----------------------------------------------------------------------------
align 32
bn256_copy:
%assign i 0
%rep 4
    mov rax, [rsi + i*8]
    mov [rdi + i*8], rax
%assign i i+1
%endrep
    ret

; -----------------------------------------------------------------------------
; bn256_is_zero — RDI = value. Returns EAX = 1 when all four limbs are zero.
; -----------------------------------------------------------------------------
align 32
bn256_is_zero:
    mov rax, [rdi]
    or rax, [rdi + 8]
    or rax, [rdi + 16]
    or rax, [rdi + 24]
    test rax, rax
    jz .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; -----------------------------------------------------------------------------
; bn256_cmp — RDI = a, RSI = b.
;
; Returns:
;   EAX = 0 when a == b, 1 when a > b, -1 when a < b
;
; Compares from the most significant limb down, which is the only order that
; gives the right answer.
; -----------------------------------------------------------------------------
align 32
bn256_cmp:
%assign i 3
%rep 4
    mov rax, [rdi + i*8]
    mov rcx, [rsi + i*8]
    cmp rax, rcx
    ja .greater
    jb .less
%assign i i-1
%endrep
    xor eax, eax
    ret
.greater:
    mov eax, 1
    ret
.less:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; bn256_mul_512 — RDI = 8-limb product, RSI = a, RDX = b.
;
; Destination must not alias either operand.
; -----------------------------------------------------------------------------
align 32
bn256_mul_512:
    push rbx
    push r12
    push r13

    mov rbx, rdx                    ; b — RDX is clobbered by MUL
    mov r12, rdi

    ; Row 0 initialises the product.
    mov rax, [rsi]
    mul qword [rbx]
    mov [r12], rax
    mov r8, rdx

%assign j 1
%rep 3
    mov rax, [rsi]
    mul qword [rbx + j*8]
    add rax, r8
    adc rdx, 0
    mov [r12 + j*8], rax
    mov r8, rdx
%assign j j+1
%endrep
    mov [r12 + 32], r8

    ; Rows 1..3 accumulate.
%assign i 1
%rep 3
    xor r9, r9
  %assign j 0
  %rep 4
    mov rax, [rsi + i*8]
    mul qword [rbx + j*8]
    add rax, r9
    adc rdx, 0
    add [r12 + (i+j)*8], rax
    adc rdx, 0
    mov r9, rdx
  %assign j j+1
  %endrep
    mov [r12 + (i+4)*8], r9
%assign i i+1
%endrep

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_mul_5x5 — RDI = 10-limb product, RSI = a (5 limbs), RDX = b (5 limbs).
;
; Internal helper for Barrett; the quotient estimate and mu are both 5 limbs.
; -----------------------------------------------------------------------------
align 32
bn256_mul_5x5:
    push rbx
    push r12

    mov rbx, rdx
    mov r12, rdi

    mov rax, [rsi]
    mul qword [rbx]
    mov [r12], rax
    mov r8, rdx

%assign j 1
%rep 4
    mov rax, [rsi]
    mul qword [rbx + j*8]
    add rax, r8
    adc rdx, 0
    mov [r12 + j*8], rax
    mov r8, rdx
%assign j j+1
%endrep
    mov [r12 + 40], r8

%assign i 1
%rep 4
    xor r9, r9
  %assign j 0
  %rep 5
    mov rax, [rsi + i*8]
    mul qword [rbx + j*8]
    add rax, r9
    adc rdx, 0
    add [r12 + (i+j)*8], rax
    adc rdx, 0
    mov r9, rdx
  %assign j j+1
  %endrep
    mov [r12 + (i+5)*8], r9
%assign i i+1
%endrep

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_barrett — reduce a 512-bit value modulo a 256-bit modulus.
;
; Inputs:
;   RDI = 4-limb output
;   RSI = 8-limb input
;   RDX = 4-limb modulus m
;   RCX = 5-limb mu = floor(2^512 / m)
;
;   q3 = floor( floor(x / 2^192) * mu / 2^320 )
;   r  = (x - q3 * m) mod 2^320, then subtract m while it fits
;
; Barrett's estimate is never too large and short by at most two, so the
; correction only ever subtracts. Three passes are run because two is the
; proven bound and the third costs nothing; stopping early would leave results
; in [m, 3m) that look like valid field elements.
; -----------------------------------------------------------------------------
align 32
bn256_barrett:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 264                    ; q1[5]=0, q2[10]=40, r2[10]=120, r1[5]=200

    mov rbx, rdi                    ; out
    mov rbp, rsi                    ; x
    mov r14, rdx                    ; m
    mov r15, rcx                    ; mu

    ; q1 = x >> 192
%assign i 0
%rep 5
    mov rax, [rbp + (3 + i)*8]
    mov [rsp + i*8], rax
%assign i i+1
%endrep

    ; q2 = q1 * mu
    lea rdi, [rsp + 40]
    lea rsi, [rsp]
    mov rdx, r15
    call bn256_mul_5x5

    ; q3 = q2 >> 320, left in place at [rsp+80]; r2 = q3 * m
    lea rdi, [rsp + 120]
    lea rsi, [rsp + 80]
    mov rdx, r14
    call bn256_mul_5x4

    ; r1 = x mod 2^320
%assign i 0
%rep 5
    mov rax, [rbp + i*8]
    mov [rsp + 200 + i*8], rax
%assign i i+1
%endrep

    ; r = r1 - r2, modulo 2^320
    mov r8,  [rsp + 200]
    sub r8,  [rsp + 120]
    mov r9,  [rsp + 208]
    sbb r9,  [rsp + 128]
    mov r10, [rsp + 216]
    sbb r10, [rsp + 136]
    mov r11, [rsp + 224]
    sbb r11, [rsp + 144]
    mov r12, [rsp + 232]
    sbb r12, [rsp + 152]

%rep 3
    mov r13, r8
    sub r13, [r14]
    mov rax, r9
    sbb rax, [r14 + 8]
    mov rcx, r10
    sbb rcx, [r14 + 16]
    mov rdx, r11
    sbb rdx, [r14 + 24]
    mov rsi, r12
    sbb rsi, 0

    cmovnc r8, r13
    cmovnc r9, rax
    cmovnc r10, rcx
    cmovnc r11, rdx
    cmovnc r12, rsi
%endrep

    mov [rbx], r8
    mov [rbx + 8], r9
    mov [rbx + 16], r10
    mov [rbx + 24], r11

    add rsp, 264
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_mul_5x4 — RDI = 9-limb product, RSI = a (5 limbs), RDX = b (4 limbs).
; -----------------------------------------------------------------------------
align 32
bn256_mul_5x4:
    push rbx
    push r12

    mov rbx, rdx
    mov r12, rdi

    mov rax, [rsi]
    mul qword [rbx]
    mov [r12], rax
    mov r8, rdx

%assign j 1
%rep 3
    mov rax, [rsi]
    mul qword [rbx + j*8]
    add rax, r8
    adc rdx, 0
    mov [r12 + j*8], rax
    mov r8, rdx
%assign j j+1
%endrep
    mov [r12 + 32], r8

%assign i 1
%rep 4
    xor r9, r9
  %assign j 0
  %rep 4
    mov rax, [rsi + i*8]
    mul qword [rbx + j*8]
    add rax, r9
    adc rdx, 0
    add [r12 + (i+j)*8], rax
    adc rdx, 0
    mov r9, rdx
  %assign j j+1
  %endrep
    mov [r12 + (i+4)*8], r9
%assign i i+1
%endrep

    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_mulmod — RDI = r, RSI = a, RDX = b, RCX = modulus, R8 = mu.
; -----------------------------------------------------------------------------
align 32
bn256_mulmod:
    push rbx
    push r12
    push r13
    sub rsp, 64                     ; 512-bit product

    mov rbx, rdi
    mov r12, rcx
    mov r13, r8

    mov rdi, rsp
    call bn256_mul_512

    mov rdi, rbx
    mov rsi, rsp
    mov rdx, r12
    mov rcx, r13
    call bn256_barrett

    add rsp, 64
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_addmod — RDI = r, RSI = a, RDX = b, RCX = modulus.
;
; Inputs must already be reduced, so the sum is below 2m and one conditional
; subtraction suffices. The carry out of the top limb has to be carried into
; that decision: a sum that overflowed 256 bits is certainly at least m even
; when its low 256 bits compare as smaller.
; -----------------------------------------------------------------------------
align 32
bn256_addmod:
    push rbx
    push r12

    mov r8,  [rsi]
    add r8,  [rdx]
    mov r9,  [rsi + 8]
    adc r9,  [rdx + 8]
    mov r10, [rsi + 16]
    adc r10, [rdx + 16]
    mov r11, [rsi + 24]
    adc r11, [rdx + 24]
    setc bl                         ; The sum did not fit in 256 bits

    ; Both operands are dead from here, so RSI and RDX are free scratch.
    mov rax, r8
    sub rax, [rcx]
    mov rsi, r9
    sbb rsi, [rcx + 8]
    mov rdx, r10
    sbb rdx, [rcx + 16]
    mov r12, r11
    sbb r12, [rcx + 24]
    setnc bh                        ; The sum was at least the modulus

    ; Subtract if the sum overflowed OR reached the modulus. Testing only the
    ; comparison misses the overflow case, where the true sum exceeds the
    ; modulus but its low 256 bits compare as smaller.
    or bl, bh
    jz .keep

    mov r8, rax
    mov r9, rsi
    mov r10, rdx
    mov r11, r12
.keep:
    pop r12

    mov [rdi], r8
    mov [rdi + 8], r9
    mov [rdi + 16], r10
    mov [rdi + 24], r11

    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_submod — RDI = r, RSI = a, RDX = b, RCX = modulus.
; -----------------------------------------------------------------------------
align 32
bn256_submod:
    push rbx
    push r12
    push r13

    mov r8,  [rsi]
    sub r8,  [rdx]
    mov r9,  [rsi + 8]
    sbb r9,  [rdx + 8]
    mov r10, [rsi + 16]
    sbb r10, [rdx + 16]
    mov r11, [rsi + 24]
    sbb r11, [rdx + 24]

    ; On borrow the result is a - b + 2^256; adding the modulus back lands it
    ; in range, because both operands were already reduced.
    sbb rax, rax                    ; 0 or -1

    ; The masking is done UP FRONT, before the add chain begins. AND writes the
    ; flags, so masking between an ADD and its following ADC clears the carry
    ; and loses it — which shows up only as an occasional off-by-one in a
    ; middle limb, on the minority of inputs that actually carry that far.
    mov rbx, [rcx]
    and rbx, rax
    mov r12, [rcx + 8]
    and r12, rax
    mov r13, [rcx + 16]
    and r13, rax
    mov rsi, [rcx + 24]
    and rsi, rax

    add r8, rbx
    adc r9, r12
    adc r10, r13
    adc r11, rsi

    mov [rdi], r8
    mov [rdi + 8], r9
    mov [rdi + 16], r10
    mov [rdi + 24], r11

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_powmod — RDI = r, RSI = base, RDX = 4-limb exponent,
;                RCX = modulus, R8 = mu.
;
; Square and multiply, most significant bit first. The exponents used here are
; fixed public constants (m - 2), so branching on their bits leaks nothing.
; -----------------------------------------------------------------------------
align 32
bn256_powmod:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 96                     ; acc, base, scratch

    mov r12, rdi                    ; result
    mov r13, rdx                    ; exponent
    mov r14, rcx                    ; modulus
    mov r15, r8                     ; mu

    lea rdi, [rsp + 32]
    call bn256_copy                 ; base

    ; acc = 1
    lea rdi, [rsp]
    mov qword [rdi], 1
    xor eax, eax
    mov [rdi + 8], rax
    mov [rdi + 16], rax
    mov [rdi + 24], rax

    mov ebp, 255
.bits:
    lea rdi, [rsp + 64]
    lea rsi, [rsp]
    lea rdx, [rsp]
    mov rcx, r14
    mov r8, r15
    call bn256_mulmod               ; scratch = acc^2
    lea rdi, [rsp]
    lea rsi, [rsp + 64]
    call bn256_copy

    mov ecx, ebp
    mov eax, ecx
    shr eax, 6
    and ecx, 63
    mov rbx, [r13 + rax*8]
    shr rbx, cl
    test rbx, 1
    jz .next

    lea rdi, [rsp + 64]
    lea rsi, [rsp]
    lea rdx, [rsp + 32]
    mov rcx, r14
    mov r8, r15
    call bn256_mulmod
    lea rdi, [rsp]
    lea rsi, [rsp + 64]
    call bn256_copy

.next:
    dec ebp
    jns .bits

    mov rdi, r12
    lea rsi, [rsp]
    call bn256_copy

    add rsp, 96
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; bn256_invmod — RDI = r, RSI = a, RDX = modulus - 2, RCX = modulus, R8 = mu.
;
; Fermat inversion, valid only for a prime modulus. Both p and n are prime, so
; it applies to each.
; -----------------------------------------------------------------------------
align 32
bn256_invmod:
    jmp bn256_powmod

%endif ; GUARD_CRYPTO_USIGN_ECDSA_BN256_ASM
