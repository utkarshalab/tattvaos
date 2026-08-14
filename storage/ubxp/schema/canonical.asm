; =============================================================================
; Tattva OS — storage/ubxp/schema/canonical.asm
; =============================================================================
; UBXP Canonical Form — Deterministic Encoding Verification.
;
; Implements:
;   - Minimal-width varint checking (`ubxp_varint_is_minimal`)
;   - Whole-frame canonical verification (`ubxp_canonical_check`)
;
; A tagged format lets the same logical message encode many ways: fields may
; appear in any order, and LEB128 permits redundant continuation bytes. That is
; harmless until bytes themselves carry meaning — content-addressed storage,
; deduplication by hash, or a signature over a frame all break when a
; re-encode produces different bytes for identical data.
;
; protobuf has exactly this problem and its documentation warns against
; assuming serialization is deterministic. Rather than repeat that trap
; silently, UBXP names the stricter form and provides a checker for it:
;
;   1. Top-level field numbers appear in strictly ascending order.
;   2. Every varint uses the fewest bytes that can represent its value.
;
; Note that ubxp_submsg_begin's fixed-width length slot deliberately violates
; rule 2, so frames containing nested messages are non-canonical by
; construction. That is the documented trade for single-pass encoding; a
; producer needing canonical output must size nested bodies in a separate pass.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_varint_is_minimal
global ubxp_canonical_check

; -----------------------------------------------------------------------------
; ubxp_varint_is_minimal
;
; A LEB128 encoding is minimal when it is one byte long, or when its final
; byte is non-zero. A trailing zero group encodes nothing and could have been
; dropped.
;
; Inputs:
;   RDI = Pointer to the first byte of the varint
;   RSI = Encoded width in bytes
;
; Returns:
;   RAX = 1 when minimal, 0 otherwise
; -----------------------------------------------------------------------------
align 32
ubxp_varint_is_minimal:
    test rsi, rsi
    jz .vm_no
    cmp rsi, 1
    je .vm_yes                      ; A single byte is always minimal

    mov rax, rsi
    dec rax
    movzx ecx, byte [rdi + rax]     ; Final group
    and ecx, 0x7F
    test ecx, ecx
    jz .vm_no                       ; Trailing zero group: padding

.vm_yes:
    mov rax, 1
    ret

.vm_no:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_canonical_check
;
; Walks a frame body and reports whether it is in canonical form. The cursor
; is left where it started, so a caller may check first and decode after.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t positioned at the body
;
; Returns:
;   RAX = UBXP_OK when canonical, UBXP_ERR_PROTO when not, or a decode error
; -----------------------------------------------------------------------------
align 32
ubxp_canonical_check:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48                 ; [rsp] field number, [rsp+16] wire type

    mov rbx, rdi
    mov r14, [rbx + ubxp_cursor_t.pos]      ; Remember where we began
    xor r13, r13                            ; Previous field number
    xor r15, r15                            ; Verdict: 0 = canonical

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .cc_sticky

.cc_loop:
    mov rdi, rbx
    call ubxp_cursor_remaining
    test rax, rax
    jz .cc_done

    mov r12, [rbx + ubxp_cursor_t.pos]      ; Tag start, for the width check

    mov rdi, rbx
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call ubxp_read_tag
    test rax, rax
    js .cc_fail

    ; Rule 2: the tag varint itself must be minimal.
    push rax
    mov rdi, [rbx + ubxp_cursor_t.base]
    add rdi, r12
    mov rsi, rax
    call ubxp_varint_is_minimal
    test rax, rax
    pop rax
    jz .cc_noncanonical

    ; Rule 1: field numbers must strictly ascend.
    mov rcx, [rsp]
    cmp rcx, r13
    jbe .cc_noncanonical
    mov r13, rcx

    mov rdi, rbx
    mov esi, dword [rsp + 16]
    call ubxp_skip_value
    test rax, rax
    js .cc_fail
    jmp .cc_loop

.cc_noncanonical:
    mov r15, UBXP_ERR_PROTO
    ; Keep walking so the cursor still lands at the body end.
    mov rdi, rbx
    mov esi, dword [rsp + 16]
    call ubxp_skip_value
    test rax, rax
    js .cc_fail
    jmp .cc_loop

.cc_done:
    mov [rbx + ubxp_cursor_t.pos], r14      ; Restore: this is a read-only probe
    mov rax, r15
    jmp .cc_return

.cc_fail:
    mov [rbx + ubxp_cursor_t.pos], r14
    jmp .cc_return

.cc_sticky:
    movsxd rax, eax

.cc_return:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
