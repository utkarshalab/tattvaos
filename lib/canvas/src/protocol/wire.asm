; ============================================================================
; Wire Protocol — Message Encoding/Decoding, Framing
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/protocol.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; wire_validate_message
;   Validate message structure
; ============================================================================
global wire_validate_message
wire_validate_message:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi       ; message buffer
    mov r12, rsi       ; size
    ASSERT_PTR rbx

    ; Minimum size check
    cmp r12, MESSAGE_HEADER_SIZE
    jl .invalid

    ; Check size field matches
    mov eax, [rbx]
    cmp eax, r12d
    jne .invalid

    ; Check opcode range
    movzx eax, word [rbx + MESSAGE_OPCODE_OFFSET]
    test ax, ax
    jz .invalid

    ; Check flags
    movzx eax, word [rbx + MESSAGE_FLAGS_OFFSET]
    test eax, ~(MESSAGE_FLAG_REPLY | MESSAGE_FLAG_EVENT | MESSAGE_FLAG_ERROR | MESSAGE_FLAG_NEEDS_ACK | MESSAGE_FLAG_HAS_FDS | MESSAGE_FLAG_COMPRESSED)
    jnz .invalid

    ; Valid
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; wire_decode_header
;   Decode message header
; ============================================================================
global wire_decode_header
wire_decode_header:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi       ; message buffer
    mov r12, rsi       ; header output struct
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx]
    mov [r12 + WireHeader_SIZE], eax
    movzx eax, word [rbx + MESSAGE_OPCODE_OFFSET]
    mov [r12 + WireHeader_OPCODE], eax
    movzx eax, word [rbx + MESSAGE_FLAGS_OFFSET]
    mov [r12 + WireHeader_FLAGS], eax
    mov eax, [rbx + MESSAGE_SENDER_OFFSET]
    mov [r12 + WireHeader_SENDER], eax
    mov eax, [rbx + MESSAGE_SEQUENCE_OFFSET]
    mov [r12 + WireHeader_SEQUENCE], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; wire_encode_header
;   Encode message header
; ============================================================================
global wire_encode_header
wire_encode_header:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi       ; message buffer
    mov r12, rsi       ; header struct
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [r12 + WireHeader_SIZE]
    mov [rbx], eax
    mov ax, [r12 + WireHeader_OPCODE]
    mov [rbx + MESSAGE_OPCODE_OFFSET], ax
    mov ax, [r12 + WireHeader_FLAGS]
    mov [rbx + MESSAGE_FLAGS_OFFSET], ax
    mov eax, [r12 + WireHeader_SENDER]
    mov [rbx + MESSAGE_SENDER_OFFSET], eax
    mov eax, [r12 + WireHeader_SEQUENCE]
    mov [rbx + MESSAGE_SEQUENCE_OFFSET], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; WireHeader Struct
; ============================================================================
%define WireHeader_SIZE      0
%define WireHeader_OPCODE    4
%define WireHeader_FLAGS     6
%define WireHeader_SENDER    8
%define WireHeader_SEQUENCE  12
%define WireHeader_SIZEOF    16

; ============================================================================
; wire_decode_args
;   Decode message arguments (simplified - real impl would be per-opcode)
; ============================================================================
global wire_decode_args
wire_decode_args:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; message buffer
    mov r12, rsi       ; args buffer
    mov r13, rdx       ; arg count
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Skip header
    lea rbx, [rbx + MESSAGE_HEADER_SIZE]

    ; For now, just copy raw args
    mov rcx, r13
    shl rcx, 3  ; 8 bytes per arg (simplified)
    mov rdi, r12
    mov rsi, rbx
    call memcopy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; wire_encode_args
;   Encode arguments (simplified)
; ============================================================================
global wire_encode_args
wire_encode_args:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; message buffer
    mov r12, rsi       ; args buffer
    mov r13, rdx       ; arg count
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Skip header
    lea rbx, [rbx + MESSAGE_HEADER_SIZE]

    mov rcx, r13
    shl rcx, 3
    mov rdi, rbx
    mov rsi, r12
    call memcopy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; wire_encode_message
