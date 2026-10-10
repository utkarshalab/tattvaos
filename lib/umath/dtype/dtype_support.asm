%ifndef GUARD_LIB_UMATH_DTYPE_DTYPE_SUPPORT_ASM
%define GUARD_LIB_UMATH_DTYPE_DTYPE_SUPPORT_ASM
; =============================================================================
; umath - unified math library
; dtype/dtype_support.asm - runtime hardware support per dtype
; =============================================================================
; dependencies:
;   dtype_id.asm
;   dtype_family.asm
;
; description:
;   queries CPU feature flags at runtime to determine which dtypes
;   can be used with native hardware instructions (via cpuid/cpuid.asm
;   plus the dtype-specific AVX-512/AMX/F16C bits, each only counted when
;   the OS has enabled its register state); results cached
;
;   support levels:
;     SUPPORT_NONE     = 0  not supported, no fallback
;     SUPPORT_SOFTWARE = 1  supported via software emulation only
;     SUPPORT_PARTIAL  = 2  partial hardware (some ops native)
;     SUPPORT_NATIVE   = 3  full native hardware support
;
; functions:
;   umath_dtype_support_init      ()         → void  (call once at startup)
;   umath_dtype_supported         (dtype_id) → bool
;   umath_dtype_support_level     (dtype_id) → u32   SUPPORT_* constant
;   umath_dtype_support_avx512f   ()         → bool
;   umath_dtype_support_avx512bf16()         → bool
;   umath_dtype_support_avx512fp16()         → bool
;   umath_dtype_support_avx512vnni()         → bool
;   umath_dtype_support_avx2      ()         → bool
;   umath_dtype_support_amx       ()         → bool
;   umath_dtype_support_matrix    ()         → *support_table
; =============================================================================

%include "lib/umath/dtype/dtype_id.asm"
%include "lib/umath/dtype/dtype_family.asm"
%include "lib/umath/cpuid/cpuid.asm"

bits 64

; =============================================================================
; support level constants
; =============================================================================

SUPPORT_NONE        equ 0
SUPPORT_SOFTWARE    equ 1
SUPPORT_PARTIAL     equ 2
SUPPORT_NATIVE      equ 3

; =============================================================================
; cached CPU feature flags (set by umath_dtype_support_init)
; =============================================================================

section .bss
alignb 8

cpu_features_cached:    resb 1      ; 1 = cache is valid
cpu_has_avx2:           resb 1
cpu_has_avx512f:        resb 1
cpu_has_avx512bw:       resb 1
cpu_has_avx512dq:       resb 1
cpu_has_avx512vl:       resb 1
cpu_has_avx512vnni:     resb 1
cpu_has_avx512bf16:     resb 1
cpu_has_avx512fp16:     resb 1
cpu_has_avx512vpopcntdq: resb 1
cpu_has_amx_tile:       resb 1
cpu_has_amx_bf16:       resb 1
cpu_has_amx_int8:       resb 1
cpu_has_bmi2:           resb 1
cpu_has_popcnt:         resb 1
cpu_has_lzcnt:          resb 1
cpu_has_f16c:           resb 1     ; VCVTPH2PS / VCVTPS2PH

; support level cache (one byte per dtype_id, up to 0x200). Must be .data, not
; .bss: NASM drops initializers in .bss, which would leave every entry 0 =
; SUPPORT_NONE instead of the 0xFF "not computed yet" sentinel.
section .data
align 8
dtype_support_cache:    times 0x200 db 0xFF  ; 0xFF = not computed yet

section .text

; =============================================================================
; CPUID helpers
; =============================================================================

; -----------------------------------------------------------------------------
; detect_cpu_features - fill the flags above
; AVX2, BMI2, POPCNT and LZCNT come from the shared detection in
; cpuid/cpuid.asm (so umath_cpu_restrict applies to them too). The dtype-
; specific extras are read here, each only when the register state it
; needs is enabled by the OS (XCR0): without that state the instructions
; fault even on hardware that has them.
; clobbers: rax, rcx, rdx (like the CPUID it replaces; callers keep edi live)
; -----------------------------------------------------------------------------
detect_cpu_features:
    push    rbx
    push    r12
    push    r13
    push    rsi
    push    rdi
    push    r8
    push    r9
    push    r10
    push    r11
    call    umath_cpu_init
    lea     rdi, [rel cpu_has_avx2] ; clear every flag (re-detection)
    mov     ecx, cpu_has_f16c - cpu_has_avx2 + 1
    xor     eax, eax
    rep stosb
    movzx   eax, byte [rel umath__has_avx2]
    mov     [rel cpu_has_avx2], al
    movzx   eax, byte [rel umath__has_bmi2]
    mov     [rel cpu_has_bmi2], al
    movzx   eax, byte [rel umath__has_popcnt]
    mov     [rel cpu_has_popcnt], al
    movzx   eax, byte [rel umath__has_lzcnt]
    mov     [rel cpu_has_lzcnt], al

    ; F16C: leaf 1 ecx bit 29, VEX-encoded, so it needs usable AVX
    cmp     byte [rel umath__has_avx], 0
    je      .no_f16c
    mov     eax, 1
    cpuid
    bt      ecx, 29
    setc    [rel cpu_has_f16c]
