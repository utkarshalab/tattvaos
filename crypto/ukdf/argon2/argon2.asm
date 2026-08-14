%ifndef GUARD_CRYPTO_UKDF_ARGON2_ARGON2_ASM
%define GUARD_CRYPTO_UKDF_ARGON2_ARGON2_ASM
; =============================================================================
; Tattva OS — crypto/ukdf/argon2/argon2.asm
; =============================================================================
; Argon2id (RFC 9106) — memory-hard password hashing.
;
; Implements:
;   - Full parameterised hash (`argon2id_hash_ex`)
;   - Fixed-policy convenience wrapper (`argon2id_hash`)
;   - Variable-length hash H' (`argon2_h_prime`)
;   - The compression function G (`argon2_fill_block`)
;
; WHY MEMORY-HARDNESS IS THE WHOLE POINT. An iterated hash like PBKDF2 costs an
; attacker only time, and time is the one resource a GPU or ASIC buys cheaply —
; thousands of cores each running the same tiny loop. Argon2 forces every guess
; to occupy megabytes of memory that must be written, re-read in a
; data-dependent order, and kept live for the duration. Silicon area for RAM
; does not shrink the way arithmetic does, so an attacker's advantage collapses
; from "thousands of guesses in parallel" to "as many as I have memory for".
;
; THE id VARIANT IS THE ONE TO USE. Argon2d indexes memory using the data
; itself, which is fastest to defend against GPUs but leaks the access pattern
; to anyone who can observe cache timing — and a password hash is exactly the
; thing a co-resident attacker wants to watch. Argon2i indexes independently of
; the data, defeating that side channel, but is measurably weaker against
; time-memory tradeoff attacks. Argon2id uses independent addressing for the
; first half of the first pass, where side-channel exposure is real, and
; data-dependent addressing afterwards, where the attacker would already need
; the secret to make use of it.
;
; G IS NOT BLAKE2b's G. It replaces each modular addition with
; fBlaMka(x, y) = x + y + 2 * lo32(x) * lo32(y). The multiplication is there to
; impose latency that cannot be optimised away — it makes each step depend on a
; multiplier, which is the expensive unit to replicate in hardware. Using
; BLAKE2b's plain G here assembles and produces plausible-looking output while
; discarding most of the ASIC resistance the design exists to provide.
;
; MEMORY COMES FROM A STATIC ARENA. There is no allocator to call at this level,
; and a password hash that can fail on allocation is a password hash that fails
; open under memory pressure. The arena is sized at build time and the requested
; cost is clamped to it.
;
; NOT REENTRANT. The arena and the addressing scratch blocks are shared state.
; Password verification is serialised by the caller; concurrent use would have
; two hashes overwriting each other's memory and both would be wrong.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%define ARGON2_BLOCK_SIZE       1024
%define ARGON2_QWORDS_IN_BLOCK  128
%define ARGON2_ADDRESSES        128     ; (J1,J2) pairs per address block
%define ARGON2_SYNC_POINTS      4       ; Slices per pass
%define ARGON2_VERSION          0x13
%define ARGON2_TYPE_D           0
%define ARGON2_TYPE_I           1
%define ARGON2_TYPE_ID          2

; Build-time ceiling on the arena: 32 MiB. Raising this costs only BSS, but a
; unikernel image reserves it unconditionally, so it is a deliberate choice
; rather than the largest number that fits.
%define ARGON2_MAX_KIB          32768
%define ARGON2_MAX_BLOCKS       ARGON2_MAX_KIB

; Defaults for the fixed-policy wrapper. RFC 9106's second recommended option
; is t=3, m=64 MiB, p=4; this halves the memory to stay inside the arena and
; keeps a single lane, since a kernel password check has no threads to spread
; across and extra lanes without parallelism only weaken the dependency chain.
%define ARGON2_DEFAULT_M_COST   16384   ; 16 MiB
%define ARGON2_DEFAULT_T_COST   3
%define ARGON2_DEFAULT_LANES    1

%define ARGON2_OK               0
%define ARGON2_ERR_PARAM        -1
%define ARGON2_ERR_MEMORY       -2

