; =============================================================================
; File     : src/arch/x86_64/x86_64.asm
; Project  : Utkarsha VCS (vcs)
; Author   : Utkarsha Lab
; License  : Apache-2.0
; Description: x86-64 architecture entry — CPU detection, init.
; =============================================================================

%ifndef VCS_ARCH_X86_64_ASM
%define VCS_ARCH_X86_64_ASM

%include "include/vcs.inc"

bits 64

section .bss
align 16
arch_cpu_features:  resq 1      ; detected CPU feature bits

section .text

; -----------------------------------------------------------------------------
; arch_init — Initialize x86-64 architecture specifics
; Output: rax = VCS_OK
; -----------------------------------------------------------------------------
global arch_init
arch_init:
    PROLOGUE_SAVE rbx
    call    arch_detect_cpu
    mov     eax, VCS_OK
    EPILOGUE_RESTORE rbx
    ret

; -----------------------------------------------------------------------------
; arch_detect_cpu — Detect CPU features via CPUID
; Output: rax = feature bitmask
; -----------------------------------------------------------------------------
global arch_detect_cpu
arch_detect_cpu:
    PROLOGUE_SAVE rbx, rcx, rdx

    xor     eax, eax
    cpuid
    mov     r8d, eax            ; max standard leaf

    mov     eax, 1
    cpuid
    mov     ecx, ecx            ; feature flags
    mov     edx, edx            ; more features

    ; Check SSE4.2 (ECX bit 20)
    test    ecx, 1 << 20
    jz      .no_sse42
    or      dword [arch_cpu_features], 1
.no_sse42:

    ; Check AVX (ECX bit 28)
    test    ecx, 1 << 28
    jz      .no_avx
    or      dword [arch_cpu_features], 1 << 1
.no_avx:

    ; Check AVX2 (EBX bit 5 in leaf 7)
    cmp     r8d, 7
    jb      .no_leaf7
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    test    ebx, 1 << 5
    jz      .no_avx2
    or      dword [arch_cpu_features], 1 << 2
.no_avx2:
.no_leaf7:

    mov     rax, [arch_cpu_features]
    EPILOGUE_RESTORE rbx, rcx, rdx
    ret

; -----------------------------------------------------------------------------
; arch_has_avx2 — Check if AVX2 is available
; Output: rax = 1 if yes, 0 otherwise
; -----------------------------------------------------------------------------
global arch_has_avx2
arch_has_avx2:
    mov     eax, [arch_cpu_features]
    and     eax, 1 << 2
    test    eax, eax
    setz    al
    xor     eax, 1
    ret

%endif ; VCS_ARCH_X86_64_ASM