%ifndef GUARD_LIB_UMATH_BITS_BITMASK_ASM
%define GUARD_LIB_UMATH_BITS_BITMASK_ASM
; =============================================================================
; umath - unified math library
; bits/bitmask.asm - bit mask generation
; =============================================================================
; functions:
;   umath_mask_low32        (u32 n -> u32)  n lowest bits set
;   umath_mask_low64        (u64 n -> u64)  n lowest bits set
;   umath_mask_high32       (u32 n -> u32)  n highest bits set
;   umath_mask_high64       (u64 n -> u64)  n highest bits set
;   umath_mask_single32     (u32 n -> u32)  single bit at position n
;   umath_mask_single64     (u64 n -> u64)  single bit at position n
;   umath_mask_range32      (u32 lo, u32 hi -> u32)  bits lo..hi inclusive
;   umath_mask_range64      (u64 lo, u64 hi -> u64)  bits lo..hi inclusive
;   umath_mask_clear32      (u32 val, u32 mask -> u32) clear masked bits
;   umath_mask_clear64      (u64 val, u64 mask -> u64) clear masked bits
;   umath_mask_set32        (u32 val, u32 mask -> u32) set masked bits
;   umath_mask_set64        (u64 val, u64 mask -> u64) set masked bits
;   umath_mask_toggle32     (u32 val, u32 mask -> u32) toggle masked bits
;   umath_mask_toggle64     (u64 val, u64 mask -> u64) toggle masked bits
;   umath_mask_extract32    (u32 val, u32 mask -> u32) extract masked bits
;   umath_mask_extract64    (u64 val, u64 mask -> u64) extract masked bits
;   umath_mask_isolate_lsb32(u32 val -> u32) isolate lowest set bit
;   umath_mask_isolate_lsb64(u64 val -> u64) isolate lowest set bit
;   umath_mask_clear_lsb32  (u32 val -> u32) clear lowest set bit
;   umath_mask_clear_lsb64  (u64 val -> u64) clear lowest set bit
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_mask_low32 - create mask with n lowest bits set
; args:    edi = n (0-32)
; returns: eax = mask
; example: n=4 → 0x0000000F
; note:    n=0  → 0x00000000
;          n=32 → 0xFFFFFFFF
; -----------------------------------------------------------------------------
global umath_mask_low32
umath_mask_low32:
    xor     eax, eax
    cmp     edi, 32
    jae     .all32
    mov     ecx, edi
    mov     eax, 1
    shl     eax, cl
    dec     eax                     ; (1 << n) - 1
    ret
.all32:
    mov     eax, 0xFFFFFFFF
    ret

; -----------------------------------------------------------------------------
; umath_mask_low64 - create mask with n lowest bits set
; args:    rdi = n (0-64)
; returns: rax = mask
; example: n=4 → 0x000000000000000F
; note:    n=0  → 0x0000000000000000
;          n=64 → 0xFFFFFFFFFFFFFFFF
; -----------------------------------------------------------------------------
global umath_mask_low64
umath_mask_low64:
    xor     eax, eax
    cmp     rdi, 64
    jae     .all64
    mov     rcx, rdi
    mov     rax, 1
    shl     rax, cl
    dec     rax                     ; (1 << n) - 1
    ret
.all64:
    mov     rax, 0xFFFFFFFFFFFFFFFF
    ret

; -----------------------------------------------------------------------------
; umath_mask_high32 - create mask with n highest bits set
; args:    edi = n (0-32)
; returns: eax = mask
; example: n=4 → 0xF0000000
; -----------------------------------------------------------------------------
global umath_mask_high32
umath_mask_high32:
    xor     eax, eax
    cmp     edi, 32
    jae     .all_high32
    mov     ecx, edi
    mov     eax, 0xFFFFFFFF
    shr     eax, cl                 ; shift right by (32 - n)... but ecx=n
    not     eax                     ; flip to get high bits
    ret
.all_high32:
    mov     eax, 0xFFFFFFFF
    ret

