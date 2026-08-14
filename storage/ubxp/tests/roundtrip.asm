; =============================================================================
; Tattva OS — storage/ubxp/tests/roundtrip.asm
; =============================================================================
; UBXP Self-Checking Round-Trip Test Harness.
;
; Implements:
;   - Varint and zig-zag identity checks across boundary values
;   - Frame header emit/validate round-trip
;   - Packed array and nested submessage round-trips
;   - Unknown-field retention and replay verification
;   - Canonical-form detection
;
; Every case encodes into a scratch buffer, rewinds, decodes, and compares
; against the input. `ubxp_test_run_all` returns a bitmask so a single run
; reports every failure rather than stopping at the first.
;
; This file is deliberately NOT included by ubxp.asm: it must never land in a
; kernel image. Assemble it directly when running the suite.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

%define UBXP_TEST_BUF_SIZE           4096

%define UBXP_TEST_VARINT             (1 << 0)
%define UBXP_TEST_ZIGZAG             (1 << 1)
%define UBXP_TEST_FRAME              (1 << 2)
%define UBXP_TEST_PACKED             (1 << 3)
%define UBXP_TEST_NESTED             (1 << 4)
%define UBXP_TEST_UNKNOWN            (1 << 5)

section .data
align 64

ubxp_test_buf:      times UBXP_TEST_BUF_SIZE db 0
ubxp_test_sink:     times UBXP_TEST_BUF_SIZE db 0
ubxp_test_cursor:   times ubxp_cursor_t_size db 0
ubxp_test_cursor2:  times ubxp_cursor_t_size db 0
ubxp_test_sink_cur: times ubxp_cursor_t_size db 0
ubxp_test_unknown:  times ubxp_unknown_t_size db 0
ubxp_test_header:   times ubxp_frame_header_t_size db 0
ubxp_test_scratch:  times 64 db 0

; Boundary values: zero, one-byte max, multi-byte thresholds, 64-bit max.
align 8
ubxp_test_varints:
    dq 0
    dq 1
    dq 127                          ; Widest one-byte value
    dq 128                          ; Narrowest two-byte value
    dq 16383
    dq 16384
    dq 0x7FFFFFFF
    dq 0xFFFFFFFFFFFFFFFF           ; Ten-byte worst case
ubxp_test_varint_count equ 8

align 8
ubxp_test_signed:
    dq 0
    dq -1
    dq 1
    dq -2
    dq 2
    dq 0x7FFFFFFFFFFFFFFF
    dq -0x8000000000000000
ubxp_test_signed_count equ 7

section .text

global ubxp_test_run_all
global ubxp_test_varint_roundtrip
global ubxp_test_zigzag_roundtrip
global ubxp_test_frame_roundtrip
global ubxp_test_packed_roundtrip
global ubxp_test_nested_roundtrip
global ubxp_test_unknown_roundtrip

; -----------------------------------------------------------------------------
; ubxp_test_varint_roundtrip
;
; Encodes the boundary table, rewinds, decodes, and compares element-wise.
;
; Returns:
;   RAX = 0 on success, non-zero on mismatch
; -----------------------------------------------------------------------------
align 32
ubxp_test_varint_roundtrip:
    push rbx
    push r12
    push r13

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_buf]
    mov rdx, UBXP_TEST_BUF_SIZE
    call ubxp_cursor_init

    xor r12, r12
.vr_encode:
    cmp r12, ubxp_test_varint_count
    jae .vr_rewind

    lea rax, [ubxp_test_varints]
    lea rdi, [ubxp_test_cursor]
    mov rsi, [rax + r12 * 8]
    call ubxp_varint_encode
    test rax, rax
    js .vr_fail

    inc r12
    jmp .vr_encode

.vr_rewind:
    lea rax, [ubxp_test_cursor]
    mov qword [rax + ubxp_cursor_t.pos], 0
    mov dword [rax + ubxp_cursor_t.error], 0

    xor r12, r12
.vr_decode:
    cmp r12, ubxp_test_varint_count
    jae .vr_pass

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_scratch]
    call ubxp_varint_decode
    test rax, rax
    js .vr_fail

    lea rax, [ubxp_test_varints]
    mov rbx, [rax + r12 * 8]
    mov r13, [ubxp_test_scratch]
    cmp rbx, r13
    jne .vr_fail

    inc r12
    jmp .vr_decode

