%ifndef GUARD_STORAGE_UBXP_DEBUG_DUMP_ASM
%define GUARD_STORAGE_UBXP_DEBUG_DUMP_ASM
; =============================================================================
; Tattva OS — storage/ubxp/debug/dump.asm
; =============================================================================
; UBXP Human-Readable Frame Rendering.
;
; Implements:
;   - Raw byte / literal / decimal emission into a sink (`ubxp_dump_*`)
;   - Descriptor-aware frame rendering (`ubxp_dump_frame`)
;
; A binary format with no readable form is painful to debug: a bad frame is
; just bytes, and in a unikernel there is no `protoc --decode` to reach for.
; This renders a frame as text using a descriptor table when one is supplied,
; falling back to field numbers and wire types when it is not — so even a
; frame written against an unknown schema prints something useful.
;
; Rendering never fails destructively: if the sink fills, output is truncated
; and the sink's sticky error records it. Diagnostics must not themselves be a
; source of faults.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .rodata

ubxp_dump_wire_names:
    dq .varint, .fixed64, .bytes, .container, .unknown, .fixed32, .unknown, .unknown
.varint:        db "varint", 0
.fixed64:       db "fixed64", 0
.bytes:         db "bytes", 0
.container:     db "container", 0
.fixed32:       db "fixed32", 0
.unknown:       db "?", 0

ubxp_dump_field_lit:    db "field ", 0
ubxp_dump_open_lit:     db " [", 0
ubxp_dump_close_lit:    db "] = ", 0
ubxp_dump_nl_lit:       db 10, 0
ubxp_dump_bytes_lit:    db " bytes", 0

section .text

global ubxp_dump_byte
global ubxp_dump_literal
global ubxp_dump_u64
global ubxp_dump_frame

; -----------------------------------------------------------------------------
; ubxp_dump_byte
;
; Appends one byte to the sink, silently dropping it once the sink is full.
;
; Inputs:
;   RDI = Pointer to the sink ubxp_cursor_t
;   ESI = Byte value
;
; Returns:
;   RAX = 1 when written, 0 when dropped
; -----------------------------------------------------------------------------
align 32
ubxp_dump_byte:
    mov rcx, [rdi + ubxp_cursor_t.base]
    add rcx, [rdi + ubxp_cursor_t.pos]
    cmp rcx, [rdi + ubxp_cursor_t.limit]
    jae .db_full

    mov [rcx], sil
    inc qword [rdi + ubxp_cursor_t.pos]
    mov rax, 1
    ret

.db_full:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_NOSPC
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_dump_literal
;
; Appends a NUL-terminated string.
;
; Inputs:
;   RDI = Pointer to the sink ubxp_cursor_t
;   RSI = Pointer to a NUL-terminated string
;
; Returns:
;   RAX = Bytes written
; -----------------------------------------------------------------------------
align 32
ubxp_dump_literal:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    xor r13, r13

    test r12, r12
    jz .dl_done                     ; Tolerate a null name pointer

.dl_loop:
    movzx eax, byte [r12]
    test al, al
    jz .dl_done

    mov rdi, rbx
    mov esi, eax
    call ubxp_dump_byte
    add r13, rax

    inc r12
    jmp .dl_loop

.dl_done:
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_dump_u64
;
; Appends an unsigned value in decimal.
;
; Inputs:
;   RDI = Pointer to the sink ubxp_cursor_t
;   RSI = Value
;
; Returns:
;   RAX = Bytes written
; -----------------------------------------------------------------------------
align 32
ubxp_dump_u64:
    push rbx
    push r12
    push r13
    sub rsp, 32                     ; Room for 20 digits

    mov rbx, rdi
    mov rax, rsi
    xor r12, r12                    ; Digit count
    mov r13, 10

    test rax, rax
    jnz .du_extract

    ; Zero needs one explicit digit.
    mov byte [rsp], '0'
    mov r12, 1
    jmp .du_emit

.du_extract:
    xor edx, edx
    div r13                         ; RAX = quotient, RDX = remainder
    add dl, '0'
    mov [rsp + r12], dl             ; Digits land reversed
    inc r12
    test rax, rax
    jnz .du_extract

