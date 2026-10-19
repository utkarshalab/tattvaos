; ============================================================================
; TRC — Tone Response Curves (gamma / table / parametric / sRGB / linear)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/colorm.inc"
%include "inc/fixed.inc"

; struct offsets (hoisted above use)
%define Trc_SIZE    56

section .text

struc Trc
    .type:          resd 1
    .gamma:         resd 1  ; 16.16
    .table:         resq 1
    .table_count:   resd 1
    .param:         resq 4  ; up to 4 params 16.16
endstruc

; ---------------------------------------------------------------------------
; trc_init_gamma
; ---------------------------------------------------------------------------
global trc_init_gamma
trc_init_gamma:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Trc.type], TRC_TYPE_GAMMA
    mov [rdi + Trc.gamma], esi
    mov qword [rdi + Trc.table], 0
    mov dword [rdi + Trc.table_count], 0
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; trc_init_table
; ---------------------------------------------------------------------------
global trc_init_table
trc_init_table:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov dword [rdi + Trc.type], TRC_TYPE_TABLE
    mov [rdi + Trc.table], rsi
    mov [rdi + Trc.table_count], edx
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; trc_init_srgb
; ---------------------------------------------------------------------------
global trc_init_srgb
trc_init_srgb:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Trc.type], TRC_TYPE_SRGB
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; trc_init_linear
; ---------------------------------------------------------------------------
global trc_init_linear
trc_init_linear:
    PROLOGUE
    ASSERT_PTR rdi
    mov dword [rdi + Trc.type], TRC_TYPE_LINEAR
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; trc_apply
;   IN: rdi = Trc*, rsi = v 16.16 (0..1) — OUT: rax = out 16.16
; ---------------------------------------------------------------------------
global trc_apply
trc_apply:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    mov eax, [rbx + Trc.type]
    cmp eax, TRC_TYPE_LINEAR
    je .linear
    cmp eax, TRC_TYPE_SRGB
    je .srgb
    cmp eax, TRC_TYPE_GAMMA
    je .gamma
    cmp eax, TRC_TYPE_TABLE
    je .table
    ; parametric: fall back to gamma param0
    mov eax, [rbx + Trc.param]
    jmp .pow_gamma
.linear:
    mov rax, r12
    EPILOGUE_RESTORE rbx, r12
    ret
.srgb:
    ; reuse srgb encode path via LUT helper
    mov rdi, r12
    shr rdi, 4
    cmp rdi, 4095
    jbe .srgb_ok
    mov rdi, 4095
.srgb_ok:
    extern linear_to_srgb_lut
    movzx eax, word [linear_to_srgb_lut + rdi * 2]
    shl eax, 8  ; u16 -> 16.16 approx
    EPILOGUE_RESTORE rbx, r12
    ret
.gamma:
    mov eax, [rbx + Trc.gamma]
.pow_gamma:
    ; x^g via repeated sqrt/multiply chain (documented approx)
    mov rdi, r12
    ; Fast exact path for gamma 2.0.
    cmp eax, 0x20000
    jne .gen_pow
    mov rax, r12
    imul rax, r12
    shr rax, 16
    EPILOGUE_RESTORE rbx, r12
    ret
.gen_pow:
    mov rdi, r12
    mov esi, eax
    call fixed_pow
    EPILOGUE_RESTORE rbx, r12
    ret
.table:
    mov rax, [rbx + Trc.table]
    test rax, rax
    jz .linear
    mov ecx, [rbx + Trc.table_count]
    test ecx, ecx
    jz .linear
    ; index = v * (n-1)
    mov rdx, r12
    shr rdx, 16  ; 0..1 int part (0 normally)
    mov rax, r12
    shr rax, 16
    cmp rax, 1
    jae .table_top
    ; fractional index
    mov rax, r12
    imul rax, rcx
    shr rax, 16
    cmp rax, rcx
    jae .table_top
    mov rdx, [rbx + Trc.table]
    movzx eax, word [rdx + rax * 2]
    shl eax, 0  ; u16 entries assumed 0..65535 -> 16.16
    mov ecx, eax
    shl ecx, 0
    mov eax, ecx
    EPILOGUE_RESTORE rbx, r12
    ret
.table_top:
    mov rax, 0x10000
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global trc_version
trc_version: dq 0x010000
