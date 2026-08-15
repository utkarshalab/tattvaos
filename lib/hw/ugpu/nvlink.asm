; =============================================================================
; Tattva OS — lib/hw/ugpu/nvlink.asm
; =============================================================================
; NVLink capability signal for detected GPUs (ugpu_devices, from detect.asm).
;
; Scope note: NVLink's actual peer-to-peer topology (which GPUs are linked,
; how many links, per-link speed) lives behind NVIDIA's proprietary MMIO
; register layout, not a public PCIe capability — there is nothing in the
; PCI config space that enumerates it generically the way the PCIe
; Capability does for link speed/width in pcie.asm. Without that
; documentation this can only report the necessary-but-not-sufficient
; precondition: is the device NVIDIA-vendor at all. It cannot tell NVLink-
; capable SKUs apart from ones without it, and reports no link count or
; bandwidth. Matches the same honesty tradeoff lib/mem/virt/cxl/cxl_t1.asm
; makes for CXL (a flag + a constant, not a real protocol walk) — extending
; either past that point needs the vendor spec, not more guessing here.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UGPU_NVLINK_ASM
%define LIB_HW_UGPU_NVLINK_ASM

%include "lib/hw/ugpu/detect.asm"

[BITS 64]

HW_PCI_VENDOR_NVIDIA equ 0x10DE

section .text

; -----------------------------------------------------------------------------
; ugpu_nvlink_capable — checks whether a detected GPU is NVIDIA-vendor
; (necessary but not sufficient for NVLink — see file header)
; Input:
;   RDI = index into ugpu_devices
; Output:
;   RAX = 1 if NVIDIA-vendor, 0 if not NVIDIA-vendor or index out of range
; Clobbers: RAX, RCX
; -----------------------------------------------------------------------------
global ugpu_nvlink_capable
ugpu_nvlink_capable:
    cmp rdi, [rel ugpu_device_count]
    jae .no

    mov rax, rdi
    imul rax, ugpu_device_t_size
    mov ecx, [rel ugpu_devices + rax + ugpu_device_t.vendor_id]
    cmp ecx, HW_PCI_VENDOR_NVIDIA
    jne .no

    mov rax, 1
    ret

.no:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; ugpu_nvlink_candidate_count — count of detected GPUs that are NVIDIA-vendor
; Input:  none
; Output: RAX = count (an upper bound on possible NVLink fabric membership,
;         not a confirmed link count — see file header)
; Clobbers: RAX, RCX, RDX, RDI
; -----------------------------------------------------------------------------
global ugpu_nvlink_candidate_count
ugpu_nvlink_candidate_count:
    push rbx

    xor rbx, rbx                    ; RBX = matched count
    xor rdx, rdx                    ; RDX = index

.loop:
    cmp rdx, [rel ugpu_device_count]
    jae .done

    mov rdi, rdx
    push rdx
    call ugpu_nvlink_capable
    pop rdx
    add rbx, rax

    inc rdx
    jmp .loop

.done:
    mov rax, rbx
    pop rbx
    ret

%endif ; LIB_HW_UGPU_NVLINK_ASM
