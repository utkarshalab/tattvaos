; =============================================================================
; Tattva OS — boot/stage2/memory/mtrr.asm
; =============================================================================
; Memory Type Range Register (MTRR) configuration.
;
; MTRRs control how the CPU caches specific physical address ranges.
; Without proper MTRR setup, framebuffer writes use uncacheable (UC)
; memory type which is ~100x slower than write-combining (WC).
;
; This module:
;   1. Reads MTRRCAP to determine how many variable MTRRs exist
;   2. Finds a free variable MTRR slot
;   3. Configures it for write-combining on the VBE framebuffer
;   4. Enables MTRRs globally via MTRR_DEF_TYPE
;
; MSR reference:
;   0x0FE  — IA32_MTRRCAP        (read-only, capability register)
;   0x200  — IA32_MTRR_PHYSBASE0  (base + type for variable range 0)
;   0x201  — IA32_MTRR_PHYSMASK0  (mask + valid for variable range 0)
;   0x202  — IA32_MTRR_PHYSBASE1  ... and so on (pairs of 2)
;   0x2FF  — IA32_MTRR_DEF_TYPE  (default type + enable bits)
;
; Memory types:
;   0x00 = UC (Uncacheable)
;   0x01 = WC (Write Combining)       ← we want this for framebuffer
;   0x04 = WT (Write Through)
;   0x05 = WP (Write Protect)
;   0x06 = WB (Write Back)            ← default for RAM
;
; Author:  Utkarsha Labs
; Target:  x86-64, 32-bit protected mode
; =============================================================================

%ifndef MTRR_ASM
%define MTRR_ASM

[BITS 32]

; MSR addresses
MTRRCAP_MSR         equ 0x0FE
MTRR_DEF_TYPE_MSR   equ 0x2FF
MTRR_PHYSBASE0_MSR  equ 0x200
MTRR_PHYSMASK0_MSR  equ 0x201

; Memory types
MTRR_TYPE_UC        equ 0x00
MTRR_TYPE_WC        equ 0x01
MTRR_TYPE_WT        equ 0x04
MTRR_TYPE_WP        equ 0x05
MTRR_TYPE_WB        equ 0x06

; MTRR_DEF_TYPE bits
MTRR_DEF_TYPE_E     equ (1 << 11)   ; MTRRs enabled
MTRR_DEF_TYPE_FE    equ (1 << 10)   ; Fixed-range MTRRs enabled

; MTRR_PHYSMASK valid bit
MTRR_MASK_VALID     equ (1 << 11)   ; mask is valid (range active)

; =============================================================================
; mtrr_init — detect MTRR support and read capabilities
; Input:  none
; Output: EAX = number of variable MTRRs available (0 = not supported)
;         [mtrr_var_count] = same value stored
; Clobbers: ECX, EDX
; =============================================================================
mtrr_init:
    push ecx
    push edx

    ; Check CPUID leaf 1 for MTRR support (EDX bit 12)
    mov eax, 1
    cpuid
    test edx, (1 << 12)            ; MTRR feature flag
    jz .no_mtrr

    ; Read MTRRCAP MSR
    mov ecx, MTRRCAP_MSR
    rdmsr                           ; EAX = low 32 bits, EDX = high 32 bits

    ; Bits 7:0 = number of variable range MTRRs
    and eax, 0xFF
    mov [mtrr_var_count], al

    pop edx
    pop ecx
    ret

.no_mtrr:
    xor eax, eax
    mov byte [mtrr_var_count], 0

    pop edx
    pop ecx
    ret

; =============================================================================
; mtrr_set_wc — configure a variable MTRR for write-combining
; Input:  EAX = physical base address (must be aligned to size)
;         EBX = size in bytes (must be power of 2, minimum 4KB)
; Output: CF clear = success, CF set = no free MTRR slot
; Clobbers: EAX, ECX, EDX
;
; This finds the first unused variable MTRR slot and programs it.
; A slot is unused when its PHYSMASK valid bit (bit 11) is clear.
;
; Base register: bits 35:12 = physical base, bits 7:0 = memory type
; Mask register: bits 35:12 = address mask, bit 11 = valid
; =============================================================================
mtrr_set_wc:
    push esi
    push edi
    push ebx

    mov esi, eax                    ; ESI = base address
    mov edi, ebx                    ; EDI = region size

    ; Find a free variable MTRR slot
    xor ecx, ecx                    ; slot index = 0
    movzx ebx, byte [mtrr_var_count]
    test ebx, ebx
    jz .no_slot                     ; no variable MTRRs at all

