%ifndef GUARD_LIB_UMATH_BITS_BIT2_ASM
%define GUARD_LIB_UMATH_BITS_BIT2_ASM
; =============================================================================
; umath - unified math library
; bits/bit2.asm - 2-bit operations
; =============================================================================
; used for: sparse 2:4 metadata, 2-bit quantization, tropical/ternary logic
;
; functions:
;   umath_bit2_get          (packed, index -> 2-bit value, 0-3)
;   umath_bit2_set          (packed, index, val -> packed)
;   umath_bit2_pack4        (e0,e1,e2,e3 -> packed byte, 4x 2-bit)
;   umath_bit2_unpack4      (packed_byte -> e0,e1,e2,e3 via rax/rdx packing)
;   umath_bit2_add_sat      (a, b -> saturating add, clamp to 3)
;   umath_bit2_sub_sat      (a, b -> saturating sub, clamp to 0)
;   umath_bit2_max          (a, b -> max of two 2-bit values)
;   umath_bit2_min          (a, b -> min of two 2-bit values)
;   umath_bit2_cmp          (a, b -> -1/0/1)
;   umath_bit2_rotate       (val, amount -> rotated 2-bit value)
;   umath_bit2_popcount     (packed_byte -> count of nonzero 2-bit groups)
;   umath_bit2_mask24       (idx0, idx1 -> 2:4 sparsity mask byte)
;   umath_bit2_mask24_decode(mask -> idx0, idx1 in rax/rdx)
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_bit2_get - extract 2-bit value at index from packed byte/word
; args:    rdi = packed value
;          esi = index (0-based, each index = 2 bits)
; returns: rax = 2-bit value (0-3)
; -----------------------------------------------------------------------------
global umath_bit2_get
umath_bit2_get:
    mov     rax, rdi
    mov     ecx, esi
    shl     ecx, 1          ; shift = index * 2
    shr     rax, cl
    and     rax, 0x3
    ret

; -----------------------------------------------------------------------------
; umath_bit2_set - set 2-bit value at index in packed value
; args:    rdi = packed value
;          esi = index
;          edx = new 2-bit value (0-3)
; returns: rax = updated packed value
; -----------------------------------------------------------------------------
global umath_bit2_set
umath_bit2_set:
    mov     rax, rdi
    mov     ecx, esi
    shl     ecx, 1          ; shift = index * 2
    mov     r8, 0x3
    shl     r8, cl          ; positioned mask
    not     r8
    and     rax, r8         ; clear target bits
    mov     r9, rdx
    and     r9, 0x3
    shl     r9, cl
    or      rax, r9
    ret

; -----------------------------------------------------------------------------
; umath_bit2_pack4 - pack four 2-bit values into one byte
; args:    dil = e0 (bits 1:0)
;          sil = e1 (bits 3:2)
;          dl  = e2 (bits 5:4)
;          cl  = e3 (bits 7:6)
; returns: al  = packed byte
; -----------------------------------------------------------------------------
global umath_bit2_pack4
umath_bit2_pack4:
    mov     al, dil
    and     al, 0x3
    mov     ah, sil
    and     ah, 0x3
    shl     ah, 2
    or      al, ah
    mov     ah, dl
    and     ah, 0x3
    shl     ah, 4
    or      al, ah
    mov     ah, cl
    and     ah, 0x3
    shl     ah, 6
    or      al, ah
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_unpack4 - unpack byte into four 2-bit values
; args:    dil = packed byte
; returns: rax = e0 | (e1<<8) | (e2<<16) | (e3<<24)  (each byte = 0-3)
; note:    caller extracts via shifts/masks; avoids multi-return complexity
; -----------------------------------------------------------------------------
global umath_bit2_unpack4
umath_bit2_unpack4:
    xor     eax, eax
    mov     cl, dil
    mov     al, cl
    and     al, 0x3                 ; e0
    mov     ah, cl
    shr     ah, 2
    and     ah, 0x3                 ; e1
    mov     dl, cl
    shr     dl, 4
    and     dl, 0x3                 ; e2
    mov     dh, cl
    shr     dh, 6
    and     dh, 0x3                 ; e3
    ; pack e0,e1 into ax already done
    ; pack e2,e3 into dx
    movzx   ecx, dx
    shl     ecx, 16
    movzx   eax, ax
    or      eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_bit2_add_sat - saturating add of two 2-bit values, clamp to 3