struc argon2_params_t
    .pwd:        resq 1
    .salt:       resq 1
    .secret:     resq 1     ; Optional pepper, folded into H0
    .ad:         resq 1     ; Optional associated data
    .out:        resq 1
    .pwdlen:     resd 1
    .saltlen:    resd 1
    .secretlen:  resd 1
    .adlen:      resd 1
    .outlen:     resd 1
    .m_cost:     resd 1     ; KiB
    .t_cost:     resd 1     ; Passes
    .lanes:      resd 1
endstruc

section .bss
alignb 64

argon2_memory:      resb ARGON2_MAX_BLOCKS * ARGON2_BLOCK_SIZE

a2_zero_block:      resb ARGON2_BLOCK_SIZE
a2_input_block:     resb ARGON2_BLOCK_SIZE
a2_addr_block:      resb ARGON2_BLOCK_SIZE
a2_h0:              resb 72         ; H0 (64) + LE32 index + LE32 lane
a2_ctx:             resb blake2b_ctx_t_size
a2_scratch:         resb 64

; Instance state. Held here rather than in registers because the fill loop
; already needs every callee-saved register it has.
a2_lanes:           resd 1
a2_m_prime:         resd 1          ; Total blocks after rounding
a2_lane_len:        resd 1
a2_seg_len:         resd 1
a2_passes:          resd 1
a2_pass:            resd 1
a2_slice:           resd 1
a2_lane:            resd 1
a2_index:           resd 1

section .text

global argon2id_hash
global argon2id_hash_ex
global argon2_h_prime
global argon2_fill_block
global argon2_generate_salt

; -----------------------------------------------------------------------------
; A2_G — Argon2's G, four 64-bit words at byte offsets %1..%4 from RBX.
;
; Structurally BLAKE2b's G with no message words and with every addition
; replaced by fBlaMka. Clobbers RAX, RCX, R8..R11.
; -----------------------------------------------------------------------------
%macro A2_FBLAMKA 2                 ; %1 += %2 + 2*lo32(%1)*lo32(%2)
    mov  eax, %1 %+ d
    mov  ecx, %2 %+ d
    imul rax, rcx                   ; Both zero-extended from 32 bits, so the
    add  rax, rax                   ; 64-bit low product is the exact value
    add  %1, %2
    add  %1, rax
%endmacro

%macro A2_G 4
    mov  r8,  [rbx + %1]            ; a
    mov  r9,  [rbx + %2]            ; b
    mov  r10, [rbx + %4]            ; d
    mov  r11, [rbx + %3]            ; c

    A2_FBLAMKA r8, r9
    xor  r10, r8
    ror  r10, 32
    A2_FBLAMKA r11, r10
    xor  r9, r11
    ror  r9, 24

    A2_FBLAMKA r8, r9
    xor  r10, r8
    ror  r10, 16
    A2_FBLAMKA r11, r10
    xor  r9, r11
    ror  r9, 63

    mov  [rbx + %1], r8
    mov  [rbx + %2], r9
    mov  [rbx + %3], r11
    mov  [rbx + %4], r10
%endmacro

; Sixteen words, eight G operations: four "columns" then four "diagonals".
%macro A2_ROUND 16
    A2_G %1, %5, %9,  %13
    A2_G %2, %6, %10, %14
    A2_G %3, %7, %11, %15
    A2_G %4, %8, %12, %16
    A2_G %1, %6, %11, %16
    A2_G %2, %7, %12, %13
    A2_G %3, %8, %9,  %14
    A2_G %4, %5, %10, %15
%endmacro

; -----------------------------------------------------------------------------
; argon2_fill_block — the compression function G(prev, ref) -> next.
;
; Inputs:
;   RDI = Previous block (1024 bytes)
;   RSI = Reference block
;   RDX = Output block
;   ECX = Nonzero to XOR into the existing output instead of overwriting
;
; R = prev XOR ref is permuted by sixteen rounds — eight over the rows of the
; 8x8 matrix of 16-byte cells, then eight over its columns — and the result is
; XORed back with the unpermuted R. That final XOR is what makes the function
; non-invertible; without it an attacker could walk the memory graph backwards
; and the whole structure would collapse.
;
; From version 0x13 onward, passes after the first XOR into the existing block
; rather than replacing it, so a later pass cannot discard the work of an
; earlier one.
;
; Aliasing ref == next is safe: R is copied out before anything is written back.
; -----------------------------------------------------------------------------
align 32
argon2_fill_block:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 2 * ARGON2_BLOCK_SIZE  ; [rsp] = R, [rsp+1024] = R_original

    mov r12, rdx                    ; next
    mov r13d, ecx                   ; with_xor
    mov rbp, rsp

    ; R = ref ^ prev, and keep an untouched copy.
    xor ecx, ecx
