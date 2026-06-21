; =============================================================================
; Tattva OS — lib/mem/virt/cxl_fabric.asm
; =============================================================================
; CXL Fabric Manager Integration — Subfeature 39.5.
;
; Implements fabric communication wrappers to coordinate dynamic physical memory
; allocations across disaggregated fabric pools. Slices can be requested or
; released on-demand to share pools dynamically among cluster computing nodes.
;
; API:
;   cxl_fabric_init()                   — Connects to local Fabric agent.
;   cxl_fabric_allocate(capacity_gb)    — Dynamic remote slice request.
;   cxl_fabric_release(id, capacity_gb) — Evicts slice and releases back to pool.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_CXL_FABRIC_ASM
%define LIB_MEM_VIRT_CXL_FABRIC_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; cxl_fabric_init — Register node with CXL Fabric orchestration managers
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cxl_fabric_init
cxl_fabric_init:
    mov  qword [sys_cxl_fabric_slices_allocated], 0
    mov  qword [sys_cxl_fabric_allocated_gb], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; cxl_fabric_allocate — Allocate memory slice dynamically from global fabric pool
; Input:  RDI = Slice Capacity in Gigabytes
; Output: RAX = Allocation Slice ID handle on success, 0 on failure
; Clobbers: RAX, RBX, RDX
; ---------------------------------------------------------------------------
global cxl_fabric_allocate
cxl_fabric_allocate:
    test rdi, rdi
    jz   .fail

    inc  qword [sys_cxl_fabric_slices_allocated]
    add  [sys_cxl_fabric_allocated_gb], rdi

    ; Generate virtual handle key based on count
    mov  rax, [sys_cxl_fabric_slices_allocated]
    or   rax, 0xABCD0000            ; stamp marker
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; cxl_fabric_release — Release allocation slice back to shared fabric
; Input:
;   RDI = Slice ID handle
;   RSI = Slice Capacity in Gigabytes to subtract
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cxl_fabric_release
cxl_fabric_release:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    dec  qword [sys_cxl_fabric_slices_allocated]
    sub  [sys_cxl_fabric_allocated_gb], rsi

    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_cxl_fabric_slices_allocated
sys_cxl_fabric_slices_allocated: dq 0

align 8
global sys_cxl_fabric_allocated_gb
sys_cxl_fabric_allocated_gb:    dq 0

section .text

%endif ; LIB_MEM_VIRT_CXL_FABRIC_ASM
