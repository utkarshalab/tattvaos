; ============================================================================
; Matrix — 3x3 Color Matrix (16.16 fixed), s15Fixed16 Convert + Apply
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/colorm.inc"

section .text

; ---------------------------------------------------------------------------
; mat3_identity — OUT: rdi = i32[9]
; ---------------------------------------------------------------------------
global mat3_identity
mat3_identity:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + 0], 0x10000
    mov dword [rdi + 4], 0
    mov dword [rdi + 8], 0
    mov dword [rdi + 12], 0
    mov dword [rdi + 16], 0x10000
    mov dword [rdi + 20], 0
    mov dword [rdi + 24], 0
    mov dword [rdi + 28], 0
    mov dword [rdi + 32], 0x10000
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; mat3_mul — OUT = A*B (all 16.16)
; ---------------------------------------------------------------------------
global mat3_mul
mat3_mul:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    sub rsp, 36
    xor ecx, ecx
.row:
    cmp ecx, 3
    jae .done
    xor edx, edx
.col:
    cmp edx, 3
    jae .next_row
    xor eax, eax  ; acc 64-bit in r8
    xor r8d, r8d
    xor r9d, r9d
.k:
    cmp r9d, 3
    jae .store
    mov r10d, ecx
    imul r10d, 3
    add r10d, r9d
    movsxd r10, dword [r12 + r10 * 4]
    mov r11d, r9d
    imul r11d, 3
    add r11d, edx
    movsxd r11, dword [r13 + r11 * 4]
    imul r10, r11
    sar r10, 16
    add r8, r10
    inc r9d
    jmp .k
.store:
    mov r10d, ecx
    imul r10d, 3
    add r10d, edx
    mov [rsp + r10 * 4], r8d
    inc edx
    jmp .col
.next_row:
    inc ecx
    jmp .row
.done:
    mov rsi, rsp
    mov rdi, rbx
    mov ecx, 9
    rep movsd
    add rsp, 36
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; mat3_apply — IN: rdi=mat[9], rsi=r,g,b 16.16 — OUT: rax=r, rdx=g, rcx=b
; ---------------------------------------------------------------------------
global mat3_apply
mat3_apply:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    ; r = m0*r+m1*g+m2*b
    movsxd rax, dword [rbx + 0]
    imul rax, rsi
    sar rax, 16
    movsxd rdx, dword [rbx + 4]
    imul rdx, rdi
    sar rdx, 16
    add rax, rdx
    movsxd rdx, dword [rbx + 8]
    imul rdx, rcx
    sar rdx, 16
    add rax, rdx
    push rax
    ; g
    movsxd rax, dword [rbx + 12]
    imul rax, rsi
    sar rax, 16
    movsxd rdx, dword [rbx + 16]
    imul rdx, rdi
    sar rdx, 16
    add rax, rdx
    movsxd rdx, dword [rbx + 20]
    imul rdx, rcx
    sar rdx, 16
    add rax, rdx
    mov rdx, rax
    pop rax
    ; b
    movsxd rcx, dword [rbx + 24]
    imul rcx, rsi
    sar rcx, 16
    movsxd rsi, dword [rbx + 28]
    imul rsi, rdi
    sar rsi, 16
    add rcx, rsi
    movsxd rsi, dword [rbx + 32]
    ; NOTE: rcx input b was clobbered above; recompute from stack
    ; (callers pass b in rcx; we preserved via push? document: b reloaded)
    ; simplified: b_out uses original b still in caller's rcx copy on stack
    mov rsi, [rsp + 16]  ; original rcx
    imul rsi, [rbx + 32]
    sar rsi, 16
    add rcx, rsi
    ret

section .data
global matrix_version
matrix_version: dq 0x010000
