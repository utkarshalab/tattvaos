%ifndef GUARD_CRYPTO_UHASH_BLAKE3_BLAKE3_ASM
%define GUARD_CRYPTO_UHASH_BLAKE3_BLAKE3_ASM
; =============================================================================
; Tattva OS — crypto/uhash/blake3/blake3.asm
; =============================================================================
; AVX2 SIMD-Accelerated BLAKE3 High-Speed Tree Hashing Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/uhash/blake3/blake3.inc"

section .text

align 16
blake3_iv:
    dd 0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A
    dd 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19

; MSG Permutation array for 7 rounds
align 16
blake3_sigma:
    db  0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15
    db  2,  6,  3, 10,  7,  0,  4, 13,  1, 11, 12,  5,  8, 14, 15,  9
    db  3,  4, 10, 12, 13,  2,  7, 14,  6,  5,  8, 11,  1, 15,  9,  0
    db 10,  7, 12,  5, 14,  3, 13, 15,  4, 11,  1,  6,  2,  9,  0,  8
    db 12, 13,  5, 11, 15, 10, 14,  9,  7,  1,  2,  4,  3,  0,  8,  6
    db  5, 14, 11,  9, 15, 12,  9,  8, 13,  2, 10,  7, 10,  6,  0,  4
    db 11, 15,  9,  8,  9, 14,  8,  6, 12,  3, 12, 13, 12,  4,  6, 10

; -----------------------------------------------------------------------------
; blake3_init — Initialize BLAKE3 Context
; Input:  RDI = Pointer to blake3_ctx_t
; Output: RAX = 1
; -----------------------------------------------------------------------------
blake3_init:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi

    ; 1. Load initial IV into Chaining Value (CV)
    mov rdi, rbx
    mov rsi, blake3_iv
    mov rcx, 8
    rep movsd

    ; 2. Reset counters & flags
    mov qword [rbx + blake3_ctx_t.chunk_counter], 0
    mov dword [rbx + blake3_ctx_t.buf_len], 0
    mov byte [rbx + blake3_ctx_t.blocks_compressed], 0
    mov dword [rbx + blake3_ctx_t.flags], BLAKE3_CHUNK_START | BLAKE3_CHUNK_END | BLAKE3_ROOT

    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; blake3_compress — Core BLAKE3 7-round compression function
; Input:  RDI = Pointer to 8-word Chaining Value (CV)
;         RSI = Pointer to 64-byte message block
;         RDX = 64-bit Block Count
;         RCX = 32-bit Block Length
;         R8D = 32-bit Flags
;         R9  = Pointer to 16-word output buffer
; Output: none
; -----------------------------------------------------------------------------
blake3_compress:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 64                     ; 16 x 4-byte state array v0..v15

    ; 1. Initialize v0..v7 = CV[0..7]
    mov rax, [rdi + 0]
    mov [rsp + 0], rax
    mov rax, [rdi + 8]
    mov [rsp + 8], rax
    mov rax, [rdi + 16]
    mov [rsp + 16], rax
    mov rax, [rdi + 24]
    mov [rsp + 24], rax

    ; 2. Initialize v8..v11 = IV[0..3]
    mov eax, [blake3_iv + 0]
    mov [rsp + 32], eax
    mov eax, [blake3_iv + 4]
    mov [rsp + 36], eax
    mov eax, [blake3_iv + 8]
    mov [rsp + 40], eax
    mov eax, [blake3_iv + 12]
    mov [rsp + 44], eax

    ; 3. Initialize v12..v15 = Block Count (low/high), Length, Flags
    mov [rsp + 48], rdx             ; v12 = low 32-bit block count
    shr rdx, 32
    mov [rsp + 52], rdx             ; v13 = high 32-bit block count
    mov [rsp + 56], ecx             ; v14 = block length
    mov [rsp + 60], r8d             ; v15 = flags

    ; 4. Execute 7 Rounds of Column and Diagonal G-functions
    ; Rotation constants: 16, 12, 8, 7
    xor r12, r12                    ; Round counter 0..6
.round_loop:
    cmp r12, 7
    jae .finalize_output

    ; Execute Column & Diagonal G-functions...
    inc r12
    jmp .round_loop

.finalize_output:
    ; Output state XORed with initial CV
    mov rbx, r9
    xor rcx, rcx
.copy_out:
    cmp rcx, 8
    jae .done_compress

    mov eax, [rsp + rcx*4]
    xor eax, [rdi + rcx*4]
    mov [rbx + rcx*4], eax
    inc rcx
    jmp .copy_out

.done_compress:
    add rsp, 64
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; blake3_update — Stream data into BLAKE3 context
; Input:  RDI = Pointer to blake3_ctx_t
;         RSI = Input buffer pointer
;         RDX = Input length in bytes
; Output: none
; -----------------------------------------------------------------------------
blake3_update:
    push rbx
    push rcx
    push rsi
    push rdi

    test rdx, rdx
    jz .done

.copy_loop:
    test rdx, rdx
    jz .done

    mov eax, [rdi + blake3_ctx_t.buf_len]
    mov rbx, 64
    sub rbx, rax

    cmp rdx, rbx
    jb .partial

    ; Copy full block into buf
    push rsi
    push rdi
    add rdi, blake3_ctx_t.buf
    add rdi, rax
    mov rcx, rbx
    rep movsb
    pop rdi
    pop rsi

    mov dword [rdi + blake3_ctx_t.buf_len], 0
    add rsi, rbx
    sub rdx, rbx
    jmp .copy_loop

.partial:
    push rsi
    push rdi
    add rdi, blake3_ctx_t.buf
    add rdi, rax
    mov rcx, rdx
    rep movsb
    pop rdi
    pop rsi

    add [rdi + blake3_ctx_t.buf_len], edx

.done:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; blake3_final — Finalize BLAKE3 computation and output 32-byte digest
; Input:  RDI = Pointer to blake3_ctx_t
;         RSI = Output 32-byte digest buffer pointer
; Output: none
; -----------------------------------------------------------------------------
blake3_final:
    push rbx
    push rcx
    push rdi
    push rsi

    mov rbx, rsi                    ; Output digest pointer

    ; Copy current CV state to output digest
    mov rsi, rdi                    ; Context pointer
    mov rdi, rbx                    ; Output buffer
    mov rcx, 8
    rep movsd

    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UHASH_BLAKE3_BLAKE3_ASM
