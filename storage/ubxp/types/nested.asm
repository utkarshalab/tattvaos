%ifndef GUARD_STORAGE_UBXP_TYPES_NESTED_ASM
%define GUARD_STORAGE_UBXP_TYPES_NESTED_ASM
; =============================================================================
; Tattva OS — storage/ubxp/types/nested.asm
; =============================================================================
; UBXP Nested Message Composition & Bounded Sub-Cursor Descent.
;
; Implements:
;   - Single-pass submessage open/close with back-patched length
;     (`ubxp_submsg_begin`, `ubxp_submsg_end`)
;   - Bounded sub-cursor descent on the read side (`ubxp_submsg_enter`)
;
; A nested body's length is not known until the body has been written, and a
; LEB128 length is variable width, so a naive encoder must either pre-compute
; every nested size in a separate pass (what protobuf's C++ runtime does via
; ByteSizeLong) or shift the buffer afterwards.
;
; Neither is attractive here, so an open reserves a FIXED four-byte length slot
; and close patches it in place. LEB128 permits redundant continuation bytes,
; so a short length simply encodes non-minimally. Four bytes address 2^28-1,
; well above UBXP_MAX_PAYLOAD, so the slot can never overflow. The cost is that
; nested frames are not in canonical form; ubxp_canonical_check reports this
; when byte-exact reproducibility is required.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_submsg_begin
global ubxp_submsg_end
global ubxp_submsg_enter
global ubxp_len_reserve_patch

; -----------------------------------------------------------------------------
; ubxp_len_reserve_patch
;
; Writes a value into a four-byte LEB128 slot, padding with redundant
; continuation bytes so the width is always exactly UBXP_LEN_RESERVE.
;
; Inputs:
;   RDI = Address of the four-byte slot
;   RSI = Value to encode (must be <= UBXP_LEN_RESERVE_MAX)
;
; Returns:
;   RAX = UBXP_LEN_RESERVE, or UBXP_ERR_OVERFLOW when the value will not fit
; -----------------------------------------------------------------------------
align 32
ubxp_len_reserve_patch:
    mov rax, UBXP_LEN_RESERVE_MAX
    cmp rsi, rax
    ja .lp_overflow

    mov rax, rsi
    and rax, 0x7F
    or rax, 0x80                    ; Continuation set: more bytes follow
    mov byte [rdi], al

    mov rax, rsi
    shr rax, 7
    and rax, 0x7F
    or rax, 0x80
    mov byte [rdi + 1], al

    mov rax, rsi
    shr rax, 14
    and rax, 0x7F
    or rax, 0x80
    mov byte [rdi + 2], al

    mov rax, rsi
    shr rax, 21
    and rax, 0x7F                   ; Terminator: continuation bit clear
    mov byte [rdi + 3], al

    mov rax, UBXP_LEN_RESERVE
    ret

.lp_overflow:
    mov rax, UBXP_ERR_OVERFLOW
    ret

; -----------------------------------------------------------------------------
; ubxp_submsg_begin
;
; Emits a container tag and reserves the length slot, then descends one
; nesting level.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Field number
;
; Returns:
;   RAX = Token to pass to ubxp_submsg_end, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_submsg_begin:
    push rbx
    push r12

    mov rbx, rdi

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .sb_sticky

    ; Container tag.
    mov rdi, rbx
    mov edx, UBXP_WIRE_CONTAINER
    call ubxp_write_tag
    test rax, rax
    js .sb_return

    ; The slot begins where the cursor now sits; that offset is the token.
    mov r12, [rbx + ubxp_cursor_t.pos]

    mov rdi, rbx
    mov rsi, UBXP_LEN_RESERVE
    call ubxp_skip_fixed            ; Reserve without writing: bounds-checked
    test rax, rax
    js .sb_return

    ; Pre-fill the slot with an encoded zero so a frame abandoned mid-write
    ; still parses as an empty submessage rather than as garbage.
    mov rdi, [rbx + ubxp_cursor_t.base]
    add rdi, r12
    xor rsi, rsi
    call ubxp_len_reserve_patch

    mov rdi, rbx
    call ubxp_enter_container
    test rax, rax
    js .sb_return

    mov rax, r12
    jmp .sb_return

.sb_sticky:
    movsxd rax, eax

.sb_return:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_submsg_end
;
; Patches the reserved slot with the body length and ascends one level.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Token from ubxp_submsg_begin
;
; Returns:
;   RAX = Body length in bytes, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_submsg_end:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi                    ; Token = slot offset

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .se_sticky

    mov r13, [rbx + ubxp_cursor_t.pos]
    sub r13, r12
    sub r13, UBXP_LEN_RESERVE       ; R13 = body length
    js .se_inval                    ; Cursor moved backwards: caller bug

    mov rdi, [rbx + ubxp_cursor_t.base]
    add rdi, r12
    mov rsi, r13
    call ubxp_len_reserve_patch
    test rax, rax
    js .se_overflow

    mov rdi, rbx
    call ubxp_exit_container
    test rax, rax
    js .se_return

    mov rax, r13
    jmp .se_return

.se_inval:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_INVAL
    mov rax, UBXP_ERR_INVAL
    jmp .se_return

.se_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .se_return

.se_sticky:
    movsxd rax, eax

.se_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_submsg_enter
;
; Reads a container length and builds a sub-cursor limited to exactly that
; body, then advances the parent past it. Decoding the child through the
; sub-cursor makes overrunning the submessage structurally impossible rather
; than merely checked.
;
; Inputs:
;   RDI = Pointer to the parent ubxp_cursor_t
;   RSI = Pointer to a caller-owned ubxp_cursor_t to initialise
;
; Returns:
;   RAX = Body length, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_submsg_enter:
    push rbx
    push r12
    push r13
    sub rsp, 16                     ; Scratch for the decoded length

    mov rbx, rdi                    ; Parent
    mov r12, rsi                    ; Child

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .sn_sticky

    mov rsi, rsp
    call ubxp_varint_decode
    test rax, rax
    js .sn_return

    mov r13, [rsp]                  ; Declared body length
    cmp r13, UBXP_MAX_PAYLOAD
    ja .sn_overflow

    ; The declared body must lie entirely inside the parent's window.
    mov rcx, [rbx + ubxp_cursor_t.base]
    add rcx, [rbx + ubxp_cursor_t.pos]
    mov rdx, rcx
    add rdx, r13
    cmp rdx, [rbx + ubxp_cursor_t.limit]
    ja .sn_truncated

    ; Child spans exactly the body.
    mov [r12 + ubxp_cursor_t.base], rcx
    mov [r12 + ubxp_cursor_t.limit], rdx
    mov qword [r12 + ubxp_cursor_t.pos], 0
    mov eax, dword [rbx + ubxp_cursor_t.depth]
    inc eax
    mov dword [r12 + ubxp_cursor_t.depth], eax
    mov dword [r12 + ubxp_cursor_t.error], 0

    cmp eax, UBXP_MAX_NESTING
    ja .sn_nesting

    add qword [rbx + ubxp_cursor_t.pos], r13    ; Parent steps over the child

    mov rax, r13
    jmp .sn_return

.sn_truncated:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    jmp .sn_return

.sn_overflow:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_OVERFLOW
    mov rax, UBXP_ERR_OVERFLOW
    jmp .sn_return

.sn_nesting:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_NESTING
    mov rax, UBXP_ERR_NESTING
    jmp .sn_return

.sn_sticky:
    movsxd rax, eax

.sn_return:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UBXP_TYPES_NESTED_ASM
