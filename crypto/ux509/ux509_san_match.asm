; =============================================================================
; Tattva OS — crypto/ux509/ux509_san_match.asm
; =============================================================================
; RFC 6125 Wildcard Domain Matcher (*.tattva.os).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_match_san_domain — Match target domain against SAN certificate pattern
; Input:  RDI = Target domain ASCII string (e.g. "api.tattva.os")
;         RSI = SAN pattern string (e.g. "*.tattva.os")
; Output: RAX = 1 (Matched), 0 (Mismatch)
; -----------------------------------------------------------------------------
ux509_match_san_domain:
    push rbx
    push rdi
    push rsi

    ; Check if SAN pattern starts with wildcard "*."
    cmp byte [rsi], '*'
    jne .exact_match

    cmp byte [rsi + 1], '.'
    jne .exact_match

    ; Wildcard pattern: skip first label of target domain until first '.'
.find_dot:
    mov al, [rdi]
    test al, al
    jz .mismatch

    cmp al, '.'
    je .match_suffix
    inc rdi
    jmp .find_dot

.match_suffix:
    add rsi, 1                      ; Compare suffix ".tattva.os"
.char_loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .mismatch

    test al, al
    jz .matched

    inc rdi
    inc rsi
    jmp .char_loop

.exact_match:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .mismatch
    test al, al
    jz .matched
    inc rdi
    inc rsi
    jmp .exact_match

.matched:
    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

.mismatch:
    xor rax, rax
    pop rsi
    pop rdi
    pop rbx
    ret