.mix:
    mov rax, [rsi + rcx*8]
    xor rax, [rdi + rcx*8]
    mov [rbp + rcx*8], rax
    mov [rbp + ARGON2_BLOCK_SIZE + rcx*8], rax
    inc ecx
    cmp ecx, ARGON2_QWORDS_IN_BLOCK
    jb .mix

    test r13d, r13d
    jz .permute

    ; Fold the existing output into the saved copy, so the final XOR carries it.
    xor ecx, ecx
.absorb:
    mov rax, [r12 + rcx*8]
    xor [rbp + ARGON2_BLOCK_SIZE + rcx*8], rax
    inc ecx
    cmp ecx, ARGON2_QWORDS_IN_BLOCK
    jb .absorb

.permute:
    mov rbx, rbp

    ; Eight rounds over rows: words 16i .. 16i+15.
%assign i 0
%rep 8
    A2_ROUND (i*128 +  0), (i*128 +  8), (i*128 + 16), (i*128 + 24), \
             (i*128 + 32), (i*128 + 40), (i*128 + 48), (i*128 + 56), \
             (i*128 + 64), (i*128 + 72), (i*128 + 80), (i*128 + 88), \
             (i*128 + 96), (i*128 +104), (i*128 +112), (i*128 +120)
%assign i i+1
%endrep

    ; Eight rounds over columns: words 2i, 2i+1, 2i+16, 2i+17, ... 2i+113.
    ; Rows alone would leave the eight 128-byte strips independent, and the
    ; block would be eight small permutations rather than one large one.
%assign i 0
%rep 8
    A2_ROUND (i*16 +   0), (i*16 +   8), (i*16 + 128), (i*16 + 136), \
             (i*16 + 256), (i*16 + 264), (i*16 + 384), (i*16 + 392), \
             (i*16 + 512), (i*16 + 520), (i*16 + 640), (i*16 + 648), \
             (i*16 + 768), (i*16 + 776), (i*16 + 896), (i*16 + 904)
%assign i i+1
%endrep

    ; next = R_permuted ^ R_original
    xor ecx, ecx
.store:
    mov rax, [rbp + rcx*8]
    xor rax, [rbp + ARGON2_BLOCK_SIZE + rcx*8]
    mov [r12 + rcx*8], rax
    inc ecx
    cmp ecx, ARGON2_QWORDS_IN_BLOCK
    jb .store

    add rsp, 2 * ARGON2_BLOCK_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; argon2_h_prime — the variable-length hash H'.
;
; Inputs:
;   RDI = Output buffer
;   ESI = Output length in bytes (may exceed 64)
;   RDX = Input pointer
;   ECX = Input length
;
; For outputs of 64 bytes or fewer this is just BLAKE2b with the length
; prefixed. Beyond that it chains 64-byte digests, emitting the first 32 bytes
; of each and the whole of the last. Emitting only half of each link is what
; keeps the chain from being unrolled: recovering block k requires the full
; digest at k, which is never exposed.
;
; The length is hashed as a prefix in both branches. Without it, H'(x, 32) would
; be a prefix of H'(x, 64), and the initial blocks of two differently-sized
; Argon2 instances would share structure.
; -----------------------------------------------------------------------------
align 32
argon2_h_prime:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 80                     ; [rsp] = LE32 length, [rsp+16] = digest

    mov r12, rdi                    ; out
    mov r13d, esi                   ; outlen
    mov r14, rdx                    ; in
    mov r15d, ecx                   ; inlen

    mov [rsp], r13d

    cmp r13d, 64
    ja .long

    ; ---- Short form ----
    lea rdi, [a2_ctx]
    mov esi, r13d
    call blake2b_init

    lea rdi, [a2_ctx]
    mov rsi, rsp
    mov edx, 4
    call blake2b_update

    lea rdi, [a2_ctx]
    mov rsi, r14
    mov edx, r15d
    call blake2b_update

    lea rdi, [a2_ctx]
    mov rsi, r12
    call blake2b_final
    jmp .done

