; =============================================================================
; Tattva OS — storage/ubxp/types/repeated.asm
; =============================================================================
; UBXP Repeated Field Codec — Packed and Tag-Per-Element Encodings.
;
; Implements:
;   - Packed scalar arrays under one tag (`ubxp_write_packed_*`)
;   - Bounded iteration over a packed blob (`ubxp_packed_enter`)
;   - Tag-per-element repeated fields (`ubxp_write_repeated_*`)
;
; A packed field writes one tag and one length, then the raw element sequence.
; The tag-per-element form repeats the tag for every value, which costs at
; least one extra byte each but allows elements to be appended by concatenating
; frames. Packing is the right default for scalars; the unpacked form exists
; because length-delimited and container elements cannot be packed at all.
;
; Packed sizing is a genuine two-pass operation: the byte length must precede
; the elements, and a LEB128 length is variable width. The size pass here is
; pure arithmetic over the source array and touches no buffer.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_packed_size_uint
global ubxp_write_packed_uint
global ubxp_write_packed_int
global ubxp_write_packed_fixed64
global ubxp_write_packed_fixed32
global ubxp_packed_enter
global ubxp_write_repeated_uint
global ubxp_write_repeated_bytes

; -----------------------------------------------------------------------------
; ubxp_packed_size_uint
;
; Sums the LEB128 widths of an unsigned array without writing anything.
;
; Inputs:
;   RDI = Pointer to a 64-bit unsigned array
;   RSI = Element count
;
; Returns:
;   RAX = Total encoded byte length
; -----------------------------------------------------------------------------
align 32
ubxp_packed_size_uint:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Array
    mov r12, rsi                    ; Remaining
    xor r13, r13                    ; Accumulated size

.ps_loop:
    test r12, r12
    jz .ps_done

    mov rdi, [rbx]
    call ubxp_varint_size
    add r13, rax

    add rbx, 8
    dec r12
    jmp .ps_loop

.ps_done:
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_packed_uint
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;   RDX = Pointer to a 64-bit unsigned array
;   RCX = Element count
;
; Returns:
;   RAX = Element count written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_packed_uint:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Cursor
    mov r12, rdx                    ; Array
    mov r13, rcx                    ; Count
    mov r14, rsi                    ; Field number

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .wp_sticky

    ; Tag carries BYTES: a packed field is one length-delimited blob.
    mov rdi, rbx
    mov rsi, r14
    mov edx, UBXP_WIRE_BYTES
    call ubxp_write_tag
    test rax, rax
    js .wp_return

    ; Size pass, then the length prefix.
    mov rdi, r12
    mov rsi, r13
    call ubxp_packed_size_uint

    mov rdi, rbx
    mov rsi, rax
    call ubxp_varint_encode
    test rax, rax
    js .wp_return

    ; Element pass.
    xor r14, r14                    ; Reuse as the loop index
.wp_loop:
    cmp r14, r13
    jae .wp_done

    mov rdi, rbx
    mov rsi, [r12 + r14 * 8]
    call ubxp_varint_encode
    test rax, rax
    js .wp_return

    inc r14
    jmp .wp_loop

.wp_done:
    mov rax, r13
    jmp .wp_return

.wp_sticky:
    movsxd rax, eax

.wp_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_packed_int
;
; Zig-zag maps each element before packing, so arrays of small negatives stay
; one byte per element.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;   RDX = Pointer to a 64-bit signed array
;   RCX = Element count
;
; Returns:
;   RAX = Element count written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_packed_int:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, rsi

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .wpi_sticky

    mov rdi, rbx
    mov rsi, r14
    mov edx, UBXP_WIRE_BYTES
    call ubxp_write_tag
    test rax, rax
    js .wpi_return

    ; Size pass over the zig-zag mapped values.
    xor r15, r15                    ; Index
    xor r14, r14                    ; Accumulated size
.wpi_size:
    cmp r15, r13
    jae .wpi_size_done
    mov rdi, [r12 + r15 * 8]
    call ubxp_zigzag_encode
    mov rdi, rax
    call ubxp_varint_size
    add r14, rax
    inc r15
    jmp .wpi_size

.wpi_size_done:
    mov rdi, rbx
    mov rsi, r14
    call ubxp_varint_encode
    test rax, rax
    js .wpi_return

    xor r15, r15
.wpi_loop:
    cmp r15, r13
    jae .wpi_done

    mov rdi, [r12 + r15 * 8]
    call ubxp_zigzag_encode

    mov rdi, rbx
    mov rsi, rax
    call ubxp_varint_encode
    test rax, rax
    js .wpi_return

    inc r15
    jmp .wpi_loop

.wpi_done:
    mov rax, r13
    jmp .wpi_return

.wpi_sticky:
    movsxd rax, eax

