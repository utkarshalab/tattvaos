; ============================================================================
; CWP Wire Framing — Encode/Decode Messages
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"

extern memcopy
%define MAX_PAYLOAD_SIZE 65536

section .text

; ---------------------------------------------------------------------------
; wire_encode_request
;   Encode request message
;   IN:  rdi = buffer, rsi = msg_hdr*, rdx = payload_ptr (hdr.len bytes)
;   OUT: rax = total_bytes, negative error
; ---------------------------------------------------------------------------
global wire_encode_request
wire_encode_request:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi        ; buffer
    mov r12, rsi        ; msg_hdr*
    mov r13, rdx        ; payload
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Validate payload length
    mov r14d, [r12 + MsgHdr.len]
    cmp r14, MAX_PAYLOAD_SIZE
    ja .too_large

    ; Write header
    mov eax, [r12 + MsgHdr.obj]
    mov [rbx + 0], eax
    mov ax, [r12 + MsgHdr.opcode]
    mov [rbx + 4], ax
    mov ax, [r12 + MsgHdr.flags]
    mov [rbx + 6], ax
    mov [rbx + 8], r14d

    ; Copy payload
    test r14, r14
    jz .no_payload
    test r13, r13
    jz .invalid
    lea rdi, [rbx + 12]
    mov rsi, r13
    mov rdx, r14
    call memcopy

.no_payload:
    lea rax, [r14 + 12]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.too_large:
    mov rax, -(EMSGSIZE)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; wire_decode_header
;   Decode message header
;   IN:  rdi = buffer, rsi = msg_hdr*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global wire_decode_header
wire_decode_header:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx + 0]
    mov [r12 + MsgHdr.obj], eax
    mov ax, [rbx + 4]
    mov [r12 + MsgHdr.opcode], ax
    mov ax, [rbx + 6]
    mov [r12 + MsgHdr.flags], ax
    mov eax, [rbx + 8]
    mov [r12 + MsgHdr.len], eax

    ; Validate
    cmp eax, MAX_PAYLOAD_SIZE
    ja .too_large

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.too_large:
    mov rax, -(EMSGSIZE)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; wire_validate_message
;   Full message validation (header + payload alignment)
;   IN:  rdi = buffer, rsi = total_len
;   OUT: rax = payload_offset (12), negative error
; ---------------------------------------------------------------------------
global wire_validate_message
wire_validate_message:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp r12, 12
    jb .too_short

    mov eax, [rbx + 8]    ; payload len
    lea rdx, [rax + 12]   ; total
    cmp rdx, r12
    jne .len_mismatch

    ; Check 4-byte alignment
    test eax, 3
    jnz .unaligned

    mov rax, 12
    EPILOGUE_RESTORE rbx, r12
    ret

.too_short:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret
.len_mismatch:
    mov rax, -(EPROTO)
    EPILOGUE_RESTORE rbx, r12
    ret
.unaligned:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; wire_encode_handles
;   Encode handle array: a u32 count, then the u32 handles
;   IN:  rdi = buffer, rsi = handle_array*, rdx = count
;   OUT: rax = bytes_written
; ---------------------------------------------------------------------------
global wire_encode_handles
wire_encode_handles:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned at the call
    mov rbx, rdx
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov [rdi], ebx                      ; count
    add rdi, 4
    shl rdx, 2                          ; bytes
    call memcopy
    lea rax, [rbx * 4 + 4]
    add rsp, 8
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; wire_decode_handles
;   Decode handle array
;   IN:  rdi = buffer, rsi = handle_array*, rdx = max_count
;   OUT: rax = actual_count, -ENOSPC if more than max_count
; ---------------------------------------------------------------------------
global wire_decode_handles
wire_decode_handles:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned at the call
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov ebx, [rdi]                      ; count
    cmp rbx, rdx
    ja .too_many

    mov rax, rdi
    mov rdi, rsi
    lea rsi, [rax + 4]
    lea rdx, [rbx * 4]
    call memcopy
    mov rax, rbx
    add rsp, 8
    EPILOGUE_RESTORE rbx
    ret

.too_many:
    mov rax, -(ENOSPC)
    add rsp, 8
    EPILOGUE_RESTORE rbx
    ret

section .data

global wire_version
wire_version: dq 0x010100