.long:
    ; V1 = BLAKE2b-512(LE32(outlen) || in)
    lea rdi, [a2_ctx]
    mov esi, 64
    call blake2b_init

    lea rdi, [a2_ctx]
    mov rsi, rsp
    mov edx, 4
    call blake2b_update

    lea rdi, [a2_ctx]
    mov rsi, r14
    mov edx, r15d
    call blake2b_update

    lea rdi, [a2_ctx]
    lea rsi, [rsp + 16]
    call blake2b_final

    ; Emit the first 32 bytes, then chain.
    mov rdi, r12
    lea rsi, [rsp + 16]
    mov ecx, 32
    rep movsb
    mov r12, rdi                    ; Advance the output cursor

    mov ebx, r13d
    sub ebx, 32                     ; Bytes still to produce

.chain:
    cmp ebx, 64
    jbe .tail

    lea rdi, [a2_scratch]
    lea rsi, [rsp + 16]
    mov ecx, 64
    rep movsb

    lea rdi, [rsp + 16]
    mov esi, 64
    lea rdx, [a2_scratch]
    mov ecx, 64
    call blake2b_hash

    mov rdi, r12
    lea rsi, [rsp + 16]
    mov ecx, 32
    rep movsb
    mov r12, rdi

    sub ebx, 32
    jmp .chain

.tail:
    lea rdi, [a2_scratch]
    lea rsi, [rsp + 16]
    mov ecx, 64
    rep movsb

    mov rdi, r12
    mov esi, ebx
    lea rdx, [a2_scratch]
    mov ecx, 64
    call blake2b_hash

.done:
    add rsp, 80
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; argon2_index_alpha — pick the reference block within a lane.
;
; Inputs:
;   EDI = J1, the low 32 bits of the pseudo-random value
;   ESI = Nonzero when the reference lane is the current lane
;
; Reads a2_pass, a2_slice, a2_index, a2_seg_len, a2_lane_len.
;
; Returns:
;   EAX = Index within the reference lane
;
; The mapping squares J1 and takes the high half, twice. That is not a
; roundabout modulo — it deliberately biases selection toward RECENT blocks,
; which is what forces an attacker trading memory for computation to recompute
; long dependency chains rather than a few old blocks.
; -----------------------------------------------------------------------------
align 32
argon2_index_alpha:
    push rbx
    push r12
    push r13

    mov r12d, edi                   ; J1
    mov r13d, esi                   ; same_lane

    mov ecx, [a2_index]
    mov edx, [a2_seg_len]
    mov r8d, [a2_lane_len]

    cmp dword [a2_pass], 0
    jne .later_pass

    cmp dword [a2_slice], 0
    jne .first_pass_later_slice

    ; First pass, first slice: only what this lane has already produced, and
    ; not the immediately previous block — a block may not reference itself
    ; through its own predecessor.
    mov eax, ecx
    dec eax                         ; ras = index - 1
    jmp .have_ras

.first_pass_later_slice:
    mov eax, [a2_slice]
    imul eax, edx                   ; slice * seg_len
    test r13d, r13d
    jz .fp_other_lane
    add eax, ecx
    dec eax                         ; + index - 1
    jmp .have_ras
.fp_other_lane:
    ; Another lane's finished slices only. Its current segment is being written
    ; concurrently in the parallel formulation, so it is off limits.
    test ecx, ecx
    jnz .have_ras
    dec eax
    jmp .have_ras

.later_pass:
    mov eax, r8d
    sub eax, edx                    ; lane_len - seg_len
    test r13d, r13d
    jz .lp_other_lane
    add eax, ecx
    dec eax
    jmp .have_ras
.lp_other_lane:
    test ecx, ecx
    jnz .have_ras
    dec eax

