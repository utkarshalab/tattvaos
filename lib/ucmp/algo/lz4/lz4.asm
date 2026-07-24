; =============================================================================
; Tattva OS — lib/ucmp/algo/lz4/lz4.asm
; =============================================================================
; Production-grade LZ4 High-Speed Streaming Compressor.
;
; Implements standard LZ4 block format:
; Token Byte [Literal Length (4-bit) | Match Length (4-bit)]
; Followed by 16-bit Little-Endian Match Offset.
;
; Hardened with strict destination capacity overflow protection.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "lib/ucmp/include/ucmp.inc"
%include "lib/ucmp/arch/common/macros.inc"

section .text

global ucmp_lz4_compress

extern ucmp_avx2_scan_match_length

; -----------------------------------------------------------------------------
; ucmp_lz4_compress
;
; Inputs:
;   RDI = Pointer to source buffer
;   RSI = Source length in bytes
;   RDX = Pointer to destination buffer
;   RCX = Destination capacity in bytes
;
; Returns:
;   RAX = Compressed bytes written (or negative error code)
; -----------------------------------------------------------------------------
align 32
ucmp_lz4_compress:
    UCMP_SAVE_REGS

    mov r8, rdi                     ; R8 = src_start
    mov r9, rsi                     ; R9 = src_len
    mov r10, rdx                    ; R10 = dst_start
    mov r11, rcx                    ; R11 = dst_cap

    xor r12, r12                    ; R12 = src_pos
    xor r13, r13                    ; R13 = dst_written
    mov r14, r12                    ; R14 = anchor (start of uncompressed literals)

.compress_loop:
    mov rax, r9
    sub rax, r12
    cmp rax, 12                     ; LZ4 requires at least 12 trailing bytes
    jle .flush_last_literals

    ; Search for match in previous 64KB window
    mov r15, r12
    sub r15, 1
    js .advance_src

.match_search_loop:
    mov rax, r12
    sub rax, r15
    cmp rax, UCMP_SNAPPY_MAX_OFFSET ; Max 64KB offset
    jg .advance_src

    ; Compare src[r12] with src[r15]
    mov al, byte [r8 + r12]
    cmp al, byte [r8 + r15]
    jne .try_prev_offset

    ; Fast AVX2 Match Length Scan
    push rdi
    push rsi
    push rdx
    lea rdi, [r8 + r15]
    lea rsi, [r8 + r12]
    mov rdx, r9
    sub rdx, r12
    call ucmp_avx2_scan_match_length
    mov rbx, rax                    ; RBX = match_length
    pop rdx
    pop rsi
    pop rdi

    cmp rbx, UCMP_LZ4_MIN_MATCH
    jge .encode_match

.try_prev_offset:
    dec r15
    jns .match_search_loop

.advance_src:
    inc r12
    jmp .compress_loop

.encode_match:
    ; Emit token byte [Literal Len (4-bit) | Match Len - 4 (4-bit)]
    mov rax, r12
    sub rax, r14                    ; RAX = literal_len
    mov rcx, rbx
    sub rcx, UCMP_LZ4_MIN_MATCH     ; RCX = match_len - 4

    ; Combine token byte
    mov rdx, rax
    cmp rdx, 15
    jle .small_lit_token
    mov rdx, 15
.small_lit_token:
    shl rdx, 4

    mov rsi, rcx
    cmp rsi, 15
    jle .combine_token
    mov rsi, 15
.combine_token:
    or rdx, rsi

    cmp r13, r11
    jge .overflow_err
    mov byte [r10 + r13], dl
    inc r13

    ; Write literal length extension bytes if >= 15
    cmp rax, 15
    jl .copy_literals
    sub rax, 15
.write_lit_ext:
    cmp r13, r11
    jge .overflow_err
    cmp rax, 255
    jl .write_last_lit_ext
    mov byte [r10 + r13], 255
    inc r13
    sub rax, 255
    jmp .write_lit_ext
.write_last_lit_ext:
    mov byte [r10 + r13], al
    inc r13

.copy_literals:
    ; Copy raw literal bytes
    mov rdx, r12
    sub rdx, r14                    ; RDX = literal_len
    test rdx, rdx
    jz .emit_offset

.copy_lit_bytes:
    cmp r13, r11
    jge .overflow_err
    mov al, byte [r8 + r14]
    mov byte [r10 + r13], al
    inc r14
    inc r13
    dec rdx
    jnz .copy_lit_bytes

.emit_offset:
    ; Emit 16-bit offset Little-Endian
    cmp r13, r11
    jge .overflow_err
    mov rax, r12
    sub rax, r15                    ; RAX = offset
    mov byte [r10 + r13], al
    inc r13

    cmp r13, r11
    jge .overflow_err
    shr rax, 8
    mov byte [r10 + r13], al
    inc r13

    ; Write match length extension bytes if >= 15
    cmp rcx, 15
    jl .finish_match
    sub rcx, 15
.write_match_ext:
    cmp r13, r11
    jge .overflow_err
    cmp rcx, 255
    jl .write_last_match_ext
    mov byte [r10 + r13], 255
    inc r13
    sub rcx, 255
    jmp .write_match_ext
.write_last_match_ext:
    mov byte [r10 + r13], cl
    inc r13

.finish_match:
    add r12, rbx                    ; Advance src_pos by match_length
    mov r14, r12                    ; New anchor = src_pos
    jmp .compress_loop

.flush_last_literals:
    mov rax, r9
    sub rax, r14                    ; Remaining literals count
    test rax, rax
    jz .done

    ; Token byte for trailing literals (match_len = 0)
    mov rdx, rax
    cmp rdx, 15
    jle .small_last_token
    mov rdx, 15
.small_last_token:
    shl rdx, 4

    cmp r13, r11
    jge .overflow_err
    mov byte [r10 + r13], dl
    inc r13

    cmp rax, 15
    jl .copy_last_literals
    sub rax, 15
.write_last_ext:
    cmp r13, r11
    jge .overflow_err
    cmp rax, 255
    jl .write_final_ext
    mov byte [r10 + r13], 255
    inc r13
    sub rax, 255
    jmp .write_last_ext
.write_final_ext:
    mov byte [r10 + r13], al
    inc r13

.copy_last_literals:
    cmp r13, r11
    jge .overflow_err
    mov al, byte [r8 + r14]
    mov byte [r10 + r13], al
    inc r14
    inc r13
    cmp r14, r9
    jl .copy_last_literals

.done:
    mov rax, r13                    ; Return bytes written
    UCMP_RESTORE_REGS
    ret

.overflow_err:
    mov rax, UCMP_ERR_BUFF_TOO_SMALL
    UCMP_RESTORE_REGS
    ret
