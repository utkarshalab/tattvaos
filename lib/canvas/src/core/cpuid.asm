; ============================================================================
; CPUID — CPU Feature Detection and SIMD Dispatch
; Detects SSE2, AVX2, AVX-512, FMA, etc.
; Patches blend_dispatch at startup
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; cpuid_init
;   Detect CPU features, patch dispatch functions
;   OUT: rax = feature bitmask
; ---------------------------------------------------------------------------
global cpuid_init
cpuid_init:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15

    ; Check CPUID supported
    pushfd
    pop rax
    mov rbx, rax
    xor rax, 0x200000
    push rax
    popfd
    pushfd
    pop rax
    xor rax, rbx
    push rbx
    popfd
    test rax, 0x200000
    jz .no_cpuid

    ; Get vendor string
    xor rax, rax
    cpuid
    mov [cpu_vendor], ebx
    mov [cpu_vendor + 4], edx
    mov [cpu_vendor + 8], ecx

    ; Get feature flags (eax=1)
    mov rax, 1
    cpuid
    mov [cpu_features_ecx], ecx
    mov [cpu_features_edx], edx

    ; Get extended features (eax=7)
    mov rax, 7
    xor rcx, rcx
    cpuid
    mov [cpu_features_ebx], ebx
    mov [cpu_features_ecx_ext], ecx

    ; Get extended function (eax=0x80000001)
    mov rax, 0x80000001
    cpuid
    mov [cpu_features_ext_ecx], ecx
    mov [cpu_features_ext_edx], edx

    ; Build feature bitmask
    xor rax, rax
    ; SSE2 (edx bit 26)
    test dword [cpu_features_edx], 1 << 26
    jz .no_sse2
    or rax, CPU_HAS_SSE2
.no_sse2:
    ; SSE3 (ecx bit 0)
    test dword [cpu_features_ecx], 1
    jz .no_sse3
    or rax, CPU_HAS_SSE3
.no_sse3:
    ; SSSE3 (ecx bit 9)
    test dword [cpu_features_ecx], 1 << 9
    jz .no_ssse3
    or rax, CPU_HAS_SSSE3
.no_ssse3:
    ; SSE4.1 (ecx bit 19)
    test dword [cpu_features_ecx], 1 << 19
    jz .no_sse41
    or rax, CPU_HAS_SSE4_1
.no_sse41:
    ; SSE4.2 (ecx bit 20)
    test dword [cpu_features_ecx], 1 << 20
    jz .no_sse42
    or rax, CPU_HAS_SSE4_2
.no_sse42:
    ; AVX (ecx bit 28) + OS support (ecx bit 27)
    test dword [cpu_features_ecx], (1 << 28) | (1 << 27)
    jnz .has_avx
    jmp .no_avx
.has_avx:
    or rax, CPU_HAS_AVX
    ; FMA (ecx bit 12)
    test dword [cpu_features_ecx], 1 << 12
    jz .no_fma
    or rax, CPU_HAS_FMA
.no_fma:
    ; AVX2 (ebx bit 5)
    test dword [cpu_features_ebx], 1 << 5
    jz .no_avx2
    or rax, CPU_HAS_AVX2
.no_avx2:
    ; AVX-512F (ebx bit 16)
    test dword [cpu_features_ebx], 1 << 16
    jz .no_avx512f
    or rax, CPU_HAS_AVX512F
    ; AVX-512BW (ebx bit 30)
    test dword [cpu_features_ebx], 1 << 30
    jz .no_avx512bw
    or rax, CPU_HAS_AVX512BW
.no_avx512bw:
    ; AVX-512VL (ebx bit 31)
    test dword [cpu_features_ebx], 1 << 31
    jz .no_avx512vl
    or rax, CPU_HAS_AVX512VL
.no_avx512vl:

.no_avx512f:
.no_avx2:
.no_fma:
.no_avx:
.no_sse42:
.no_sse41:
.no_ssse3:
.no_sse3:
    ; Patch dispatch functions
    mov rdi, rax
    call patch_dispatch

    mov rax, [cpu_feature_mask]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_cpuid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; patch_dispatch
;   Patch function pointers based on detected features
;   IN:  rdi = feature mask
; ---------------------------------------------------------------------------
patch_dispatch:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov [cpu_feature_mask], rbx

    ; Patch blend_dispatch
    test rbx, CPU_HAS_AVX512F + CPU_HAS_AVX512BW + CPU_HAS_AVX512VL
    jz .check_avx2
    mov rax, blend_avx512
    jmp .patch_blend
.check_avx2:
    test rbx, CPU_HAS_AVX2
    jz .check_sse2
    mov rax, blend_avx2
    jmp .patch_blend
.check_sse2:
    test rbx, CPU_HAS_SSE2
    jz .patch_scalar
    mov rax, blend_sse2
    jmp .patch_blend
.patch_scalar:
    mov rax, blend_scalar
.patch_blend:
    ; Self-modifying code: patch the jmp at blend_dispatch
    mov r12, blend_dispatch
    mov word [r12], 0xE9      ; JMP rel32
    sub rax, r12
    sub rax, 5
    mov dword [r12 + 1], eax

    ; TODO: Patch other dispatch functions (fill, blit, scale, etc.)

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; cpuid_get_features
;   Get cached feature mask
;   OUT: rax = feature mask
; ---------------------------------------------------------------------------
global cpuid_get_features
cpuid_get_features:
    PROLOGUE
    mov rax, [cpu_feature_mask]
    leave
    ret

; ---------------------------------------------------------------------------
; cpuid_has_feature
;   Check specific feature
;   IN:  rdi = feature bit
;   OUT: rax = 1 if supported, 0 if not
; ---------------------------------------------------------------------------
global cpuid_has_feature
cpuid_has_feature:
    PROLOGUE
    mov rax, [cpu_feature_mask]
    test rax, rdi
    jz .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

section .data

global cpu_feature_mask
cpu_feature_mask: dq 0

cpu_vendor:       dq 0, 0
cpu_features_ecx: dd 0
cpu_features_edx: dd 0
cpu_features_ebx: dd 0
cpu_features_ecx_ext: dd 0
cpu_features_ext_ecx: dd 0
cpu_features_ext_edx: dd 0

global cpuid_version
cpuid_version: dq 0x010000
