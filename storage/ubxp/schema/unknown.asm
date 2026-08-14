; =============================================================================
; Tattva OS — storage/ubxp/schema/unknown.asm
; =============================================================================
; UBXP Unknown-Field Retention & Verbatim Re-emission.
;
; Implements:
;   - Retention store binding (`ubxp_unknown_init`)
;   - Verbatim capture of an unrecognised field (`ubxp_unknown_capture`)
;   - Replay of retained bytes into an outgoing frame (`ubxp_unknown_replay`)
;
; Skipping an unknown field is enough to READ a newer frame. It is not enough
; to FORWARD one. A relay that decodes, skips what it does not understand, and
; re-encodes silently strips every field added after its schema was frozen —
; the sender believes the data was delivered and it was not.
;
; Retention closes that hole: the raw tag-and-value bytes are copied aside
; exactly as they arrived and appended on re-encode, so a field survives a hop
; through a process that has no idea what it means. This mirrors protobuf's
; unknown-field set, and matters most for urpc, where intermediaries are
; routinely older than the endpoints they carry traffic between.
;
; Retention is bounded by the caller's sink. On overflow the store latches
; `truncated` rather than failing the decode, so a relay degrades to the old
; lossy behaviour visibly instead of dropping the message outright.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/ubxp/ubxp.inc"

section .text

global ubxp_unknown_init
global ubxp_unknown_capture
global ubxp_unknown_replay
global ubxp_unknown_truncated

; -----------------------------------------------------------------------------
; ubxp_unknown_init
;
; Binds a retention store to a cursor over caller-owned scratch memory.
;
; Inputs:
;   RDI = Pointer to ubxp_unknown_t
;   RSI = Pointer to an initialised ubxp_cursor_t used as the sink
;
; Returns:
;   RAX = UBXP_OK
; -----------------------------------------------------------------------------
align 32
ubxp_unknown_init:
    mov [rdi + ubxp_unknown_t.sink], rsi
    mov dword [rdi + ubxp_unknown_t.count], 0
    mov dword [rdi + ubxp_unknown_t.truncated], 0
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ubxp_unknown_capture
;
; Consumes one whole field — tag and value — from the source cursor and copies
; its raw bytes into the store. The bytes are never reinterpreted, so a field
; whose wire type this build cannot parse still round-trips intact.
;
; Inputs:
;   RDI = Pointer to the source ubxp_cursor_t
;   RSI = Pointer to ubxp_unknown_t
;
; Returns:
;   RAX = Bytes retained, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_unknown_capture:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32                     ; [rsp] field number, [rsp+16] wire type

    mov rbx, rdi                    ; Source cursor
    mov r12, rsi                    ; Store

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .uc_sticky

    mov r13, [rbx + ubxp_cursor_t.pos]          ; Field start offset

    ; Walk the field so the cursor lands exactly past its end.
    mov rdi, rbx
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call ubxp_read_tag
    test rax, rax
    js .uc_return

    mov rdi, rbx
    mov esi, dword [rsp + 16]
    call ubxp_skip_value
    test rax, rax
    js .uc_return

    mov r14, [rbx + ubxp_cursor_t.pos]
    sub r14, r13                    ; R14 = whole field width

    ; Copy verbatim into the sink, if it fits.
    mov r15, [r12 + ubxp_unknown_t.sink]

    mov rdi, r15
    call ubxp_cursor_remaining
    cmp rax, r14
    jb .uc_truncated

    mov rcx, [r15 + ubxp_cursor_t.base]
    add rcx, [r15 + ubxp_cursor_t.pos]

    mov rdi, rcx                    ; Destination
    mov rsi, [rbx + ubxp_cursor_t.base]
    add rsi, r13                    ; Source: the field's first byte
    mov rcx, r14
    rep movsb

    add [r15 + ubxp_cursor_t.pos], r14
    inc dword [r12 + ubxp_unknown_t.count]

    mov rax, r14
    jmp .uc_return

.uc_truncated:
    ; Sink full: record the loss but let the decode continue.
    mov dword [r12 + ubxp_unknown_t.truncated], 1
    xor eax, eax
    jmp .uc_return

.uc_sticky:
    movsxd rax, eax

.uc_return:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_unknown_replay
;
; Appends every retained byte to an outgoing frame. Call this last, after the
; fields this build does understand, so retained fields land at the end.
;
; Inputs:
;   RDI = Pointer to the destination ubxp_cursor_t
;   RSI = Pointer to ubxp_unknown_t
;
; Returns:
;   RAX = Bytes replayed, or a negative error
; -----------------------------------------------------------------------------
align 32
ubxp_unknown_replay:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Destination
    mov r12, rsi                    ; Store

    mov eax, dword [rbx + ubxp_cursor_t.error]
    test eax, eax
    jnz .ur_sticky

    mov r13, [r12 + ubxp_unknown_t.sink]
    mov r14, [r13 + ubxp_cursor_t.pos]          ; Retained byte count
    test r14, r14
    jz .ur_empty

    mov rdi, rbx
    call ubxp_cursor_remaining
    cmp rax, r14
    jb .ur_nospc

    mov rcx, [rbx + ubxp_cursor_t.base]
    add rcx, [rbx + ubxp_cursor_t.pos]

    mov rdi, rcx
    mov rsi, [r13 + ubxp_cursor_t.base]
    mov rcx, r14
    rep movsb

    add [rbx + ubxp_cursor_t.pos], r14

.ur_empty:
    mov rax, r14
    jmp .ur_return

.ur_nospc:
    mov dword [rbx + ubxp_cursor_t.error], UBXP_ERR_NOSPC
    mov rax, UBXP_ERR_NOSPC
    jmp .ur_return

.ur_sticky:
    movsxd rax, eax

.ur_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubxp_unknown_truncated
;
; Reports whether retention overflowed. A relay that cares about lossless
; forwarding should treat a non-zero result as a reason to refuse rather than
; forward a silently shortened message.
;
; Inputs:
;   RDI = Pointer to ubxp_unknown_t
;
; Returns:
;   RAX = Non-zero when at least one field could not be retained
; -----------------------------------------------------------------------------
align 32
ubxp_unknown_truncated:
    mov eax, dword [rdi + ubxp_unknown_t.truncated]
    ret