.have_ras:
    mov ebx, eax                    ; reference_area_size

    ; relative = ras - 1 - ((ras * ((J1^2) >> 32)) >> 32)
    mov eax, r12d
    mov ecx, r12d
    imul rax, rcx
    shr rax, 32                     ; (J1 * J1) >> 32

    mov ecx, ebx
    imul rax, rcx
    shr rax, 32
    mov ecx, ebx
    dec ecx
    sub ecx, eax                    ; relative position
    mov r12d, ecx

    ; Later passes start from the slice after the current one, so the window
    ; wraps around the lane and always trails the write cursor.
    xor eax, eax
    cmp dword [a2_pass], 0
    je .have_start
    mov ecx, [a2_slice]
    cmp ecx, ARGON2_SYNC_POINTS - 1
    je .have_start
    inc ecx
    imul ecx, [a2_seg_len]
    mov eax, ecx

.have_start:
    add eax, r12d
    xor edx, edx
    div dword [a2_lane_len]         ; EAX = quotient, EDX = remainder
    mov eax, edx

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; argon2_next_addresses — regenerate the data-independent address block.
;
; address_block = G(0, G(0, input_block)), with a counter advanced each time.
; Running G twice is what makes the addresses look random without consulting
; the password: one application is invertible enough to be predictable from the
; counter alone.
; -----------------------------------------------------------------------------
align 32
argon2_next_addresses:
    push rbx

    inc qword [a2_input_block + 48]     ; v[6], the counter

    lea rdi, [a2_zero_block]
    lea rsi, [a2_input_block]
    lea rdx, [a2_addr_block]
    xor ecx, ecx
    call argon2_fill_block

    lea rdi, [a2_zero_block]
    lea rsi, [a2_addr_block]
    lea rdx, [a2_addr_block]
    xor ecx, ecx
    call argon2_fill_block

    pop rbx
    ret

; -----------------------------------------------------------------------------
; argon2_fill_segment — fill one lane's slice for the current pass.
;
; Reads a2_pass, a2_slice, a2_lane and the instance geometry.
; -----------------------------------------------------------------------------
align 32
argon2_fill_segment:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    ; Argon2id: independent addressing for the first half of the first pass
    ; only. Slices 2 and 3 of pass 0, and every later pass, use the data.
    xor r15d, r15d                  ; data_independent
    cmp dword [a2_pass], 0
    jne .addressing_done
    cmp dword [a2_slice], 2
    jae .addressing_done
    mov r15d, 1

    ; Seed the address input block. It is zeroed explicitly: BSS is not
    ; guaranteed clear on a kernel that skipped the wipe, and stale words here
    ; would silently change every address this segment produces.
    lea rdi, [a2_input_block]
    xor eax, eax
    mov ecx, ARGON2_QWORDS_IN_BLOCK
    rep stosq

    mov eax, [a2_pass]
    mov [a2_input_block + 0], rax
    mov eax, [a2_lane]
    mov [a2_input_block + 8], rax
    mov eax, [a2_slice]
    mov [a2_input_block + 16], rax
    mov eax, [a2_m_prime]
    mov [a2_input_block + 24], rax
    mov eax, [a2_passes]
    mov [a2_input_block + 32], rax
    mov qword [a2_input_block + 40], ARGON2_TYPE_ID
    mov qword [a2_input_block + 48], 0

.addressing_done:
    ; starting_index: the first two blocks of pass 0 slice 0 are already built.
    xor r14d, r14d
    cmp dword [a2_pass], 0
    jne .start_known
    cmp dword [a2_slice], 0
    jne .start_known
    mov r14d, 2
    test r15d, r15d
    jz .start_known
    call argon2_next_addresses      ; i=2 will not trigger a regeneration

.start_known:
    ; curr = lane*lane_len + slice*seg_len + starting_index
    mov eax, [a2_lane]
    imul eax, [a2_lane_len]
    mov ebx, [a2_slice]
    imul ebx, [a2_seg_len]
    add eax, ebx
    add eax, r14d
    mov r12d, eax                   ; curr_offset

    ; prev is the block before it, wrapping to the end of the lane at index 0.
    mov eax, r12d
    xor edx, edx
    div dword [a2_lane_len]
    test edx, edx
    jnz .prev_simple
    mov r13d, r12d
    add r13d, [a2_lane_len]
    dec r13d
    jmp .have_prev
.prev_simple:
    mov r13d, r12d
    dec r13d

