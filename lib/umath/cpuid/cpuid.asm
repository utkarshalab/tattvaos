%ifndef GUARD_LIB_UMATH_CPUID_CPUID_ASM
%define GUARD_LIB_UMATH_CPUID_CPUID_ASM
; =============================================================================
; umath - unified math library
; cpuid/cpuid.asm - runtime CPU feature detection for umath's fast paths
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Everything in umath runs on the x86-64 baseline (SSE2). Faster paths use
; later extensions; before using one, umath checks the matching byte below
; (see cpuid/fallback.asm, which falls back to SSE2 code when it is 0).
;
; Detection runs once (umath_cpu_init, or lazily from the first fallback
; call) and caches one byte per feature. AVX, AVX2, FMA and AVX-512 count
; as present only if the OS has also enabled their register state (CPUID
; OSXSAVE + XGETBV): without that, every ymm/zmm instruction raises #UD
; even on hardware that has it.
;
; Feature bits (umath_cpu_features / umath_cpu_has / umath_cpu_restrict):
;   0 SSE3   1 SSSE3   2 SSE4.1   3 SSE4.2   4 POPCNT   5 LZCNT
;   6 BMI1   7 BMI2    8 AVX      9 AVX2    10 FMA     11 AVX-512 (F+BW+VL)
;  12 PREFETCHW
; =============================================================================

bits 64

UMATH_CPU_SSE3      equ 0
UMATH_CPU_SSSE3     equ 1
UMATH_CPU_SSE41     equ 2
UMATH_CPU_SSE42     equ 3
UMATH_CPU_POPCNT    equ 4
UMATH_CPU_LZCNT     equ 5
UMATH_CPU_BMI1      equ 6
UMATH_CPU_BMI2      equ 7
UMATH_CPU_AVX       equ 8
UMATH_CPU_AVX2      equ 9
UMATH_CPU_FMA       equ 10
UMATH_CPU_AVX512    equ 11
UMATH_CPU_PRFCHW    equ 12
UMATH_CPU_NFEATURES equ 13

section .data
align 8
umath__cpu_detected:    dq 0            ; what the CPU and OS support
umath__cpu_allowed:     dq -1           ; umath_cpu_restrict mask
umath__cpu_xcr0:        dq 0            ; OS-enabled state (XCR0; 0 without OSXSAVE)
umath__cpu_ready:       db 0            ; 1 once detection has run
; one byte per feature, effective = detected & allowed (fast-path checks)
umath__cpu_flags:
umath__has_sse3:        db 0
umath__has_ssse3:       db 0
umath__has_sse41:       db 0
umath__has_sse42:       db 0
umath__has_popcnt:      db 0
umath__has_lzcnt:       db 0
umath__has_bmi1:        db 0
umath__has_bmi2:        db 0
umath__has_avx:         db 0
umath__has_avx2:        db 0
umath__has_fma:         db 0
umath__has_avx512:      db 0
umath__has_prfchw:      db 0

section .text

; set umath feature bit %3 in r12 when bit %2 of register %1 is set
%macro umath__cpu_bit 3
    bt      %1, %2
    jnc     %%no
    bts     r12, %3
%%no:
%endmacro

; -----------------------------------------------------------------------------
; umath__cpu_publish - internal: refresh the per-feature bytes from
;                      detected & allowed
; Clobbers rax, rcx, rdx.
; -----------------------------------------------------------------------------
umath__cpu_publish:
    mov     rax, [rel umath__cpu_detected]
    and     rax, [rel umath__cpu_allowed]
    lea     rdx, [rel umath__cpu_flags]
    xor     ecx, ecx
.loop:
    bt      rax, rcx
    setc    byte [rdx + rcx]
    inc     ecx
    cmp     ecx, UMATH_CPU_NFEATURES
    jb      .loop
    ret

