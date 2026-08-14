%ifndef GUARD_STORAGE_UBXP_SCHEMA_DESCRIPTOR_ASM
%define GUARD_STORAGE_UBXP_SCHEMA_DESCRIPTOR_ASM
; =============================================================================
; Tattva OS — storage/ubxp/schema/descriptor.asm
; =============================================================================
; UBXP Schema Descriptors — Reflection, Validation & Presence Tracking.
;
; Implements:
;   - Field lookup by number (`ubxp_desc_find`)
;   - Generic descriptor-driven frame walk (`ubxp_desc_validate`)
;   - Required-field presence enforcement (`ubxp_desc_check_required`)
;   - Enum domain checking (`ubxp_enum_valid`)
;
; protobuf gets its type safety from generated accessors: `protoc` turns a
; .proto file into code that knows every field's number and wire type. There is
; no code generator here, so that knowledge lives in static descriptor tables
; instead. A table is data, not code, which costs an indirection per field but
; buys something codegen does not: a frame can be validated, walked and dumped
; by a build that has never seen the schema it was written against.
;
; Presence tracking uses a 64-bit mask, so required-field enforcement covers
; field numbers 1..64. Higher numbers still encode and decode normally; they
; are simply not tracked for presence, which is why required fields should be
; assigned low numbers.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_desc_find
global ubxp_desc_validate
global ubxp_desc_check_required
global ubxp_enum_valid

; -----------------------------------------------------------------------------
; ubxp_desc_find
;
; Linear scan for a field number. Descriptor tables are small and cache-warm,
; so a scan beats a hash for realistic field counts.
;
; Inputs:
;   RDI = Pointer to ubxp_msg_desc_t
;   RSI = Field number
;
; Returns:
;   RAX = Pointer to the matching ubxp_field_desc_t, or 0 when absent
; -----------------------------------------------------------------------------
align 32
ubxp_desc_find:
    push rbx

    mov rbx, [rdi + ubxp_msg_desc_t.fields]
    mov ecx, dword [rdi + ubxp_msg_desc_t.field_count]
    test ecx, ecx
    jz .df_missing

.df_loop:
    cmp dword [rbx + ubxp_field_desc_t.number], esi
    je .df_found

    add rbx, ubxp_field_desc_t_size
    dec ecx
    jnz .df_loop

.df_missing:
    xor eax, eax
    pop rbx
    ret

.df_found:
    mov rax, rbx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_desc_validate
;
; Walks a frame body against a descriptor table. Every field is checked for a
; wire type matching its declaration; recognised fields are skipped over and
; recorded as present, unrecognised ones are retained when a store is supplied
; and skipped when it is not.
;
; A wire-type mismatch on a KNOWN field is a hard error: it means the writer
; and reader disagree about a field number they both claim to understand,
; which is the one schema-evolution rule that must never be broken.
;
; Inputs:
;   RDI = Pointer to ubxp_cursor_t positioned at the body
;   RSI = Pointer to ubxp_msg_desc_t
;   RDX = Pointer to ubxp_unknown_t, or 0 to discard unknown fields
;
; Returns:
;   RAX = Presence bitmask for field numbers 1..64, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_desc_validate:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48                 ; [rsp] field number, [rsp+16] wire type

    mov rbx, rdi                ; Cursor
    mov r12, rsi                ; Descriptor
    mov r13, rdx                ; Unknown store or 0
    xor r14, r14                ; Presence mask

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .dv_sticky

.dv_loop:
    ; Stop cleanly at the end of the body.
    mov rdi, rbx
    call ubxp_cursor_remaining
    test rax, rax
    jz .dv_done

    mov r15, [rbx + ubxp_cursor_t.pos]      ; Rewind point

    mov rdi, rbx
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call ubxp_read_tag
    test rax, rax
    js .dv_return

    mov rdi, r12
    mov rsi, [rsp]
    call ubxp_desc_find
    test rax, rax
    jz .dv_unknown

    ; Known field: the declared wire type must match what arrived.
    movzx ecx, byte [rax + ubxp_field_desc_t.wire]
    cmp ecx, dword [rsp + 16]
    jne .dv_proto

    ; Record presence for low-numbered fields.
    mov rcx, [rsp]
    test rcx, rcx
    jz .dv_skip_value
    cmp rcx, 64
    ja .dv_skip_value
    dec rcx
    mov rdx, 1
    shl rdx, cl
    or r14, rdx

