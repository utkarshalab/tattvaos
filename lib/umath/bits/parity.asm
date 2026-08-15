%ifndef GUARD_LIB_UMATH_BITS_PARITY_ASM
%define GUARD_LIB_UMATH_BITS_PARITY_ASM
; =============================================================================
; umath - unified math library
; bits/parity.asm - parity computation
; =============================================================================
; generic parity (XOR of all bits) across register widths and buffers.
; used for: error detection codes, Hamming/BCH/LDPC helpers, hash mixing,
;           Galois field trace computation
;
; functions:
;   umath_parity_u8          (val -> 0/1)
;   umath_parity_u16         (val -> 0/1)
;   umath_parity_u32         (val -> 0/1)
;   umath_parity_u64         (val -> 0/1)
;   umath_parity_u128        (lo, hi -> 0/1)
;   umath_parity_buf         (*buf, byte_len -> 0/1)  parity of entire buffer
;   umath_parity_masked_u32  (val, mask -> 0/1)  parity of (val & mask)
;   umath_parity_masked_u64  (val, mask -> 0/1)
;   umath_parity_row_xor     (*buf, byte_len, *out_byte -> void)
;                              XOR-reduce buffer to single byte (running XOR)
;   umath_parity_even_u32    (val -> 0/1)  alias of parity_u32 (even parity bit)
;   umath_parity_odd_u32     (val -> 0/1)  1 - parity_u32 (odd parity bit)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_parity_u8 - parity of byte (1 if odd number of set bits)
; args:    dil = val
; returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_parity_u8
umath_parity_u8:
    movzx   eax, dil
    popcnt  eax, eax
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_u16 - parity of 16-bit value
; args:    di = val
; returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_parity_u16
umath_parity_u16:
    movzx   eax, di
    popcnt  eax, eax
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_u32 - parity of 32-bit value
; args:    edi = val
; returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_parity_u32
umath_parity_u32:
    popcnt  eax, edi
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_u64 - parity of 64-bit value
; args:    rdi = val
; returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_parity_u64
umath_parity_u64:
    popcnt  rax, rdi
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_u128 - parity of 128-bit value (lo/hi pair)
; args:    rdi = lo, rsi = hi
; returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_parity_u128
umath_parity_u128:
    popcnt  rax, rdi
    popcnt  rdx, rsi
    add     eax, edx
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_buf - parity of all bits in a byte buffer
; args:    rdi = pointer to buffer
;          rsi = byte length
; returns: eax = 0/1 (parity of total popcount across buffer)
;
; processes 8 bytes at a time via POPCNT, falls back to byte loop for
; the remainder
; -----------------------------------------------------------------------------
global umath_parity_buf
umath_parity_buf:
    xor     eax, eax            ; running popcount total
    xor     rcx, rcx            ; byte index
    mov     r8, rsi
    mov     r9, r8
    shr     r9, 3               ; number of full qwords
    shl     r9, 3               ; byte count covered by qwords

.qword_loop:
    cmp     rcx, r9
    jge     .byte_loop
    mov     rdx, [rdi + rcx]
    popcnt  rdx, rdx
    add     eax, edx
    add     rcx, 8
    jmp     .qword_loop

.byte_loop:
    cmp     rcx, r8
    jge     .done
    movzx   edx, byte [rdi + rcx]
    popcnt  edx, edx
    add     eax, edx
    inc     rcx
    jmp     .byte_loop

.done:
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_masked_u32 - parity of (val & mask)
; args:    edi = val, esi = mask
; returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_parity_masked_u32
umath_parity_masked_u32:
    mov     eax, edi
    and     eax, esi
    popcnt  eax, eax
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_masked_u64 - parity of (val & mask)
; args:    rdi = val, rsi = mask
; returns: eax = 0/1
; -----------------------------------------------------------------------------
global umath_parity_masked_u64
umath_parity_masked_u64:
    mov     rax, rdi
    and     rax, rsi
    popcnt  rax, rax
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_row_xor - XOR-reduce a buffer down to a single byte checksum
; args:    rdi = pointer to buffer
;          rsi = byte length
;          rdx = pointer to output byte
; returns: void; *rdx = XOR of all bytes in buffer
;
; note: this is a simple longitudinal redundancy check (LRC), not a
;       cryptographic checksum. useful as a fast sanity check for
;       sparse metadata blocks or GF(2) row reduction.
; -----------------------------------------------------------------------------
global umath_parity_row_xor
umath_parity_row_xor:
    xor     al, al
    xor     rcx, rcx
.loop:
    cmp     rcx, rsi
    jge     .done
    xor     al, [rdi + rcx]
    inc     rcx
    jmp     .loop
.done:
    mov     [rdx], al
    ret

; -----------------------------------------------------------------------------
; umath_parity_even_u32 - even parity bit (alias of parity_u32)
; args:    edi = val
; returns: eax = parity of val (1 if val has odd popcount)
; note:    "even parity" scheme: appending this bit makes the total
;          number of set bits even.
; -----------------------------------------------------------------------------
global umath_parity_even_u32
umath_parity_even_u32:
    popcnt  eax, edi
    and     eax, 1
    ret

; -----------------------------------------------------------------------------
; umath_parity_odd_u32 - odd parity bit
; args:    edi = val
; returns: eax = complement of parity_u32 (for odd-parity schemes)
; -----------------------------------------------------------------------------
global umath_parity_odd_u32
umath_parity_odd_u32:
    popcnt  eax, edi
    and     eax, 1
    xor     eax, 1
    ret
%endif ; GUARD_LIB_UMATH_BITS_PARITY_ASM
