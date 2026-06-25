; =============================================================================
; str/parse/csv_line.asm
; Parse a single CSV line into an array of StrSlice fields.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; CSV parsing rules (RFC 4180):
;
;   - Fields separated by delimiter (default: ',')
;   - Fields may be quoted with double quotes
;   - Quoted fields may contain delimiter, newlines, double quotes
;   - Double quote inside quoted field escaped as ""
;   - Leading/trailing whitespace is part of the field
;   - Newline terminates the record
;
; Two modes:
;   UNQUOTED: field is bytes between delimiters
;   QUOTED:   field starts with '"', ends with '"' + delimiter/newline
;
; This parser returns StrSlice fields pointing INTO the source buffer.
; For quoted fields, the returned slice INCLUDES the quotes.
; Use str_csv_unquote to strip quotes and unescape "" sequences.
;
; Functions:
;   str_csv_parse_line   — parse one line into StrSlice array
;   str_csv_field_count  — count fields without allocating slices
;   str_csv_unquote      — strip quotes and unescape a quoted field
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

section .text

; -----------------------------------------------------------------------------
; str_csv_parse_line
;
; Parse a CSV line into an array of StrSlice fields.
; Stops at newline (LF, CRLF) or end of input.
;
; Signature:
;   int64_t str_csv_parse_line(const StrSlice *src, uint8_t delimiter,
;                               StrSlice *fields, uint64_t fields_cap,
;                               uint64_t *out_count,
;                               uint64_t *out_consumed)
;
; Arguments:
;   RDI  — source StrSlice
;   SIL  — delimiter byte (usually ',')
;   RDX  — output StrSlice array
;   RCX  — array capacity (max fields)
;   R8   — pointer to uint64_t for field count
;   R9   — pointer to uint64_t for bytes consumed (may be null)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_BUF_TOO_SMALL  more fields than capacity
;   RAX  = STR_ERR_PARSE          malformed quoted field
; -----------------------------------------------------------------------------

STR_FUNC str_csv_parse_line

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]   ; src ptr
    mov     r12, [rdi + StrSlice.len]   ; src len
    movzx   r13d, sil                   ; delimiter
    mov     r14, rdx                    ; fields array
    mov     r15, rcx                    ; cap
    push    r8                          ; out_count
    push    r9                          ; out_consumed

    xor     r9, r9              ; field count
    xor     r10, r10            ; src index
    xor     r11, r11            ; field start

.csv_field_start:
    ; check for line end or end of input
    cmp     r10, r12
    jae     .csv_flush_field

    movzx   eax, byte [rbx + r10]

    cmp     al, 0x0A            ; LF
    je      .csv_line_end

    cmp     al, 0x0D            ; CR
    je      .csv_line_end

    ; check for quoted field
    cmp     al, '"'
    je      .csv_quoted_field

    ; unquoted field — scan to next delimiter or line end
    mov     r11, r10            ; field start

.csv_unquoted_scan:
    cmp     r10, r12
    jae     .csv_flush_field

    movzx   eax, byte [rbx + r10]

    cmp     al, r13b            ; delimiter
    je      .csv_emit_unquoted

    cmp     al, 0x0A
    je      .csv_flush_field

    cmp     al, 0x0D
    je      .csv_flush_field

    inc     r10
    jmp     .csv_unquoted_scan

.csv_emit_unquoted:
    ; emit field [r11, r10)
    cmp     r9, r15
    jae     .csv_too_many

    lea     rax, [rbx + r11]
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.ptr], rax
    mov     rax, r10
    sub     rax, r11
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9

    inc     r10                 ; skip delimiter
    mov     r11, r10
    jmp     .csv_field_start

.csv_quoted_field:
    ; quoted field starts with '"'
    mov     r11, r10            ; field start (includes opening quote)
    inc     r10                 ; skip opening quote

.csv_quoted_scan:
    cmp     r10, r12
    jae     .csv_quote_err      ; unterminated quote

    movzx   eax, byte [rbx + r10]

    cmp     al, '"'
    jne     .csv_quoted_next

    ; found quote — check for "" (escaped quote) or end of field
    inc     r10
    cmp     r10, r12
    jae     .csv_quoted_end     ; quote at end of input

    movzx   ecx, byte [rbx + r10]

    cmp     cl, '"'
    je      .csv_escaped_quote  ; "" → escaped quote, continue

    ; end of quoted field
    ; next char should be delimiter, newline, or end

.csv_quoted_end:
    ; emit field [r11, r10) including quotes
    cmp     r9, r15
    jae     .csv_too_many

    lea     rax, [rbx + r11]
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.ptr], rax
    mov     rax, r10
    sub     rax, r11
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9

    ; skip delimiter if present
    cmp     r10, r12
    jae     .csv_flush_done

    movzx   eax, byte [rbx + r10]
    cmp     al, r13b
    jne     .csv_field_start_after_quote

    inc     r10                 ; skip delimiter
    jmp     .csv_field_start

.csv_field_start_after_quote:
    jmp     .csv_field_start

.csv_escaped_quote:
    ; "" inside quoted field — skip both, continue
    inc     r10
    jmp     .csv_quoted_scan

.csv_quoted_next:
    inc     r10
    jmp     .csv_quoted_scan