; -----------------------------------------------------------------------------
; umath_mask_high64 - create mask with n highest bits set
; args:    rdi = n (0-64)
; returns: rax = mask
; example: n=4 → 0xF000000000000000
; -----------------------------------------------------------------------------
global umath_mask_high64
umath_mask_high64:
    xor     eax, eax
    cmp     rdi, 64
    jae     .all_high64
    mov     rcx, rdi
    mov     rax, 0xFFFFFFFFFFFFFFFF
    shr     rax, cl
    not     rax
    ret
.all_high64:
    mov     rax, 0xFFFFFFFFFFFFFFFF
    ret

; -----------------------------------------------------------------------------
; umath_mask_single32 - single bit mask at position n
; args:    edi = n (0-31)
; returns: eax = mask with bit n set
; example: n=3 → 0x00000008
; -----------------------------------------------------------------------------
global umath_mask_single32
umath_mask_single32:
    mov     ecx, edi
    mov     eax, 1
    shl     eax, cl
    ret

; -----------------------------------------------------------------------------
; umath_mask_single64 - single bit mask at position n
; args:    rdi = n (0-63)
; returns: rax = mask with bit n set
; example: n=3 → 0x0000000000000008
; -----------------------------------------------------------------------------
global umath_mask_single64
umath_mask_single64:
    mov     rcx, rdi
    mov     rax, 1
    shl     rax, cl
    ret

; -----------------------------------------------------------------------------
; umath_mask_range32 - mask covering bits lo..hi inclusive
; args:    edi = lo (0-31)
;          esi = hi (0-31), must be >= lo
; returns: eax = mask
; example: lo=4, hi=7 → 0x000000F0
; -----------------------------------------------------------------------------
global umath_mask_range32
umath_mask_range32:
    ; low mask = (1 << (hi - lo + 1)) - 1
    ; result   = low_mask << lo
    mov     eax, esi
    sub     eax, edi                ; eax = hi - lo
    inc     eax                     ; eax = hi - lo + 1 (width)
    mov     ecx, eax
    mov     eax, 1
    shl     eax, cl                 ; eax = 1 << width
    dec     eax                     ; eax = low_mask
    mov     ecx, edi
    shl     eax, cl                 ; eax = low_mask << lo
    ret

; -----------------------------------------------------------------------------
; umath_mask_range64 - mask covering bits lo..hi inclusive
; args:    rdi = lo (0-63)
;          rsi = hi (0-63), must be >= lo
; returns: rax = mask
; example: lo=4, hi=7 → 0x00000000000000F0
; -----------------------------------------------------------------------------
global umath_mask_range64
umath_mask_range64:
    mov     rax, rsi
    sub     rax, rdi                ; rax = hi - lo
    inc     rax                     ; rax = width
    mov     rcx, rax
    mov     rax, 1
    shl     rax, cl
    dec     rax                     ; rax = low_mask
    mov     rcx, rdi
    shl     rax, cl                 ; rax = low_mask << lo
    ret

; -----------------------------------------------------------------------------
; umath_mask_clear32 - clear bits specified by mask
; args:    edi = value (u32)
;          esi = mask  (u32)
; returns: eax = value with masked bits cleared
; -----------------------------------------------------------------------------
global umath_mask_clear32
umath_mask_clear32:
    mov     eax, edi
    not     esi
    and     eax, esi
    ret

; -----------------------------------------------------------------------------
; umath_mask_clear64 - clear bits specified by mask
; args:    rdi = value (u64)
;          rsi = mask  (u64)
; returns: rax = value with masked bits cleared
; -----------------------------------------------------------------------------
global umath_mask_clear64
umath_mask_clear64:
    mov     rax, rdi
    not     rsi
    and     rax, rsi
    ret

; -----------------------------------------------------------------------------
; umath_mask_set32 - set bits specified by mask
; args:    edi = value (u32)
;          esi = mask  (u32)
; returns: eax = value with masked bits set
; -----------------------------------------------------------------------------
global umath_mask_set32
umath_mask_set32:
    mov     eax, edi
    or      eax, esi
    ret