;   Encode complete message
; ============================================================================
global wire_encode_message
wire_encode_message:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; output buffer
    mov r12, rsi       ; opcode
    mov r13, rdx       ; flags
    mov r14, rcx       ; sender_id
    mov r15, r8        ; sequence
    mov r10, r9        ; payload
    mov r11, [rsp + 8] ; payload size
    ASSERT_PTR rbx

    ; Write header
    mov eax, MESSAGE_HEADER_SIZE
    add eax, r11d
    mov [rbx], eax

    mov word [rbx + MESSAGE_OPCODE_OFFSET], r12w
    mov word [rbx + MESSAGE_FLAGS_OFFSET], r13w
    mov [rbx + MESSAGE_SENDER_OFFSET], r14d
    mov [rbx + MESSAGE_SEQUENCE_OFFSET], r15d

    ; Copy payload
    test r11d, r11d
    jz .no_payload
    mov rdi, rbx
    add rdi, MESSAGE_HEADER_SIZE
    mov rsi, r10
    mov ecx, r11d
    call memcopy

.no_payload:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; wire_read_message
;   Read message from ring buffer
; ============================================================================
global wire_read_message
wire_read_message:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi       ; ring buffer
    mov r12, rsi       ; output message
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check available data
    mov rax, [rbx + RingBuffer_READ_POS]
    mov r12, [rbx + RingBuffer_WRITE_POS]
    cmp rax, r12
    je .no_data

    ; Read header
    mov r13, rbx
    add r13, [rbx + RingBuffer_BUFFER]
    add r13, [rbx + RingBuffer_READ_POS]

    mov eax, [r13]
    mov [r12 + WireHeader_SIZE], eax
    movzx eax, word [r13 + MESSAGE_OPCODE_OFFSET]
    mov [r12 + WireHeader_OPCODE], eax
    movzx eax, word [r13 + MESSAGE_FLAGS_OFFSET]
    mov [r12 + WireHeader_FLAGS], eax
    mov eax, [r13 + MESSAGE_SENDER_OFFSET]
    mov [r12 + WireHeader_SENDER], eax
    mov eax, [r13 + MESSAGE_SEQUENCE_OFFSET]
    mov [r12 + WireHeader_SEQUENCE], eax

    ; Check if full message available
    mov eax, [r12 + WireHeader_SIZE]
    sub r12, rax
    jb .partial

    ; Full message available
    mov rdi, r12
    lea rsi, [rbx + RingBuffer_BUFFER]
    add rsi, [rbx + RingBuffer_READ_POS]
    mov ecx, [r12 + WireHeader_SIZE]
    call memcopy

    ; Update read position
    add [rbx + RingBuffer_READ_POS], rax
    and [rbx + RingBuffer_READ_POS], [rbx + RingBuffer_MASK]

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.partial:
    mov rax, -EAGAIN
    EPILOGUE_RESTORE rbx
    ret

.no_data:
    mov rax, -EAGAIN
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; wire_write_message
;   Write message to ring buffer
; ============================================================================
global wire_write_message
wire_write_message:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; ring buffer
    mov r12, rsi       ; message
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check space
    mov rax, [rbx + RingBuffer_WRITE_POS]
    mov r12, [rbx + RingBuffer_READ_POS]
    mov r13, [rbx + RingBuffer_CAPACITY]
    mov r14, [rbx + RingBuffer_BUFFER]

    ; Calculate available space
    sub r13, rax
    cmp r13, r12
    jb .no_space

    ; Write message
    mov rdi, rbx
    add rdi, [rbx + RingBuffer_WRITE_POS]
    add rdi, [rbx + RingBuffer_BUFFER]
    mov rsi, rsi
    mov ecx, [rsi + WireHeader_SIZE]
    call memcopy

    ; Update write position
    add [rbx + RingBuffer_WRITE_POS], rax
    and [rbx + RingBuffer_WRITE_POS], [rbx + RingBuffer_MASK]

    xor rax, rax
    leave
    ret

.no_space:
    mov rax, -ENOSPC
    leave
    ret

section .data
global wire_version
wire_version: dq 0x010000