; args:    dil = a (0-3)
;          sil = b (0-3)
; returns: al  = min(a+b, 3)
; -----------------------------------------------------------------------------
global umath_bit2_add_sat
umath_bit2_add_sat:
    mov     al, dil
    add     al, sil
    cmp     al, 3
    jbe     .done
    mov     al, 3
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_sub_sat - saturating sub of two 2-bit values, clamp to 0
; args:    dil = a (0-3)
;          sil = b (0-3)
; returns: al  = max(a-b, 0)
; -----------------------------------------------------------------------------
global umath_bit2_sub_sat
umath_bit2_sub_sat:
    mov     al, dil
    cmp     al, sil
    jae     .sub
    xor     eax, eax
    ret
.sub:
    sub     al, sil
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_max - max of two 2-bit values
; args:    dil = a, sil = b
; returns: al  = max(a,b)
; -----------------------------------------------------------------------------
global umath_bit2_max
umath_bit2_max:
    mov     al, dil
    cmp     al, sil
    jae     .done
    mov     al, sil
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_min - min of two 2-bit values
; args:    dil = a, sil = b
; returns: al  = min(a,b)
; -----------------------------------------------------------------------------
global umath_bit2_min
umath_bit2_min:
    mov     al, dil
    cmp     al, sil
    jbe     .done
    mov     al, sil
.done:
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_cmp - compare two 2-bit values
; args:    dil = a, sil = b
; returns: eax = -1 if a<b, 0 if equal, 1 if a>b
; -----------------------------------------------------------------------------
global umath_bit2_cmp
umath_bit2_cmp:
    mov     al, dil
    cmp     al, sil
    je      .eq
    jb      .lt
    mov     eax, 1
    ret
.eq:
    xor     eax, eax
    ret
.lt:
    mov     eax, -1
    ret

; -----------------------------------------------------------------------------
; umath_bit2_rotate - rotate 2-bit value (mod 4 rotation of the 2-bit field)
; args:    dil = val (0-3)
;          sil = amount (rotation amount, mod 4)
; returns: al  = rotated value within 2-bit space
; note:    rotates the 2-bit value as a 2-bit ring: 0->1->2->3->0
; -----------------------------------------------------------------------------
global umath_bit2_rotate
umath_bit2_rotate:
    mov     al, dil
    and     al, 0x3
    mov     cl, sil
    and     cl, 0x3
    add     al, cl
    and     al, 0x3
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_popcount - count nonzero 2-bit groups in a byte
; args:    dil = packed byte (4x 2-bit groups)
; returns: eax = count of groups that are nonzero (0-4)
; -----------------------------------------------------------------------------
global umath_bit2_popcount
umath_bit2_popcount:
    xor     eax, eax
    mov     cl, dil
    test    cl, 0x03
    setnz   dl
    add     al, dl
    mov     dl, cl
    shr     dl, 2
    and     dl, 0x03
    test    dl, dl
    setnz   dh
    add     al, dh
    mov     dl, cl
    shr     dl, 4
    and     dl, 0x03
    test    dl, dl
    setnz   dh
    add     al, dh
    mov     dl, cl
    shr     dl, 6
    and     dl, 0x03
    test    dl, dl
    setnz   dh
    add     al, dh
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_mask24 - build 2:4 structured sparsity mask byte
; args:    dil = idx0 (0-3, position of first nonzero in group of 4)
;          sil = idx1 (0-3, position of second nonzero in group of 4)
; returns: al  = mask byte: bit idx0 set, bit idx1 set (2 of 4 bits set)
; note:    used for NVIDIA-style 2:4 structured sparsity metadata
; -----------------------------------------------------------------------------
global umath_bit2_mask24
umath_bit2_mask24:
    mov     al, 1
    mov     cl, dil
    and     cl, 0x3
    shl     al, cl
    mov     ah, 1
    mov     cl, sil
    and     cl, 0x3
    shl     ah, cl
    or      al, ah
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_bit2_mask24_decode - decode 2:4 sparsity mask back to indices
; args:    dil = mask byte (exactly 2 bits set, within low nibble)
; returns: eax = idx0 (lowest set bit position)
;          edx = idx1 (highest set bit position)
; -----------------------------------------------------------------------------
global umath_bit2_mask24_decode
umath_bit2_mask24_decode:
    movzx   ecx, dil
    and     ecx, 0xF
    ; idx0 = position of lowest set bit
    tzcnt   eax, ecx
    ; clear lowest set bit, idx1 = position of remaining bit
    mov     edx, ecx
    blsr    edx, edx        ; clear lowest set bit (BMI1)
    tzcnt   edx, edx
    ret
%endif ; GUARD_LIB_UMATH_BITS_BIT2_ASM
