; ============================================================================
; Fmt — Number and Text Formatting (printf-style for serial output)
; ============================================================================
; Each call writes its text at the buffer (no terminator) and returns how
; many bytes it wrote; the caller sizes the buffer (fmt_uint at most 64 +
; width bytes).
;
;   fmt_uint(buf, value, base, width, pad)  unsigned in base 2 .. 16 (0: 10),
;                                           upper-case digits, padded on the
;                                           left to width with pad (0: ' ')
;   fmt_int(buf, value, base, width, pad)   signed: a '-' then the magnitude
;   fmt_ptr(buf, value)                     16 hex digits, zero padded
;   fmt_str(buf, string)                    the string without its terminator
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern str_len

section .text

; ---------------------------------------------------------------------------
; fmt_uint — rdi = buffer, rsi = value, rdx = base, rcx = width, r8 = pad
;   -> rax = bytes written
; ---------------------------------------------------------------------------
global fmt_uint
fmt_uint:
    push rbx
    sub rsp, 64                         ; the digits, last first
    mov rax, rsi
    mov r9, rdx
    cmp r9, 2
    jb .base10
    cmp r9, 16
    jbe .based
.base10:
    mov r9d, 10
.based:
    test r8, r8
    jnz .padded
    mov r8d, ' '
.padded:
    lea r10, [rsp + 64]                 ; digits grow down from here
.digit:
    xor edx, edx
    div r9
    lea rbx, [rel fmt_digits]
    mov dl, [rbx + rdx]
    dec r10
    mov [r10], dl
    test rax, rax
    jnz .digit
    lea r11, [rsp + 64]
    sub r11, r10                        ; digit count
    xor eax, eax                        ; written
.pad:
    lea rdx, [rax + r11]
    cmp rdx, rcx
    jae .copy
    mov [rdi + rax], r8b
    inc rax
    jmp .pad
.copy:
    xor edx, edx
.copy_digit:
    cmp rdx, r11
    jae .done
    mov bl, [r10 + rdx]
    mov [rdi + rax], bl
    inc rax
    inc rdx
    jmp .copy_digit
.done:
    add rsp, 64
    pop rbx
    ret

; ---------------------------------------------------------------------------
; fmt_int — the same, the value signed -> rax = bytes written
; ---------------------------------------------------------------------------
global fmt_int
fmt_int:
    test rsi, rsi
    jns fmt_uint
    mov byte [rdi], '-'
    inc rdi
    neg rsi
    test rcx, rcx
    jz .width
    dec rcx                             ; the sign takes one of the width
.width:
    sub rsp, 8
    call fmt_uint
    add rsp, 8
    inc rax
    ret

; ---------------------------------------------------------------------------
; fmt_ptr — rdi = buffer, rsi = value -> rax = 16
; ---------------------------------------------------------------------------
global fmt_ptr
fmt_ptr:
    mov edx, 16
    mov ecx, 16
    mov r8d, '0'
    jmp fmt_uint

; ---------------------------------------------------------------------------
; fmt_str — rdi = buffer, rsi = string -> rax = its length
; ---------------------------------------------------------------------------
global fmt_str
fmt_str:
    push rdi
    push rsi
    sub rsp, 8
    mov rdi, rsi
    call str_len
    add rsp, 8
    pop rsi
    pop rdi
    mov rcx, rax
    rep movsb
    ret

section .rodata
fmt_digits: db "0123456789ABCDEF"

section .data
global fmt_version
fmt_version: dq 0x010100