.du_emit:
    mov r13, r12                    ; Walk back down
.du_emit_loop:
    test r13, r13
    jz .du_done
    dec r13

    mov rdi, rbx
    movzx esi, byte [rsp + r13]
    call ubxp_dump_byte
    jmp .du_emit_loop

.du_done:
    mov rax, r12
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_dump_frame
;
; Renders a frame body as one line per field. With a descriptor the field name
; is printed; without one, the field number and wire type still are.
;
; The cursor is restored to its starting position, so a dump is a side-effect
; free probe that can be dropped into a decode path while debugging.
;
; Inputs:
;   RDI = Pointer to the source ubxp_cursor_t positioned at the body
;   RSI = Pointer to ubxp_msg_desc_t, or 0 for a schema-less dump
;   RDX = Pointer to the sink ubxp_cursor_t
;
; Returns:
;   RAX = Fields rendered, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_dump_frame:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48                 ; [rsp] field number, [rsp+16] wire type

    mov rbx, rdi                ; Source
    mov r12, rsi                ; Descriptor or 0
    mov r13, rdx                ; Sink
    xor r14, r14                ; Fields rendered
    mov r15, [rbx + ubxp_cursor_t.pos]

.dfr_loop:
    mov rdi, rbx
    call ubxp_cursor_remaining
    test rax, rax
    jz .dfr_done

    mov rdi, rbx
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call ubxp_read_tag
    test rax, rax
    js .dfr_fail

    ; Prefer the declared name; fall back to "field N".
    xor rax, rax
    test r12, r12
    jz .dfr_no_name

    mov rdi, r12
    mov rsi, [rsp]
    call ubxp_desc_find
    test rax, rax
    jz .dfr_no_name

    mov rdi, r13
    mov rsi, [rax + ubxp_field_desc_t.name]
    call ubxp_dump_literal
    jmp .dfr_wire

.dfr_no_name:
    mov rdi, r13
    lea rsi, [ubxp_dump_field_lit]
    call ubxp_dump_literal
    mov rdi, r13
    mov rsi, [rsp]
    call ubxp_dump_u64

.dfr_wire:
    mov rdi, r13
    lea rsi, [ubxp_dump_open_lit]
    call ubxp_dump_literal

    mov rcx, [rsp + 16]
    and rcx, UBXP_WIRE_MASK
    lea rax, [ubxp_dump_wire_names]
    mov rdi, r13
    mov rsi, [rax + rcx * 8]
    call ubxp_dump_literal

    mov rdi, r13
    lea rsi, [ubxp_dump_close_lit]
    call ubxp_dump_literal

    ; Value: varints print numerically, everything else prints its width.
    mov rcx, [rsp + 16]
    cmp rcx, UBXP_WIRE_VARINT
    jne .dfr_width

    mov rdi, rbx
    lea rsi, [rsp + 32]
    call ubxp_varint_decode
    test rax, rax
    js .dfr_fail

    mov rdi, r13
    mov rsi, [rsp + 32]
    call ubxp_dump_u64
    jmp .dfr_eol

.dfr_width:
    mov r8, [rbx + ubxp_cursor_t.pos]
    mov rdi, rbx
    mov esi, dword [rsp + 16]
    push r8
    call ubxp_skip_value
    pop r8
    test rax, rax
    js .dfr_fail

    mov rcx, [rbx + ubxp_cursor_t.pos]
    sub rcx, r8                     ; Bytes the value occupied

    mov rdi, r13
    mov rsi, rcx
    call ubxp_dump_u64
    mov rdi, r13
    lea rsi, [ubxp_dump_bytes_lit]
    call ubxp_dump_literal

.dfr_eol:
    mov rdi, r13
    lea rsi, [ubxp_dump_nl_lit]
    call ubxp_dump_literal

    inc r14
    jmp .dfr_loop

.dfr_done:
    mov [rbx + ubxp_cursor_t.pos], r15      ; Restore the probe
    mov rax, r14
    jmp .dfr_return

.dfr_fail:
    mov [rbx + ubxp_cursor_t.pos], r15

.dfr_return:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UBXP_DEBUG_DUMP_ASM