.no_f16c:

    xor     eax, eax
    cpuid
    cmp     eax, 7
    jb      .done
    mov     eax, 7
    xor     ecx, ecx
    cpuid
    mov     r12d, eax               ; highest leaf-7 subleaf
    mov     r13, [rel umath__cpu_xcr0]

    ; AMX: XCR0 bits 17-18 (XTILECFG, XTILEDATA). On Linux a process must
    ; still request XTILEDATA (arch_prctl) before using the tiles.
    mov     eax, r13d
    and     eax, (1 << 17) | (1 << 18)
    cmp     eax, (1 << 17) | (1 << 18)
    jne     .no_amx
    bt      edx, 24
    setc    [rel cpu_has_amx_tile]
    bt      edx, 22
    setc    [rel cpu_has_amx_bf16]
    bt      edx, 25
    setc    [rel cpu_has_amx_int8]
.no_amx:

    ; AVX-512 family: XCR0 opmask + zmm state (bits 1-2, 5-7), and not
    ; removed by umath_cpu_restrict
    mov     eax, r13d
    and     eax, 0xE6
    cmp     eax, 0xE6
    jne     .done
    cmp     byte [rel umath__has_avx], 0
    je      .done
    bt      qword [rel umath__cpu_allowed], UMATH_CPU_AVX512
    jnc     .done
    bt      ebx, 16
    setc    [rel cpu_has_avx512f]
    bt      ebx, 17
    setc    [rel cpu_has_avx512dq]
    bt      ebx, 30
    setc    [rel cpu_has_avx512bw]
    bt      ebx, 31
    setc    [rel cpu_has_avx512vl]
    bt      ecx, 11
    setc    [rel cpu_has_avx512vnni]
    bt      ecx, 14
    setc    [rel cpu_has_avx512vpopcntdq]
    bt      edx, 23
    setc    [rel cpu_has_avx512fp16]
    test    r12d, r12d
    jz      .done
    mov     eax, 7
    mov     ecx, 1
    cpuid
    bt      eax, 5                  ; leaf 7 subleaf 1 eax bit 5
    setc    [rel cpu_has_avx512bf16]

.done:
    mov     byte [rel cpu_features_cached], 1
    pop     r11
    pop     r10
    pop     r9
    pop     r8
    pop     rdi
    pop     rsi
    pop     r13
    pop     r12
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; ensure_features - call detect_cpu_features if not already cached
; -----------------------------------------------------------------------------
ensure_features:
    cmp     byte [rel cpu_features_cached], 0
    jne     .cached
    call    detect_cpu_features
.cached:
    ret

; =============================================================================
; public feature query functions
; =============================================================================

; -----------------------------------------------------------------------------
; umath_dtype_support_init - (re)detect support; optional, queries detect
;                            lazily. Call again after umath_cpu_restrict.
; args:    none
; returns: void
; -----------------------------------------------------------------------------
global umath_dtype_support_init
umath_dtype_support_init:
    push    rdi                     ; (aligns the stack for the calls)
    call    detect_cpu_features
    lea     rdi, [rel dtype_support_cache]
    mov     ecx, 0x200
    mov     al, 0xFF                ; forget levels computed earlier
    rep stosb
    pop     rdi
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512f - check AVX-512 Foundation support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512f
umath_dtype_support_avx512f:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512f]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512bf16 - check AVX-512 BF16 support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512bf16
umath_dtype_support_avx512bf16:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512bf16]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512fp16 - check AVX-512 FP16 support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512fp16
umath_dtype_support_avx512fp16:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512fp16]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx512vnni - check AVX-512 VNNI support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx512vnni
umath_dtype_support_avx512vnni:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx512vnni]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_avx2 - check AVX2 support
; returns: eax = 1 if supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_avx2
umath_dtype_support_avx2:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_avx2]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_amx - check Intel AMX support
; returns: eax = 1 if AMX-TILE supported, 0 otherwise
; -----------------------------------------------------------------------------
global umath_dtype_support_amx
umath_dtype_support_amx:
    call    ensure_features
    movzx   eax, byte [rel cpu_has_amx_tile]
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_level - get hardware support level for dtype
; args:    edi = dtype_id
; returns: eax = SUPPORT_* level
; -----------------------------------------------------------------------------
global umath_dtype_support_level
umath_dtype_support_level:
    call    ensure_features
    push    rbx
    mov     ebx, edi

    ; check cache first
    cmp     edi, 0x200
    jae     .compute
    lea     rax, [rel dtype_support_cache]
    movzx   eax, byte [rax + rdi]
    cmp     eax, 0xFF
    jne     .cached_return

