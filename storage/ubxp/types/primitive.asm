; =============================================================================
; Tattva OS — storage/ubxp/types/primitive.asm
; =============================================================================
; UBXP Scalar Type Codec — booleans, integers and fixed-width words.
;
; Implements:
;   - Boolean encode / decode normalised to 0 or 1 (`ubxp_write/read_bool`)
;   - Unsigned and zig-zag signed integers (`ubxp_write/read_uint`, `_int`)
;   - Little-endian fixed 32/64-bit words (`ubxp_write/read_fixed32/64`)
;
; IEEE-754 doubles travel as their raw 64-bit pattern through the fixed64
; path, so nothing here touches x87 or SSE state and the codec stays usable
; from contexts where the FPU is not live.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_write_bool
global ubxp_read_bool
global ubxp_write_uint
global ubxp_read_uint
global ubxp_write_int
global ubxp_read_int
global ubxp_write_fixed64
global ubxp_read_fixed64
global ubxp_write_fixed32
global ubxp_read_fixed32

; -----------------------------------------------------------------------------
; ubxp_write_bool
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   ESI = Value; any non-zero input is normalised to 1
;
; Returns:
;   RAX = Bytes written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_bool:
    xor eax, eax
    test esi, esi
    setnz al                        ; Normalise to exactly 0 or 1
    mov rsi, rax
    jmp ubxp_varint_encode          ; Tail call: a bool is a one-byte varint

; -----------------------------------------------------------------------------
; ubxp_read_bool
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a byte-sized output slot
;
; Returns:
;   RAX = Bytes consumed, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_bool:
    push rbx
    push r12
    sub rsp, 16                     ; Scratch slot for the decoded varint

    mov rbx, rsi                    ; Caller's byte slot
    mov rsi, rsp
    call ubxp_varint_decode
    mov r12, rax

    test rax, rax
    js .rb_return                   ; Propagate decode failure untouched

    xor eax, eax
    cmp qword [rsp], 0
    setne al
    mov byte [rbx], al
    mov rax, r12

.rb_return:
    add rsp, 16
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_uint
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = 64-bit unsigned value
;
; Returns:
;   RAX = Bytes written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_uint:
    jmp ubxp_varint_encode

; -----------------------------------------------------------------------------
; ubxp_read_uint
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a 64-bit output slot
;
; Returns:
;   RAX = Bytes consumed, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_uint:
    jmp ubxp_varint_decode

; -----------------------------------------------------------------------------
; ubxp_write_int
;
; Zig-zag maps the value first so that small negatives stay one byte wide.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = 64-bit signed value
;
; Returns:
;   RAX = Bytes written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_int:
    push rbx
    mov rbx, rdi
    mov rdi, rsi
    call ubxp_zigzag_encode
    mov rsi, rax
    mov rdi, rbx
    pop rbx
    jmp ubxp_varint_encode

; -----------------------------------------------------------------------------
; ubxp_read_int
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a 64-bit signed output slot
;
; Returns:
;   RAX = Bytes consumed, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_int:
    push rbx
    push r12
    sub rsp, 16

    mov rbx, rsi                    ; Caller's output slot
    mov rsi, rsp
    call ubxp_varint_decode
    mov r12, rax

    test rax, rax
    js .ri_return

    mov rdi, [rsp]
    call ubxp_zigzag_decode
    mov [rbx], rax
    mov rax, r12

.ri_return:
    add rsp, 16
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_fixed64
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = 64-bit raw word (also the carrier for IEEE-754 doubles)
;
; Returns:
;   RAX = 8, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_fixed64:
    mov eax, dword [rdi + ubxp_cursor_t.error]
    test eax, eax
    jnz .wf64_sticky

    mov rcx, [rdi + ubxp_cursor_t.base]
    add rcx, [rdi + ubxp_cursor_t.pos]
    mov rdx, rcx
    add rdx, 8
    cmp rdx, [rdi + ubxp_cursor_t.limit]
    ja .wf64_nospc

    mov [rcx], rsi
    add qword [rdi + ubxp_cursor_t.pos], 8
    mov rax, 8
    ret

.wf64_nospc:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_NOSPC
    mov rax, UBXP_ERR_NOSPC
    ret

.wf64_sticky:
    movsxd rax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_read_fixed64
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a 64-bit output slot
;
; Returns:
;   RAX = 8, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_fixed64:
    mov eax, dword [rdi + ubxp_cursor_t.error]
    test eax, eax
    jnz .rf64_sticky

    mov rcx, [rdi + ubxp_cursor_t.base]
    add rcx, [rdi + ubxp_cursor_t.pos]
    mov rdx, rcx
    add rdx, 8
    cmp rdx, [rdi + ubxp_cursor_t.limit]
    ja .rf64_truncated

    mov rax, [rcx]
    mov [rsi], rax
    add qword [rdi + ubxp_cursor_t.pos], 8
    mov rax, 8
    ret

.rf64_truncated:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    ret

.rf64_sticky:
    movsxd rax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_write_fixed32
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   ESI = 32-bit raw word
;
; Returns:
;   RAX = 4, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_fixed32:
    mov eax, dword [rdi + ubxp_cursor_t.error]
    test eax, eax
    jnz .wf32_sticky

    mov rcx, [rdi + ubxp_cursor_t.base]
    add rcx, [rdi + ubxp_cursor_t.pos]
    mov rdx, rcx
    add rdx, 4
    cmp rdx, [rdi + ubxp_cursor_t.limit]
    ja .wf32_nospc

    mov [rcx], esi
    add qword [rdi + ubxp_cursor_t.pos], 4
    mov rax, 4
    ret

.wf32_nospc:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_NOSPC
    mov rax, UBXP_ERR_NOSPC
    ret

.wf32_sticky:
    movsxd rax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_read_fixed32
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a 32-bit output slot
;
; Returns:
;   RAX = 4, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_fixed32:
    mov eax, dword [rdi + ubxp_cursor_t.error]
    test eax, eax
    jnz .rf32_sticky

    mov rcx, [rdi + ubxp_cursor_t.base]
    add rcx, [rdi + ubxp_cursor_t.pos]
    mov rdx, rcx
    add rdx, 4
    cmp rdx, [rdi + ubxp_cursor_t.limit]
    ja .rf32_truncated

    mov eax, [rcx]
    mov [rsi], eax
    add qword [rdi + ubxp_cursor_t.pos], 4
    mov rax, 4
    ret

.rf32_truncated:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    ret

.rf32_sticky:
    movsxd rax, eax
    ret