; -----------------------------------------------------------------------------
; umath_cpu_init - detect CPU features (idempotent)
; args:    none
; returns: rax = effective feature mask (bits listed in the header)
; -----------------------------------------------------------------------------
global umath_cpu_init
umath_cpu_init:
    cmp     byte [rel umath__cpu_ready], 0
    jne     umath_cpu_features
    push    rbx                 ; cpuid writes ebx (callee-saved)
    push    r12
    push    r13
    xor     r12d, r12d          ; detected mask

    xor     eax, eax
    cpuid
    mov     r13d, eax           ; highest standard leaf

    mov     eax, 1
    cpuid
    umath__cpu_bit ecx, 0, UMATH_CPU_SSE3
    umath__cpu_bit ecx, 9, UMATH_CPU_SSSE3
    umath__cpu_bit ecx, 19, UMATH_CPU_SSE41
    umath__cpu_bit ecx, 20, UMATH_CPU_SSE42
    umath__cpu_bit ecx, 23, UMATH_CPU_POPCNT
    mov     r9d, ecx            ; keep leaf-1 ecx for the AVX/FMA/OSXSAVE bits

    ; OS-enabled register state: XCR0 bits 1-2 (xmm, ymm), 5-7 (AVX-512)
    xor     r10d, r10d          ; r10 = XCR0 (0 if XGETBV is unavailable)
    bt      r9d, 27             ; OSXSAVE
    jnc     .no_xgetbv
    xor     ecx, ecx
    xgetbv
    mov     r10d, eax
.no_xgetbv:
    mov     [rel umath__cpu_xcr0], r10
    mov     eax, r10d
    and     eax, 0x6
    cmp     eax, 0x6
    jne     .no_ymm
    umath__cpu_bit r9d, 28, UMATH_CPU_AVX
    umath__cpu_bit r9d, 12, UMATH_CPU_FMA
.no_ymm:

    cmp     r13d, 7
    jb      .no_leaf7
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    umath__cpu_bit ebx, 3, UMATH_CPU_BMI1
    umath__cpu_bit ebx, 8, UMATH_CPU_BMI2
    bt      r12, UMATH_CPU_AVX  ; AVX2 needs the OS-enabled ymm state too
    jnc     .no_leaf7
    umath__cpu_bit ebx, 5, UMATH_CPU_AVX2
    mov     eax, r10d
    and     eax, 0xE6           ; xmm, ymm, opmask, zmm0-15 hi, zmm16-31
    cmp     eax, 0xE6
    jne     .no_leaf7
    mov     eax, ebx
    and     eax, (1 << 16) | (1 << 30) | (1 << 31)   ; AVX512 F, BW, VL
    cmp     eax, (1 << 16) | (1 << 30) | (1 << 31)
    jne     .no_leaf7
    bts     r12, UMATH_CPU_AVX512
.no_leaf7:

    mov     eax, 0x80000000
    cpuid
    cmp     eax, 0x80000001
    jb      .no_ext
    mov     eax, 0x80000001
    cpuid
    umath__cpu_bit ecx, 5, UMATH_CPU_LZCNT   ; ABM / LZCNT
    umath__cpu_bit ecx, 8, UMATH_CPU_PRFCHW  ; PREFETCHW (3DNowPrefetch)
.no_ext:

    mov     [rel umath__cpu_detected], r12
    call    umath__cpu_publish
    mov     byte [rel umath__cpu_ready], 1
    pop     r13
    pop     r12
    pop     rbx
    ; fall through: return the effective mask

; -----------------------------------------------------------------------------
; umath_cpu_features - effective feature mask (detecting first if needed)
; returns: rax = mask (bits listed in the header)
; -----------------------------------------------------------------------------
global umath_cpu_features
umath_cpu_features:
    cmp     byte [rel umath__cpu_ready], 0
    je      umath_cpu_init
    mov     rax, [rel umath__cpu_detected]
    and     rax, [rel umath__cpu_allowed]
    ret

; -----------------------------------------------------------------------------
; umath_cpu_has - is one feature usable?
; args:    edi = feature bit (UMATH_CPU_*)
; returns: eax = 1 if usable, 0 otherwise
; -----------------------------------------------------------------------------
global umath_cpu_has
umath_cpu_has:
    push    rdi
    call    umath_cpu_features
    pop     rdi
    xor     ecx, ecx
    bt      rax, rdi
    setc    cl
    mov     eax, ecx
    ret

; -----------------------------------------------------------------------------
; umath_cpu_restrict - limit umath to a subset of the detected features
; args:    rdi = mask of features umath may use (-1 = all detected,
;                0 = SSE2 baseline only)
; returns: rax = new effective mask
;
; Only removes features: a bit the CPU/OS lacks stays off. Useful for
; testing the fallbacks, and for a kernel that has not enabled some state.
; -----------------------------------------------------------------------------
global umath_cpu_restrict
umath_cpu_restrict:
    push    rdi
    call    umath_cpu_features  ; make sure detection has run
    pop     rdi
    mov     [rel umath__cpu_allowed], rdi
    call    umath__cpu_publish
    jmp     umath_cpu_features

%endif ; GUARD_LIB_UMATH_CPUID_CPUID_ASM