.wpi_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_packed_fixed64
;
; Fixed-width elements need no size pass: the length is count * 8.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;   RDX = Pointer to a 64-bit array
;   RCX = Element count
;
; Returns:
;   RAX = Element count written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_packed_fixed64:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .wf_sticky

    mov rdi, rbx
    mov edx, UBXP_WIRE_BYTES
    call ubxp_write_tag             ; RSI still holds the field number
    test rax, rax
    js .wf_return

    mov rdi, rbx
    mov rsi, r13
    shl rsi, 3                      ; count * 8
    call ubxp_varint_encode
    test rax, rax
    js .wf_return

    xor r14, r14
.wf_loop:
    cmp r14, r13
    jae .wf_done

    mov rdi, rbx
    mov rsi, [r12 + r14 * 8]
    call ubxp_write_fixed64
    test rax, rax
    js .wf_return

    inc r14
    jmp .wf_loop

.wf_done:
    mov rax, r13
    jmp .wf_return

.wf_sticky:
    movsxd rax, eax

.wf_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_packed_fixed32
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;   RDX = Pointer to a 32-bit array
;   RCX = Element count
;
; Returns:
;   RAX = Element count written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_packed_fixed32:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .wg_sticky

    mov rdi, rbx
    mov edx, UBXP_WIRE_BYTES
    call ubxp_write_tag
    test rax, rax
    js .wg_return

    mov rdi, rbx
    mov rsi, r13
    shl rsi, 2                      ; count * 4
    call ubxp_varint_encode
    test rax, rax
    js .wg_return

    xor r14, r14
.wg_loop:
    cmp r14, r13
    jae .wg_done

    mov rdi, rbx
    mov esi, dword [r12 + r14 * 4]
    call ubxp_write_fixed32
    test rax, rax
    js .wg_return

    inc r14
    jmp .wg_loop

.wg_done:
    mov rax, r13
    jmp .wg_return

.wg_sticky:
    movsxd rax, eax

.wg_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_packed_enter
;
; Builds a sub-cursor spanning exactly one packed blob. The caller then pulls
; elements with the ordinary scalar readers until the sub-cursor is exhausted,
; which needs no element count on the wire.
;
; Inputs:
;   RDI = Pointer to the parent ubxp_cursor_t
;   RSI = Pointer to a caller-owned ubxp_cursor_t to initialise
;
; Returns:
;   RAX = Blob length in bytes, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_packed_enter:
    push rbx
    push r12
    sub rsp, 16                     ; Scratch ubxp_slice_t

    mov rbx, rdi
    mov r12, rsi

    mov rdi, rbx
    mov rsi, rsp
    call ubxp_read_bytes
    test rax, rax
    js .pe_return

    mov rcx, [rsp + ubxp_slice_t.ptr]
    mov rdx, [rsp + ubxp_slice_t.len]

    mov [r12 + ubxp_cursor_t.base], rcx
    add rdx, rcx
    mov [r12 + ubxp_cursor_t.limit], rdx
    mov qword [r12 + ubxp_cursor_t.pos], 0
    mov dword [r12 + ubxp_cursor_t.depth], 0
    mov dword [r12 + ubxp_cursor_t.error], 0

    mov rax, [rsp + ubxp_slice_t.len]

.pe_return:
    add rsp, 16
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_repeated_uint
;
; Tag-per-element form. Costs more bytes than packing but lets a producer
; append elements by concatenation.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;   RDX = Pointer to a 64-bit unsigned array
;   RCX = Element count
;
; Returns:
;   RAX = Element count written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_repeated_uint:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r15, rsi                    ; Field number
    mov r12, rdx
    mov r13, rcx
    xor r14, r14

.wr_loop:
    cmp r14, r13
    jae .wr_done

    mov rdi, rbx
    mov rsi, r15
    mov edx, UBXP_WIRE_VARINT
    call ubxp_write_tag
    test rax, rax
    js .wr_return

    mov rdi, rbx
    mov rsi, [r12 + r14 * 8]
    call ubxp_varint_encode
    test rax, rax
    js .wr_return

    inc r14
    jmp .wr_loop

.wr_done:
    mov rax, r13

.wr_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_repeated_bytes
;
; Length-delimited elements can never be packed, so this tag-per-element form
; is the only encoding available for repeated strings and blobs.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;   RDX = Pointer to a ubxp_slice_t array
;   RCX = Element count
;
; Returns:
;   RAX = Element count written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_repeated_bytes:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r15, rsi
    mov r12, rdx
    mov r13, rcx
    xor r14, r14

.wrb_loop:
    cmp r14, r13
    jae .wrb_done

    mov rdi, rbx
    mov rsi, r15
    mov edx, UBXP_WIRE_BYTES
    call ubxp_write_tag
    test rax, rax
    js .wrb_return

    ; Each row is a ubxp_slice_t: 16 bytes of {ptr, len}.
    mov rax, r14
    shl rax, 4
    add rax, r12

    mov rdi, rbx
    mov rsi, [rax + ubxp_slice_t.ptr]
    mov rdx, [rax + ubxp_slice_t.len]
    call ubxp_write_bytes
    test rax, rax
    js .wrb_return

    inc r14
    jmp .wrb_loop

.wrb_done:
    mov rax, r13

.wrb_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
