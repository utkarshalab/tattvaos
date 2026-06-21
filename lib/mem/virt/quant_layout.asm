; =============================================================================
; Tattva OS — lib/mem/virt/quant_layout.asm
; =============================================================================
; Quantized Memory Layout Manager — Subfeature 36.6.
;
; Optimizes layout for low-precision tensor operations (INT4/NF4).
; Packs pairs of 4-bit weights into single bytes inside 64-bit registers.
; Validates 32-byte boundary alignment to guarantee compatibility with
; high-performance AVX2 vector registers.
;
; API:
;   quant_layout_pack_int4(src, dst, count)   — Pack count bytes into count/2 bytes.
;   quant_layout_unpack_int4(src, dst, count) — Unpack count/2 bytes to count bytes.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_QUANT_LAYOUT_ASM
%define LIB_MEM_VIRT_QUANT_LAYOUT_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; quant_layout_pack_int4 — Pack 4-bit weights (1 per byte) into packed bytes
; Input:
;   RDI = Source bytes buffer (each byte contains 4-bit weight in bits 3:0)
;   RSI = Destination buffer (will store packed bytes: 2 weights per byte)
;   RDX = Weight count (must be multiple of 2)
; Output: RAX = Packed byte count, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8, R9
; ---------------------------------------------------------------------------
global quant_layout_pack_int4
quant_layout_pack_int4:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdx, rdx
    jz   .fail
    test rdx, 1                     ; must be multiple of 2
    jnz  .fail

    ; Check AVX2 alignment (32-byte boundary) on buffers
    mov  rax, rsi
    and  rax, 31
    jnz  .no_avx2_align
    inc  qword [sys_quant_avx2_alignments]
.no_avx2_align:

    mov  rcx, rdx
    shr  rcx, 1                     ; RCX = packed bytes count
    mov  r9, rcx                    ; save return count
    xor  r8, r8                     ; source index

.pack_loop:
    movzx eax, byte [rdi + r8]      ; EAX = weight A (low 4 bits)
    and  eax, 0x0F
    
    movzx ebx, byte [rdi + r8 + 1]  ; EBX = weight B (low 4 bits)
    and  ebx, 0x0F
    shl  ebx, 4
    
    or   eax, ebx                   ; EAX = packed byte (B in high nibble, A in low)
    mov  [rsi], al
    inc  rsi                        ; advance dest by 1 byte
    add  r8, 2                      ; advance source by 2 bytes
    loop .pack_loop

    inc  qword [sys_quant_packed_weights]
    mov  rax, r9                    ; return packed bytes count
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; quant_layout_unpack_int4 — Unpack 4-bit packed weights into individual bytes
; Input:
;   RDI = Source packed bytes buffer (2 weights per byte)
;   RSI = Destination byte buffer (1 weight per byte, in bits 3:0)
;   RDX = Output weight count (must be multiple of 2)
; Output: RAX = Unpacked weights count, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8
; ---------------------------------------------------------------------------
global quant_layout_unpack_int4
quant_layout_unpack_int4:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdx, rdx
    jz   .fail
    test rdx, 1
    jnz  .fail

    mov  rcx, rdx
    shr  rcx, 1                     ; RCX = source bytes count
    mov  r8, rdx                    ; R8 = return count
    xor  rdx, rdx                   ; destination index

.unpack_loop:
    movzx eax, byte [rdi]           ; EAX = packed byte
    inc  rdi                        ; advance source

    ; Extract weight A
    mov  ebx, eax
    and  ebx, 0x0F                  ; mask low nibble
    mov  [rsi + rdx], bl

    ; Extract weight B
    mov  ebx, eax
    shr  ebx, 4                     ; mask high nibble
    and  ebx, 0x0F
    mov  [rsi + rdx + 1], bl

    add  rdx, 2                     ; advance dest index by 2
    loop .unpack_loop

    mov  rax, r8
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_quant_packed_weights
sys_quant_packed_weights:       dq 0

align 8
global sys_quant_avx2_alignments
sys_quant_avx2_alignments:      dq 0

section .text

%endif ; LIB_MEM_VIRT_QUANT_LAYOUT_ASM
