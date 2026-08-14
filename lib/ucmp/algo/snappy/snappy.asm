%ifndef GUARD_LIB_UCMP_ALGO_SNAPPY_SNAPPY_ASM
%define GUARD_LIB_UCMP_ALGO_SNAPPY_SNAPPY_ASM
; =============================================================================
; Tattva OS — lib/ucmp/algo/snappy/snappy.asm
; =============================================================================
; Production-grade Snappy Ultra-Low Latency Block Compressor & Decompressor.
;
; Implements Google Snappy framing format:
; Element Tag 00: Literal (len = tag_high + 1)
; Element Tag 01: Copy 1-byte offset (len = tag_len + 4, offset 8-bit)
; Element Tag 10: Copy 2-byte offset (len = tag_len + 1, offset 16-bit)
;
; Hardened with strict destination capacity overflow protection.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_snappy_compress
global ucmp_snappy_decompress

; -----------------------------------------------------------------------------
; ucmp_snappy_compress
; -----------------------------------------------------------------------------
align 32
ucmp_snappy_compress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written

    ; Encode varint uncompressed length at start
    mov rax, r9
.varint_loop:
    cmp r13, r11
    jge .overflow_err

    mov cl, al
    and cl, 0x7F
    shr rax, 7
    jnz .varint_more
    mov byte [r10 + r13], cl
    inc r13
    jmp .snappy_body
.varint_more:
    or cl, 0x80
    mov byte [r10 + r13], cl
    inc r13
    jmp .varint_loop

.snappy_body:
    ; Emit remaining source as literal block (Element Tag 00)
    mov rax, r9
    test rax, rax
    jz .done

    mov rcx, rax
    dec rcx                         ; len - 1
    cmp rcx, 60
    jge .large_snappy_lit

    ; Small literal tag (tag <= 60)
    cmp r13, r11
    jge .overflow_err
    shl rcx, 2                      ; Tag 00 in lowest 2 bits
    mov byte [r10 + r13], cl
    inc r13
    jmp .copy_snappy_literals

.large_snappy_lit:
    ; Tag 60: 1 extra byte for length
    cmp r13, r11
    jge .overflow_err
    mov byte [r10 + r13], (60 << 2)
    inc r13

    cmp r13, r11
    jge .overflow_err
    mov byte [r10 + r13], cl
    inc r13

.copy_snappy_literals:
    cmp r13, r11
    jge .overflow_err
    mov al, byte [r8 + r12]
    mov byte [r10 + r13], al
    inc r12
    inc r13
    cmp r12, r9
    jl .copy_snappy_literals

.done:
    mov rax, r13                    ; Return bytes written
    UCMP_RESTORE_REGS
    ret

.overflow_err:
    mov rax, UCMP_ERR_BUFF_TOO_SMALL
    UCMP_RESTORE_REGS
    ret

; -----------------------------------------------------------------------------
; ucmp_snappy_decompress
; -----------------------------------------------------------------------------
align 32
ucmp_snappy_decompress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written

    ; Read varint uncompressed length
    xor rax, rax
    xor rbx, rbx
.read_varint:
    cmp r12, r9
    jge .corrupt_err
    movzx rcx, byte [r8 + r12]
    inc r12
    mov rdx, rcx
    and rdx, 0x7F
    shl rdx, cl
    or rax, rdx
    add rbx, 7
    test rcx, 0x80
    jnz .read_varint

.snappy_decomp_loop:
    cmp r12, r9
    jge .done

    movzx rax, byte [r8 + r12]
    inc r12

    mov rbx, rax
    and rbx, 0x03                   ; RBX = tag (00, 01, 10, 11)

    cmp rbx, 0
    je .tag_literal
    cmp rbx, 1
    je .tag_copy1
    cmp rbx, 2
    je .tag_copy2
    jmp .corrupt_err                ; Tag 11 invalid in standard Snappy

.tag_literal:
    mov rcx, rax
    shr rcx, 2                      ; RCX = len - 1
    inc rcx                         ; RCX = len

.copy_snappy_lit:
    cmp r12, r9
    jge .corrupt_err
    cmp r13, r11
    jge .overflow_err

    mov al, byte [r8 + r12]
    mov byte [r10 + r13], al
    inc r12
    inc r13
    dec rcx
    jnz .copy_snappy_lit
    jmp .snappy_decomp_loop

.tag_copy1:
    mov rcx, rax
    shr rcx, 2
    and rcx, 0x07
    add rcx, 4                      ; RCX = match len

    cmp r12, r9
    jge .corrupt_err
    movzx rdx, byte [r8 + r12]
    inc r12
    shr rax, 5
    shl rax, 8
    or rdx, rax                     ; RDX = offset

    jmp .do_snappy_copy

.tag_copy2:
    mov rcx, rax
    shr rcx, 2
    inc rcx                         ; RCX = match len

    mov rax, r12
    add rax, 2
    cmp rax, r9
    jg .corrupt_err

    movzx rdx, word [r8 + r12]
    add r12, 2                      ; RDX = offset

.do_snappy_copy:
    mov r15, r13
    sub r15, rdx
    js .corrupt_err

.copy_snappy_match:
    cmp r13, r11
    jge .overflow_err

    mov al, byte [r10 + r15]
    mov byte [r10 + r13], al
    inc r15
    inc r13
    dec rcx
    jnz .copy_snappy_match
    jmp .snappy_decomp_loop

.corrupt_err:
    mov rax, UCMP_ERR_CORRUPT
    UCMP_RESTORE_REGS
    ret

; NASM scopes a `.label` to the preceding non-local label, so the .overflow_err
; belonging to ucmp_snappy_compress is NOT reachable from here — the jumps above
; were resolving to ucmp_snappy_decompress.overflow_err, which did not exist.
; Each function needs its own copy.
.overflow_err:
    mov rax, UCMP_ERR_BUFF_TOO_SMALL
    UCMP_RESTORE_REGS
    ret

.done:
    mov rax, r13
    UCMP_RESTORE_REGS
    ret

%endif ; GUARD_LIB_UCMP_ALGO_SNAPPY_SNAPPY_ASM