; -----------------------------------------------------------------------------
; umath_mask_set64 - set bits specified by mask
; args:    rdi = value (u64)
;          rsi = mask  (u64)
; returns: rax = value with masked bits set
; -----------------------------------------------------------------------------
global umath_mask_set64
umath_mask_set64:
    mov     rax, rdi
    or      rax, rsi
    ret

; -----------------------------------------------------------------------------
; umath_mask_toggle32 - toggle bits specified by mask
; args:    edi = value (u32)
;          esi = mask  (u32)
; returns: eax = value with masked bits toggled
; -----------------------------------------------------------------------------
global umath_mask_toggle32
umath_mask_toggle32:
    mov     eax, edi
    xor     eax, esi
    ret

; -----------------------------------------------------------------------------
; umath_mask_toggle64 - toggle bits specified by mask
; args:    rdi = value (u64)
;          rsi = mask  (u64)
; returns: rax = value with masked bits toggled
; -----------------------------------------------------------------------------
global umath_mask_toggle64
umath_mask_toggle64:
    mov     rax, rdi
    xor     rax, rsi
    ret

; -----------------------------------------------------------------------------
; umath_mask_extract32 - extract bits at mask positions, packed to low bits
; args:    edi = value (u32)
;          esi = mask  (u32)
; returns: eax = extracted bits packed into lowest positions
; note:    uses PEXT (BMI2) for single instruction extraction
; -----------------------------------------------------------------------------
global umath_mask_extract32
umath_mask_extract32:
    pext    eax, edi, esi
    ret

; -----------------------------------------------------------------------------
; umath_mask_extract64 - extract bits at mask positions, packed to low bits
; args:    rdi = value (u64)
;          rsi = mask  (u64)
; returns: rax = extracted bits packed into lowest positions
; note:    uses PEXT (BMI2)
; -----------------------------------------------------------------------------
global umath_mask_extract64
umath_mask_extract64:
    pext    rax, rdi, rsi
    ret

; -----------------------------------------------------------------------------
; umath_mask_isolate_lsb32 - isolate lowest set bit
; args:    edi = value (u32)
; returns: eax = value with only lowest set bit kept
; example: 0b10110100 → 0b00000100
; note:    returns 0 if input is 0
; -----------------------------------------------------------------------------
global umath_mask_isolate_lsb32
umath_mask_isolate_lsb32:
    mov     eax, edi
    neg     eax
    and     eax, edi                ; x & (-x) isolates lowest set bit
    ret

; -----------------------------------------------------------------------------
; umath_mask_isolate_lsb64 - isolate lowest set bit
; args:    rdi = value (u64)
; returns: rax = value with only lowest set bit kept
; -----------------------------------------------------------------------------
global umath_mask_isolate_lsb64
umath_mask_isolate_lsb64:
    mov     rax, rdi
    neg     rax
    and     rax, rdi
    ret

; -----------------------------------------------------------------------------
; umath_mask_clear_lsb32 - clear lowest set bit
; args:    edi = value (u32)
; returns: eax = value with lowest set bit cleared
; example: 0b10110100 → 0b10110000
; note:    returns 0 if input is 0
; -----------------------------------------------------------------------------
global umath_mask_clear_lsb32
umath_mask_clear_lsb32:
    mov     eax, edi
    dec     eax
    and     eax, edi                ; x & (x-1) clears lowest set bit
    ret

; -----------------------------------------------------------------------------
; umath_mask_clear_lsb64 - clear lowest set bit
; args:    rdi = value (u64)
; returns: rax = value with lowest set bit cleared
; -----------------------------------------------------------------------------
global umath_mask_clear_lsb64
umath_mask_clear_lsb64:
    mov     rax, rdi
    dec     rax
    and     rax, rdi
    ret
%endif ; GUARD_LIB_UMATH_BITS_BITMASK_ASM
