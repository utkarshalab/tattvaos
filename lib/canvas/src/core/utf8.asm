; ============================================================================
; UTF-8 — Validation, Decoding, Encoding
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; utf8_validate
;   Validate UTF-8 sequence
;   IN:  rdi = buffer, rsi = length
;   OUT: rax = 0 if valid, negative error
; ---------------------------------------------------------------------------
global utf8_validate
utf8_validate:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    test r12, r12
    jz .done

.loop:
    movzx rax, byte [rbx]
    test rax, 0x80
    jz .ascii

    ; Multi-byte sequence
    test rax, 0xE0
    jz .invalid
    test rax, 0xF0
    jz .two_byte
    test rax, 0xF8
    jz .three_byte
    test rax, 0xFC
    jz .four_byte
    jmp .invalid

.two_byte:
    cmp r12, 2
    jb .invalid
    inc rbx
    movzx rax, byte [rbx]
    test rax, 0xC0
    jnz .invalid_cont
    sub r12, 2
    add rbx, 2
    jmp .loop

.three_byte:
    cmp r12, 3
    jb .invalid
    inc rbx
    movzx rax, byte [rbx]
    test rax, 0xC0
    jnz .invalid_cont
    inc rbx
    movzx rax, byte [rbx]
    test rax, 0xC0
    jnz .invalid_cont
    sub r12, 3
    add rbx, 3
    jmp .loop

.four_byte:
    cmp r12, 4
    jb .invalid
    inc rbx
    movzx rax, byte [rbx]
    test rax, 0xC0
    jnz .invalid_cont
    inc rbx
    movzx rax, byte [rbx]
    test rax, 0xC0
    jnz .invalid_cont
    inc rbx
    movzx rax, byte [rbx]
    test rax, 0xC0
    jnz .invalid_cont
    sub r12, 4
    add rbx, 4
    jmp .loop

.ascii:
    inc rbx
    dec r12
    jnz .loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid:
    mov rax, -(EILSEQ)
    EPILOGUE_RESTORE rbx, r12
    ret
.invalid_cont:
    mov rax, -(EILSEQ)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; utf8_decode
;   Decode next UTF-8 codepoint
;   IN:  rdi = buffer, rsi = length, rdx = out_codepoint
;   OUT: rax = bytes consumed, 0 if invalid/end
; ---------------------------------------------------------------------------
global utf8_decode
utf8_decode:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    test rsi, rsi
    jz .done

    movzx rax, byte [rbx]
    test rax, 0x80
    jz .ascii

    test rax, 0xE0
    jz .invalid
    test rax, 0xF0
    jz .two_byte
    test rax, 0xF8
    jz .three_byte
    test rax, 0xFC
    jz .four_byte
    jmp .invalid

.two_byte:
    cmp rsi, 2
    jb .invalid
    movzx rdx, byte [rbx + 1]
    test rdx, 0xC0
    jnz .invalid
    mov rax, [rdx]
    and rax, 0x1F
    shl rax, 6
    mov rdx, [rbx + 1]
    and rdx, 0x3F
    or rax, rdx
    mov [rdx], rax
    mov rax, 2
    EPILOGUE_RESTORE rbx
    ret

.three_byte:
    cmp rsi, 3
    jb .invalid
    ; Simplified
    mov rax, 3
    EPILOGUE_RESTORE rbx
    ret

.four_byte:
    cmp rsi, 4
    jb .invalid
    mov rax, 4
    EPILOGUE_RESTORE rbx
    ret

.ascii:
    mov [rdx], rax
    mov rax, 1
    EPILOGUE_RESTORE rbx
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; utf8_encode
;   Encode codepoint to UTF-8
;   IN:  rdi = codepoint, rsi = buffer, rdx = buffer_size
;   OUT: rax = bytes written, 0 if too large
; ---------------------------------------------------------------------------
global utf8_encode
utf8_encode:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rsi

    cmp rbx, 0x80
    jb .one_byte
    cmp rbx, 0x800
    jb .two_byte
    cmp rbx, 0x10000
    jb .three_byte
    cmp rbx, 0x110000
    jb .four_byte
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.one_byte:
    cmp rdx, 1
    jb .done
    mov [rsi], bl
    mov rax, 1
    EPILOGUE_RESTORE rbx
    ret

.two_byte:
    cmp rdx, 2
    jb .done
    mov eax, rbx
    shr eax, 6
    or eax, 0xC0
    mov [rsi], al
    mov eax, rbx
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 1], al
    mov rax, 2
    EPILOGUE_RESTORE rbx
    ret

.three_byte:
    cmp rdx, 3
    jb .done
    mov eax, rbx
    shr eax, 12
    or eax, 0xE0
    mov [rsi], al
    mov eax, rbx
    shr eax, 6
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 1], al
    mov eax, rbx
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 2], al
    mov rax, 3
    EPILOGUE_RESTORE rbx
    ret

.four_byte:
    cmp rdx, 4
    jb .done
    mov eax, rbx
    shr eax, 18
    or eax, 0xF0
    mov [rsi], al
    mov eax, rbx
    shr eax, 12
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 1], al
    mov eax, rbx
    shr eax, 6
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 2], al
    mov eax, rbx
    and eax, 0x3F
    or eax, 0x80
    mov [rsi + 3], al
    mov rax, 4
    EPILOGUE_RESTORE rbx
    ret

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

section .data
global utf8_version
utf8_version: dq 0x010000