.csv_flush_field:
    ; emit final field [r11, r10)
    cmp     r9, r15
    jae     .csv_too_many

    lea     rax, [rbx + r11]
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.ptr], rax
    mov     rax, r10
    sub     rax, r11
    mov     [r14 + r9 * STRSLICE_SIZE + StrSlice.len], rax
    inc     r9

.csv_flush_done:
.csv_line_end:
    ; skip CRLF
    cmp     r10, r12
    jae     .csv_write_counts

    movzx   eax, byte [rbx + r10]
    cmp     al, 0x0D
    jne     .csv_check_lf

    inc     r10
    cmp     r10, r12
    jae     .csv_write_counts

    movzx   eax, byte [rbx + r10]
    cmp     al, 0x0A
    jne     .csv_write_counts
    inc     r10
    jmp     .csv_write_counts

.csv_check_lf:
    cmp     al, 0x0A
    jne     .csv_write_counts
    inc     r10

.csv_write_counts:
    pop     rax                 ; out_consumed
    pop     rcx                 ; out_count

    mov     [rcx], r9

    test    rax, rax
    jz      .csv_ok
    mov     [rax], r10

.csv_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.csv_too_many:
    pop     rax
    pop     rcx
    mov     [rcx], r9           ; partial count
    test    rax, rax
    jz      .csv_too_many_ret
    mov     [rax], r10

.csv_too_many_ret:
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

.csv_quote_err:
    pop     rax
    pop     rcx
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

STR_ENDFUNC str_csv_parse_line

; -----------------------------------------------------------------------------
; str_csv_field_count
;
; Count fields in a CSV line without allocating StrSlices.
; Useful for pre-allocating the field array.
;
; Signature:
;   int64_t str_csv_field_count(const StrSlice *src, uint8_t delimiter,
;                                uint64_t *out_count)
;
; Arguments:
;   RDI  — source StrSlice
;   SIL  — delimiter
;   RDX  — out_count
; -----------------------------------------------------------------------------

STR_FUNC str_csv_field_count

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    movzx   r13d, sil
    ; rdx = out_count

    xor     r9, r9              ; count
    xor     r10, r10            ; index

    ; count = 1 if non-empty (first field), then +1 per delimiter
    test    r12, r12
    jz      .cfc_done

    inc     r9                  ; at least one field

.cfc_loop:
    cmp     r10, r12
    jae     .cfc_done

    movzx   eax, byte [rbx + r10]

    cmp     al, 0x0A
    je      .cfc_done
    cmp     al, 0x0D
    je      .cfc_done

    cmp     al, '"'
    je      .cfc_skip_quoted

    cmp     al, r13b
    jne     .cfc_next
    inc     r9                  ; delimiter found → new field
    jmp     .cfc_next

.cfc_skip_quoted:
    ; skip to closing quote
    inc     r10

.cfc_quoted_scan:
    cmp     r10, r12
    jae     .cfc_done

    movzx   eax, byte [rbx + r10]
    inc     r10

    cmp     al, '"'
    jne     .cfc_quoted_scan

    ; check for "" escape
    cmp     r10, r12
    jae     .cfc_done

    movzx   eax, byte [rbx + r10]
    cmp     al, '"'
    je      .cfc_quoted_cont
    jmp     .cfc_loop

.cfc_quoted_cont:
    inc     r10
    jmp     .cfc_quoted_scan

.cfc_next:
    inc     r10
    jmp     .cfc_loop

.cfc_done:
    mov     [rdx], r9

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_csv_field_count

; -----------------------------------------------------------------------------
; str_csv_unquote
;
; Given a quoted CSV field (including surrounding '"'), produce
; an unescaped version in a caller-supplied buffer.
; Handles "" → " unescaping.
;
; Signature:
;   int64_t str_csv_unquote(const StrSlice *field, uint8_t *dst,
;                            uint64_t dst_cap, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_csv_unquote

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rcx            ; out

    ; must start with '"'
    test    r12, r12
    jz      .uq_empty

    movzx   eax, byte [rbx]
    cmp     al, '"'
    jne     .uq_not_quoted

    ; skip opening quote
    xor     r9, r9              ; src index (start at 0, first char is '"')
    inc     r9
    xor     r10, r10            ; dst index

.uq_loop:
    cmp     r9, r12
    jae     .uq_done

    movzx   eax, byte [rbx + r9]
    inc     r9

    cmp     al, '"'
    jne     .uq_copy

    ; check for "" escape or end of field
    cmp     r9, r12
    jae     .uq_done            ; closing quote at end

    movzx   ecx, byte [rbx + r9]
    cmp     cl, '"'
    jne     .uq_done            ; closing quote (followed by non-quote)

    ; escaped quote: "" → write one '"'
    inc     r9                  ; skip second quote

.uq_copy:
    ; check capacity
    cmp     r10, rdx
    jae     .uq_too_small

    mov     [r13 + r10], al
    inc     r10
    jmp     .uq_loop

.uq_done:
    mov     [r14 + StrSlice.ptr], r13
    mov     [r14 + StrSlice.len], r10

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uq_not_quoted:
    ; field not quoted — just return it as-is
    mov     rax, [rdi + StrSlice.ptr]
    mov     [rcx + StrSlice.ptr], rax
    mov     rax, [rdi + StrSlice.len]
    mov     [rcx + StrSlice.len], rax

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uq_empty:
    mov     qword [rcx + StrSlice.ptr], 0
    mov     qword [rcx + StrSlice.len], 0

    pop_regs r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.uq_too_small:
    pop_regs r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_csv_unquote