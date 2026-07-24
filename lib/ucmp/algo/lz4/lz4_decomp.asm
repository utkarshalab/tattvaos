; =============================================================================
; Tattva OS — lib/ucmp/algo/lz4/lz4_decomp.asm
; =============================================================================
; Production-grade LZ4 High-Speed Decompressor.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_lz4_decompress

; -----------------------------------------------------------------------------
; ucmp_lz4_decompress
;
; Decompresses LZ4 block into raw destination buffer.
;
; Inputs:
;   RDI = Pointer to compressed source buffer
;   RSI = Compressed source length in bytes
;   RDX = Pointer to destination buffer
;   RCX = Destination capacity in bytes
;
; Returns:
;   RAX = Uncompressed bytes written (or negative error code)
; -----------------------------------------------------------------------------
align 32
ucmp_lz4_decompress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written

.decomp_loop:
    cmp r12, r9
    jge .done

    ; Read Token Byte [Literal Len (4-bit) | Match Len (4-bit)]
    movzx rax, byte [r8 + r12]
    inc r12

    mov rbx, rax
    shr rbx, 4                      ; RBX = literal_len
    and rax, 0x0F                   ; RAX = match_len_token

    ; Read Literal Length Extensions
    cmp rbx, 15
    jne .read_literals

.read_lit_ext:
    cmp r12, r9
    jge .corrupt_err
    movzx rcx, byte [r8 + r12]
    inc r12
    add rbx, rcx
    cmp rcx, 255
    je .read_lit_ext

.read_literals:
    ; Copy raw literal bytes
    test rbx, rbx
    jz .check_match

.copy_literals_loop:
    cmp r12, r9
    jge .corrupt_err
    cmp r13, r11
    jge .overflow_err

    mov cl, byte [r8 + r12]
    mov byte [r10 + r13], cl
    inc r12
    inc r13
    dec rbx
    jnz .copy_literals_loop

.check_match:
    ; If we reached end of stream, finish
    cmp r12, r9
    jge .done

    ; Read 16-bit Little-Endian Offset
    mov r14w, word [r8 + r12]
    add r12, 2
    movzx r14, r14w                 ; R14 = offset

    test r14, r14
    jz .corrupt_err                 ; Offset 0 is invalid

    ; Match Length = match_len_token + 4
    mov rbx, rax
    add rbx, UCMP_LZ4_MIN_MATCH     ; RBX = match_length

    ; Read Match Length Extensions
    cmp rax, 15
    jne .copy_match

.read_match_ext:
    cmp r12, r9
    jge .corrupt_err
    movzx rcx, byte [r8 + r12]
    inc r12
    add rbx, rcx
    cmp rcx, 255
    je .read_match_ext

.copy_match:
    ; Match Source Pointer = dst_written - offset
    mov r15, r13
    sub r15, r14
    js .corrupt_err                 ; Invalid offset prior to dst_start

.copy_match_loop:
    cmp r13, r11
    jge .overflow_err

    mov cl, byte [r10 + r15]
    mov byte [r10 + r13], cl
    inc r15
    inc r13
    dec rbx
    jnz .copy_match_loop

    jmp .decomp_loop

.corrupt_err:
    mov rax, UCMP_ERR_CORRUPT
    UCMP_RESTORE_REGS
    ret

.overflow_err:
    mov rax, UCMP_ERR_BUFF_TOO_SMALL
    UCMP_RESTORE_REGS
    ret

.done:
    mov rax, r13                    ; Return uncompressed bytes written
    UCMP_RESTORE_REGS
    ret
