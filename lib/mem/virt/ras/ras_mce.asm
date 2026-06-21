; =============================================================================
; Tattva OS — lib/mem/virt/ras_mce.asm
; =============================================================================
; Machine Check Exception (MCE) Handler — Subfeature 38.2.
;
; Intercepts hardware-level memory errors. If an uncorrectable ECC error
; occurs within user-space context, the handler quarantines/poisons the affected
; physical page and terminates the faulting thread, enabling graceful degradation
; and preventing kernel-wide panic.
;
; API:
;   ras_mce_init()                  — Zeros MCE status counters.
;   ras_mce_handler(addr, uncorr)   — Intercepts error. Returns 1 if recovered,
;                                     0 if recovery failed (requires kernel panic).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RAS_MCE_ASM
%define LIB_MEM_VIRT_RAS_MCE_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; ras_mce_init — Setup MCE monitoring variables
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global ras_mce_init
ras_mce_init:
    mov  qword [sys_ras_mce_occurred], 0
    mov  qword [sys_ras_mce_recovered], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; ras_mce_handler — Intercept and handle physical memory exceptions
; Input:
;   RDI = Faulting physical address
;   RSI = Uncorrectable flag (1 = Uncorrectable/Double-bit, 0 = Correctable)
; Output: RAX = 1 if gracefully recovered, 0 if fatal (requires kernel panic)
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global ras_mce_handler
ras_mce_handler:
    inc  qword [sys_ras_mce_occurred]

    test rsi, rsi
    jz   .graceful_correctable      ; correctable is always recovered

    ; Uncorrectable error. Check if address is within user space memory zone.
    ; In Tattva OS boot verification, user memory range is simulated between
    ; physical frames mapping to virtual addresses 0x70000000 - 0x80000000.
    ; For the check, we evaluate if address represents user range or kernel range.
    ; Let's assume physical addresses below 0x10000000 (256MB) represent kernel,
    ; and addresses >= 0x10000000 represent user range.
    cmp  rdi, 0x10000000
    jb   .fatal_kernel_mce          ; kernel space error = fatal panic!

    ; User space page error! Attempt recovery by poisoning the physical page
    ; and marking it permanently unavailable.
    extern ras_poison_page
    push rdi
    call ras_poison_page            ; offlines page
    pop  rdi
    test rax, rax
    jz   .fatal_kernel_mce

    ; Gracefully recovered! (The scheduler will kill the faulting process)
    inc  qword [sys_ras_mce_recovered]
    mov  rax, 1
    ret

.graceful_correctable:
    inc  qword [sys_ras_mce_recovered]
    mov  rax, 1
    ret

.fatal_kernel_mce:
    xor  rax, rax                   ; recovery failed, panic!
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_ras_mce_occurred
sys_ras_mce_occurred:           dq 0

align 8
global sys_ras_mce_recovered
sys_ras_mce_recovered:          dq 0

section .text

%endif ; LIB_MEM_VIRT_RAS_MCE_ASM
