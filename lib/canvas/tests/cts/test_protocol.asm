; ============================================================================
; Protocol Tests — Encoding, Decoding, Validation
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/protocol.inc"
%include "inc/wire.asm"

section .text

; ============================================================================
; test_protocol_encode_decode
;   Test message encode/decode round-trip
; ============================================================================
global test_protocol_encode_decode
test_protocol_encode_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    ; Create test message
    mov rdi, rsp
    mov r12d, 1        ; opcode
    mov r13d, 0        ; flags
    mov r14d, 42       ; sender_id
    mov r15d, 1        ; sequence
    mov r10, 0         ; no payload
    mov r11, 0
    call wire_encode_message

    ; Decode header
    mov rdi, rsp
    lea rsi, [rsp + 48]
    call wire_decode_header

    ; Verify
    TEST_ASSERT [rsp + 48 + WireHeader_OPCODE], 1
    TEST_ASSERT [rsp + 48 + WireHeader_FLAGS], 0
    TEST_ASSERT [rsp + 48 + WireHeader_SENDER], 42
    TEST_ASSERT [rsp + 48 + WireHeader_SEQUENCE], 1

    xor rax, rax
    leave
    ret

; ============================================================================
; test_protocol_validation
;   Test message validation
; ============================================================================
global test_protocol_validation
test_protocol_validation:
    PROLOGUE_SAVE rbx, r12
    ; Test valid message
    mov rdi, rsp
    mov r12d, MESSAGE_HEADER_SIZE
    call wire_validate_message
    TEST_ASSERT rax, 0

    ; Test too small
    mov rdi, rsp
    mov r12d, MESSAGE_HEADER_SIZE - 1
    call wire_validate_message
    TEST_ASSERT_NE rax, 0

    ; Test zero opcode
    mov rdi, rsp
    mov r12d, MESSAGE_HEADER_SIZE
    mov word [rsp + MESSAGE_OPCODE_OFFSET], 0
    call wire_validate_message
    TEST_ASSERT_NE rax, 0

    xor rax, rax
    leave
    ret

; ============================================================================
; test_opcode_mapping
;   Test opcode to handler mapping
; ============================================================================
global test_opcode_mapping
test_opcode_mapping:
    PROLOGUE_SAVE rbx
    ; Test all display opcodes
    TEST_ASSERT DISPLAY_SYNC, 1
    TEST_ASSERT DISPLAY_GET_REGISTRY, 2
    TEST_ASSERT DISPLAY_CREATE_SURFACE, 3

    ; Surface opcodes
    TEST_ASSERT SURFACE_DESTROY, 1
    TEST_ASSERT SURFACE_ATTACH, 2
    TEST_ASSERT SURFACE_DAMAGE, 3
    TEST_ASSERT SURFACE_FRAME, 4
    TEST_ASSERT SURFACE_COMMIT, 6

    ; Seat opcodes
    TEST_ASSERT SEAT_GET_POINTER, 1
    TEST_ASSERT SEAT_GET_KEYBOARD, 2
    TEST_ASSERT SEAT_GET_TOUCH, 3

    xor rax, rax
    leave
    ret

; ============================================================================
; test_protocol_errors
;   Test protocol error handling
; ============================================================================
global test_protocol_errors
test_protocol_errors:
    PROLOGUE_SAVE rbx
    ; Test error codes
    TEST_ASSERT ERROR_INVALID_OBJECT, 1
    TEST_ASSERT ERROR_INVALID_METHOD, 2
    TEST_ASSERT ERROR_INVALID_ARGUMENT, 3
    TEST_ASSERT ERROR_INVALID_FORMAT, 4
    TEST_ASSERT ERROR_NO_MEMORY, 5
    TEST_ASSERT ERROR_IMPLEMENTATION, 6
    TEST_ASSERT ERROR_OBJECT_DESTROYED, 7
    TEST_ASSERT ERROR_POST_REJECTED, 8
    TEST_ASSERT ERROR_OBJECT_DEAD, 9

    xor rax, rax
    leave
    ret

section .data
global test_protocol_version
test_protocol_version: dq 0x010000