.compute:
    mov     edi, ebx
    call    compute_support_level
    ; cache it
    cmp     ebx, 0x200
    jae     .no_cache
    lea     rcx, [rel dtype_support_cache]
    mov     byte [rcx + rbx], al
.no_cache:
    pop     rbx
    ret

.cached_return:
    pop     rbx
    ret

; -----------------------------------------------------------------------------
; compute_support_level - compute support level without cache
; args:    edi = dtype_id
; returns: eax = SUPPORT_* level
; -----------------------------------------------------------------------------
compute_support_level:
    ; ids are compared unsigned and in increasing order: each family is a
    ; contiguous range (see dtype_id.asm), so a wider check must never come
    ; before a narrower one inside the same range
    test    edi, edi            ; DTYPE_NONE
    jz      .none

    ; signed integers 0x001-0x009: native up to 64 bits, 128/256 partial
    cmp     edi, DTYPE_INT64
    jbe     .native
    cmp     edi, DTYPE_INT256
    jbe     .partial

    ; unsigned integers 0x010-0x019: native up to 64 bits, 128/256 partial
    ; (no single instruction), 512+ software
    cmp     edi, DTYPE_UINT4
    jb      .software
    cmp     edi, DTYPE_UINT64
    jbe     .native
    cmp     edi, DTYPE_UINT256
    jbe     .partial
    cmp     edi, DTYPE_UINT2048
    jbe     .software

    ; IEEE floats: FP32/FP64 native, FP16/BF16 by CPU feature, FP128 and
    ; TF32 software (no x86 hardware)
    cmp     edi, DTYPE_FP32
    je      .native
    cmp     edi, DTYPE_FP64
    je      .native
    cmp     edi, DTYPE_FP16
    je      .check_fp16
    cmp     edi, DTYPE_BF16
    je      .check_bf16

    ; complex: partial (no native complex arithmetic in x86)
    cmp     edi, DTYPE_CF32
    je      .partial
    cmp     edi, DTYPE_CF64
    je      .partial
    cmp     edi, DTYPE_CI8
    je      .partial
    cmp     edi, DTYPE_CI16
    je      .partial
    cmp     edi, DTYPE_CI32
    je      .partial

    ; everything else (FP8, FP6, OCP MX, BIGINT, posit, ...) is software
    jmp     .software

.check_fp16:
    cmp     byte [rel cpu_has_avx512fp16], 1
    je      .native
    cmp     byte [rel cpu_has_f16c], 1
    je      .partial            ; F16C only converts, no FP16 arithmetic
    jmp     .software

.check_bf16:
    cmp     byte [rel cpu_has_avx512bf16], 1
    je      .native
    jmp     .software

.none:
    mov     eax, SUPPORT_NONE
    ret
.native:
    mov     eax, SUPPORT_NATIVE
    ret
.partial:
    mov     eax, SUPPORT_PARTIAL
    ret
.software:
    mov     eax, SUPPORT_SOFTWARE
    ret

; -----------------------------------------------------------------------------
; umath_dtype_supported - is dtype usable (at any support level)?
; args:    edi = dtype_id
; returns: eax = 1 if usable, 0 if SUPPORT_NONE
; -----------------------------------------------------------------------------
global umath_dtype_supported
umath_dtype_supported:
    call    umath_dtype_support_level
    test    eax, eax
    setnz   al
    movzx   eax, al
    ret

; -----------------------------------------------------------------------------
; umath_dtype_support_matrix - get pointer to full support cache table
; args:    none
; returns: rax = pointer to 512-byte support cache (one byte per dtype_id)
; note:    call umath_dtype_support_init first to populate
; -----------------------------------------------------------------------------
global umath_dtype_support_matrix
umath_dtype_support_matrix:
    call    ensure_features
    ; populate cache for common dtypes
    mov     edi, DTYPE_INT8
    call    umath_dtype_support_level
    mov     edi, DTYPE_FP32
    call    umath_dtype_support_level
    mov     edi, DTYPE_FP16
    call    umath_dtype_support_level
    mov     edi, DTYPE_BF16
    call    umath_dtype_support_level
    mov     edi, DTYPE_FP64
    call    umath_dtype_support_level
    lea     rax, [rel dtype_support_cache]
    ret
%endif ; GUARD_LIB_UMATH_DTYPE_DTYPE_SUPPORT_ASM
