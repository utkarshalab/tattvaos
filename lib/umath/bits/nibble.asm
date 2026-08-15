%ifndef GUARD_LIB_UMATH_BITS_NIBBLE_ASM
%define GUARD_LIB_UMATH_BITS_NIBBLE_ASM
; =============================================================================
; umath - unified math library
; bits/nibble.asm - nibble (4-bit) array/buffer operations
; =============================================================================
; complements bit4.asm (single-nibble arithmetic) with buffer-level
; nibble access used by INT4/UINT4/FP4/Q4_0/Q4_1 tensor storage
;
; layout convention: nibble index 0 = low nibble of byte 0,
;                     nibble index 1 = high nibble of byte 0,
;                     nibble index 2 = low nibble of byte 1, etc.
;
; functions:
;   umath_nibble_get          (*buf, index -> nibble value 0-15)
;   umath_nibble_set          (*buf, index, val -> void)
;   umath_nibble_count        (byte_len -> nibble_count)  (= byte_len*2)
;   umath_nibble_swap_buf     (*buf, byte_len -> void)  swap nibbles in each byte
;   umath_nibble_fill         (*buf, byte_len, val -> void)  fill all nibbles with val
;   umath_nibble_copy         (*dst, *src, nibble_count -> void)
;   umath_nibble_popcount_buf (*buf, byte_len -> total set bits across nibbles)
;   umath_nibble_xor_buf      (*dst, *a, *b, byte_len -> void)
;   umath_nibble_extract_lo   (*buf, byte_len, *out -> void) extract all low nibbles
;   umath_nibble_extract_hi   (*buf, byte_len, *out -> void) extract all high nibbles
;   umath_nibble_interleave   (*dst, *lo, *hi, count -> void) pack two nibble arrays
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_nibble_get - read nibble at index from buffer
; args:    rdi = pointer to buffer
;          rsi = nibble index
; returns: eax = nibble value (0-15)
; -----------------------------------------------------------------------------
global umath_nibble_get
umath_nibble_get:
    mov     rax, rsi
    shr     rax, 1              ; byte index = index / 2
    movzx   ecx, byte [rdi + rax]
    test    rsi, 1
    jz      .lo
    shr     ecx, 4              ; odd index -> high nibble
.lo:
    and     ecx, 0x0F
    mov     eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_nibble_set - write nibble at index in buffer
; args:    rdi = pointer to buffer
;          rsi = nibble index
;          edx = new value (0-15, masked)
; returns: void
; -----------------------------------------------------------------------------
global umath_nibble_set
umath_nibble_set:
    mov     rax, rsi
    shr     rax, 1
    movzx   ecx, byte [rdi + rax]
    and     edx, 0x0F
    test    rsi, 1
    jz      .lo
    ; high nibble: clear bits 7:4, set new value shifted
    and     ecx, 0x0F
    shl     edx, 4
    or      ecx, edx
    jmp     .store
.lo:
    and     ecx, 0xF0
    or      ecx, edx
.store:
    mov     byte [rdi + rax], cl
    ret

; -----------------------------------------------------------------------------
; umath_nibble_count - convert byte length to nibble count
; args:    rdi = byte length
; returns: rax = nibble count (byte_len * 2)
; -----------------------------------------------------------------------------
global umath_nibble_count
umath_nibble_count:
    lea     rax, [rdi*2]
    ret

; -----------------------------------------------------------------------------
; umath_nibble_swap_buf - swap the two nibbles in every byte of buffer
; args:    rdi = pointer to buffer
;          rsi = byte length
; returns: void (modifies in-place)
; -----------------------------------------------------------------------------
global umath_nibble_swap_buf
umath_nibble_swap_buf:
    xor     rcx, rcx
.loop:
    cmp     rcx, rsi
    jge     .done
    mov     al, [rdi + rcx]
    rol     al, 4
    mov     [rdi + rcx], al
    inc     rcx
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_nibble_fill - fill all nibbles in buffer with given 4-bit value
; args:    rdi = pointer to buffer
;          rsi = byte length
;          edx = value (0-15, masked); replicated into both nibbles
; returns: void
; -----------------------------------------------------------------------------
global umath_nibble_fill
umath_nibble_fill:
    mov     eax, edx
    and     eax, 0x0F
    mov     ecx, eax
    shl     ecx, 4
    or      eax, ecx            ; replicate nibble into full byte
    mov     cl, al
    xor     rdx, rdx