.dv_skip_value:
    mov rdi, rbx
    mov esi, dword [rsp + 16]
    call ubxp_skip_value
    test rax, rax
    js .dv_return
    jmp .dv_loop

.dv_unknown:
    test r13, r13
    jz .dv_discard

    ; Rewind so the field is retained whole, tag included.
    mov [rbx + ubxp_cursor_t.pos], r15
    mov rdi, rbx
    mov rsi, r13
    call ubxp_unknown_capture
    test rax, rax
    js .dv_return
    jmp .dv_loop

.dv_discard:
    mov rdi, rbx
    mov esi, dword [rsp + 16]
    call ubxp_skip_value
    test rax, rax
    js .dv_return
    jmp .dv_loop

.dv_done:
    mov rax, r14
    jmp .dv_return

.dv_proto:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_PROTO
    mov rax, UBXP_ERR_PROTO
    jmp .dv_return

.dv_sticky:
    movsxd rax, eax

.dv_return:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_desc_check_required
;
; Confirms every UBXP_FIELD_REQUIRED field numbered 1..64 was present.
;
; Inputs:
;   RDI = Pointer to ubxp_msg_desc_t
;   RSI = Presence mask from ubxp_desc_validate
;
; Returns:
;   RAX = UBXP_OK, or the field number of the first missing requirement
;         returned negated so the caller can tell it apart from success
; -----------------------------------------------------------------------------
align 32
ubxp_desc_check_required:
    push rbx
    push r12

    mov rbx, [rdi + ubxp_msg_desc_t.fields]
    mov r12d, dword [rdi + ubxp_msg_desc_t.field_count]
    test r12d, r12d
    jz .cr_ok

.cr_loop:
    test byte [rbx + ubxp_field_desc_t.flags], UBXP_FIELD_REQUIRED
    jz .cr_next

    mov ecx, dword [rbx + ubxp_field_desc_t.number]
    test ecx, ecx
    jz .cr_next
    cmp ecx, 64
    ja .cr_next                     ; Beyond mask range: not tracked

    dec ecx
    mov rax, 1
    shl rax, cl
    test rsi, rax
    jnz .cr_next

    ; Missing: report which one, negated.
    mov eax, dword [rbx + ubxp_field_desc_t.number]
    neg rax
    pop r12
    pop rbx
    ret

.cr_next:
    add rbx, ubxp_field_desc_t_size
    dec r12d
    jnz .cr_loop

.cr_ok:
    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_enum_valid
;
; Checks a decoded value against an enum's permitted set.
;
; An unrecognised enum value is NOT automatically an error: a newer writer may
; have added a member. Callers decide whether to reject or fold it into a
; default, so this only reports membership.
;
; Inputs:
;   RDI = Pointer to ubxp_enum_desc_t
;   RSI = Candidate value
;
; Returns:
;   RAX = 1 when the value is a declared member, 0 otherwise
; -----------------------------------------------------------------------------
align 32
ubxp_enum_valid:
    push rbx

    mov rbx, [rdi + ubxp_enum_desc_t.values]
    mov ecx, dword [rdi + ubxp_enum_desc_t.value_count]
    test ecx, ecx
    jz .ev_no

.ev_loop:
    cmp [rbx], rsi
    je .ev_yes
    add rbx, 8
    dec ecx
    jnz .ev_loop

.ev_no:
    xor eax, eax
    pop rbx
    ret

.ev_yes:
    mov rax, 1
    pop rbx
    ret

%endif ; GUARD_STORAGE_UBXP_SCHEMA_DESCRIPTOR_ASM
