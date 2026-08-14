; =============================================================================
; Tattva OS — storage/ubxp/frame/frame.asm
; =============================================================================
; UBXP Frame Header Emission, Validation & Bounds-Checked Cursor Primitives.
;
; Implements:
;   - Cursor construction and remaining-space queries (`ubxp_cursor_*`)
;   - Frame header emit with deferred length patching (`ubxp_frame_write_header`)
;   - Body length / CRC / field-count back-patching (`ubxp_frame_finalize`)
;   - Header validation on ingest (`ubxp_frame_read_header`)
;   - Hardware CRC32C over the frame body (`ubxp_crc32c`)
;
; The integrity field is CRC32C (Castagnoli), computed with the SSE4.2 `crc32`
; instruction. It is deliberately self-contained rather than delegating to
; lib/ucmp so a UBXP frame can be validated without pulling in the compression
; subsystem.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM, SSE4.2)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_cursor_init
global ubxp_cursor_remaining
global ubxp_cursor_error
global ubxp_frame_write_header
global ubxp_frame_finalize
global ubxp_frame_read_header
global ubxp_crc32c

; -----------------------------------------------------------------------------
; ubxp_cursor_init
;
; Binds a cursor to a caller-owned buffer. The cursor never allocates.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Buffer base pointer
;   RDX = Buffer length in bytes
;
; Returns:
;   RAX = UBXP_OK
; -----------------------------------------------------------------------------
align 32
ubxp_cursor_init:
    mov [rdi + ubxp_cursor_t.base], rsi
    lea rax, [rsi + rdx]
    mov [rdi + ubxp_cursor_t.limit], rax        ; Absolute one-past-end
    mov qword [rdi + ubxp_cursor_t.pos], 0
    mov dword [rdi + ubxp_cursor_t.depth], 0
    mov dword [rdi + ubxp_cursor_t.error], 0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_cursor_remaining
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;
; Returns:
;   RAX = Bytes still addressable from the current position
; -----------------------------------------------------------------------------
align 32
ubxp_cursor_remaining:
    mov rax, [rdi + ubxp_cursor_t.limit]
    sub rax, [rdi + ubxp_cursor_t.base]
    sub rax, [rdi + ubxp_cursor_t.pos]
    ret

; -----------------------------------------------------------------------------
; ubxp_cursor_error
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;
; Returns:
;   RAX = Sticky result code (UBXP_OK when the whole sequence succeeded)
; -----------------------------------------------------------------------------
align 32
ubxp_cursor_error:
    mov eax, dword [rdi + ubxp_cursor_t.error]
    movsxd rax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_frame_write_header
;
; Emits a frame header at the current position. payload_len, crc32 and
; field_count are left zero; ubxp_frame_finalize patches them once the body
; has been written.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   ESI = Schema identifier
;   EDX = UBXP_FLAG_* bitmask
;
; Returns:
;   RAX = Byte offset of the header within the buffer, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_frame_write_header:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12d, esi                   ; Schema identifier
    mov r13d, edx                   ; Flags

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .wh_sticky

    mov rdi, rbx
    call ubxp_cursor_remaining
    cmp rax, UBXP_HEADER_SIZE
    jb .wh_nospc

    mov r8, [rbx + ubxp_cursor_t.pos]           ; Remember the header offset
    mov rax, [rbx + ubxp_cursor_t.base]
    add rax, r8

    mov dword [rax + ubxp_frame_header_t.magic], UBXP_MAGIC
    mov byte  [rax + ubxp_frame_header_t.version], UBXP_VERSION
    mov byte  [rax + ubxp_frame_header_t.flags], r13b
    mov word  [rax + ubxp_frame_header_t.reserved], 0
    mov dword [rax + ubxp_frame_header_t.payload_len], 0
    mov dword [rax + ubxp_frame_header_t.schema_id], r12d
    mov dword [rax + ubxp_frame_header_t.crc32], 0
    mov dword [rax + ubxp_frame_header_t.field_count], 0

    add qword [rbx + ubxp_cursor_t.pos], UBXP_HEADER_SIZE

    mov rax, r8
    pop r13
    pop r12
    pop rbx
    ret

.wh_nospc:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_NOSPC
    mov rax, UBXP_ERR_NOSPC
    pop r13
    pop r12
    pop rbx
    ret

.wh_sticky:
    movsxd rax, eax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_frame_finalize