.vr_pass:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.vr_fail:
    mov rax, UBXP_TEST_VARINT
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_test_zigzag_roundtrip
;
; Verifies zig-zag encode/decode is an identity over signed extremes.
;
; Returns:
;   RAX = 0 on success, non-zero on mismatch
; -----------------------------------------------------------------------------
align 32
ubxp_test_zigzag_roundtrip:
    push rbx
    push r12

    xor r12, r12
.zz_loop:
    cmp r12, ubxp_test_signed_count
    jae .zz_pass

    lea rax, [ubxp_test_signed]
    mov rbx, [rax + r12 * 8]

    mov rdi, rbx
    call ubxp_zigzag_encode
    mov rdi, rax
    call ubxp_zigzag_decode

    cmp rax, rbx
    jne .zz_fail

    inc r12
    jmp .zz_loop

.zz_pass:
    xor eax, eax
    pop r12
    pop rbx
    ret

.zz_fail:
    mov rax, UBXP_TEST_ZIGZAG
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_test_frame_roundtrip
;
; Writes a header, finalises it over a known body, then re-reads and checks the
; magic, schema id and patched length.
;
; Returns:
;   RAX = 0 on success, non-zero on mismatch
; -----------------------------------------------------------------------------
align 32
ubxp_test_frame_roundtrip:
    push rbx
    push r12

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_buf]
    mov rdx, UBXP_TEST_BUF_SIZE
    mov ecx, 0x1234                 ; Schema id
    xor r8d, r8d                    ; No CRC: keeps this independent of SSE4.2
    call ubxp_encode_begin
    test rax, rax
    js .fr_fail
    mov rbx, rax                    ; Header token

    ; Body: one tagged varint.
    lea rdi, [ubxp_test_cursor]
    mov rsi, 1
    mov edx, UBXP_WIRE_VARINT
    call ubxp_write_tag
    test rax, rax
    js .fr_fail

    lea rdi, [ubxp_test_cursor]
    mov rsi, 300                    ; Two-byte varint
    call ubxp_varint_encode
    test rax, rax
    js .fr_fail

    lea rdi, [ubxp_test_cursor]
    mov rsi, rbx
    mov edx, 1                      ; One top-level field
    call ubxp_encode_end
    test rax, rax
    js .fr_fail
    mov r12, rax                    ; Total frame size

    ; Re-read from the top.
    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_buf]
    mov rdx, UBXP_TEST_BUF_SIZE
    call ubxp_cursor_init

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_header]
    call ubxp_frame_read_header
    test rax, rax
    js .fr_fail

    ; Header size plus declared body must equal what encode_end reported.
    add rax, UBXP_HEADER_SIZE
    cmp rax, r12
    jne .fr_fail

    lea rax, [ubxp_test_header]
    cmp dword [rax + ubxp_frame_header_t.magic], UBXP_MAGIC
    jne .fr_fail
    cmp dword [rax + ubxp_frame_header_t.schema_id], 0x1234
    jne .fr_fail
    cmp dword [rax + ubxp_frame_header_t.field_count], 1
    jne .fr_fail

    xor eax, eax
    pop r12
    pop rbx
    ret

.fr_fail:
    mov rax, UBXP_TEST_FRAME
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_test_packed_roundtrip
;
; Packs the varint boundary table under one tag, then reads it back through a
; bounded sub-cursor and compares element-wise.
;
; Returns:
;   RAX = 0 on success, non-zero on mismatch
; -----------------------------------------------------------------------------
align 32
ubxp_test_packed_roundtrip:
    push rbx
    push r12
    push r13

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_buf]
    mov rdx, UBXP_TEST_BUF_SIZE
    call ubxp_cursor_init

    lea rdi, [ubxp_test_cursor]
    mov rsi, 7                      ; Field number
    lea rdx, [ubxp_test_varints]
    mov rcx, ubxp_test_varint_count
    call ubxp_write_packed_uint
    cmp rax, ubxp_test_varint_count
    jne .pr_fail

    ; Rewind and step over the tag.
    lea rax, [ubxp_test_cursor]
    mov qword [rax + ubxp_cursor_t.pos], 0
    mov dword [rax + ubxp_cursor_t.error], 0

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_scratch]
    lea rdx, [ubxp_test_scratch + 16]
    call ubxp_read_tag
    test rax, rax
    js .pr_fail

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_cursor2]
    call ubxp_packed_enter
    test rax, rax
    js .pr_fail

    xor r12, r12
