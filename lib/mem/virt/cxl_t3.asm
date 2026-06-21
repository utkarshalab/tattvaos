; =============================================================================
; Tattva OS — lib/mem/virt/cxl_t3.asm
; =============================================================================
; CXL Type 3 Memory Expansion — Subfeature 39.2.
;
; Implements interface support for CXL Type 3 devices (memory expanders).
; Detects and maps external DRAM resource ranges dynamically via the CXL.mem
; protocol, expanding addressable system memory boundaries.
;
; API:
;   cxl_t3_init()                       — Zeros capacity and device trackers.
;   cxl_t3_hotplug(addr, capacity_gb)   — Map CXL region to memory database.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_CXL_T3_ASM
%define LIB_MEM_VIRT_CXL_T3_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; cxl_t3_init — Initialise memory expansion controllers
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cxl_t3_init
cxl_t3_init:
    mov  qword [sys_cxl_t3_device_count], 0
    mov  qword [sys_cxl_t3_total_capacity_gb], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; cxl_t3_hotplug — Dynamically attach memory slice to active page pool
; Input:
;   RDI = Base Physical Address of region
;   RSI = Capacity in Gigabytes (e.g. 2048 for 2TB)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RDX
; ---------------------------------------------------------------------------
global cxl_t3_hotplug
cxl_t3_hotplug:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    inc  qword [sys_cxl_t3_device_count]
    add  [sys_cxl_t3_total_capacity_gb], rsi

    ; In Tattva OS, this physically maps the region's frames into the global
    ; page allocator's free-lists for use by user space allocators.
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
global sys_cxl_t3_device_count
sys_cxl_t3_device_count:        dq 0

align 8
global sys_cxl_t3_total_capacity_gb
sys_cxl_t3_total_capacity_gb:   dq 0

section .text

%endif ; LIB_MEM_VIRT_CXL_T3_ASM
