; =============================================================================
; Tattva OS — boot/stage2/cpu/simd_enable.asm
; =============================================================================
; Enable SSE and AVX SIMD coprocessor features.
; Must be called in 32-bit Protected Mode before entering Long Mode.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit)
; =============================================================================

%ifndef SIMD_ENABLE_ASM
%define SIMD_ENABLE_ASM

[BITS 32]

; =============================================================================
; simd_enable — configure CR0, CR4, and XCR0 to enable SSE and AVX safely
; Output: CF=0 on success, CF=1 if mandatory state cannot be enabled
; =============================================================================
simd_enable:
    push eax
    push ebx
    push ecx
    push edx

    mov eax, [FEATURES_DEST]
    and eax, CPU_FEAT_SSE | CPU_FEAT_SSE2
    cmp eax, CPU_FEAT_SSE | CPU_FEAT_SSE2
    jne .failed

    ; Clear EM/TS, set MP/NE. Leaving TS set would turn the first SIMD
    ; instruction into #NM; CR0.NE gives architectural x87 exception handling.
    mov eax, cr0
    and eax, ~((1 << 2) | (1 << 3))
    or eax, (1 << 1) | (1 << 5)
    mov cr0, eax

    ; -------------------------------------------------------------------------
    ; Step 2: Configure CR4 flags
    ; Set CR4.OSFXSR (bit 9)      — enable FXSAVE/FXRSTOR for SSE registers
    ; Set CR4.OSXMMEXCPT (bit 10) — enable unmasked SIMD floating-point exceptions
    ; -------------------------------------------------------------------------
    mov eax, cr4
    or eax, (1 << 9) | (1 << 10)    ; set OSFXSR + OSXMMEXCPT
    mov cr4, eax

    ; A CPU without AVX remains a valid stage2 target. When AVX was advertised,
    ; require the complete XSAVE contract before executing XSETBV.
    test dword [FEATURES_DEST], CPU_FEAT_AVX
    jz .success
    cmp dword [cpu_max_leaf], 0x0D
    jb .failed

    mov eax, 1
    cpuid
    mov eax, ecx
    and eax, (1 << 26) | (1 << 28) ; XSAVE + AVX hardware support
    cmp eax, (1 << 26) | (1 << 28)
    jne .failed

    mov eax, 0x0D
    xor ecx, ecx
    cpuid
    and eax, 0x07                   ; x87, SSE, and AVX state components
    cmp eax, 0x07
    jne .failed

    ; Set CR4.OSXSAVE (bit 18) to allow XSETBV/XGETBV instructions
    mov eax, cr4
    or eax, (1 << 18)
    mov cr4, eax

    ; Set XCR0: enable bit 0 (x87), bit 1 (SSE), bit 2 (AVX)
    xor ecx, ecx                    ; XCR0 index = 0
    xgetbv                          ; read current XCR0 into EDX:EAX
    or eax, 0x07                    ; set x87 + SSE + AVX flags
    xsetbv                          ; write back XCR0

    xor ecx, ecx
    xgetbv
    and eax, 0x07
    cmp eax, 0x07
    jne .failed

.success:
    pop edx
    pop ecx
    pop ebx
    pop eax
    clc
    ret

.failed:
    pop edx
    pop ecx
    pop ebx
    pop eax
    stc
    ret

[BITS 16]

%endif ; SIMD_ENABLE_ASM
