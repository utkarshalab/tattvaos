; ============================================================================
; UTF-8 — Validation, Decoding, Encoding
; ============================================================================
; Strict UTF-8 (RFC 3629): no overlong forms, no surrogates (U+D800 ..
; U+DFFF), nothing above U+10FFFF, continuation bytes 10xxxxxx.
;
;   utf8_decode(buf, len, out*)   -> bytes of the first character (1 .. 4),
;                                    its code point in *out (u32); 0 when the
;                                    buffer is empty or does not start with a
;                                    valid character
;   utf8_validate(buf, len)       -> 0 valid, -EILSEQ
;   utf8_encode(cp, buf, size)    -> bytes written (1 .. 4), 0 when the code
;                                    point is not a scalar value or does not fit
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; utf8_decode — rdi = buffer, rsi = length, rdx = u32 *out -> rax
; ---------------------------------------------------------------------------
global utf8_decode
utf8_decode:
    test rsi, rsi
    jz .invalid
    movzx eax, byte [rdi]
    cmp eax, 0x80
    jb .one
    cmp eax, 0xC2                       ; 0x80 .. 0xC1: continuation or overlong
    jb .invalid
    cmp eax, 0xE0
    jb .two
    cmp eax, 0xF0
    jb .three
    cmp eax, 0xF5
    jb .four
.invalid:
    xor eax, eax
    ret
.one:
    mov [rdx], eax
    mov eax, 1
    ret
.two:
    cmp rsi, 2
    jb .invalid
    and eax, 0x1F
    movzx ecx, byte [rdi + 1]
    xor ecx, 0x80
    cmp ecx, 0x3F
    ja .invalid
    shl eax, 6
    or eax, ecx
    mov [rdx], eax
    mov eax, 2
    ret
.three:
    cmp rsi, 3
    jb .invalid
    and eax, 0x0F
    movzx ecx, byte [rdi + 1]
    xor ecx, 0x80
    cmp ecx, 0x3F
    ja .invalid
    shl eax, 6
    or eax, ecx
    movzx ecx, byte [rdi + 2]
    xor ecx, 0x80
    cmp ecx, 0x3F
    ja .invalid
    shl eax, 6
    or eax, ecx
    cmp eax, 0x800                      ; overlong
    jb .invalid
    mov ecx, eax
    sub ecx, 0xD800                     ; a surrogate
    cmp ecx, 0x7FF
    jbe .invalid
    mov [rdx], eax
    mov eax, 3
    ret
.four:
    cmp rsi, 4
    jb .invalid
    and eax, 0x07
    mov r8d, 1
.four_cont:
    movzx ecx, byte [rdi + r8]
    xor ecx, 0x80
    cmp ecx, 0x3F
    ja .invalid
    shl eax, 6
    or eax, ecx
    inc r8d
    cmp r8d, 4
    jb .four_cont
    cmp eax, 0x10000                    ; overlong
    jb .invalid
    cmp eax, 0x10FFFF
    ja .invalid
    mov [rdx], eax
    mov eax, 4
    ret

; ---------------------------------------------------------------------------
; utf8_validate — rdi = buffer, rsi = length -> rax = 0, -EILSEQ
; ---------------------------------------------------------------------------
global utf8_validate
utf8_validate:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
.loop:
    test r12, r12
    jz .valid
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rsp]
    call utf8_decode
    test rax, rax
    jz .bad
    add rbx, rax
    sub r12, rax
    jmp .loop
.valid:
    xor eax, eax
    jmp .out
.bad:
    mov rax, -(EILSEQ)
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; utf8_encode — rdi = code point, rsi = buffer, rdx = buffer size -> rax
; ---------------------------------------------------------------------------
global utf8_encode
utf8_encode:
    mov eax, edi
    cmp rdi, 0x80
    jb .one
    cmp rdi, 0x800
    jb .two
    mov ecx, edi
    sub ecx, 0xD800
    cmp ecx, 0x7FF
    jbe .none                           ; a surrogate is no scalar value
    cmp rdi, 0x10000
    jb .three
    cmp rdi, 0x110000
    jb .four
.none:
    xor eax, eax
    ret
.one:
    cmp rdx, 1
    jb .none
    mov [rsi], al
    mov eax, 1
    ret
.two:
    cmp rdx, 2
    jb .none
    shr eax, 6
    or eax, 0xC0
    mov [rsi], al
    mov eax, edi
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 1], al
    mov eax, 2
    ret
.three:
    cmp rdx, 3
    jb .none
    shr eax, 12
    or eax, 0xE0
    mov [rsi], al
    mov eax, edi
    shr eax, 6
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 1], al
    mov eax, edi
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 2], al
    mov eax, 3
    ret
.four:
    cmp rdx, 4
    jb .none
    shr eax, 18
    or eax, 0xF0
    mov [rsi], al
    mov eax, edi
    shr eax, 12
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 1], al
    mov eax, edi
    shr eax, 6
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 2], al
    mov eax, edi
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 3], al
    mov eax, 4
    ret

section .data
global utf8_version
utf8_version: dq 0x010100
