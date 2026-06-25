; =============================================================================
; Tattva OS — lib/mem/virt/paging/kpti.asm
; =============================================================================
; Kernel Page Table Isolation (KPTI / Meltdown Mitigation) (Feature 18).
; Protects kernel memory from side-channel leakages while in user mode.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PAGING_KPTI_ASM
%define LIB_MEM_VIRT_PAGING_KPTI_ASM

[BITS 64]

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text

; -----------------------------------------------------------------------------
; kpti_switch_to_kernel — Swap CR3 to the kernel shadow/full PML4 address
; Input:  None
; Output: None
; Clobbers: RAX, RSI, RDI
; -----------------------------------------------------------------------------
global kpti_switch_to_kernel
kpti_switch_to_kernel:
    mov rdi, cr3
    mov rsi, rdi
    and rsi, ~0xFFF                 ; mask off PCID (lower 12 bits)
    mov rax, [current_thread_kernel_pml4]
    test rax, rax
    jz .done                         ; if not configured, do nothing

    cmp rsi, rax
    je .done                         ; already using kernel pml4

    ; Keep the PCID bits from current CR3 and load new kernel PML4
    and rdi, 0xFFF
    or rax, rdi
    mov cr3, rax

.done:
    ret

; -----------------------------------------------------------------------------
; kpti_switch_to_user — Swap CR3 to the user shadow/restricted PML4 address
; Input:  None
; Output: None
; Clobbers: RAX, RSI, RDI
; -----------------------------------------------------------------------------
global kpti_switch_to_user
kpti_switch_to_user:
    mov rdi, cr3
    mov rsi, rdi
    and rsi, ~0xFFF                 ; mask off PCID (lower 12 bits)
    mov rax, [current_thread_user_pml4]
    test rax, rax
    jz .done                         ; if not configured, do nothing

    cmp rsi, rax
    je .done                         ; already using user pml4

    ; Keep the PCID bits from current CR3 and load user PML4
    and rdi, 0xFFF
    or rax, rdi
    mov cr3, rax

.done:
    ret

; -----------------------------------------------------------------------------
; Section .data
; -----------------------------------------------------------------------------
section .data

align 8
global current_thread_kernel_pml4
current_thread_kernel_pml4: dq 0

align 8
global current_thread_user_pml4
current_thread_user_pml4:   dq 0

section .text

%endif ; LIB_MEM_VIRT_PAGING_KPTI_ASM
