; =============================================================================
; Tattva OS — lib/mem/virt/hardware/svm.asm
; =============================================================================
; Shared Virtual Memory (SVM) via IOMMU Direct Sharing (Feature 6).
; Maps process PML4 tables directly into the physical PCIe PASID descriptor tables.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HARDWARE_SVM_ASM
%define LIB_MEM_VIRT_HARDWARE_SVM_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; iommu_bind_pasid_table — writes the cpu PML4 page table base to the IOMMU PASID table
; Input:
;   RDI = pasid_number (0 to 511)
;   RSI = cpu_pml4_paddr (physical frame address of target PML4)
; Output: none
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global iommu_bind_pasid_table
iommu_bind_pasid_table:
    mov rdx, [pasid_table_base]
    test rdx, rdx
    jz .exit                        ; Exit if mock IOMMU table is not registered

    ; Build PASID entry value: PML4 Base Address + Present (bit 0) + PRI (bit 1)
    mov rax, rsi
    and rax, 0xFFFFFFFFFFFFF000     ; Mask address
    or rax, 0x03                    ; Present | PRI

    ; Index entry (each entry is 64 bytes)
    imul rdi, 64                    ; RDI = offset
    mov [rdx + rdi], rax            ; Write entry in mock PASID table

    ; Force IOMMU cache flush (normally wbinvd + simulated IOMMU register flush)
    wbinvd

.exit:
    ret

section .bss

global pasid_table_base
alignb 8
pasid_table_base: resq 1            ; Pointer to mock physical PASID table

%endif ; LIB_MEM_VIRT_HARDWARE_SVM_ASM