.find_free:
    cmp ecx, ebx
    jae .no_slot                    ; all slots used

    ; Read PHYSMASK for slot ECX
    push ecx
    lea ecx, [ecx * 2]             ; slot * 2 (base/mask pairs)
    add ecx, MTRR_PHYSMASK0_MSR    ; ECX = PHYSMASK MSR for this slot
    rdmsr                           ; EAX = low, EDX = high
    pop ecx

    test eax, MTRR_MASK_VALID       ; is this slot in use?
    jz .found_free                   ; valid bit clear = free slot

    inc ecx
    jmp .find_free

.found_free:
    ; Program PHYSBASE: base address + WC type
    push ecx
    lea ecx, [ecx * 2]             ; slot * 2
    add ecx, MTRR_PHYSBASE0_MSR

    mov eax, esi                    ; base address
    and eax, 0xFFFFF000             ; clear low 12 bits
    or  eax, MTRR_TYPE_WC           ; set memory type = write combining
    xor edx, edx                    ; high 32 bits = 0 (< 4GB)
    wrmsr
    pop ecx

    ; Program PHYSMASK: compute mask from size
    ; mask = ~(size - 1) & 0xFFFFF000
    push ecx
    lea ecx, [ecx * 2]
    add ecx, MTRR_PHYSMASK0_MSR

    mov eax, edi                    ; size
    dec eax                         ; size - 1
    not eax                         ; ~(size - 1)
    and eax, 0xFFFFF000             ; clear low 12 bits
    or  eax, MTRR_MASK_VALID        ; set valid bit
    xor edx, edx                    ; high 32 bits = 0 (for < 4GB)
    or  edx, 0x0F                   ; set bits 35:32 of mask for full 36-bit coverage
    wrmsr
    pop ecx

    pop ebx
    pop edi
    pop esi
    clc                              ; success
    ret

.no_slot:
    pop ebx
    pop edi
    pop esi
    stc                              ; failure — no free MTRR
    ret

; =============================================================================
; mtrr_enable — enable MTRRs globally
; Input:  none
; Output: none
; Clobbers: EAX, ECX, EDX
;
; Sets the E bit (bit 11) in MTRR_DEF_TYPE MSR.
; The default memory type is left as UC (uncacheable) which is the
; safest default — specific ranges are overridden by variable MTRRs.
; =============================================================================
mtrr_enable:
    mov ecx, MTRR_DEF_TYPE_MSR
    rdmsr                           ; read current value

    or eax, MTRR_DEF_TYPE_E         ; set enable bit
    ; Default type stays as 0 (UC) — safe default
    ; Variable MTRRs override specific ranges to WB/WC

    wrmsr                           ; write back
    ret

; =============================================================================
; mtrr_setup_framebuffer — convenience: init + set WC on framebuffer
; Input:  EAX = framebuffer physical address
;         EBX = framebuffer size (round up to power of 2)
; Output: CF clear = success, CF set = failed
; Clobbers: EAX, EBX, ECX, EDX
;
; Typical usage from stage2:
;   mov eax, [best_fb_addr]
;   mov ebx, (1920 * 1080 * 4)     ; ~8MB → round to 8MB
;   call mtrr_setup_framebuffer
; =============================================================================
mtrr_setup_framebuffer:
    push eax
    push ebx

    ; Step 1: detect MTRRs
    call mtrr_init
    test eax, eax
    jz .mtrr_fail                   ; no MTRR support

    ; Step 2: round size up to next power of 2
    pop ebx
    pop eax
    push eax
    push ebx

    call .round_up_pow2             ; EBX = rounded size
    pop ebx                         ; discard saved (use rounded)
    pop eax                         ; restore base address
    push eax
    push ebx

    ; Step 3: configure WC range
    ; (restore EAX=base, EBX=rounded size already on stack)
    pop ebx                         ; rounded size
    pop eax                         ; base address
    call mtrr_set_wc
    jc .mtrr_fail_nostack

    ; Step 4: enable MTRRs
    call mtrr_enable
    clc
    ret

.mtrr_fail:
    pop ebx
    pop eax
.mtrr_fail_nostack:
    stc
    ret

; ---- internal: round EBX up to next power of 2 ----
.round_up_pow2:
    ; Uses bit manipulation: round up to next power of 2
    ; If already power of 2, returns unchanged
    dec ebx
    mov ecx, ebx
    shr ecx, 1
    or  ebx, ecx
    shr ecx, 1
    or  ebx, ecx
    shr ecx, 1
    or  ebx, ecx
    shr ecx, 1
    or  ebx, ecx
    shr ecx, 1
    or  ebx, ecx
    inc ebx
    ret

; =============================================================================
; Data
; =============================================================================
mtrr_var_count:     db 0            ; number of variable MTRRs available

[BITS 16]

%endif ; MTRR_ASM
