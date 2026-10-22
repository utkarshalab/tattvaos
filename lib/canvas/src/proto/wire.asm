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
;   IN:  rdi = buffer, rsi = msg_hdr*, rdx = payload_ptr, rcx = payload_len
;   OUT: rax = total_bytes, negative error
; ---------------------------------------------------------------------------
global wire_encode_request
wire_encode_request:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi        ; buffer
    mov r12, rsi        ; msg_hdr*
    mov r13, rdx        ; payload
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Validate payload length
    mov rax, [r12 + MsgHdr_len]
    cmp rax, MAX_PAYLOAD_SIZE
    ja .too_large

    ; Write header
    mov rax, [r12 + MsgHdr_obj]
    mov [rbx + 0], eax
    mov ax, [r12 + MsgHdr_opcode]
    mov [rbx + 4], ax
    mov ax, [r12 + MsgHdr_flags]
    mov [rbx + 6], ax
    mov eax, [r12 + MsgHdr_len]
    mov [rbx + 8], eax

    ; Copy payload
    test r13, r13
    jz .no_payload
    mov rdi, rbx
    add rdi, 12
    mov rsi, r13
    mov rcx, [r12 + MsgHdr_len]
    call memcopy

.no_payload:
    mov rax, 12
    add rax, [r12 + MsgHdr_len]
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.too_large:
    mov rax, -(EMSGSIZE)
    EPILOGUE_RESTORE rbx, r12, r13
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
    mov [r12 + MsgHdr_obj], eax
    mov ax, [rbx + 4]
    mov [r12 + MsgHdr_opcode], ax
    mov ax, [rbx + 6]
    mov [r12 + MsgHdr_flags], ax
    mov eax, [rbx + 8]
    mov [r12 + MsgHdr_len], eax

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
;   Encode handle array
;   IN:  rdi = buffer, rsi = handle_array*, rdx = count
;   OUT: rax = bytes_written
; ---------------------------------------------------------------------------
global wire_encode_handles
wire_encode_handles:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, edx
    mov [rbx], eax        ; count
    test rdx, rdx
    jz .done

    mov rcx, rdx
    shl rcx, 2            ; * 4 bytes per handle
    mov rdi, rbx
    add rdi, 4
    mov rsi, r12
    call memcopy
    mov rax, rdx
    shl rax, 2
    add rax, 4

.done:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; wire_decode_handles
;   Decode handle array
;   IN:  rdi = buffer, rsi = handle_array*, rdx = max_count
;   OUT: rax = actual_count, negative error
; ---------------------------------------------------------------------------
global wire_decode_handles
wire_decode_handles:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx]
    cmp eax, edx
    ja .too_many

    mov rcx, rax
    shl rcx, 2
    mov rdi, r12
    mov rsi, rbx
    add rsi, 4
    call memcopy
    mov rax, rcx
    shr rax, 2
    EPILOGUE_RESTORE rbx, r12
    ret

.too_many:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data


global wire_version
wire_version: dq 0x010000