.have_prev:
    mov ebp, r14d                   ; i

.loop:
    cmp ebp, [a2_seg_len]
    jae .done

    mov [a2_index], ebp

    ; At lane offset 1 the wrap above no longer applies.
    mov eax, r12d
    xor edx, edx
    div dword [a2_lane_len]
    cmp edx, 1
    jne .prev_ok
    mov r13d, r12d
    dec r13d
.prev_ok:

    ; ---- pseudo-random value ----
    test r15d, r15d
    jz .data_dependent

    mov eax, ebp
    and eax, ARGON2_ADDRESSES - 1
    test eax, eax
    jnz .addr_ready
    call argon2_next_addresses
.addr_ready:
    mov eax, ebp
    and eax, ARGON2_ADDRESSES - 1
    lea rcx, [a2_addr_block]
    mov rbx, [rcx + rax*8]
    jmp .have_rand

.data_dependent:
    ; The first word of the previous block. This is the step that makes the
    ; access pattern depend on the password.
    mov eax, r13d
    imul rax, rax, ARGON2_BLOCK_SIZE
    lea rcx, [argon2_memory]
    add rcx, rax
    mov rbx, [rcx]

.have_rand:
    ; ---- reference lane ----
    mov rax, rbx
    shr rax, 32                     ; J2
    xor edx, edx
    div dword [a2_lanes]
    mov r8d, edx                    ; ref_lane

    cmp dword [a2_pass], 0
    jne .lane_ok
    cmp dword [a2_slice], 0
    jne .lane_ok
    mov r8d, [a2_lane]              ; Nothing else exists yet
.lane_ok:

    ; ---- reference index ----
    push r8
    mov edi, ebx                    ; J1
    xor esi, esi
    cmp r8d, [a2_lane]
    jne .not_same
    mov esi, 1
.not_same:
    call argon2_index_alpha
    pop r8

    ; ref_block = memory[ref_lane * lane_len + ref_index]
    mov ecx, r8d
    imul ecx, [a2_lane_len]
    add eax, ecx
    imul rax, rax, ARGON2_BLOCK_SIZE
    lea rsi, [argon2_memory]
    add rsi, rax

    ; prev_block
    mov eax, r13d
    imul rax, rax, ARGON2_BLOCK_SIZE
    lea rdi, [argon2_memory]
    add rdi, rax

    ; curr_block
    mov eax, r12d
    imul rax, rax, ARGON2_BLOCK_SIZE
    lea rdx, [argon2_memory]
    add rdx, rax

    ; Version 0x13: every pass after the first XORs into what is already there.
    xor ecx, ecx
    cmp dword [a2_pass], 0
    je .no_xor
    mov ecx, 1
.no_xor:
    call argon2_fill_block

    inc r12d
    inc r13d
    inc ebp
    jmp .loop

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; argon2id_hash_ex — the full algorithm.
;
; Inputs:
;   RDI = Pointer to an argon2_params_t
;
; Returns:
;   EAX = ARGON2_OK, or a negative ARGON2_ERR_* code
; -----------------------------------------------------------------------------
align 32
argon2id_hash_ex:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32

    mov rbp, rdi

    ; ---- validate ----
    cmp dword [rbp + argon2_params_t.outlen], 4
    jb .bad_param
    cmp dword [rbp + argon2_params_t.saltlen], 8
    jb .bad_param                   ; RFC 9106 floor; shorter salts collide
    mov eax, [rbp + argon2_params_t.lanes]
    test eax, eax
    jz .bad_param
    cmp eax, 255
    ja .bad_param
    cmp dword [rbp + argon2_params_t.t_cost], 1
    jb .bad_param

    ; m must be at least 8*p KiB, and is rounded down to a multiple of 4*p so
    ; that every lane holds a whole number of four-slice segments.
    mov ecx, [rbp + argon2_params_t.m_cost]
    mov eax, [rbp + argon2_params_t.lanes]
    mov edx, eax
    shl edx, 3                      ; 8 * lanes
    cmp ecx, edx
    jb .bad_param
    cmp ecx, ARGON2_MAX_BLOCKS
    jbe .m_ok
    mov ecx, ARGON2_MAX_BLOCKS      ; Clamp rather than fail
