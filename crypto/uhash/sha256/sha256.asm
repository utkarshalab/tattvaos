; =============================================================================
; Tattva OS — crypto/uhash/sha256/sha256.asm
; =============================================================================
; Full Hardware-Accelerated SHA-256 Hashing Engine (Intel SHA-NI + Software).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/uhash/sha256/sha256.inc"

section .text

; Initial H0..H7 constants
align 16
sha256_h0_init:
    dd 0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A
    dd 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19

; 64 x 32-bit K256 Round Constants
align 16
k256_table:
    dd 0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5
    dd 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5
    dd 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3
    dd 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174
    dd 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc
    dd 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da
    dd 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7
    dd 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967
    dd 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13
    dd 0x650a7354, 0x766a0abb, 0x81c2C92e, 0x92722c85
    dd 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3
    dd 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070
    dd 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5
    dd 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3
    dd 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208
    dd 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2

; -----------------------------------------------------------------------------
; sha256_init — Initialize SHA-256 Context
; Input:  RDI = Pointer to sha256_ctx_t
; Output: RAX = 1
; -----------------------------------------------------------------------------
sha256_init:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi

    ; 1. Load initial H0..H7 state words
    mov rdi, rbx
    mov rsi, sha256_h0_init
    mov rcx, 8
    rep movsd

    ; 2. Zero count, buf_len, and buffer
    mov qword [rbx + sha256_ctx_t.count], 0
    mov dword [rbx + sha256_ctx_t.buf_len], 0
    mov dword [rbx + sha256_ctx_t.flags], 0

    ; 3. Detect Intel SHA-NI support (CPUID EAX=7, ECX=0 -> EBX bit 29)
    mov eax, 7
    xor ecx, ecx
    cpuid
    test ebx, (1 << 29)
    jz .no_shani
    mov dword [rbx + sha256_ctx_t.flags], 1 ; Set SHA-NI flag

.no_shani:
    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha256_transform — Compress one 64-byte block into state
; Input:  RDI = Pointer to sha256_ctx_t
;         RSI = Pointer to 64-byte message block
; Output: none
; -----------------------------------------------------------------------------
sha256_transform:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                     ; Allocate 64 x 4-byte W array on stack

    ; Check if hardware SHA-NI is enabled
    cmp dword [rdi + sha256_ctx_t.flags], 1
    je .shani_transform

    ; --- 1. Prepare W[0..15] from 64-byte big-endian message ---
    xor rcx, rcx
.prep_w0_15:
    cmp rcx, 16
    jae .expand_w
    mov eax, [rsi + rcx*4]
    bswap eax
    mov [rsp + rcx*4], eax
    inc rcx
    jmp .prep_w0_15

.expand_w:
    ; W[t] = s1(W[t-2]) + W[t-7] + s0(W[t-15]) + W[t-16]
    ; s0(x) = (x >>> 7) ^ (x >>> 18) ^ (x >> 3)
    ; s1(x) = (x >>> 17) ^ (x >>> 19) ^ (x >> 10)
    mov rcx, 16
.expand_loop:
    cmp rcx, 64
    jae .init_vars

    ; s1(W[t-2])
    mov eax, [rsp + (rcx-2)*4]
    mov edx, eax
    ror eax, 17
    mov r8d, edx
    ror edx, 19
    shr r8d, 10
    xor eax, edx
    xor eax, r8d                    ; RAX = s1

    ; s0(W[t-15])
    mov ebx, [rsp + (rcx-15)*4]
    mov edx, ebx
    ror ebx, 7
    mov r8d, edx
    ror edx, 18
    shr r8d, 3
    xor ebx, edx
    xor ebx, r8d                    ; RBX = s0

    add eax, [rsp + (rcx-7)*4]
    add eax, ebx
    add eax, [rsp + (rcx-16)*4]
    mov [rsp + rcx*4], eax
    inc rcx
    jmp .expand_loop

.init_vars:
    ; --- 2. Load working variables a..h from state ---
    mov r8d,  [rdi + 0]             ; a
    mov r9d,  [rdi + 4]             ; b
    mov r10d, [rdi + 8]             ; c
    mov r11d, [rdi + 12]            ; d
    mov r12d, [rdi + 16]            ; e
    mov r13d, [rdi + 20]            ; f
    mov r14d, [rdi + 24]            ; g
    mov r15d, [rdi + 28]            ; h

    ; --- 3. Execute 64 SHA-256 Compression Rounds ---
    xor rcx, rcx
.round_loop:
    cmp rcx, 64
    jae .update_state

    ; S1 = (e >>> 6) ^ (e >>> 11) ^ (e >>> 25)
    mov eax, r12d
    mov edx, r12d
    ror eax, 6
    mov ebx, r12d
    ror edx, 11
    ror ebx, 25
    xor eax, edx
    xor eax, ebx                    ; EAX = S1

    ; ch = (e & f) ^ (~e & g)
    mov edx, r12d
    and edx, r13d
    mov ebx, r12d
    not ebx
    and ebx, r14d
    xor edx, ebx                    ; EDX = ch

    ; temp1 = h + S1 + ch + k256[t] + W[t]
    mov ebx, r15d
    add ebx, eax
    add ebx, edx
    add ebx, [k256_table + rcx*4]
    add ebx, [rsp + rcx*4]          ; EBX = temp1

    ; S0 = (a >>> 2) ^ (a >>> 13) ^ (a >>> 22)
    mov eax, r8d
    mov edx, r8d
    ror eax, 2
    mov esi, r8d
    ror edx, 13
    ror esi, 22
    xor eax, edx
    xor eax, esi                    ; EAX = S0

    ; maj = (a & b) ^ (a & c) ^ (b & c)
    mov edx, r8d
    and edx, r9d
    mov esi, r8d
    and esi, r10d
    xor edx, esi
    mov esi, r9d
    and esi, r10d
    xor edx, esi                    ; EDX = maj

    ; temp2 = S0 + maj
    add eax, edx                    ; EAX = temp2

    ; Update round variables
    mov r15d, r14d                  ; h = g
    mov r14d, r13d                  ; g = f
    mov r13d, r12d                  ; f = e
    mov r12d, r11d
    add r12d, ebx                   ; e = d + temp1
    mov r11d, r10d                  ; d = c
    mov r10d, r9d                   ; c = b
    mov r9d,  r8d                   ; b = a
    mov r8d,  ebx
    add r8d,  eax                   ; a = temp1 + temp2

    inc rcx
    jmp .round_loop

