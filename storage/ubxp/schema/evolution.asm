%ifndef GUARD_STORAGE_UBXP_SCHEMA_EVOLUTION_ASM
%define GUARD_STORAGE_UBXP_SCHEMA_EVOLUTION_ASM
; =============================================================================
; Tattva OS — storage/ubxp/schema/evolution.asm
; =============================================================================
; UBXP Schema Evolution — Unknown-Field Tolerance & Version Negotiation.
;
; Implements:
;   - Wire-type driven value skipping (`ubxp_skip_value`)
;   - Whole unknown-field traversal (`ubxp_skip_unknown_field`)
;   - Bounded container recursion (`ubxp_enter/exit_container`)
;   - Header version acceptance rules (`ubxp_version_compatible`)
;
; The evolution contract:
;   - A reader MUST skip field numbers it does not recognise rather than fail,
;     which is what lets an old reader consume a new writer's frame.
;   - Field numbers are never reused once retired, so a stale reader can never
;     mistake a new field for an old one.
;   - Wire types are never changed in place for an existing field number;
;     a changed representation takes a new number.
;   - Older frame versions are accepted; newer ones are refused, because a
;     newer writer may use a wire type this build cannot even skip.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_skip_value
global ubxp_skip_unknown_field
global ubxp_skip_fixed
global ubxp_enter_container
global ubxp_exit_container
global ubxp_version_compatible

; -----------------------------------------------------------------------------
; ubxp_skip_fixed
;
; Advances the cursor by a fixed width after bounds-checking it.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   RSI = Width in bytes
;
; Returns:
;   RAX = Bytes skipped, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_skip_fixed:
    mov eax, dword [rdi + ubxp_cursor_t.error]
    test eax, eax
    jnz .sf_sticky

    mov rcx, [rdi + ubxp_cursor_t.base]
    add rcx, [rdi + ubxp_cursor_t.pos]
    add rcx, rsi
    cmp rcx, [rdi + ubxp_cursor_t.limit]
    ja .sf_truncated

    add [rdi + ubxp_cursor_t.pos], rsi
    mov rax, rsi
    ret

.sf_truncated:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_TRUNCATED
    mov rax, UBXP_ERR_TRUNCATED
    ret

.sf_sticky:
    movsxd rax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_skip_value
;
; Steps over one value of the given wire type. This is the whole of forward
; compatibility: the reader does not need to know what the field means, only
; how wide it is.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;   ESI = Wire type (UBXP_WIRE_*)
;
; Returns:
;   RAX = Bytes skipped, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_skip_value:
    push rbx
    sub rsp, 16                     ; Scratch for the discarded varint

    mov rbx, rdi

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .sv_sticky

    cmp esi, UBXP_WIRE_VARINT
    je .sv_varint
    cmp esi, UBXP_WIRE_FIXED64
    je .sv_fixed64
    cmp esi, UBXP_WIRE_BYTES
    je .sv_delimited
    cmp esi, UBXP_WIRE_CONTAINER
    je .sv_delimited                ; Nested frames are length-prefixed too
    cmp esi, UBXP_WIRE_FIXED32
    je .sv_fixed32
    jmp .sv_proto                   ; Unknown wire type: unsafe to guess a width

.sv_varint:
    mov rdi, rbx
    mov rsi, rsp
    call ubxp_varint_decode
    jmp .sv_return

.sv_fixed64:
    mov rdi, rbx
    mov rsi, 8
    call ubxp_skip_fixed
    jmp .sv_return

.sv_fixed32:
    mov rdi, rbx
    mov rsi, 4
    call ubxp_skip_fixed
    jmp .sv_return

.sv_delimited:
    mov rdi, rbx
    call ubxp_skip_bytes
    jmp .sv_return

.sv_proto:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_PROTO
    mov rax, UBXP_ERR_PROTO
    jmp .sv_return

.sv_sticky:
    movsxd rax, eax

.sv_return:
    add rsp, 16
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_skip_unknown_field
;
; Reads a tag and discards its value. Callers use this when a decoded field
; number matches nothing in their schema.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;
; Returns:
;   RAX = Field number that was skipped, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_skip_unknown_field:
    push rbx
    push r12
    sub rsp, 32                     ; [rsp] = field number, [rsp+16] = wire type

    mov rbx, rdi

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .su_sticky

    mov rdi, rbx
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call ubxp_read_tag
    test rax, rax
    js .su_return

    mov r12, [rsp]                  ; Remember the field number for the caller

    mov rdi, rbx
    mov esi, dword [rsp + 16]
    call ubxp_skip_value
    test rax, rax
    js .su_return

    mov rax, r12
    jmp .su_return

.su_sticky:
    movsxd rax, eax

.su_return:
    add rsp, 32
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_enter_container
;
; Increments nesting depth, refusing to descend past UBXP_MAX_NESTING so a
; hostile frame cannot drive unbounded recursion in a caller's decode loop.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;
; Returns:
;   RAX = New depth, or UBXP_ERR_NESTING
; -----------------------------------------------------------------------------
align 32
ubxp_enter_container:
    mov eax, dword [rdi + ubxp_cursor_t.error]
    test eax, eax
    jnz .ec_sticky

    mov eax, dword [rdi + ubxp_cursor_t.depth]
    cmp eax, UBXP_MAX_NESTING
    jae .ec_toodeep

    inc eax
    mov dword [rdi + ubxp_cursor_t.depth], eax
    ret

.ec_toodeep:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_NESTING
    mov rax, UBXP_ERR_NESTING
    ret

.ec_sticky:
    movsxd rax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_exit_container
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t
;
; Returns:
;   RAX = New depth, or UBXP_ERR_INVAL on an unbalanced exit
; -----------------------------------------------------------------------------
align 32
ubxp_exit_container:
    mov eax, dword [rdi + ubxp_cursor_t.depth]
    test eax, eax
    jz .xc_unbalanced

    dec eax
    mov dword [rdi + ubxp_cursor_t.depth], eax
    ret

.xc_unbalanced:
    mov dword [rdi + ubxp_cursor_t.error], UBXP_ERR_INVAL
    mov rax, UBXP_ERR_INVAL
    ret

; -----------------------------------------------------------------------------
; ubxp_version_compatible
;
; Inputs:
;   RDI = Pointer to a ubxp_frame_header_t
;
; Returns:
;   RAX = UBXP_OK when this build can decode the frame, else UBXP_ERR_PROTO
; -----------------------------------------------------------------------------
align 32
ubxp_version_compatible:
    cmp dword [rdi + ubxp_frame_header_t.magic], UBXP_MAGIC
    jne .vc_bad

    movzx eax, byte [rdi + ubxp_frame_header_t.version]
    test eax, eax
    jz .vc_bad                      ; Version 0 was never issued
    cmp eax, UBXP_VERSION
    ja .vc_bad                      ; Newer than we know how to skip

    xor eax, eax                    ; UBXP_OK
    ret

.vc_bad:
    mov rax, UBXP_ERR_PROTO
    ret

%endif ; GUARD_STORAGE_UBXP_SCHEMA_EVOLUTION_ASM
