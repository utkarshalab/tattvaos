; =============================================================================
; Tattva OS — storage/ubxp/frame/varint.asm
; =============================================================================
; LEB128 Variable-Length Integer Codec & Zig-Zag Signed Mapping.
;
; Implements:
;   - Unsigned 64-bit LEB128 encode / decode (`ubxp_varint_encode/decode`)
;   - Zig-zag signed mapping so small negatives stay small (`ubxp_zigzag_*`)
;   - Encoded-width precomputation for buffer sizing (`ubxp_varint_size`)
;
; Every decode path is bounded: a varint may never consume more than
; UBXP_VARINT_MAX_BYTES, so a corrupt stream of 0x80 bytes cannot spin.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_varint_size
global ubxp_varint_encode
global ubxp_varint_decode
global ubxp_zigzag_encode
global ubxp_zigzag_decode

; -----------------------------------------------------------------------------
; ubxp_varint_size
;
; Returns the number of LEB128 bytes a value will occupy. Callers use this to
; size a buffer before committing to an encode.
;
; Inputs:
;   RDI = 64-bit unsigned value
;
; Returns:
;   RAX = Encoded width in bytes (1..10)
; -----------------------------------------------------------------------------
align 32
ubxp_varint_size:
    mov rax, 1
    mov rcx, rdi

.size_loop:
    shr rcx, 7
    jz .size_done
    inc rax
    jmp .size_loop

.size_done:
    ret

; -----------------------------------------------------------------------------
; ubxp_varint_encode
;
; Appends a 64-bit unsigned value to the cursor in LEB128 form.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = 64-bit unsigned value
;
; Returns:
;   RAX = Bytes written, or a negative UBXP_ERR_* code
; -----------------------------------------------------------------------------
align 32
ubxp_varint_encode:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Cursor
    mov r12, rsi                    ; Working value
    xor r13, r13                    ; Bytes written

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .enc_sticky                 ; Short-circuit on a prior failure

.enc_loop:
    mov rax, [rbx + ubxp_cursor_t.base]
    add rax, [rbx + ubxp_cursor_t.pos]
    cmp rax, [rbx + ubxp_cursor_t.limit]
    jae .enc_nospc                  ; No room for even one more byte

    mov rcx, r12
    and rcx, 0x7F                   ; Low 7 payload bits
    shr r12, 7
    jz .enc_final                   ; Nothing left: this is the last group

    or rcx, 0x80                    ; Continuation bit
    mov byte [rax], cl
    inc qword [rbx + ubxp_cursor_t.pos]
    inc r13
    jmp .enc_loop

.enc_final:
    mov byte [rax], cl
    inc qword [rbx + ubxp_cursor_t.pos]
    inc r13

    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

.enc_nospc:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_NOSPC
    mov rax, UBXP_ERR_NOSPC
    pop r13
    pop r12
    pop rbx
    ret

.enc_sticky:
    movsxd rax, eax                 ; Propagate the existing error unchanged
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_varint_decode
;
; Consumes one LEB128 value from the cursor.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a 64-bit output slot
;
; Returns:
;   RAX = Bytes consumed, or a negative UBXP_ERR_* code
; -----------------------------------------------------------------------------
align 32
ubxp_varint_decode:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Cursor
    mov r14, rsi                    ; Output slot
    xor r12, r12                    ; Accumulated value
    xor r13, r13                    ; Bytes consumed
    xor r15, r15                    ; Current shift

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .dec_sticky

.dec_loop:
    cmp r13, UBXP_VARINT_MAX_BYTES
    jae .dec_overflow               ; Refuse an unbounded continuation run

    mov rax, [rbx + ubxp_cursor_t.base]
    add rax, [rbx + ubxp_cursor_t.pos]
    cmp rax, [rbx + ubxp_cursor_t.limit]
    jae .dec_truncated

    movzx edx, byte [rax]           ; 32-bit load already zero-extends into RDX
    inc qword [rbx + ubxp_cursor_t.pos]
    inc r13

    mov r8, rdx                     ; Keep the raw byte for the continuation test
    and rdx, 0x7F
    mov rcx, r15
    shl rdx, cl                     ; Shift never exceeds 63: capped at 10 bytes
    or r12, rdx

    add r15, 7
    test r8b, 0x80
    jnz .dec_loop

    mov [r14], r12
    mov rax, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.dec_truncated:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    jmp .dec_return

.dec_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .dec_return

.dec_sticky:
    movsxd rax, eax

.dec_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_zigzag_encode
;
; Maps a signed value onto an unsigned one so that small magnitudes of either
; sign encode short: -1 -> 1, 1 -> 2, -2 -> 3, 2 -> 4.
;
; Inputs:
;   RDI = 64-bit signed value
;
; Returns:
;   RAX = 64-bit zig-zag encoded value
; -----------------------------------------------------------------------------
align 32
ubxp_zigzag_encode:
    mov rax, rdi
    sar rax, 63                     ; All ones when negative, zero otherwise
    mov rdx, rdi
    shl rdx, 1
    xor rax, rdx
    ret

; -----------------------------------------------------------------------------
; ubxp_zigzag_decode
;
; Inverse of ubxp_zigzag_encode.
;
; Inputs:
;   RDI = 64-bit zig-zag encoded value
;
; Returns:
;   RAX = 64-bit signed value
; -----------------------------------------------------------------------------
align 32
ubxp_zigzag_decode:
    mov rax, rdi
    shr rax, 1
    mov rdx, rdi
    and rdx, 1
    neg rdx                         ; 0 stays 0, 1 becomes -1 (all ones)
    xor rax, rdx
    ret
