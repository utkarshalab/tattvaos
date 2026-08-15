%ifndef GUARD_LIB_UMATH_BITS_BITINSERT_ASM
%define GUARD_LIB_UMATH_BITS_BITINSERT_ASM
; =============================================================================
; umath - unified math library
; bits/bitinsert.asm - generic bit field insertion
; =============================================================================
; counterpart to bitextract.asm — insert a value into a bitfield at
; arbitrary position/width, either in a register or a byte buffer.
;
; functions:
;   umath_bitinsert_u32     (val, field, pos, width -> new value)
;   umath_bitinsert_u64     (val, field, pos, width -> new value)
;   umath_bitinsert_pdep32  (val, mask -> deposited bits, BMI2 PDEP)
;   umath_bitinsert_pdep64  (val, mask -> deposited bits, BMI2 PDEP)
;   umath_bitinsert_buf     (*buf, bit_offset, width, value -> void)
;                            insert <=64-bit field into byte buffer
;                            at arbitrary bit offset
;   umath_bitinsert_buf128  (*buf, bit_offset, width, lo, hi -> void)
;                            insert up to 128-bit field
;   umath_bitinsert_range   (val, field, hi, lo -> val with bits[hi:lo]=field)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bitinsert_u32 - insert `field` into `val` at bits [pos+width-1:pos]
; args:    edi = val (base value)
;          esi = field (value to insert, only low `width` bits used)
;          edx = pos (0-31)
;          ecx = width (1-32)
; returns: eax = val with field inserted
; -----------------------------------------------------------------------------
global umath_bitinsert_u32
umath_bitinsert_u32:
    push    rbx
    mov     eax, edi            ; base
    mov     ebx, esi            ; field

    ; build mask = (1<<width)-1, handle width==32
    cmp     ecx, 32
    jge     .full_mask
    mov     r8d, 1
    mov     r9d, ecx
    shl     r8d, r9b
    dec     r8d                 ; field mask
    and     ebx, r8d            ; mask field
    ; positioned mask
    mov     r9d, edx
    shl     r8d, r9b            ; positioned mask
    not     r8d
    and     eax, r8d            ; clear target bits
    jmp     .insert
.full_mask:
    xor     eax, eax            ; clearing entire 32-bit value
.insert:
    mov     r9d, edx
    shl     ebx, r9b
    or      eax, ebx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitinsert_u64 - insert `field` into `val` at bits [pos+width-1:pos]
; args:    rdi = val, rsi = field, edx = pos (0-63), ecx = width (1-64)
; returns: rax = val with field inserted
; -----------------------------------------------------------------------------
global umath_bitinsert_u64
umath_bitinsert_u64:
    push    rbx
    mov     rax, rdi
    mov     rbx, rsi

    cmp     ecx, 64
    jge     .full_mask
    mov     r8, 1
    mov     r9d, ecx
    shl     r8, r9b
    dec     r8                  ; field mask
    and     rbx, r8
    mov     r9d, edx
    shl     r8, r9b             ; positioned mask
    not     r8
    and     rax, r8
    jmp     .insert
.full_mask:
    xor     rax, rax
.insert:
    mov     r9d, edx
    shl     rbx, r9b
    or      rax, rbx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitinsert_pdep32 - deposit bits according to mask (BMI2 PDEP)
; args:    edi = val (source bits, packed low)
;          esi = mask
; returns: eax = deposited result
; -----------------------------------------------------------------------------
global umath_bitinsert_pdep32
umath_bitinsert_pdep32:
    pdep    eax, edi, esi
    ret

; -----------------------------------------------------------------------------
; umath_bitinsert_pdep64 - deposit bits according to mask (BMI2 PDEP)
; args:    rdi = val, rsi = mask
; returns: rax = deposited result
; -----------------------------------------------------------------------------
global umath_bitinsert_pdep64
umath_bitinsert_pdep64:
    pdep    rax, rdi, rsi
    ret

; -----------------------------------------------------------------------------
; umath_bitinsert_buf - insert a bitfield (<=64 bits) into byte buffer
; args:    rdi = pointer to buffer (read-modify-write)
;          rsi = bit_offset (absolute bit position from start of buffer)
;          edx = width (1-64)
;          rcx = value (right-justified, only low `width` bits used)
; returns: void
;
; algorithm: load 16 bytes covering the affected region (handles spans
;            up to 64 bits crossing a byte boundary plus 1 extra byte),
;            clear target bits, OR in shifted value, store back.
; -----------------------------------------------------------------------------
global umath_bitinsert_buf
umath_bitinsert_buf:
    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rax, rsi
    shr     rax, 3              ; byte_offset
    mov     r12, rax            ; save byte_offset
    mov     r13, rsi
    and     r13, 7              ; bit_in_byte

    ; load low qword at byte_offset
    mov     rbx, [rdi + r12]

    ; build value mask (low `width` bits)
    mov     r14, rcx
    cmp     edx, 64
    jge     .full_val_mask
    mov     r8, 1
    mov     r9d, edx
    shl     r8, r9b
    dec     r8
    and     r14, r8             ; masked value
    jmp     .have_val_mask
