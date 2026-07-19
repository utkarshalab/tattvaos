; =============================================================================
; lib/cal/iso8601.asm
; ISO 8601 date and time formatting and parsing.
;
; Formats tm_t dates into standard "YYYY-MM-DDTHH:MM:SSZ" format strings,
; and parses compliant ISO 8601 strings back into tm_t structures.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_ISO8601_ASM
%define IO_CAL_ISO8601_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/cal/cal.inc"
%include "lib/io/error/codes.asm"

section .text

global cal_format_iso8601
global cal_parse_iso8601

; =============================================================================
; cal_format_iso8601 — Format tm_t structure into standard ISO 8601 string
; In : RDI = -> tm_t input structure
;      RSI = -> output character buffer (minimum 21 bytes)
; Out: RAX = length of formatted string (20), or negative error code
; =============================================================================
IO_FUNC cal_format_iso8601
    guard_null rdi
    guard_null rsi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     r12, rdi                ; r12 = -> tm_t
    mov     r13, rsi                ; r13 = -> output buffer

    ; Year (4 digits)
    mov     rax, [r12 + tm_t.year]
    mov     rdi, r13
    mov     rcx, 4
    call    .write_dec_padded
    add     r13, 4

    ; '-'
    mov     byte [r13], '-'
    inc     r13

    ; Month (2 digits)
    mov     rax, [r12 + tm_t.month]
    mov     rdi, r13
    mov     rcx, 2
    call    .write_dec_padded
    add     r13, 2

    ; '-'
    mov     byte [r13], '-'
    inc     r13

    ; Day (2 digits)
    mov     rax, [r12 + tm_t.day]
    mov     rdi, r13
    mov     rcx, 2
    call    .write_dec_padded
    add     r13, 2

    ; 'T'
    mov     byte [r13], 'T'
    inc     r13

    ; Hour (2 digits)
    mov     rax, [r12 + tm_t.hour]
    mov     rdi, r13
    mov     rcx, 2
    call    .write_dec_padded
    add     r13, 2

    ; ':'
    mov     byte [r13], ':'
    inc     r13

    ; Minute (2 digits)
    mov     rax, [r12 + tm_t.minute]
    mov     rdi, r13
    mov     rcx, 2
    call    .write_dec_padded
    add     r13, 2

    ; ':'
    mov     byte [r13], ':'
    inc     r13

    ; Second (2 digits)
    mov     rax, [r12 + tm_t.second]
    mov     rdi, r13
    mov     rcx, 2
    call    .write_dec_padded
    add     r13, 2

    ; 'Z'
    mov     byte [r13], 'Z'
    inc     r13

    ; Null terminator
    mov     byte [r13], 0

    mov     rax, 20                 ; Formatted length is always 20 bytes

    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; Helper: .write_dec_padded
; Inputs: RAX = Value to format
;         RCX = Width (2 or 4)
;         RDI = Destination buffer
; -----------------------------------------------------------------------------
.write_dec_padded:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; Align RDI to end of the digits group
    add     rdi, rcx                ; Point past the group
    dec     rdi                     ; Point to last digit slot

    mov     rbx, 10
.loop_digits:
    xor     rdx, rdx
    div     rbx                     ; RAX = value/10, RDX = remainder digit
    add     dl, '0'
    mov     [rdi], dl
    dec     rdi
    dec     rcx
    jnz     .loop_digits

    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC cal_format_iso8601

; =============================================================================
; cal_parse_iso8601 — Parse standard ISO 8601 string into tm_t structure
; In : RDI = -> input ISO 8601 format string (e.g. "2026-07-19T11:15:53Z")
;      RSI = -> tm_t output structure to populate
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; =============================================================================
IO_FUNC cal_parse_iso8601
    guard_null rdi
    guard_null rsi
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     r12, rdi                ; r12 = -> input string
    mov     r13, rsi                ; r13 = -> output tm_t

    ; 1. Verify basic separator placements
    cmp     byte [r12 + 4], '-'
    jne     .err_format
    cmp     byte [r12 + 7], '-'
    jne     .err_format
    cmp     byte [r12 + 10], 'T'
    je      .sep_t_ok
    cmp     byte [r12 + 10], ' '    ; Allow space separator as fallback
    jne     .err_format
.sep_t_ok:
    cmp     byte [r12 + 13], ':'
    jne     .err_format
    cmp     byte [r12 + 16], ':'
    jne     .err_format

    ; 2. Parse Year (offset 0, 4 digits)
    mov     rsi, r12
    mov     rcx, 4
    call    .parse_int_digits
    cmp     rax, 0
    jl      .done                   ; Forward format error code
    mov     [r13 + tm_t.year], rax

    ; 3. Parse Month (offset 5, 2 digits)
    lea     rsi, [r12 + 5]
    mov     rcx, 2
    call    .parse_int_digits
    cmp     rax, 0
    jl      .done
    cmp     rax, 1
    jb      .err_format
    cmp     rax, 12
    ja      .err_format
    mov     [r13 + tm_t.month], rax

    ; 4. Parse Day (offset 8, 2 digits)
    lea     rsi, [r12 + 8]
    mov     rcx, 2
    call    .parse_int_digits
    cmp     rax, 0
    jl      .done
    cmp     rax, 1
    jb      .err_format
    cmp     rax, 31
    ja      .err_format
    mov     [r13 + tm_t.day], rax

    ; 5. Parse Hour (offset 11, 2 digits)
    lea     rsi, [r12 + 11]
    mov     rcx, 2
    call    .parse_int_digits
    cmp     rax, 0
    jl      .done
    cmp     rax, 23
    ja      .err_format
    mov     [r13 + tm_t.hour], rax

    ; 6. Parse Minute (offset 14, 2 digits)
    lea     rsi, [r12 + 14]
    mov     rcx, 2
    call    .parse_int_digits
    cmp     rax, 0
    jl      .done
    cmp     rax, 59
    ja      .err_format
    mov     [r13 + tm_t.minute], rax

    ; 7. Parse Second (offset 17, 2 digits)
    lea     rsi, [r12 + 17]
    mov     rcx, 2
    call    .parse_int_digits
    cmp     rax, 0
    jl      .done
    cmp     rax, 59
    ja      .err_format
    mov     [r13 + tm_t.second], rax

    ; Clear nanoseconds
    mov     qword [r13 + tm_t.nanosecond], 0

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_format:
    mov     rax, IO_ERR_BADARG

.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; Helper: .parse_int_digits
; Inputs: RSI = -> digit characters block
;         RCX = Width (2 or 4)
; Outputs: RAX = Decoded value, or negative error code (IO_ERR_BADARG)
; -----------------------------------------------------------------------------
.parse_int_digits:
    push    rbx
    push    rcx
    push    rdx
    push    rsi

    xor     rax, rax                ; Accumulator
    mov     rbx, 10                 ; Base

.loop_parse:
    movzx   rdx, byte [rsi]
    cmp     dl, '0'
    jb      .err_parse
    cmp     dl, '9'
    ja      .err_parse
    sub     dl, '0'

    imul    rax, rbx                ; acc * 10
    add     rax, rdx                ; acc + digit
    
    inc     rsi
    dec     rcx
    jnz     .loop_parse
    jmp     .done_parse

.err_parse:
    mov     rax, IO_ERR_BADARG

.done_parse:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC cal_parse_iso8601

%endif ; IO_CAL_ISO8601_ASM
