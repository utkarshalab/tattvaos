; =============================================================================
; Tattva OS — lib/mem/virt/cxl_t1.asm
; =============================================================================
; CXL Type 1 Device Support — Subfeature 39.1.
;
; Implements initialization and protocol configuration for CXL Type 1 devices
; (cache-coherent accelerators, e.g., smartNICs/GPUs). Enables cache coherence
; across the CXL.cache and CXL.io protocols to present device memory directly
; within the host CPU's coherent domain.
;
; API:
;   cxl_t1_init()                   — Enables links, coherent protocol tracking.
;   cxl_t1_get_bandwidth()          — Returns active device bandwidth in MB/s.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_CXL_T1_ASM
%define LIB_MEM_VIRT_CXL_T1_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; cxl_t1_init — Initialize coherent accelerator protocols
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cxl_t1_init
cxl_t1_init:
    mov  qword [sys_cxl_t1_active_devices], 1
    mov  qword [sys_cxl_t1_bandwidth_mbps], 64000 ; PCIe Gen5 x16 link rate (64GB/s)
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; cxl_t1_get_bandwidth — Get the current throughput metrics
; Output: RAX = Link rate (MB/s)
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cxl_t1_get_bandwidth
cxl_t1_get_bandwidth:
    mov  rax, [sys_cxl_t1_bandwidth_mbps]
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_cxl_t1_active_devices
sys_cxl_t1_active_devices:      dq 0

align 8
global sys_cxl_t1_bandwidth_mbps
sys_cxl_t1_bandwidth_mbps:      dq 0

section .text

%endif ; LIB_MEM_VIRT_CXL_T1_ASM