.full_val_mask:
    ; width==64: no mask needed
.have_val_mask:

    ; check if field fits entirely within low qword
    mov     r8d, r13d           ; bit_in_byte
    add     r8d, edx            ; bit_in_byte + width
    cmp     r8d, 64
    jle     .single_word

    ; spans into byte at offset+8: handle low part in rbx, high part separately
    ; low_width = 64 - bit_in_byte
    mov     r9d, 64
    sub     r9d, r13d           ; low_width

    ; clear low_width bits starting at bit_in_byte in rbx
    mov     r8, 1
    mov     r10d, r9d
    cmp     r10d, 64
    jge     .low_mask_full
    shl     r8, r10b
    dec     r8
    jmp     .low_mask_done
.low_mask_full:
    xor     r8, r8
    not     r8                  ; all ones
.low_mask_done:
    mov     r10d, r13d
    shl     r8, r10b            ; positioned clear mask
    not     r8
    and     rbx, r8

    ; insert low_width bits of value at bit_in_byte
    mov     r10, r14
    mov     r11d, r9d
    cmp     r11d, 64
    jge     .low_val_full
    mov     r8, 1
    shl     r8, r11b
    dec     r8
    and     r10, r8
.low_val_full:
    mov     r11d, r13d
    shl     r10, r11b
    or      rbx, r10
    mov     [rdi + r12], rbx

    ; remaining bits go into byte at offset+8
    ; remaining_width = width - low_width
    mov     r8d, edx
    sub     r8d, r9d            ; remaining_width
    ; remaining value = value >> low_width
    mov     r10, r14
    mov     r11d, r9d
    shr     r10, r11b

    ; load byte(s) at offset+8 (load as qword for simplicity)
    mov     rax, [rdi + r12 + 8]
    ; clear remaining_width bits at position 0
    mov     r9, 1
    mov     r11d, r8d
    cmp     r11d, 64
    jge     .hi_mask_full
    shl     r9, r11b
    dec     r9
    jmp     .hi_mask_done
.hi_mask_full:
    xor     r9, r9
    not     r9
.hi_mask_done:
    not     r9
    and     rax, r9
    or      rax, r10
    mov     [rdi + r12 + 8], rax
    jmp     .out

.single_word:
    ; build positioned clear mask
    mov     r8, 1
    mov     r9d, edx
    cmp     r9d, 64
    jge     .sw_mask_full
    shl     r8, r9b
    dec     r8
    jmp     .sw_mask_done
.sw_mask_full:
    xor     r8, r8
    not     r8
.sw_mask_done:
    mov     r9d, r13d
    shl     r8, r9b
    not     r8
    and     rbx, r8

    mov     r9d, r13d
    mov     r10, r14
    shl     r10, r9b
    or      rbx, r10
    mov     [rdi + r12], rbx

.out:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitinsert_buf128 - insert a bitfield up to 128 bits into byte buffer
; args:    rdi = pointer to buffer
;          rsi = bit_offset
;          edx = width (1-128)
;          rcx = value_lo (low 64 bits of value)
;          r8  = value_hi (high bits, used if width>64)
; returns: void
; -----------------------------------------------------------------------------
global umath_bitinsert_buf128
umath_bitinsert_buf128:
    push    rbx
    push    r12
    push    r13
    push    r14
    mov     rbx, rdi
    mov     r12, rsi
    mov     r13d, edx
    mov     r14, rcx            ; value_lo
    ; r8 already holds value_hi

    cmp     r13d, 64
    jle     .low_only

    ; insert low 64 bits
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, 64
    mov     rcx, r14
    call    umath_bitinsert_buf

    ; insert remaining (width-64) bits at bit_offset+64
    mov     edx, r13d
    sub     edx, 64
    mov     rdi, rbx
    mov     rsi, r12
    add     rsi, 64
    mov     rcx, r8

    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    jmp     umath_bitinsert_buf

.low_only:
    mov     rdi, rbx
    mov     rsi, r12
    mov     edx, r13d
    mov     rcx, r14
    call    umath_bitinsert_buf
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; umath_bitinsert_range - set bits[hi:lo] of val to field (inclusive range)
; args:    rdi = val, rsi = field, edx = hi, ecx = lo
; returns: rax = val with bits[hi:lo] replaced by low bits of field
; -----------------------------------------------------------------------------
global umath_bitinsert_range
umath_bitinsert_range:
    push    rbx
    mov     rax, rdi
    mov     rbx, rsi

    ; width = hi - lo + 1
    mov     r8d, edx
    sub     r8d, ecx
    inc     r8d

    cmp     r8d, 64
    jge     .full_mask
    mov     r9, 1
    mov     r10d, r8d
    shl     r9, r10b
    dec     r9                  ; field mask
    and     rbx, r9
    mov     r10d, ecx
    shl     r9, r10b            ; positioned mask
    not     r9
    and     rax, r9
    jmp     .insert
.full_mask:
    xor     rax, rax
.insert:
    mov     r10d, ecx
    shl     rbx, r10b
    or      rax, rbx
    pop     rbx
    ret
%endif ; GUARD_LIB_UMATH_BITS_BITINSERT_ASM
