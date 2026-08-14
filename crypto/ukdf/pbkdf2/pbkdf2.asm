%ifndef GUARD_CRYPTO_UKDF_PBKDF2_ASM
%define GUARD_CRYPTO_UKDF_PBKDF2_ASM
; =============================================================================
; Tattva OS — crypto/ukdf/pbkdf2/pbkdf2.asm
; =============================================================================
; PBKDF2-HMAC-SHA256 (RFC 8018 / NIST SP 800-132).
;
; Implements:
;   - Full derivation over arbitrary output lengths (`pbkdf2_sha256`)
;   - Single block function F (`pbkdf2_sha256_block`)
;
;   DK   = T(1) || T(2) || ... || T(n)
;   T(i) = U(1) XOR U(2) XOR ... XOR U(c)
;   U(1) = HMAC(P, S || INT_BE32(i))
;   U(j) = HMAC(P, U(j-1))
;
; The XOR fold across every iteration is what forces an attacker to run the
; whole chain. Keeping only the final U — a common misimplementation — makes
; the result computable in the same time but destroys the chaining property the
; construction is built on.
;
; The block index is appended BIG-ENDIAN. Getting that wrong produces a KDF
; that is self-consistent but incompatible with every other implementation,
; which surfaces only when credentials must move between systems.
;
; NOT MEMORY-HARD. PBKDF2 resists CPU brute force but parallelises almost
; perfectly on GPUs and ASICs, because each guess needs negligible RAM.
; Argon2id is the preferred stretch function for crypto/upass; this exists
; because it is buildable and verifiable today on primitives that work, and
; a real PBKDF2 is far better than a stubbed Argon2id that computes nothing.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%define PBKDF2_HASH_LEN     32          ; SHA-256 output
%define PBKDF2_MAX_SALT     64

section .data
align 64
pbkdf2_u:           times 32 db 0       ; Running U(j)
pbkdf2_t:           times 32 db 0       ; Accumulated XOR fold
pbkdf2_saltblk:     times PBKDF2_MAX_SALT + 4 db 0

section .text

global pbkdf2_sha256
global pbkdf2_sha256_block

; -----------------------------------------------------------------------------
; pbkdf2_sha256_block
;
; Computes one output block T(i).
;
; Inputs:
;   RDI = Password pointer
;   ESI = Password length
;   RDX = Salt pointer
;   ECX = Salt length (<= PBKDF2_MAX_SALT)
;   R8D = Iteration count (>= 1)
;   R9D = Block index i (1-based)
;   [rsp+8] is not used; output goes to pbkdf2_t
;
; Returns:
;   RAX = 0 on success, -1 on a bad argument
; -----------------------------------------------------------------------------
align 32
pbkdf2_sha256_block:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov [rsp], rdi                  ; Password
    mov [rsp + 8], rsi              ; Password length
    mov r12, rdx                    ; Salt
    mov r13d, ecx                   ; Salt length
    mov r14d, r8d                   ; Iterations
    mov r15d, r9d                   ; Block index

    cmp r13d, PBKDF2_MAX_SALT
    ja .bl_inval
    test r14d, r14d
    jz .bl_inval

    ; ---- Build salt || INT_BE32(i) ----
    lea rdi, [pbkdf2_saltblk]
    mov rsi, r12
    mov ecx, r13d
    rep movsb

    mov eax, r15d
    bswap eax                       ; Big-endian block index
    lea rdi, [pbkdf2_saltblk]
    mov dword [rdi + r13], eax

    ; ---- U(1) = HMAC(P, salt || i) ----
    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [pbkdf2_saltblk]
    mov ecx, r13d
    add ecx, 4
    lea r8, [pbkdf2_u]
    call hmac_sha256

    ; T = U(1)
    lea rdi, [pbkdf2_t]
    lea rsi, [pbkdf2_u]
    mov rcx, 4
    rep movsq

    ; ---- U(j) = HMAC(P, U(j-1)), folding each into T ----
    mov ebx, 1                      ; Iterations completed

.bl_iter:
    cmp ebx, r14d
    jae .bl_done

    mov rdi, [rsp]
    mov rsi, [rsp + 8]
    lea rdx, [pbkdf2_u]
    mov ecx, PBKDF2_HASH_LEN
    lea r8, [pbkdf2_u]
    call hmac_sha256

    ; T ^= U(j). The fold is what makes every iteration mandatory.
    lea rdi, [pbkdf2_t]
    lea rsi, [pbkdf2_u]
    mov rax, [rsi]
    xor [rdi], rax
    mov rax, [rsi + 8]
    xor [rdi + 8], rax
    mov rax, [rsi + 16]
    xor [rdi + 16], rax
    mov rax, [rsi + 24]
    xor [rdi + 24], rax

    inc ebx
    jmp .bl_iter

.bl_done:
    xor rax, rax
    jmp .bl_return

.bl_inval:
    mov rax, -1

.bl_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pbkdf2_sha256
;
; Derives an arbitrary-length key.
;
; Inputs:
;   RDI = Password pointer
;   ESI = Password length
;   RDX = Salt pointer
;   ECX = Salt length
;   R8D = Iteration count
;   R9  = Output buffer
;   [rsp+8 after prologue] = Output length in bytes
;
; Returns:
;   RAX = Bytes written, or -1 on a bad argument
; -----------------------------------------------------------------------------
align 32
pbkdf2_sha256:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64

    ; Sixth integer argument arrives on the stack, above the return address and
    ; the six registers pushed here.
    mov rax, [rsp + 64 + 48 + 8]
    mov [rsp + 32], rax             ; Output length

    mov [rsp], rdi                  ; Password
    mov [rsp + 8], rsi              ; Password length
    mov [rsp + 16], rdx             ; Salt
    mov [rsp + 24], rcx             ; Salt length
    mov r14d, r8d                   ; Iterations
    mov r15, r9                     ; Output

    test r15, r15
    jz .pk_inval
    mov rax, [rsp + 32]
    test rax, rax
    jz .pk_inval

    xor rbp, rbp                    ; Bytes emitted
    mov ebx, 1                      ; Block index, 1-based per the spec

.pk_loop:
    mov rax, [rsp + 32]
    cmp rbp, rax
    jae .pk_done

    mov rdi, [rsp]
    mov esi, dword [rsp + 8]
    mov rdx, [rsp + 16]
    mov ecx, dword [rsp + 24]
    mov r8d, r14d
    mov r9d, ebx
    call pbkdf2_sha256_block
    test rax, rax
    js .pk_inval

    ; Copy as much of T as still fits.
    mov rax, [rsp + 32]
    sub rax, rbp                    ; Bytes still wanted
    mov rcx, PBKDF2_HASH_LEN
    cmp rax, rcx
    jae .pk_copy
    mov rcx, rax

.pk_copy:
    lea rdi, [r15 + rbp]
    lea rsi, [pbkdf2_t]
    rep movsb

    mov rax, [rsp + 32]
    sub rax, rbp
    cmp rax, PBKDF2_HASH_LEN
    jbe .pk_final
    add rbp, PBKDF2_HASH_LEN
    inc ebx
    jmp .pk_loop

.pk_final:
    mov rbp, [rsp + 32]

.pk_done:
    ; Do not leave derived material resident.
    lea rdi, [pbkdf2_t]
    xor rax, rax
    mov rcx, 4
    rep stosq
    lea rdi, [pbkdf2_u]
    xor rax, rax
    mov rcx, 4
    rep stosq

    mov rax, rbp
    jmp .pk_return

.pk_inval:
    mov rax, -1

.pk_return:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UKDF_PBKDF2_ASM
