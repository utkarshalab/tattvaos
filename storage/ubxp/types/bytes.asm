%ifndef GUARD_STORAGE_UBXP_TYPES_BYTES_ASM
%define GUARD_STORAGE_UBXP_TYPES_BYTES_ASM
; =============================================================================
; Tattva OS — storage/ubxp/types/bytes.asm
; =============================================================================
; UBXP Length-Delimited Codec — byte blobs, UTF-8 strings and nested frames.
;
; Implements:
;   - Length-prefixed blob emission (`ubxp_write_bytes`)
;   - Zero-copy blob views into the source buffer (`ubxp_read_bytes`)
;   - UTF-8 string aliases carrying the same wire shape (`ubxp_write/read_string`)
;   - Length-delimited skip used by the unknown-field path (`ubxp_skip_bytes`)
;
; Reads never copy: ubxp_read_bytes hands back a pointer into the caller's own
; input buffer plus a length. The slice is valid only while that buffer lives,
; which keeps decode allocation-free on the hot path.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_write_bytes
global ubxp_read_bytes
global ubxp_write_string
global ubxp_read_string
global ubxp_skip_bytes

; -----------------------------------------------------------------------------
; ubxp_write_bytes
;
; Emits a varint length followed by the raw payload.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Source buffer pointer
;   RDX = Length in bytes
;
; Returns:
;   RAX = Total bytes written including the length prefix, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_bytes:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Cursor
    mov r12, rsi                    ; Source
    mov r13, rdx                    ; Length

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .wb_sticky

    cmp r13, UBXP_MAX_PAYLOAD
    ja .wb_overflow

    ; Length prefix first.
    mov rdi, rbx
    mov rsi, r13
    call ubxp_varint_encode
    test rax, rax
    js .wb_return                   ; Encoder already set the sticky error
    mov r14, rax                    ; Prefix width

    ; Then the body, if any.
    test r13, r13
    jz .wb_done

    mov rcx, [rbx + ubxp_cursor_t.base]
    add rcx, [rbx + ubxp_cursor_t.pos]
    mov rdx, rcx
    add rdx, r13
    cmp rdx, [rbx + ubxp_cursor_t.limit]
    ja .wb_nospc

    mov rdi, rcx
    mov rsi, r12
    mov rcx, r13
    rep movsb

    add qword [rbx + ubxp_cursor_t.pos], r13

.wb_done:
    mov rax, r14
    add rax, r13                    ; Prefix + body
    jmp .wb_return

.wb_nospc:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_NOSPC
    mov rax, UBXP_ERR_NOSPC
    jmp .wb_return

.wb_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .wb_return

.wb_sticky:
    movsxd rax, eax

.wb_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_read_bytes
;
; Reads a length-delimited blob and returns a view of it. No copy is made.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a caller-owned ubxp_slice_t
;
; Returns:
;   RAX = Payload length, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_bytes:
    push rbx
    push r12
    push r13
    sub rsp, 16                     ; Scratch slot for the decoded length

    mov rbx, rdi                    ; Cursor
    mov r12, rsi                    ; Destination slice

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .rb_sticky

    mov rsi, rsp
    call ubxp_varint_decode
    test rax, rax
    js .rb_return

    mov r13, [rsp]                  ; Declared length
    cmp r13, UBXP_MAX_PAYLOAD
    ja .rb_overflow

    ; The declared payload must be entirely inside the buffer.
    mov rcx, [rbx + ubxp_cursor_t.base]
    add rcx, [rbx + ubxp_cursor_t.pos]
    mov rdx, rcx
    add rdx, r13
    cmp rdx, [rbx + ubxp_cursor_t.limit]
    ja .rb_truncated

    mov [r12 + ubxp_slice_t.ptr], rcx
    mov [r12 + ubxp_slice_t.len], r13

    add qword [rbx + ubxp_cursor_t.pos], r13

    mov rax, r13
    jmp .rb_return

.rb_truncated:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    jmp .rb_return

.rb_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .rb_return

.rb_sticky:
    movsxd rax, eax

.rb_return:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_string
;
; UTF-8 strings share the byte-blob wire shape; the distinction lives in the
; schema's logical type, not on the wire.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = UTF-8 buffer pointer
;   RDX = Length in bytes
;
; Returns:
;   RAX = Total bytes written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_string:
    jmp ubxp_write_bytes

; -----------------------------------------------------------------------------
; ubxp_read_string
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a caller-owned ubxp_slice_t
;
; Returns:
;   RAX = String length in bytes, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_read_string:
    jmp ubxp_read_bytes

; -----------------------------------------------------------------------------
; ubxp_skip_bytes
;
; Steps over a length-delimited value without materialising a view. This is
; what lets a decoder walk past a field it has no schema for.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;
; Returns:
;   RAX = Bytes skipped, excluding the length prefix, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_skip_bytes:
    push rbx
    push r12
    sub rsp, 16

    mov rbx, rdi

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .sb_sticky

    mov rsi, rsp
    call ubxp_varint_decode
    test rax, rax
    js .sb_return

    mov r12, [rsp]
    cmp r12, UBXP_MAX_PAYLOAD
    ja .sb_overflow

    mov rcx, [rbx + ubxp_cursor_t.base]
    add rcx, [rbx + ubxp_cursor_t.pos]
    add rcx, r12
    cmp rcx, [rbx + ubxp_cursor_t.limit]
    ja .sb_truncated

    add qword [rbx + ubxp_cursor_t.pos], r12
    mov rax, r12
    jmp .sb_return

.sb_truncated:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    jmp .sb_return

.sb_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .sb_return

.sb_sticky:
    movsxd rax, eax

.sb_return:
    add rsp, 16
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UBXP_TYPES_BYTES_ASM