.m_ok:
    mov eax, [rbp + argon2_params_t.lanes]
    shl eax, 2                      ; 4 * lanes
    mov r8d, eax
    mov eax, ecx
    xor edx, edx
    div r8d                         ; floor(m / 4p)
    imul eax, r8d                   ; m' = 4p * floor(m / 4p)
    mov [a2_m_prime], eax

    mov ecx, [rbp + argon2_params_t.lanes]
    mov [a2_lanes], ecx
    xor edx, edx
    div ecx
    mov [a2_lane_len], eax
    shr eax, 2
    mov [a2_seg_len], eax
    test eax, eax
    jz .bad_param

    mov eax, [rbp + argon2_params_t.t_cost]
    mov [a2_passes], eax

    ; ---- H0 = BLAKE2b-512 over every parameter and every input ----
    ; The parameters are hashed in, so a tag produced at one cost setting can
    ; never be mistaken for one produced at another.
    lea rdi, [a2_ctx]
    mov esi, 64
    call blake2b_init

%macro A2_ABSORB_LE32 1
    mov eax, %1
    mov [rsp], eax
    lea rdi, [a2_ctx]
    mov rsi, rsp
    mov edx, 4
    call blake2b_update
%endmacro

    A2_ABSORB_LE32 [rbp + argon2_params_t.lanes]
    A2_ABSORB_LE32 [rbp + argon2_params_t.outlen]
    A2_ABSORB_LE32 dword [a2_m_prime]
    A2_ABSORB_LE32 [rbp + argon2_params_t.t_cost]
    A2_ABSORB_LE32 ARGON2_VERSION
    A2_ABSORB_LE32 ARGON2_TYPE_ID

%macro A2_ABSORB_FIELD 2            ; %1 = pointer field, %2 = length field
    A2_ABSORB_LE32 [rbp + %2]
    mov eax, [rbp + %2]
    test eax, eax
    jz %%empty
    lea rdi, [a2_ctx]
    mov rsi, [rbp + %1]
    mov edx, [rbp + %2]
    call blake2b_update
%%empty:
%endmacro

    A2_ABSORB_FIELD argon2_params_t.pwd,    argon2_params_t.pwdlen
    A2_ABSORB_FIELD argon2_params_t.salt,   argon2_params_t.saltlen
    A2_ABSORB_FIELD argon2_params_t.secret, argon2_params_t.secretlen
    A2_ABSORB_FIELD argon2_params_t.ad,     argon2_params_t.adlen

    lea rdi, [a2_ctx]
    lea rsi, [a2_h0]
    call blake2b_final

    ; ---- initial two blocks per lane ----
    ; B[i][0] = H'(H0 || LE32(0) || LE32(i)), B[i][1] = H'(H0 || LE32(1) || LE32(i))
    xor r12d, r12d                  ; lane
.init_lane:
    cmp r12d, [a2_lanes]
    jae .init_done

    xor r13d, r13d                  ; block index within the lane (0 then 1)
.init_block:
    mov [a2_h0 + 64], r13d
    mov [a2_h0 + 68], r12d

    mov eax, r12d
    imul eax, [a2_lane_len]
    add eax, r13d
    imul rax, rax, ARGON2_BLOCK_SIZE
    lea rdi, [argon2_memory]
    add rdi, rax

    mov esi, ARGON2_BLOCK_SIZE
    lea rdx, [a2_h0]
    mov ecx, 72
    call argon2_h_prime

    inc r13d
    cmp r13d, 2
    jb .init_block

    inc r12d
    jmp .init_lane

.init_done:
    ; The zero block really must be zero — it is the "previous block" for every
    ; address generation, and a nonzero one would corrupt all of them.
    lea rdi, [a2_zero_block]
    xor eax, eax
    mov ecx, ARGON2_QWORDS_IN_BLOCK
    rep stosq

    ; ---- passes ----
    xor r12d, r12d                  ; pass
.pass_loop:
    cmp r12d, [a2_passes]
    jae .passes_done
    mov [a2_pass], r12d

    xor r13d, r13d                  ; slice
.slice_loop:
    cmp r13d, ARGON2_SYNC_POINTS
    jae .slice_done
    mov [a2_slice], r13d

    xor r14d, r14d                  ; lane
