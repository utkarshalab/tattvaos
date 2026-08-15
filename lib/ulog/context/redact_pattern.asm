; =============================================================================
; Tattva OS — lib/ulog/context/redact_pattern.asm
; =============================================================================
; Defense in depth for redact_registry.asm: a value that leaks into a field
; without its key ever being explicitly registered as sensitive. Heuristic,
; not proof — long runs of hex or base64-alphabet characters are what key
; material and bearer tokens look like, so treat them as guilty until a
; caller says otherwise (git-secrets / truffleHog take the same approach
; before reaching for real entropy analysis).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONTEXT_REDACT_PATTERN_ASM
%define LIB_ULOG_CONTEXT_REDACT_PATTERN_ASM

[BITS 64]

%define REDACT_PATTERN_MIN_LEN  20

section .text

; -----------------------------------------------------------------------------
; redact_pattern_looks_sensitive — Input: RDI = buffer, RSI = length
; Output: RAX = 1 if it looks like key material / a token, else 0
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global redact_pattern_looks_sensitive
redact_pattern_looks_sensitive:
    cmp rsi, REDACT_PATTERN_MIN_LEN
    jl .not_sensitive

    push rbx
    push rdi
    push rsi

    xor rbx, rbx                     ; RBX = index

.scan_hex:
    cmp rbx, rsi
    jae .is_hex
    movzx eax, byte [rdi + rbx]
    call .is_hex_digit
    test eax, eax
    jz .try_base64
    inc rbx
    jmp .scan_hex

.is_hex:
    mov rax, 1
    jmp .done

.try_base64:
    xor rbx, rbx
.scan_b64:
    cmp rbx, rsi
    jae .is_b64
    movzx eax, byte [rdi + rbx]
    call .is_base64_char
    test eax, eax
    jz .not_matched
    inc rbx
    jmp .scan_b64

.is_b64:
    mov rax, 1
    jmp .done

.not_matched:
    xor rax, rax

.done:
    pop rsi
    pop rdi
    pop rbx
    ret

.not_sensitive:
    xor rax, rax
    ret

; ---- .is_hex_digit: AL = char -> EAX = 1/0, clobbers nothing else ----------
.is_hex_digit:
    cmp al, '0'
    jl .hex_no
    cmp al, '9'
    jle .hex_yes
    cmp al, 'a'
    jl .hex_no
    cmp al, 'f'
    jle .hex_yes
    cmp al, 'A'
    jl .hex_no
    cmp al, 'F'
    jle .hex_yes
.hex_no:
    xor eax, eax
    ret
.hex_yes:
    mov eax, 1
    ret

; ---- .is_base64_char: AL = char -> EAX = 1/0 -------------------------------
.is_base64_char:
    cmp al, 'A'
    jl .b64_check_lower
    cmp al, 'Z'
    jle .b64_yes
.b64_check_lower:
    cmp al, 'a'
    jl .b64_check_digit
    cmp al, 'z'
    jle .b64_yes
.b64_check_digit:
    cmp al, '0'
    jl .b64_check_sym
    cmp al, '9'
    jle .b64_yes
.b64_check_sym:
    cmp al, '+'
    je .b64_yes
    cmp al, '/'
    je .b64_yes
    cmp al, '='
    je .b64_yes
    xor eax, eax
    ret
.b64_yes:
    mov eax, 1
    ret

%endif ; LIB_ULOG_CONTEXT_REDACT_PATTERN_ASM