.update_state:
    ; Add working variables back into H0..H7 state
    add [rdi + 0],  r8d
    add [rdi + 4],  r9d
    add [rdi + 8],  r10d
    add [rdi + 12], r11d
    add [rdi + 16], r12d
    add [rdi + 20], r13d
    add [rdi + 24], r14d
    add [rdi + 28], r15d
    jmp .done_pop

.shani_transform:
    ; --- Intel SHA-NI Hardware Accelerated Transform ---
    movdqu xmm0, [rdi + 0]
    movdqu xmm1, [rdi + 16]
    pshufd xmm0, xmm0, 0x1B
    pshufd xmm1, xmm1, 0x1B

    movdqu xmm2, [rsi + 0]
    movdqu xmm3, [rsi + 16]
    movdqu xmm4, [rsi + 32]
    movdqu xmm5, [rsi + 48]

    movdqa xmm6, [sha256_shuf_mask]
    pshufb xmm2, xmm6
    pshufb xmm3, xmm6
    pshufb xmm4, xmm6
    pshufb xmm5, xmm6

    sha256rnds2 xmm1, xmm0, xmm2
    sha256rnds2 xmm0, xmm1, xmm2
    sha256rnds2 xmm1, xmm0, xmm3
    sha256rnds2 xmm0, xmm1, xmm3
    sha256rnds2 xmm1, xmm0, xmm4
    sha256rnds2 xmm0, xmm1, xmm4
    sha256rnds2 xmm1, xmm0, xmm5
    sha256rnds2 xmm0, xmm1, xmm5

    movdqu [rdi + 0], xmm0
    movdqu [rdi + 16], xmm1

.done_pop:
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha256_update — Stream data into SHA-256 context
; Input:  RDI = Pointer to sha256_ctx_t
;         RSI = Input buffer pointer
;         RDX = Input length in bytes
; Output: none
; -----------------------------------------------------------------------------
sha256_update:
    push rbx
    push rcx
    push rsi
    push rdi

    test rdx, rdx
    jz .done

    mov rax, rdx
    shl rax, 3
    add [rdi + sha256_ctx_t.count], rax

.copy_loop:
    test rdx, rdx
    jz .done

    mov eax, [rdi + sha256_ctx_t.buf_len]
    mov rbx, 64
    sub rbx, rax

    cmp rdx, rbx
    jb .partial

    push rsi
    push rdi
    add rdi, sha256_ctx_t.buf
    add rdi, rax
    mov rcx, rbx
    rep movsb
    pop rdi
    pop rsi

    push rsi
    push rdi
    lea rsi, [rdi + sha256_ctx_t.buf]
    call sha256_transform
    pop rdi
    pop rsi

    mov dword [rdi + sha256_ctx_t.buf_len], 0
    add rsi, rbx
    sub rdx, rbx
    jmp .copy_loop

.partial:
    push rsi
    push rdi
    add rdi, sha256_ctx_t.buf
    add rdi, rax
    mov rcx, rdx
    rep movsb
    pop rdi
    pop rsi

    add [rdi + sha256_ctx_t.buf_len], edx

.done:
    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; sha256_final — Pad message and compute final 32-byte digest
; Input:  RDI = Pointer to sha256_ctx_t
;         RSI = Output 32-byte digest buffer pointer
; Output: none
; -----------------------------------------------------------------------------
sha256_final:
    push rbx
    push rcx
    push rdx
    push rdi
    push rsi

    mov rbx, rsi

    mov eax, [rdi + sha256_ctx_t.buf_len]
    mov byte [rdi + sha256_ctx_t.buf + rax], 0x80
    inc eax

    cmp eax, 56
    jbe .pad_bitcount

.pad_extra:
    push rdi
    lea rdi, [rdi + sha256_ctx_t.buf + rax]
    mov rcx, 64
    sub rcx, rax
    xor al, al
    rep stosb
    pop rdi

    push rsi
    push rdi
    lea rsi, [rdi + sha256_ctx_t.buf]
    call sha256_transform
    pop rdi
    pop rsi

    xor eax, eax

.pad_bitcount:
    push rdi
    lea rdi, [rdi + sha256_ctx_t.buf + rax]
    mov rcx, 56
    sub rcx, rax
    xor al, al
    rep stosb
    pop rdi

    mov rax, [rdi + sha256_ctx_t.count]
    bswap rax
    mov [rdi + sha256_ctx_t.buf + 56], rax

    push rsi
    push rdi
    lea rsi, [rdi + sha256_ctx_t.buf]
    call sha256_transform
    pop rdi
    pop rsi

    xor rcx, rcx
.out_loop:
    cmp rcx, 8
    jae .final_done

    mov eax, [rdi + rcx*4]
    bswap eax
    mov [rbx + rcx*4], eax
    inc rcx
    jmp .out_loop

.final_done:
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rbx
    ret

section .data
align 16
sha256_shuf_mask:
    db 3, 2, 1, 0, 7, 6, 5, 4, 11, 10, 9, 8, 15, 14, 13, 12