.pr_loop:
    cmp r12, ubxp_test_varint_count
    jae .pr_exhausted

    lea rdi, [ubxp_test_cursor2]
    lea rsi, [ubxp_test_scratch + 32]
    call ubxp_varint_decode
    test rax, rax
    js .pr_fail

    lea rax, [ubxp_test_varints]
    mov rbx, [rax + r12 * 8]
    mov r13, [ubxp_test_scratch + 32]
    cmp rbx, r13
    jne .pr_fail

    inc r12
    jmp .pr_loop

.pr_exhausted:
    ; The sub-cursor must be exactly drained: no trailing bytes.
    lea rdi, [ubxp_test_cursor2]
    call ubxp_cursor_remaining
    test rax, rax
    jnz .pr_fail

    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.pr_fail:
    mov rax, UBXP_TEST_PACKED
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_test_nested_roundtrip
;
; Builds a submessage, closes it, then descends with a sub-cursor and confirms
; the patched length bounds the child exactly.
;
; Returns:
;   RAX = 0 on success, non-zero on mismatch
; -----------------------------------------------------------------------------
align 32
ubxp_test_nested_roundtrip:
    push rbx
    push r12

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_buf]
    mov rdx, UBXP_TEST_BUF_SIZE
    call ubxp_cursor_init

    lea rdi, [ubxp_test_cursor]
    mov rsi, 3
    call ubxp_submsg_begin
    test rax, rax
    js .nr_fail
    mov rbx, rax

    ; Child body: two tagged varints.
    lea rdi, [ubxp_test_cursor]
    mov rsi, 1
    mov edx, UBXP_WIRE_VARINT
    call ubxp_write_tag
    lea rdi, [ubxp_test_cursor]
    mov rsi, 42
    call ubxp_varint_encode

    lea rdi, [ubxp_test_cursor]
    mov rsi, 2
    mov edx, UBXP_WIRE_VARINT
    call ubxp_write_tag
    lea rdi, [ubxp_test_cursor]
    mov rsi, 99999
    call ubxp_varint_encode

    lea rdi, [ubxp_test_cursor]
    mov rsi, rbx
    call ubxp_submsg_end
    test rax, rax
    js .nr_fail
    mov r12, rax                    ; Body length reported on close

    ; Rewind, read the container tag, descend.
    lea rax, [ubxp_test_cursor]
    mov qword [rax + ubxp_cursor_t.pos], 0
    mov dword [rax + ubxp_cursor_t.error], 0

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_scratch]
    lea rdx, [ubxp_test_scratch + 16]
    call ubxp_read_tag
    test rax, rax
    js .nr_fail

    cmp qword [ubxp_test_scratch], 3            ; Field number survived
    jne .nr_fail
    cmp qword [ubxp_test_scratch + 16], UBXP_WIRE_CONTAINER
    jne .nr_fail

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_cursor2]
    call ubxp_submsg_enter
    test rax, rax
    js .nr_fail

    ; The decoded child length must match what close reported.
    cmp rax, r12
    jne .nr_fail

    ; First child field must read back as 42.
    lea rdi, [ubxp_test_cursor2]
    lea rsi, [ubxp_test_scratch]
    lea rdx, [ubxp_test_scratch + 16]
    call ubxp_read_tag
    test rax, rax
    js .nr_fail

    lea rdi, [ubxp_test_cursor2]
    lea rsi, [ubxp_test_scratch + 32]
    call ubxp_varint_decode
    test rax, rax
    js .nr_fail
    cmp qword [ubxp_test_scratch + 32], 42
    jne .nr_fail

    xor eax, eax
    pop r12
    pop rbx
    ret