.lane_loop:
    cmp r14d, [a2_lanes]
    jae .lane_done
    mov [a2_lane], r14d

    call argon2_fill_segment

    inc r14d
    jmp .lane_loop
.lane_done:

    inc r13d
    jmp .slice_loop
.slice_done:

    inc r12d
    jmp .pass_loop
.passes_done:

    ; ---- finalise: XOR the last block of every lane, then H' to the tag ----
    ; XORing rather than taking one lane is what makes every lane's work
    ; load-bearing; otherwise p-1 lanes could simply be skipped.
    mov eax, [a2_lane_len]
    dec eax
    imul rax, rax, ARGON2_BLOCK_SIZE
    lea r15, [argon2_memory]
    add r15, rax                    ; B[0][q-1]

    mov r14d, 1
.xor_lane:
    cmp r14d, [a2_lanes]
    jae .xor_done

    mov eax, r14d
    imul eax, [a2_lane_len]
    add eax, [a2_lane_len]
    dec eax
    imul rax, rax, ARGON2_BLOCK_SIZE
    lea rsi, [argon2_memory]
    add rsi, rax

    xor ecx, ecx
.xor_words:
    mov rax, [rsi + rcx*8]
    xor [r15 + rcx*8], rax
    inc ecx
    cmp ecx, ARGON2_QWORDS_IN_BLOCK
    jb .xor_words

    inc r14d
    jmp .xor_lane

.xor_done:
    mov rdi, [rbp + argon2_params_t.out]
    mov esi, [rbp + argon2_params_t.outlen]
    mov rdx, r15
    mov ecx, ARGON2_BLOCK_SIZE
    call argon2_h_prime

    mov eax, ARGON2_OK
    jmp .out

.bad_param:
    mov eax, ARGON2_ERR_PARAM

.out:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; argon2id_hash — fixed-policy wrapper.
;
; Inputs:
;   RDI = Password, ESI = Password length
;   RDX = Salt,     ECX = Salt length
;   R8  = Output buffer (32 bytes)
;
; Returns:
;   EAX = 1 on success, 0 on failure
;
; Kept at this signature because crypto/ukdf/ukdf.asm dispatches to it
; positionally. Callers wanting to choose cost parameters use the _ex form.
; -----------------------------------------------------------------------------
align 32
argon2id_hash:
    push rbx
    sub rsp, argon2_params_t_size

    mov [rsp + argon2_params_t.pwd], rdi
    mov [rsp + argon2_params_t.pwdlen], esi
    mov [rsp + argon2_params_t.salt], rdx
    mov [rsp + argon2_params_t.saltlen], ecx
    mov qword [rsp + argon2_params_t.secret], 0
    mov dword [rsp + argon2_params_t.secretlen], 0
    mov qword [rsp + argon2_params_t.ad], 0
    mov dword [rsp + argon2_params_t.adlen], 0
    mov [rsp + argon2_params_t.out], r8
    mov dword [rsp + argon2_params_t.outlen], 32
    mov dword [rsp + argon2_params_t.m_cost], ARGON2_DEFAULT_M_COST
    mov dword [rsp + argon2_params_t.t_cost], ARGON2_DEFAULT_T_COST
    mov dword [rsp + argon2_params_t.lanes], ARGON2_DEFAULT_LANES

    mov rdi, rsp
    call argon2id_hash_ex

    test eax, eax
    jnz .fail
    mov eax, 1
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, argon2_params_t_size
    pop rbx
    ret

; -----------------------------------------------------------------------------
; argon2_generate_salt — 16 random bytes from the kernel CSPRNG.
;
; Inputs:
;   RDI = 16-byte output buffer
;
; Returns:
;   EAX = 1 on success, 0 if the entropy source refused
; -----------------------------------------------------------------------------
align 32
argon2_generate_salt:
    push rbx
    mov rbx, rdi
    mov rsi, 16
    call urand_get_bytes
    test rax, rax
    jz .fail
    mov eax, 1
    pop rbx
    ret
.fail:
    ; Never fall back to a fixed or predictable salt. A salt that repeats turns
    ; the whole table into one rainbow-table target.
    xor eax, eax
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UKDF_ARGON2_ARGON2_ASM
