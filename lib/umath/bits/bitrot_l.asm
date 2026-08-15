%ifndef GUARD_LIB_UMATH_BITS_BITROT_L_ASM
%define GUARD_LIB_UMATH_BITS_BITROT_L_ASM
; =============================================================================
; umath - unified math library
; bits/bitrot_l.asm - generic left rotation over arbitrary-width buffers
; =============================================================================
; complements the fixed-width rotl in bit8/16/32/64/128.asm with a
; general buffer-level rotation for arbitrary bit-widths (bignum,
; Galois field elements, hash function state, etc.)
;
; convention: buffer is little-endian word order, word[0] = least
; significant 64 bits. rotation treats the buffer as one big unsigned
; integer of (word_count * 64) bits.
;
; functions:
;   umath_bitrot_l_word     (val, amount, width -> rotated)
;                            generic single-word rotate, width in {8,16,32,64}
;   umath_bitrot_l_buf      (*dst, *src, word_count, amount -> void)
;                            rotate left by `amount` bits (mod total_bits)
;   umath_bitrot_l_bytes    (*dst, *src, byte_count, bit_amount -> void)
;                            byte-buffer rotation (any byte_count)
;   umath_bitrot_l32_arr    (*dst, *src, count, amount -> void)
;                            rotate each u32 element independently
;   umath_bitrot_l64_arr    (*dst, *src, count, amount -> void)
;                            rotate each u64 element independently
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bitrot_l_word - rotate a single value left by `amount`, for given width
; args:    rdi = value (right-justified in register)
;          esi = amount
;          edx = width in bits (8, 16, 32, or 64)
; returns: rax = rotated value, masked to width bits
; -----------------------------------------------------------------------------
global umath_bitrot_l_word
umath_bitrot_l_word:
    mov     ecx, esi
    cmp     edx, 8
    je      .w8
    cmp     edx, 16
    je      .w16
    cmp     edx, 32
    je      .w32
    and     cl, 63
    mov     rax, rdi
    rol     rax, cl
    ret
.w8:
    and     cl, 7
    mov     al, dil
    rol     al, cl
    movzx   eax, al
    ret
.w16:
    and     cl, 15
    mov     ax, di
    rol     ax, cl
    movzx   eax, ax
    ret
.w32:
    and     cl, 31
    mov     eax, edi
    rol     eax, cl
    ret

; -----------------------------------------------------------------------------
; umath_bitrot_l_buf - rotate a multi-word little-endian buffer left
; args:    rdi = dst buffer (word_count * 8 bytes)
;          rsi = src buffer (word_count * 8 bytes; may alias dst)
;          rdx = word_count (number of u64 words, 1-64 supported)
;          rcx = amount (bit rotation amount, reduced mod total_bits)
; returns: void
;
; total_bits = word_count * 64
; word_shift = (amount mod total_bits) / 64
; bit_shift  = (amount mod total_bits) % 64
; out[i] = (local[src_idx] << bit_shift) | (local[src_idx_prev] >> (64-bit_shift))
;   where src_idx = (i - word_shift) mod word_count
;         src_idx_prev = (src_idx - 1) mod word_count
;
; note: uses a local stack copy (max 64 words = 512 bytes) so dst may alias src.
;       word_count > 64 is not supported.
; -----------------------------------------------------------------------------
global umath_bitrot_l_buf
umath_bitrot_l_buf:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdx            ; word_count
    test    r12, r12
    jz      .done_nop

    mov     r13, r12
    shl     r13, 6              ; total_bits

    mov     rax, rcx
    xor     rdx, rdx
    div     r13                 ; rdx = amount mod total_bits
    mov     r14, rdx

    test    r14, r14
    jnz     .rotate
    cmp     rdi, rsi
    je      .done_nop
    xor     rcx, rcx
.copy_loop:
    cmp     rcx, r12
    jge     .done_nop
    mov     rax, [rsi + rcx*8]
    mov     [rdi + rcx*8], rax
    inc     rcx
    jmp     .copy_loop

.rotate:
    sub     rsp, 512
    xor     rcx, rcx
.cpy:
    cmp     rcx, r12
    jge     .cpy_done
    mov     rax, [rsi + rcx*8]
    mov     [rsp + rcx*8], rax
    inc     rcx
    jmp     .cpy
.cpy_done:

    mov     rax, r14
    mov     rcx, 64
    xor     rdx, rdx
    div     rcx                 ; rax = word_shift, rdx = bit_shift
    mov     r15, rax
    mov     r13, rdx

    xor     rbx, rbx            ; output index i
.out_loop:
    cmp     rbx, r12
    jge     .rot_done

    mov     rax, rbx
    sub     rax, r15
.norm1:
    cmp     rax, 0
    jge     .norm1_done
    add     rax, r12
    jmp     .norm1
.norm1_done:
    cmp     rax, r12
    jl      .src_idx_ok
    sub     rax, r12
.src_idx_ok:
    mov     r8, rax             ; src_idx

    test    r13, r13
    jz      .no_bitshift

    mov     rax, r8
    sub     rax, 1
    cmp     rax, 0
    jge     .prev_ok
    add     rax, r12
