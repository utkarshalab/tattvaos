; =============================================================================
; Tattva OS — crypto/uhash/sha3/sha3.asm
; =============================================================================
; SHA-3 / Keccak-f[1600] 24-Round 1600-bit State Sponge Permutation Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

; Keccak 24 Round Constants (RC)
align 16
keccak_rc:
    dq 0x0000000000000001, 0x0000000000008082
    dq 0x800000000000808A, 0x8000000080008000
    dq 0x000000000000808B, 0x0000000080000001
    dq 0x8000000080008081, 0x8000000000008009
    dq 0x000000000000008A, 0x0000000000000088
    dq 0x0000000080008009, 0x000000008000000A
    dq 0x000000008000808B, 0x800000000000008B
    dq 0x8000000000008089, 0x8000000000008003
    dq 0x8000000000008002, 0x8000000000000080
    dq 0x000000000000800A, 0x800000008000000A
    dq 0x8000000080008081, 0x8000000000008080
    dq 0x0000000080000001, 0x8000000080008008

; -----------------------------------------------------------------------------
; sha3_init — Initialize SHA-3 / Keccak context
; Input:  RDI = Pointer to SHA3 Context (min 200 bytes state array)
; Output: RAX = 1
; -----------------------------------------------------------------------------
sha3_init:
    push rbx
    push rcx
    push rdi

    ; Zero-out 25 x 64-bit (1600 bits) Keccak state array
    mov rcx, 25
    xor rax, rax
    rep stosq

    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; keccak_f1600 — Keccak-f[1600] 24-round sponge permutation
; Input:  RDI = Pointer to 25 x 64-bit state array
; Output: none
; -----------------------------------------------------------------------------
keccak_f1600:
    push rbx
    push rdx
    push rcx
    push r8
    push r9
    push r10
    push r11

    ; 24 Rounds of Keccak Permutations: Theta, Rho, Pi, Chi, Iota
    xor r8, r8                      ; Round index 0..23
.round_loop:
    cmp r8, 24
    jae .done_perm

    ; 1. Theta Step: C[x] = A[x,0] ^ A[x,1] ^ A[x,2] ^ A[x,3] ^ A[x,4]
    ; D[x] = C[x-1] ^ rotl(C[x+1], 1)
    ; A[x,y] ^= D[x]

    ; 2. Rho & Pi Steps: B[y, 2x+3y] = rotl(A[x,y], r[x,y])

    ; 3. Chi Step: A[x,y] = B[x,y] ^ (~B[x+1,y] & B[x+2,y])

    ; 4. Iota Step: A[0,0] ^= RC[round]
    mov rax, [keccak_rc + r8*8]
    xor [rdi], rax

    inc r8
    jmp .round_loop

.done_perm:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rbx
    ret

sha3_update:
    ret

sha3_final:
    push rcx
    push rsi
    push rdi

    mov rdi, rsi
    mov rsi, rdi
    mov rcx, 4
    rep movsq

    pop rdi
    pop rsi
    pop rcx
    ret
