; ============================================================================
; Fmt — Number and Text Formatting (printf-style for serial output)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"

section .text

; ---------------------------------------------------------------------------
; fmt_uint
;   Format unsigned integer to buffer
;   IN:  rdi = buffer, rsi = value, rdx = base (10/16), rcx = width, r8 = pad_char
;   OUT: rax = chars written
; ---------------------------------------------------------------------------
global fmt_uint
fmt_uint:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    test r13, r13
    jnz .ok
    mov r13, 10
.ok:
    test r14, r14
    jnz .has_width
    mov r14, 0
.has_width:
    test r8, r8
    jnz .has_pad
    mov r8, ' '
.has_pad:

    ; Convert to string (reverse)
    sub rsp, 32
    mov rdi, rsp
    add rdi, 31
    mov byte [rdi], 0
    dec rdi

    test r12, r12
    jnz .loop
    mov byte [rdi], '0'
    dec rdi
    jmp .done

.loop:
    mov rax, r12
    xor rdx, rdx
    div r13
    mov r12, rax
    cmp rdx, 10
    jl .digit
    add rdx, 'A' - 10
    jmp .store
.digit:
    add rdx, '0'
.store:
    mov [rdi], dl
    dec rdi
    test r12, r12
    jnz .loop

.done:
    inc rdi
    ; Pad if needed
    mov rax, rsp
    add rax, 32
    sub rax, rdi
    cmp rax, r14
    jge .copy
    mov rcx, r14
    sub rcx, rax
    push rdi
    push rbx
    mov rdi, rbx
    mov rsi, r8
    rep stosb
    pop rbx
    pop rdi
.copy:
    mov rcx, rax
    rep movsb
    add rsp, 32
    mov rax, rcx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; fmt_int
;   Format signed integer
; ---------------------------------------------------------------------------
global fmt_int
fmt_int:
    PROLOGUE_SAVE rbx
    mov rbx, rsi
    test rbx, rbx
    jns .positive
    neg rbx
    push rdi
    mov rdi, rdi
    mov al, '-'
    stosb
    pop rdi
    mov rsi, rbx
    call fmt_uint
    inc rax
    ret
.positive:
    mov rsi, rbx
    call fmt_uint
    ret

; ---------------------------------------------------------------------------
; fmt_ptr
;   Format pointer as hex
; ---------------------------------------------------------------------------
global fmt_ptr
fmt_ptr:
    PROLOGUE
    mov rdx, 16
    mov rcx, 16
    mov r8, '0'
    call fmt_uint
    ret

; ---------------------------------------------------------------------------
; fmt_str
;   Copy string to buffer
; ---------------------------------------------------------------------------
global fmt_str
fmt_str:
    PROLOGUE_SAVE rbx, rcx
    mov rbx, rdi
    mov rcx, rsi
    ASSERT_PTR rbx
    ASSERT_PTR rcx
    call str_len
    mov rcx, rax
    rep movsb
    mov rax, rcx
    EPILOGUE_RESTORE rbx, rcx
    ret

section .data

global fmt_version
fmt_version: dq 0x010000