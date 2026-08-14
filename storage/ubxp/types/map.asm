; =============================================================================
; Tattva OS — storage/ubxp/types/map.asm
; =============================================================================
; UBXP Map Codec — Key/Value Association as Repeated Entries.
;
; Implements:
;   - Entry framing (`ubxp_map_entry_begin`, `ubxp_map_entry_end`)
;   - Scalar and string-keyed convenience writers (`ubxp_write_map_*`)
;   - Entry descent on the read side (`ubxp_map_entry_enter`)
;
; A map is not a distinct wire type. It is a repeated container whose entries
; each carry field 1 as the key and field 2 as the value — the same shape
; protobuf uses, chosen so the two remain conceptually interchangeable and so
; maps degrade gracefully: a reader with no map support still sees a
; well-formed repeated container and can skip or relay it intact.
;
; Ordering is not preserved and duplicate keys are not rejected here. A decoder
; applying entries in arrival order yields last-write-wins, which is the same
; rule protobuf specifies.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

%define UBXP_MAP_KEY_FIELD           1
%define UBXP_MAP_VALUE_FIELD         2

section .text

global ubxp_map_entry_begin
global ubxp_map_entry_end
global ubxp_map_entry_enter
global ubxp_write_map_uint_uint
global ubxp_write_map_str_bytes

; -----------------------------------------------------------------------------
; ubxp_map_entry_begin
;
; Opens one map entry. The caller then writes field 1 (key) and field 2
; (value) with any scalar or length-delimited writer.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Map field number
;
; Returns:
;   RAX = Token for ubxp_map_entry_end, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_map_entry_begin:
    jmp ubxp_submsg_begin

; -----------------------------------------------------------------------------
; ubxp_map_entry_end
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Token from ubxp_map_entry_begin
;
; Returns:
;   RAX = Entry body length, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_map_entry_end:
    jmp ubxp_submsg_end

; -----------------------------------------------------------------------------
; ubxp_map_entry_enter
;
; Builds a sub-cursor over one map entry body.
;
; Inputs:
;   RDI = Pointer to the parent ubxp_cursor_t
;   RSI = Pointer to a caller-owned ubxp_cursor_t
;
; Returns:
;   RAX = Entry body length, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_map_entry_enter:
    jmp ubxp_submsg_enter

; -----------------------------------------------------------------------------
; ubxp_write_map_uint_uint
;
; Emits an entire map of unsigned keys to unsigned values as a run of entries
; sharing one field number.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Map field number
;   RDX = Pointer to a 64-bit key array
;   RCX = Pointer to a 64-bit value array
;   R8  = Entry count
;
; Returns:
;   RAX = Entries written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_map_uint_uint:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Cursor
    mov r15, rsi                    ; Map field number
    mov r12, rdx                    ; Keys
    mov r13, rcx                    ; Values
    mov r14, r8                     ; Count

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .mu_sticky

    push rbp
    xor rbp, rbp                    ; Entry index

.mu_loop:
    cmp rbp, r14
    jae .mu_done

    mov rdi, rbx
    mov rsi, r15
    call ubxp_map_entry_begin
    test rax, rax
    js .mu_fail
    mov r9, rax                     ; Entry token

    ; Key: field 1, varint.
    mov rdi, rbx
    mov rsi, UBXP_MAP_KEY_FIELD
    mov edx, UBXP_WIRE_VARINT
    push r9
    call ubxp_write_tag
    pop r9
    test rax, rax
    js .mu_fail

    mov rdi, rbx
    mov rsi, [r12 + rbp * 8]
    push r9
    call ubxp_varint_encode
    pop r9
    test rax, rax
    js .mu_fail

    ; Value: field 2, varint.
    mov rdi, rbx
    mov rsi, UBXP_MAP_VALUE_FIELD
    mov edx, UBXP_WIRE_VARINT
    push r9
    call ubxp_write_tag
    pop r9
    test rax, rax
    js .mu_fail

    mov rdi, rbx
    mov rsi, [r13 + rbp * 8]
    push r9
    call ubxp_varint_encode
    pop r9
    test rax, rax
    js .mu_fail

    mov rdi, rbx
    mov rsi, r9
    call ubxp_map_entry_end
    test rax, rax
    js .mu_fail

    inc rbp
    jmp .mu_loop

.mu_done:
    mov rax, r14
    pop rbp
    jmp .mu_return

.mu_fail:
    pop rbp
    jmp .mu_return

.mu_sticky:
    movsxd rax, eax

.mu_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_write_map_str_bytes
;
; String-keyed map of byte blobs — the shape uobject metadata needs.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Map field number
;   RDX = Pointer to a ubxp_slice_t key array
;   RCX = Pointer to a ubxp_slice_t value array
;   R8  = Entry count
;
; Returns:
;   RAX = Entries written, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_write_map_str_bytes:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    mov r15, rsi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .ms_sticky

    push rbp
    xor rbp, rbp

.ms_loop:
    cmp rbp, r14
    jae .ms_done

    mov rdi, rbx
    mov rsi, r15
    call ubxp_map_entry_begin
    test rax, rax
    js .ms_fail
    mov r9, rax

    ; Key: field 1, length-delimited.
    mov rdi, rbx
    mov rsi, UBXP_MAP_KEY_FIELD
    mov edx, UBXP_WIRE_BYTES
    push r9
    call ubxp_write_tag
    pop r9
    test rax, rax
    js .ms_fail

    mov rax, rbp
    shl rax, 4                      ; ubxp_slice_t is 16 bytes
    add rax, r12
    mov rdi, rbx
    mov rsi, [rax + ubxp_slice_t.ptr]
    mov rdx, [rax + ubxp_slice_t.len]
    push r9
    call ubxp_write_bytes
    pop r9
    test rax, rax
    js .ms_fail

    ; Value: field 2, length-delimited.
    mov rdi, rbx
    mov rsi, UBXP_MAP_VALUE_FIELD
    mov edx, UBXP_WIRE_BYTES
    push r9
    call ubxp_write_tag
    pop r9
    test rax, rax
    js .ms_fail

    mov rax, rbp
    shl rax, 4
    add rax, r13
    mov rdi, rbx
    mov rsi, [rax + ubxp_slice_t.ptr]
    mov rdx, [rax + ubxp_slice_t.len]
    push r9
    call ubxp_write_bytes
    pop r9
    test rax, rax
    js .ms_fail

    mov rdi, rbx
    mov rsi, r9
    call ubxp_map_entry_end
    test rax, rax
    js .ms_fail

    inc rbp
    jmp .ms_loop

.ms_done:
    mov rax, r14
    pop rbp
    jmp .ms_return

.ms_fail:
    pop rbp
    jmp .ms_return

.ms_sticky:
    movsxd rax, eax

.ms_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