.loop:
    cmp     rdx, rsi
    jge     .done
    mov     [rdi + rdx], cl
    inc     rdx
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_nibble_copy - copy nibble_count nibbles from src to dst
; args:    rdi = dst buffer pointer
;          rsi = src buffer pointer
;          rdx = nibble count
; returns: void
; note:    handles unaligned (odd-start) cases via per-nibble copy;
;          if nibble_count is even and both start at nibble 0,
;          equivalent to byte memcpy of nibble_count/2 bytes
; -----------------------------------------------------------------------------
global umath_nibble_copy
umath_nibble_copy:
    push    rbx
    test    rdx, 1
    jnz     .per_nibble
    ; even count: fast path byte copy
    mov     rcx, rdx
    shr     rcx, 1
    xor     rbx, rbx
.fast_loop:
    cmp     rbx, rcx
    jge     .done
    mov     al, [rsi + rbx]
    mov     [rdi + rbx], al
    inc     rbx
    jmp     .fast_loop
.per_nibble:
    xor     rbx, rbx
.pn_loop:
    cmp     rbx, rdx
    jge     .done
    ; get nibble from src
    push    rdi
    push    rsi
    push    rdx
    mov     rdi, rsi
    mov     rsi, rbx
    call    umath_nibble_get
    pop     rdx
    pop     rsi
    pop     rdi
    ; set nibble in dst
    push    rsi
    push    rdx
    mov     edx, eax            ; value
    mov     rsi, rbx            ; index
    call    umath_nibble_set
    pop     rdx
    pop     rsi
    inc     rbx
    jmp     .pn_loop
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_nibble_popcount_buf - total popcount across all nibbles in buffer
; args:    rdi = pointer to buffer
;          rsi = byte length
; returns: eax = total set bits (0 to byte_len*8)
; note:    equivalent to byte-level popcount but expressed at nibble
;          granularity for clarity; result is the same as full byte popcount
; -----------------------------------------------------------------------------
global umath_nibble_popcount_buf
umath_nibble_popcount_buf:
    xor     eax, eax
    xor     rcx, rcx
.loop:
    cmp     rcx, rsi
    jge     .done
    movzx   edx, byte [rdi + rcx]
    popcnt  edx, edx
    add     eax, edx
    inc     rcx
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_nibble_xor_buf - dst[i] = a[i] XOR b[i] for all bytes (nibble-agnostic)
; args:    rdi = dst buffer
;          rsi = a buffer
;          rdx = b buffer
;          rcx = byte length
; returns: void
; note:    XOR at byte granularity covers both nibbles simultaneously
; -----------------------------------------------------------------------------
global umath_nibble_xor_buf
umath_nibble_xor_buf:
    xor     r8, r8
.loop:
    cmp     r8, rcx
    jge     .done
    mov     al, [rsi + r8]
    xor     al, [rdx + r8]
    mov     [rdi + r8], al
    inc     r8
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_nibble_extract_lo - extract all low nibbles into output byte array
; args:    rdi = pointer to packed buffer
;          rsi = byte length of packed buffer
;          rdx = output buffer (byte_len entries, one nibble value per byte)
; returns: void
; -----------------------------------------------------------------------------
global umath_nibble_extract_lo
umath_nibble_extract_lo:
    xor     rcx, rcx
.loop:
    cmp     rcx, rsi
    jge     .done
    mov     al, [rdi + rcx]
    and     al, 0x0F
    mov     [rdx + rcx], al
    inc     rcx
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_nibble_extract_hi - extract all high nibbles into output byte array
; args:    rdi = pointer to packed buffer
;          rsi = byte length of packed buffer
;          rdx = output buffer (byte_len entries, one nibble value per byte)
; returns: void
; -----------------------------------------------------------------------------
global umath_nibble_extract_hi
umath_nibble_extract_hi:
    xor     rcx, rcx
.loop:
    cmp     rcx, rsi
    jge     .done
    mov     al, [rdi + rcx]
    shr     al, 4
    and     al, 0x0F
    mov     [rdx + rcx], al
    inc     rcx
    jmp     .loop
.done:
    ret

; -----------------------------------------------------------------------------
; umath_nibble_interleave - pack two nibble arrays into one byte buffer
; args:    rdi = dst buffer (count bytes)
;          rsi = lo nibble array (count bytes, one value 0-15 per byte)
;          rdx = hi nibble array (count bytes, one value 0-15 per byte)
;          rcx = count
; returns: void
; note:    dst[i] = (hi[i] << 4) | lo[i]
; -----------------------------------------------------------------------------
global umath_nibble_interleave
umath_nibble_interleave:
    xor     r8, r8
.loop:
    cmp     r8, rcx
    jge     .done
    mov     al, [rsi + r8]
    and     al, 0x0F
    mov     ah, [rdx + r8]
    and     ah, 0x0F
    shl     ah, 4
    or      al, ah
    mov     [rdi + r8], al
    inc     r8
    jmp     .loop
.done:
    ret
%endif ; GUARD_LIB_UMATH_BITS_NIBBLE_ASM
