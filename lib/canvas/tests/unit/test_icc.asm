; ============================================================================
; Unit Test — Colour (src/color/icc_parse.asm, matrix.asm, trc.asm)
; ============================================================================
; test_icc_suite -> eax = failed cases (each case returns 0 / 1).
; ICC: the signature at offset 36, short and unsigned data refused. Matrices
; (16.16): identity, a product, applying one to r, g, b. Curves: linear,
; gamma 2.0, a table.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern icc_probe
extern mat3_identity
extern mat3_mul
extern mat3_apply
extern trc_init_linear
extern trc_init_gamma
extern trc_init_table
extern trc_apply

%define ONE 0x10000

section .text

global test_icc_suite
global test_icc_main
test_icc_suite:
test_icc_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call %1
    add ebx, eax
%endmacro
    CASE tc_probe
    CASE tc_probe_reject
    CASE tm_identity
    CASE tm_mul
    CASE tm_apply
    CASE tt_linear
    CASE tt_gamma2
    CASE tt_table
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; a 132-byte header with a size and 'acsp' at offset 36
header:
    lea rdi, [rel icc]
    xor eax, eax
    mov ecx, 132
    rep stosb
    mov dword [rel icc], 0x84000000
    mov dword [rel icc + 36], 'acsp'
    ret

tc_probe:
    sub rsp, 8
    call header
    lea rdi, [rel icc]
    mov esi, 132
    call icc_probe
    cmp rax, 1
    jne .fail
    PASS

tc_probe_reject:
    sub rsp, 8
    call header
    lea rdi, [rel icc]
    mov esi, 131                        ; too short
    call icc_probe
    test rax, rax
    jnz .fail
    mov dword [rel icc + 36], 'xcsp'
    lea rdi, [rel icc]
    mov esi, 132
    call icc_probe
    test rax, rax
    jnz .fail
    call header
    mov dword [rel icc], 0              ; no size
    lea rdi, [rel icc]
    mov esi, 132
    call icc_probe
    test rax, rax
    jnz .fail
    PASS

tm_identity:
    sub rsp, 8
    lea rdi, [rel m_a]
    call mat3_identity
    lea rdi, [rel m_a]
    mov esi, ONE / 2
    mov edx, ONE / 4
    mov ecx, 3 * ONE
    call mat3_apply
    cmp rax, ONE / 2
    jne .fail
    cmp rdx, ONE / 4
    jne .fail
    cmp rcx, 3 * ONE
    jne .fail
    PASS

tm_mul:
    sub rsp, 8
    lea rdi, [rel m_c]
    lea rsi, [rel m_scale]
    lea rdx, [rel m_shear]
    call mat3_mul
    ; scale(2, 3, 4) * shear: rows of the shear scaled
    cmp dword [rel m_c + 0], 2 * ONE
    jne .fail
    cmp dword [rel m_c + 4], ONE
    jne .fail
    cmp dword [rel m_c + 16], 3 * ONE
    jne .fail
    cmp dword [rel m_c + 32], 4 * ONE
    jne .fail
    cmp dword [rel m_c + 12], 0
    jne .fail
    PASS

tm_apply:
    sub rsp, 8
    lea rdi, [rel m_rows]
    mov esi, ONE
    mov edx, 2 * ONE
    mov ecx, 3 * ONE
    call mat3_apply
    cmp rax, 14 * ONE                   ; 1 + 4 + 9
    jne .fail
    cmp rdx, 2 * ONE                    ; the middle row keeps g
    jne .fail
    cmp rcx, 6 * ONE                    ; 1 + 2 + 3
    jne .fail
    PASS

tt_linear:
    sub rsp, 8
    lea rdi, [rel trc]
    call trc_init_linear
    lea rdi, [rel trc]
    mov esi, 0x4000
    call trc_apply
    cmp rax, 0x4000
    jne .fail
    PASS

tt_gamma2:
    sub rsp, 8
    lea rdi, [rel trc]
    mov esi, 2 * ONE
    call trc_init_gamma
    lea rdi, [rel trc]
    mov esi, ONE / 2                    ; 0.5 ^ 2
    call trc_apply
    cmp rax, ONE / 4
    jne .fail
    PASS

tt_table:
    sub rsp, 8
    lea rdi, [rel trc]
    lea rsi, [rel curve]
    mov edx, 4
    call trc_init_table
    lea rdi, [rel trc]
    mov esi, ONE / 2                    ; index 2
    call trc_apply
    cmp rax, 3000
    jne .fail
    lea rdi, [rel trc]
    mov esi, ONE                        ; the top
    call trc_apply
    cmp rax, ONE
    jne .fail
    PASS

section .rodata
alignb 4
m_scale:    dd 2 * ONE, 0, 0,  0, 3 * ONE, 0,  0, 0, 4 * ONE
m_shear:    dd ONE, ONE / 2, 0,  0, ONE, 0,  0, 0, ONE
m_rows:     dd ONE, 2 * ONE, 3 * ONE,  0, ONE, 0,  ONE, ONE, ONE
curve:      dw 1000, 2000, 3000, 4000

section .bss
alignb 16
icc:    resb 132
m_a:    resd 9
m_c:    resd 9
trc:    resb 64
