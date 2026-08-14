%ifndef GUARD_LIB_UCMP_CORE_BITSTREAM_ASM
%define GUARD_LIB_UCMP_CORE_BITSTREAM_ASM
; =============================================================================
; Tattva OS — lib/ucmp/core/bitstream.asm
; =============================================================================
; Bit-Level Reader & Writer Engine (LSB/MSB) for DEFLATE & Huffman Coding.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

struc ucmp_bitstream_t
    .buf_ptr:           resq 1      ; Source/Destination buffer
    .buf_len:           resq 1      ; Capacity
    .byte_pos:          resq 1      ; Byte offset
    .bit_accum:         resq 1      ; 64-bit accumulator register
    .bits_count:        resd 1      ; Count of valid bits in accumulator
endstruc

section .text

global ucmp_bitstream_init
global ucmp_bitstream_read_bits
global ucmp_bitstream_write_bits

; -----------------------------------------------------------------------------
; ucmp_bitstream_init
; -----------------------------------------------------------------------------
align 32
ucmp_bitstream_init:
    mov [rdi + ucmp_bitstream_t.buf_ptr], rsi
    mov [rdi + ucmp_bitstream_t.buf_len], rdx
    mov qword [rdi + ucmp_bitstream_t.byte_pos], 0
    mov qword [rdi + ucmp_bitstream_t.bit_accum], 0
    mov dword [rdi + ucmp_bitstream_t.bits_count], 0
    ret

; -----------------------------------------------------------------------------
; ucmp_bitstream_read_bits
;
; Inputs:
;   RDI = Pointer to ucmp_bitstream_t
;   ESI = Number of bits to read (1..32)
;
; Returns:
;   EAX = Value of bits read
; -----------------------------------------------------------------------------
align 32
ucmp_bitstream_read_bits:
    UCMP_SAVE_REGS

    mov r8, rdi
    mov ecx, esi                    ; ECX = bits_needed

.refill_loop:
    cmp dword [r8 + ucmp_bitstream_t.bits_count], ecx
    jge .extract_bits

    ; Refill 8 bits from source buffer
    mov r9, [r8 + ucmp_bitstream_t.byte_pos]
    cmp r9, [r8 + ucmp_bitstream_t.buf_len]
    jge .extract_bits

    mov r10, [r8 + ucmp_bitstream_t.buf_ptr]
    movzx r11, byte [r10 + r9]
    inc qword [r8 + ucmp_bitstream_t.byte_pos]

    mov rdx, [r8 + ucmp_bitstream_t.bit_accum]
    mov eax, [r8 + ucmp_bitstream_t.bits_count]
    shl r11, cl
    or rdx, r11
    mov [r8 + ucmp_bitstream_t.bit_accum], rdx
    add dword [r8 + ucmp_bitstream_t.bits_count], 8
    jmp .refill_loop

.extract_bits:
    mov rdx, [r8 + ucmp_bitstream_t.bit_accum]
    mov eax, 1
    shl eax, cl
    dec eax                         ; EAX = mask ((1 << n) - 1)
    and eax, edx

    shr rdx, cl
    mov [r8 + ucmp_bitstream_t.bit_accum], rdx
    sub dword [r8 + ucmp_bitstream_t.bits_count], ecx

    UCMP_RESTORE_REGS
    ret

; -----------------------------------------------------------------------------
; ucmp_bitstream_write_bits
;
; Inputs:
;   RDI = Pointer to ucmp_bitstream_t
;   ESI = Bit value
;   EDX = Number of bits to write (1..32)
; -----------------------------------------------------------------------------
align 32
ucmp_bitstream_write_bits:
    UCMP_SAVE_REGS

    mov r8, rdi
    mov r9, rsi
    mov ecx, edx                    ; ECX = num_bits

    mov r10, [r8 + ucmp_bitstream_t.bit_accum]
    mov eax, [r8 + ucmp_bitstream_t.bits_count]
    shl r9, cl
    or r10, r9
    add eax, ecx
    mov [r8 + ucmp_bitstream_t.bit_accum], r10
    mov [r8 + ucmp_bitstream_t.bits_count], eax

.flush_bytes:
    cmp dword [r8 + ucmp_bitstream_t.bits_count], 8
    jl .done

    mov r11, [r8 + ucmp_bitstream_t.byte_pos]
    cmp r11, [r8 + ucmp_bitstream_t.buf_len]
    jge .done

    mov r12, [r8 + ucmp_bitstream_t.buf_ptr]
    mov byte [r12 + r11], r10b
    inc qword [r8 + ucmp_bitstream_t.byte_pos]

    shr r10, 8
    mov [r8 + ucmp_bitstream_t.bit_accum], r10
    sub dword [r8 + ucmp_bitstream_t.bits_count], 8
    jmp .flush_bytes

.done:
    UCMP_RESTORE_REGS
    ret

%endif ; GUARD_LIB_UCMP_CORE_BITSTREAM_ASM