;
; Back-patches the length, field count and (when UBXP_FLAG_CRC_PRESENT is set)
; the CRC32C of everything written after the header.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Header offset returned by ubxp_frame_write_header
;   EDX = Top-level field count
;
; Returns:
;   RAX = Body length in bytes, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_frame_finalize:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi                    ; Header offset
    mov r13d, edx                   ; Field count

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .fin_sticky

    ; Body length = current position - header offset - header size
    mov r14, [rbx + ubxp_cursor_t.pos]
    sub r14, r12
    sub r14, UBXP_HEADER_SIZE
    js .fin_inval                   ; Position moved backwards: caller bug

    cmp r14, UBXP_MAX_PAYLOAD
    ja .fin_overflow

    mov rax, [rbx + ubxp_cursor_t.base]
    add rax, r12                    ; RAX = header address

    mov dword [rax + ubxp_frame_header_t.payload_len], r14d
    mov dword [rax + ubxp_frame_header_t.field_count], r13d

    test byte [rax + ubxp_frame_header_t.flags], UBXP_FLAG_CRC_PRESENT
    jz .fin_done

    ; CRC covers the body only, never the header it is stored in.
    push rax
    lea rdi, [rax + UBXP_HEADER_SIZE]
    mov rsi, r14
    call ubxp_crc32c
    mov rcx, rax
    pop rax
    mov dword [rax + ubxp_frame_header_t.crc32], ecx

.fin_done:
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.fin_inval:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_INVAL
    mov rax, UBXP_ERR_INVAL
    jmp .fin_return

.fin_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .fin_return

.fin_sticky:
    movsxd rax, eax

.fin_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_frame_read_header
;
; Validates and copies a frame header out of the cursor, advancing past it.
;
; A frame whose version is newer than UBXP_VERSION is rejected outright; older
; versions are accepted, which is the half of schema evolution the header can
; decide on its own. Field-level compatibility is handled in schema/evolution.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Pointer to a caller-owned ubxp_frame_header_t
;
; Returns:
;   RAX = Declared payload length, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_frame_read_header:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .rh_sticky

    mov rdi, rbx
    call ubxp_cursor_remaining
    cmp rax, UBXP_HEADER_SIZE
    jb .rh_truncated

    mov r13, [rbx + ubxp_cursor_t.base]
    add r13, [rbx + ubxp_cursor_t.pos]          ; R13 = header address

    cmp dword [r13 + ubxp_frame_header_t.magic], UBXP_MAGIC
    jne .rh_proto

    cmp byte [r13 + ubxp_frame_header_t.version], UBXP_VERSION
    ja .rh_proto                                ; Written by a newer encoder

    mov ecx, dword [r13 + ubxp_frame_header_t.payload_len]
    cmp ecx, UBXP_MAX_PAYLOAD
    ja .rh_overflow

    ; The declared body must actually be present in the buffer.
    mov rdi, rbx
    call ubxp_cursor_remaining
    sub rax, UBXP_HEADER_SIZE
    mov ecx, dword [r13 + ubxp_frame_header_t.payload_len]
    cmp rax, rcx
    jb .rh_truncated

    ; Copy the validated header out to the caller.
    mov rdi, r12
    mov rsi, r13
    mov rcx, UBXP_HEADER_SIZE
    rep movsb

    add qword [rbx + ubxp_cursor_t.pos], UBXP_HEADER_SIZE

    mov eax, dword [r13 + ubxp_frame_header_t.payload_len]
    pop r13
    pop r12
    pop rbx
    ret

.rh_truncated:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    jmp .rh_return

.rh_proto:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_PROTO
    mov rax, UBXP_ERR_PROTO
    jmp .rh_return

.rh_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .rh_return

.rh_sticky:
    movsxd rax, eax

.rh_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_crc32c
;
; CRC32C (Castagnoli) over a byte range using the SSE4.2 `crc32` instruction,
; eight bytes at a time with a byte-wise tail.
;
; Inputs:
;   RDI = Buffer pointer
;   RSI = Length in bytes
;
; Returns:
;   EAX = CRC32C checksum
; -----------------------------------------------------------------------------
align 32
ubxp_crc32c:
    push rbx

    mov rbx, rdi
    mov rcx, rsi
    mov eax, 0xFFFFFFFF             ; Standard CRC32C initial value

.crc_qword:
    cmp rcx, 8
    jb .crc_tail
    crc32 rax, qword [rbx]
    add rbx, 8
    sub rcx, 8
    jmp .crc_qword

.crc_tail:
    test rcx, rcx
    jz .crc_done
    crc32 eax, byte [rbx]
    inc rbx
    dec rcx
    jmp .crc_tail

.crc_done:
    not eax                         ; Final inversion
    pop rbx
    ret
