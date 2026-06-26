; =============================================================================
; umath - unified math library
; bits/bitrot_r.asm - generic right rotation over arbitrary-width buffers
; =============================================================================
; mirror of bitrot_l.asm for rightward rotation
;
; functions:
;   umath_bitrot_r_word     (val, amount, width -> rotated)
;   umath_bitrot_r_buf      (*dst, *src, word_count, amount -> void)
;   umath_bitrot_r_bytes    (*dst, *src, byte_count, bit_amount -> void)
;   umath_bitrot_r32_arr    (*dst, *src, count, amount -> void)
;   umath_bitrot_r64_arr    (*dst, *src, count, amount -> void)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bitrot_r_word - rotate a single value right by `amount`
; args:    rdi = value, esi = amount, edx = width (8/16/32/64)
; returns: rax = rotated value
; -----------------------------------------------------------------------------
global umath_bitrot_r_word
umath_bitrot_r_word:
    mov     ecx, esi
    cmp     edx, 8
    je      .w8
    cmp     edx, 16
    je      .w16
    cmp     edx, 32
    je      .w32
    and     cl, 63
    mov     rax, rdi
    ror     rax, cl
    ret
.w8:
    and     cl, 7
    mov     al, dil
    ror     al, cl
    movzx   eax, al
    ret
.w16:
    and     cl, 15
    mov     ax, di
    ror     ax, cl
    movzx   eax, ax
    ret
.w32:
    and     cl, 31
    mov     eax, edi
    ror     eax, cl
    ret

; -----------------------------------------------------------------------------
; umath_bitrot_r_buf - rotate a multi-word little-endian buffer right
; args:    rdi=*dst, rsi=*src, rdx=word_count, rcx=amount
; returns: void
;
; equivalent to left-rotation by (total_bits - (amount mod total_bits))
; -----------------------------------------------------------------------------
global umath_bitrot_r_buf
umath_bitrot_r_buf:
    push    r12
    push    r13

    mov     r12, rdx            ; word_count
    test    r12, r12
    jz      .done

    mov     r13, r12
    shl     r13, 6              ; total_bits

    mov     rax, rcx
    xor     rdx, rdx
    div     r13                 ; rdx = amount mod total_bits
    ; left_amount = total_bits - rdx  (if rdx != 0, else 0)
    test    rdx, rdx
    jz      .zero_amount
    mov     rax, r13
    sub     rax, rdx
    mov     rcx, rax
    jmp     .call_left
.zero_amount:
    xor     rcx, rcx
.call_left:
    mov     rdx, r12
    call    umath_bitrot_l_buf
.done:
    pop     r13
    pop     r12
    ret

extern umath_bitrot_l_buf

; -----------------------------------------------------------------------------
; umath_bitrot_r_bytes - rotate a byte buffer right by bit_amount
; args:    rdi=*dst, rsi=*src, rdx=byte_count, rcx=bit_amount
; returns: void
; -----------------------------------------------------------------------------
global umath_bitrot_r_bytes
umath_bitrot_r_bytes:
    push    r12
    push    r13

    mov     r12, rdx            ; byte_count
    test    r12, r12
    jz      .done

    mov     r13, r12
    shl     r13, 3              ; total_bits

    mov     rax, rcx
    xor     rdx, rdx
    div     r13
    test    rdx, rdx
    jz      .zero_amount
    mov     rax, r13
    sub     rax, rdx
    mov     rcx, rax
    jmp     .call_left
.zero_amount:
    xor     rcx, rcx
.call_left:
    mov     rdx, r12
    call    umath_bitrot_l_bytes
.done:
    pop     r13
    pop     r12
    ret

extern umath_bitrot_l_bytes

; -----------------------------------------------------------------------------
; umath_bitrot_r32_arr - rotate each u32 element of an array right
; args:    rdi=*dst, rsi=*src, rdx=count, ecx=amount (0-31, masked)
; returns: void
; -----------------------------------------------------------------------------
global umath_bitrot_r32_arr
umath_bitrot_r32_arr:
    push    rbx
    and     ecx, 31
    mov     r8d, ecx
    xor     rbx, rbx
.loop:
    cmp     rbx, rdx
    jge     .done
    mov     eax, [rsi + rbx*4]
    mov     cl, r8b
    ror     eax, cl
    mov     [rdi + rbx*4], eax
    inc     rbx
    jmp     .loop
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitrot_r64_arr - rotate each u64 element of an array right
; args:    rdi=*dst, rsi=*src, rdx=count, ecx=amount (0-63, masked)
; returns: void
; -----------------------------------------------------------------------------
global umath_bitrot_r64_arr
umath_bitrot_r64_arr:
    push    rbx
    and     ecx, 63
    mov     r8d, ecx
    xor     rbx, rbx
.loop:
    cmp     rbx, rdx
    jge     .done
    mov     rax, [rsi + rbx*8]
    mov     cl, r8b
    ror     rax, cl
    mov     [rdi + rbx*8], rax
    inc     rbx
    jmp     .loop
.done:
    pop     rbx
    ret