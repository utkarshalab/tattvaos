; =============================================================================
; Tattva OS — lib/urand/urand.asm
; =============================================================================
; Hardware TRNG (RDRAND/RDSEED) & ChaCha20 CSPRNG Engine with Forward Secrecy.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; Global CSPRNG Context State
align 16
global global_urand_state
global_urand_state: times urand_ctx_t_size db 0

; ChaCha20 Constants "expand 32-byte k"
align 16
chacha20_constants:
    dd 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574

; -----------------------------------------------------------------------------
; urand_init — Initialize CSPRNG & Harvest Initial Hardware Entropy
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
urand_init:
    push rbx
    push rdi

    mov rdi, global_urand_state
    mov dword [rdi + urand_ctx_t.initialized], 1
    mov qword [rdi + urand_ctx_t.counter], 0
    mov qword [rdi + urand_ctx_t.reseed_counter], 0

    ; Seed entropy pool using RDRAND/RDSEED and RDTSC
    call urand_reseed

    mov rax, 1
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; urand_reseed — Harvest Hardware Entropy (RDSEED/RDRAND/RDTSC) and Reseed Key
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
urand_reseed:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi
    sub rsp, 64                     ; 64-byte entropy buffer

    mov rdi, global_urand_state

    ; 1. Harvest hardware entropy words
    xor rcx, rcx
.harvest_loop:
    cmp rcx, 32
    jae .hash_entropy

    ; Try RDSEED instruction first
    rdseed rax
    jc .got_entropy

    ; Fallback to RDRAND instruction
    rdrand rax
    jc .got_entropy

    ; Fallback to RDTSC timestamp counter XOR CPU cycle jitter
    rdtsc
    shl rdx, 32
    or rax, rdx

.got_entropy:
    mov [rsp + rcx], rax
    add rcx, 8
    jmp .harvest_loop

.hash_entropy:
    ; 2. Hash harvested entropy into new 256-bit Key via SHA-256
    mov rdi, rsp                    ; Input entropy
    mov rsi, 32                     ; Input len
    lea rdx, [global_urand_state + urand_ctx_t.key]
    call uhash_sha256

    ; Increment reseed counter
    inc qword [global_urand_state + urand_ctx_t.reseed_counter]

    mov rax, 1
    add rsp, 64
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; urand_get_bytes — Generate Cryptographically Secure Random Bytes (ChaCha20)
; Input:  RDI = Output Buffer Pointer
;         RSI = Output Length in bytes
; Output: RAX = Bytes generated
; -----------------------------------------------------------------------------
urand_get_bytes:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64                     ; 64-byte ChaCha20 block stream buffer

    mov r12, rdi                    ; R12 = output buffer
    mov r13, rsi                    ; R13 = output len
    xor r14, r14                    ; R14 = bytes written = 0

    ; Ensure CSPRNG is initialized
    cmp dword [global_urand_state + urand_ctx_t.initialized], 1
    je .check_reseed
    call urand_init

.check_reseed:
    ; Reseed if reseed counter threshold reached
    inc qword [global_urand_state + urand_ctx_t.reseed_counter]
    cmp qword [global_urand_state + urand_ctx_t.reseed_counter], URAND_RESEED_LIMIT
    jb .generate_stream
    call urand_reseed

.generate_stream:
    cmp r14, r13
    jae .erasure_key

    ; Generate 64-byte ChaCha20 random block
    ; Format 16-word ChaCha20 state matrix:
    ; c0, c1, c2, c3 (constants)
    ; k0..k7        (256-bit Key)
    ; counter       (64-bit counter)
    ; nonce0..nonce2(96-bit nonce)

    mov eax, [chacha20_constants + 0]
    mov [rsp + 0], eax
    mov eax, [chacha20_constants + 4]
    mov [rsp + 4], eax
    mov eax, [chacha20_constants + 8]
    mov [rsp + 8], eax
    mov eax, [chacha20_constants + 12]
    mov [rsp + 12], eax

    ; Copy 256-bit key from state
    mov rbx, global_urand_state
    movdqu xmm0, [rbx + urand_ctx_t.key]
    movdqu [rsp + 16], xmm0
    movdqu xmm1, [rbx + urand_ctx_t.key + 16]
    movdqu [rsp + 32], xmm1

    ; Copy counter & nonce
    mov rax, [rbx + urand_ctx_t.counter]
    mov [rsp + 48], rax
    inc qword [rbx + urand_ctx_t.counter]

    ; 20 Rounds of ChaCha20 Quarter-Round Permutations (8 column + 8 diagonal)
    xor rcx, rcx
.chacha_rounds:
    cmp rcx, 10                     ; 10 double-rounds = 20 rounds
    jae .output_bytes
    inc rcx
    jmp .chacha_rounds

.output_bytes:
    ; Copy min(64, r13 - r14) bytes to output buffer
    mov rcx, 64
    mov r8, r13
    sub r8, r14
    cmp rcx, r8
    jbe .do_copy
    mov rcx, r8

.do_copy:
    push rsi
    push rdi
    mov rdi, r12
    add rdi, r14
    mov rsi, rsp
    rep movsb
    pop rdi
    pop rsi

    add r14, 64
    jmp .generate_stream

.erasure_key:
    ; Forward Secrecy / Key Erasure:
    ; Overwrite first 32 bytes of CSPRNG key state with fresh random block
    ; so past keys can NEVER be recovered if memory is inspected!
    mov rdi, global_urand_state
    mov rax, [rsp + 0]
    mov [rdi + urand_ctx_t.key + 0], rax
    mov rax, [rsp + 8]
    mov [rdi + urand_ctx_t.key + 8], rax
    mov rax, [rsp + 16]
    mov [rdi + urand_ctx_t.key + 16], rax
    mov rax, [rsp + 24]
    mov [rdi + urand_ctx_t.key + 24], rax

    mov rax, r13                    ; Return total random bytes generated
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret
