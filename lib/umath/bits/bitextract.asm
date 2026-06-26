; =============================================================================
; umath - unified math library
; bits/bitextract.asm - generic bit field extraction
; =============================================================================
; general-purpose bit field extraction, independent of dtype.
; complements dtype_pack.asm (which is dtype-aware) with raw
; position/width based extraction for arbitrary bitfields —
; used by encoding/compression, header parsing, GF element access.
;
; functions:
;   umath_bitextract_u32     (val, pos, width -> extracted value)
;   umath_bitextract_u64     (val, pos, width -> extracted value)
;   umath_bitextract_s32     (val, pos, width -> sign-extended value)
;   umath_bitextract_s64     (val, pos, width -> sign-extended value)
;   umath_bitextract_pext32  (val, mask -> extracted via PEXT, BMI2)
;   umath_bitextract_pext64  (val, mask -> extracted via PEXT, BMI2)
;   umath_bitextract_buf     (*buf, bit_offset, width -> u64 value)
;                             extract arbitrary bitfield (<=64 bits) from
;                             a byte buffer at arbitrary bit offset
;   umath_bitextract_buf128  (*buf, bit_offset, width -> rax=lo, rdx=hi)
;                             extract up to 128-bit field
;   umath_bitextract_range   (val, hi, lo -> bits[hi:lo], inclusive)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bitextract_u32 - extract `width` bits starting at `pos` (unsigned)
; args:    edi = value
;          esi = pos (0-31)
;          edx = width (1-32)
; returns: eax = extracted value, right-justified, zero-extended
; -----------------------------------------------------------------------------
global umath_bitextract_u32
umath_bitextract_u32:
    mov     eax, edi
    mov     ecx, esi
    shr     eax, cl
    ; mask = (1 << width) - 1; handle width==32 (shift by 32 is UB on x86)
    cmp     edx, 32
    jge     .full_mask
    mov     ecx, edx
    mov     r8d, 1
    shl     r8d, cl
    dec     r8d
    and     eax, r8d
    ret
.full_mask:
    ret                          ; width==32: no mask needed, value already shifted appropriately

; -----------------------------------------------------------------------------
; umath_bitextract_u64 - extract `width` bits starting at `pos` (unsigned)
; args:    rdi = value
;          esi = pos (0-63)
;          edx = width (1-64)
; returns: rax = extracted value, right-justified, zero-extended
; -----------------------------------------------------------------------------
global umath_bitextract_u64
umath_bitextract_u64:
    mov     rax, rdi
    mov     ecx, esi
    shr     rax, cl
    cmp     edx, 64
    jge     .full_mask
    mov     ecx, edx
    mov     r8, 1
    shl     r8, cl
    dec     r8
    and     rax, r8
    ret
.full_mask:
    ret

; -----------------------------------------------------------------------------
; umath_bitextract_s32 - extract `width` bits and sign-extend result
; args:    edi = value, esi = pos (0-31), edx = width (1-32)
; returns: eax = sign-extended extracted value
; -----------------------------------------------------------------------------
global umath_bitextract_s32
umath_bitextract_s32:
    mov     eax, edi
    mov     ecx, esi
    shr     eax, cl
    cmp     edx, 32
    jge     .done                ; already full width, no sign extend needed beyond natural
    ; shift left to put sign bit at bit 31, then arithmetic shift right
    mov     ecx, 32
    sub     ecx, edx
    shl     eax, cl
    sar     eax, cl
.done:
    ret

; -----------------------------------------------------------------------------
; umath_bitextract_s64 - extract `width` bits and sign-extend result
; args:    rdi = value, esi = pos (0-63), edx = width (1-64)
; returns: rax = sign-extended extracted value
; -----------------------------------------------------------------------------
global umath_bitextract_s64
umath_bitextract_s64:
    mov     rax, rdi
    mov     ecx, esi
    shr     rax, cl
    cmp     edx, 64
    jge     .done
    mov     ecx, 64
    sub     ecx, edx
    shl     rax, cl
    sar     rax, cl
.done:
    ret