.prev_ok:
    mov     r9, rax             ; src_idx_prev

    mov     rax, [rsp + r8*8]
    mov     rcx, r13
    shl     rax, cl
    mov     r10, [rsp + r9*8]
    mov     rcx, 64
    sub     rcx, r13
    shr     r10, cl
    or      rax, r10
    mov     [rdi + rbx*8], rax
    jmp     .next

.no_bitshift:
    mov     rax, [rsp + r8*8]
    mov     [rdi + rbx*8], rax

.next:
    inc     rbx
    jmp     .out_loop

.rot_done:
    add     rsp, 512

.done_nop:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitrot_l_bytes - rotate a byte buffer left by bit_amount
; args:    rdi = dst buffer (byte_count bytes)
;          rsi = src buffer (byte_count bytes; may alias dst)
;          rdx = byte_count
;          rcx = bit_amount
; returns: void
; note:    for byte_count not a multiple of 8; bit-by-bit construction.
;          intended for small buffers (crypto state, GF(2^n) elements).
;          max 512 bytes supported (stack temp buffer).
; -----------------------------------------------------------------------------
global umath_bitrot_l_bytes
umath_bitrot_l_bytes:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     r12, rdx            ; byte_count
    test    r12, r12
    jz      .done

    mov     r13, r12
    shl     r13, 3              ; total_bits

    mov     rax, rcx
    xor     rdx, rdx
    div     r13
    mov     r14, rdx            ; reduced bit amount

    test    r14, r14
    jnz     .do_rotate
    cmp     rdi, rsi
    je      .done
    xor     rcx, rcx
.cpy:
    cmp     rcx, r12
    jge     .done
    mov     al, [rsi + rcx]
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .cpy

.do_rotate:
    sub     rsp, 512
    xor     rcx, rcx
.cpy2:
    cmp     rcx, r12
    jge     .cpy2_done
    mov     al, [rsi + rcx]
    mov     [rsp + rcx], al
    inc     rcx
    jmp     .cpy2
.cpy2_done:

    xor     rbx, rbx            ; output bit index
.bit_loop:
    cmp     rbx, r13
    jge     .rot_done

    mov     rax, rbx
    sub     rax, r14
.norm:
    cmp     rax, 0
    jge     .norm_done
    add     rax, r13
    jmp     .norm
.norm_done:
    cmp     rax, r13
    jl      .src_ok
    sub     rax, r13
.src_ok:
    mov     rcx, rax
    shr     rcx, 3              ; src byte index
    mov     r8, rax
    and     r8, 7               ; src bit-in-byte
    mov     dl, [rsp + rcx]
    shr     dl, r8b
    and     dl, 1               ; dl = source bit value

    mov     rcx, rbx
    shr     rcx, 3              ; dst byte index
    mov     r9, rbx
    and     r9, 7               ; dst bit-in-byte
    mov     al, [rdi + rcx]
    mov     r10b, 1
    mov     r11, r9
    shl     r10b, r11b
    not     r10b
    and     al, r10b
    mov     r10b, dl
    mov     r11, r9
    shl     r10b, r11b
    or      al, r10b
    mov     [rdi + rcx], al

    inc     rbx
    jmp     .bit_loop

.rot_done:
    add     rsp, 512
.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitrot_l32_arr - rotate each u32 element of an array left independently
; args:    rdi = dst array (count * 4 bytes)
;          rsi = src array (count * 4 bytes)
;          rdx = count
;          ecx = amount (0-31, masked)
; returns: void
; note:    used in SHA-1/MD5/ChaCha-style per-word rotations applied
;          uniformly across a state array
; -----------------------------------------------------------------------------
global umath_bitrot_l32_arr
umath_bitrot_l32_arr:
    push    rbx
    and     ecx, 31
    mov     r8d, ecx
    xor     rbx, rbx
.loop:
    cmp     rbx, rdx
    jge     .done
    mov     eax, [rsi + rbx*4]
    mov     cl, r8b
    rol     eax, cl
    mov     [rdi + rbx*4], eax
    inc     rbx
    jmp     .loop
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitrot_l64_arr - rotate each u64 element of an array left independently
; args:    rdi = dst array (count * 8 bytes)
;          rsi = src array (count * 8 bytes)
;          rdx = count
;          ecx = amount (0-63, masked)
; returns: void
; -----------------------------------------------------------------------------
global umath_bitrot_l64_arr
umath_bitrot_l64_arr:
    push    rbx
    and     ecx, 63
    mov     r8d, ecx
    xor     rbx, rbx
.loop:
    cmp     rbx, rdx
    jge     .done
    mov     rax, [rsi + rbx*8]
    mov     cl, r8b
    rol     rax, cl
    mov     [rdi + rbx*8], rax
    inc     rbx
    jmp     .loop
.done:
    pop     rbx
    ret
%endif ; GUARD_LIB_UMATH_BITS_BITROT_L_ASM