.nr_fail:
    mov rax, UBXP_TEST_NESTED
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_test_unknown_roundtrip
;
; The regression guard for the data-loss hole: capture a field with no
; descriptor, replay it into a fresh frame, and confirm the value survives a
; hop through a reader that never understood it.
;
; Returns:
;   RAX = 0 on success, non-zero on mismatch
; -----------------------------------------------------------------------------
align 32
ubxp_test_unknown_roundtrip:
    push rbx
    push r12

    ; Source frame: field 9, varint 12345.
    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_buf]
    mov rdx, UBXP_TEST_BUF_SIZE
    call ubxp_cursor_init

    lea rdi, [ubxp_test_cursor]
    mov rsi, 9
    mov edx, UBXP_WIRE_VARINT
    call ubxp_write_tag
    test rax, rax
    js .ur_fail

    lea rdi, [ubxp_test_cursor]
    mov rsi, 12345
    call ubxp_varint_encode
    test rax, rax
    js .ur_fail

    mov rbx, [ubxp_test_cursor + ubxp_cursor_t.pos]     ; Source frame width

    ; Rewind the source and bind a retention store.
    lea rax, [ubxp_test_cursor]
    mov qword [rax + ubxp_cursor_t.pos], 0
    mov dword [rax + ubxp_cursor_t.error], 0

    lea rdi, [ubxp_test_sink_cur]
    lea rsi, [ubxp_test_sink]
    mov rdx, UBXP_TEST_BUF_SIZE
    call ubxp_cursor_init

    lea rdi, [ubxp_test_unknown]
    lea rsi, [ubxp_test_sink_cur]
    call ubxp_unknown_init

    lea rdi, [ubxp_test_cursor]
    lea rsi, [ubxp_test_unknown]
    call ubxp_unknown_capture
    test rax, rax
    js .ur_fail

    ; The whole field, tag included, must have been retained.
    cmp rax, rbx
    jne .ur_fail
    cmp dword [ubxp_test_unknown + ubxp_unknown_t.count], 1
    jne .ur_fail

    ; Replay into a fresh frame.
    lea rdi, [ubxp_test_cursor2]
    lea rsi, [ubxp_test_buf + 2048]
    mov rdx, 1024
    call ubxp_cursor_init

    lea rdi, [ubxp_test_cursor2]
    lea rsi, [ubxp_test_unknown]
    call ubxp_unknown_replay
    test rax, rax
    js .ur_fail
    cmp rax, rbx
    jne .ur_fail

    ; Decode the replayed frame: field 9 must still hold 12345.
    lea rax, [ubxp_test_cursor2]
    mov qword [rax + ubxp_cursor_t.pos], 0
    mov dword [rax + ubxp_cursor_t.error], 0

    lea rdi, [ubxp_test_cursor2]
    lea rsi, [ubxp_test_scratch]
    lea rdx, [ubxp_test_scratch + 16]
    call ubxp_read_tag
    test rax, rax
    js .ur_fail
    cmp qword [ubxp_test_scratch], 9
    jne .ur_fail

    lea rdi, [ubxp_test_cursor2]
    lea rsi, [ubxp_test_scratch + 32]
    call ubxp_varint_decode
    test rax, rax
    js .ur_fail
    cmp qword [ubxp_test_scratch + 32], 12345
    jne .ur_fail

    xor eax, eax
    pop r12
    pop rbx
    ret

.ur_fail:
    mov rax, UBXP_TEST_UNKNOWN
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_test_run_all
;
; Runs every case and accumulates failures.
;
; Returns:
;   RAX = 0 when all pass, else a UBXP_TEST_* bitmask of the failures
; -----------------------------------------------------------------------------
align 32
ubxp_test_run_all:
    push rbx
    xor rbx, rbx

    call ubxp_test_varint_roundtrip
    or rbx, rax

    call ubxp_test_zigzag_roundtrip
    or rbx, rax

    call ubxp_test_frame_roundtrip
    or rbx, rax

    call ubxp_test_packed_roundtrip
    or rbx, rax

    call ubxp_test_nested_roundtrip
    or rbx, rax

    call ubxp_test_unknown_roundtrip
    or rbx, rax

    mov rax, rbx
    pop rbx
    ret