; -----------------------------------------------------------------------------
; umath_bitextract_pext32 - extract bits selected by mask (BMI2 PEXT)
; args:    edi = value, esi = mask
; returns: eax = packed extracted bits
; -----------------------------------------------------------------------------
global umath_bitextract_pext32
umath_bitextract_pext32:
    pext    eax, edi, esi
    ret

; -----------------------------------------------------------------------------
; umath_bitextract_pext64 - extract bits selected by mask (BMI2 PEXT)
; args:    rdi = value, rsi = mask
; returns: rax = packed extracted bits
; -----------------------------------------------------------------------------
global umath_bitextract_pext64
umath_bitextract_pext64:
    pext    rax, rdi, rsi
    ret

; -----------------------------------------------------------------------------
; umath_bitextract_buf - extract a bitfield (<=64 bits) from a byte buffer
; args:    rdi = pointer to buffer (assumed readable for at least 8 bytes
;                beyond bit_offset/8, i.e. caller ensures bounds)
;          rsi = bit_offset (absolute bit position from start of buffer)
;          edx = width (1-64)
; returns: rax = extracted value, right-justified, zero-extended
;
; algorithm: load an unaligned u64 starting at byte_offset = bit_offset/8,
;            shift right by (bit_offset%8), mask to width bits.
;            if width spans beyond 64 bits from byte_offset (i.e.
;            bit_in_byte + width > 64), loads next byte too.
; -----------------------------------------------------------------------------
global umath_bitextract_buf
umath_bitextract_buf:
    push    rbx
    mov     rax, rsi
    shr     rax, 3              ; byte_offset
    mov     rcx, rsi
    and     rcx, 7              ; bit_in_byte (0-7)

    ; load 8 bytes at byte_offset
    mov     rbx, [rdi + rax]
    shr     rbx, cl             ; shift down by bit_in_byte

    ; check if we need one more byte (bit_in_byte + width > 64)
    mov     r8d, ecx
    add     r8d, edx
    cmp     r8d, 64
    jle     .mask
    ; need extra byte: load byte at offset+8, shift left by (64-bit_in_byte), OR in
    movzx   r9, byte [rdi + rax + 8]
    mov     r10d, 64
    sub     r10d, ecx
    mov     rcx, r10
    shl     r9, cl
    or      rbx, r9

.mask:
    mov     rax, rbx
    cmp     edx, 64
    jge     .done
    mov     ecx, edx
    mov     r8, 1
    shl     r8, cl
    dec     r8
    and     rax, r8
.done:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitextract_buf128 - extract a bitfield up to 128 bits from buffer
; args:    rdi = pointer to buffer
;          rsi = bit_offset
;          edx = width (1-128)
; returns: rax = low 64 bits of extracted value
;          rdx = high bits of extracted value (0 if width<=64)
;
; algorithm: extract low min(width,64) bits via umath_bitextract_buf,
;            then if width>64, extract remaining (width-64) bits
;            starting at bit_offset+64
; -----------------------------------------------------------------------------
global umath_bitextract_buf128
umath_bitextract_buf128:
    push    rbx
    push    r12
    push    r13
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx

    cmp     r13d, 64
    jle     .low_only

    ; extract low 64 bits
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, 64
    call    umath_bitextract_buf
    mov     r8, rax             ; low result

    ; extract high (width-64) bits
    mov     edx, r13d
    sub     edx, 64
    mov     rdi, rbx
    mov     rsi, r12
    add     rsi, 64
    call    umath_bitextract_buf
    mov     rdx, rax            ; high result
    mov     rax, r8

    pop     r13
    pop     r12
    pop     rbx
    ret

.low_only:
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    call    umath_bitextract_buf
    xor     rdx, rdx
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitextract_range - extract inclusive bit range [hi:lo] from value
; args:    rdi = value
;          esi = hi (bit index, inclusive)
;          edx = lo (bit index, inclusive)
; returns: rax = bits[hi:lo], right-justified
; -----------------------------------------------------------------------------
global umath_bitextract_range
umath_bitextract_range:
    mov     rax, rdi
    mov     ecx, edx
    shr     rax, cl
    ; width = hi - lo + 1
    mov     ecx, esi
    sub     ecx, edx
    inc     ecx
    cmp     ecx, 64
    jge     .done
    mov     r8, 1
    shl     r8, cl
    dec     r8
    and     rax, r8
.done:
    ret