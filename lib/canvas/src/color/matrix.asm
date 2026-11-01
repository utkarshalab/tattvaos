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
    leave
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
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; mat3_apply — IN: rdi=mat[9], rsi=r, rdx=g, rcx=b (16.16)
;              OUT: rax=r, rdx=g, rcx=b
; ---------------------------------------------------------------------------
global mat3_apply
mat3_apply:
    mov r8, rdx                         ; g
    mov r9, rcx                         ; b
%macro MAT3_ROW 2                       ; %1 = row's byte offset, %2 = the result
    movsxd %2, dword [rdi + %1]
    imul %2, rsi
    sar %2, 16
    movsxd r10, dword [rdi + %1 + 4]
    imul r10, r8
    sar r10, 16
    add %2, r10
    movsxd r10, dword [rdi + %1 + 8]
    imul r10, r9
    sar r10, 16
    add %2, r10
%endmacro
    MAT3_ROW 0, rax
    MAT3_ROW 12, rdx
    MAT3_ROW 24, rcx
    ret

section .data
global matrix_version
matrix_version: dq 0x010000
