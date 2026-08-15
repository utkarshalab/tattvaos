; =============================================================================
; Tattva OS — lib/hw/uhwloc/hwloc.asm
; =============================================================================
; Combined hardware locality: ties ucpu (topology), unuma (NUMA node),
; uhbm (bandwidth tier), ugpu, and ucxl (device inventories) together into
; single queries, rather than each caller re-deriving the same three-call
; sequence.
;
; Scope note: this does not attempt GPU/CXL-to-NUMA-node locality (e.g.
; "which node is this GPU closest to"). That mapping is exposed by ACPI
; via each PCI device's _PXM object in the DSDT, which needs a general
; AML interpreter to evaluate — well beyond what a fixed-table parser
; (SRAT/SLIT/HMAT, as everything else in lib/hw is) can reach. What this
; file combines is only what the other lib/hw subsystems already expose.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UHWLOC_HWLOC_ASM
%define LIB_HW_UHWLOC_HWLOC_ASM

%include "lib/percpu.inc"
%include "lib/hw/ucpu/topology.asm"
%include "lib/hw/unuma/affinity.asm"
%include "lib/hw/uhbm/layout.asm"
%include "lib/hw/ugpu/detect.asm"
%include "lib/hw/ucxl/cxl.asm"

[BITS 64]

UHWLOC_NODE_UNKNOWN equ 0xFFFFFFFF

struc uhwloc_locality_t
    .cpu_id         resd 1
    .smt_id         resd 1
    .core_id        resd 1
    .package_id     resd 1
    .numa_node      resd 1      ; UHWLOC_NODE_UNKNOWN if not resolved
    .is_hbm_node    resd 1      ; 1/0; meaningless if numa_node is unknown
endstruc

struc uhwloc_summary_t
    .cpu_count           resd 1   ; smp_active_cores
    .cache_level_count   resd 1   ; ucpu_cache_level_count
    .numa_node_count     resd 1   ; uhbm_node_count (HMAT-derived; 0 if no HMAT)
    .gpu_count           resd 1   ; ugpu_device_count
    .cxl_count           resd 1   ; ucxl_device_count
endstruc

section .text

; -----------------------------------------------------------------------------
; uhwloc_current_locality — combined topology + NUMA + bandwidth-tier for
; the currently executing core
; Input:
;   RDI = pointer to a uhwloc_locality_t to fill
; Output:
;   RAX = 1 if this core's SMT/core/package topology was known, 0 if not
;         (numa_node/is_hbm_node are filled independently either way, per
;         their own availability)
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8-R11, R12
; -----------------------------------------------------------------------------
global uhwloc_current_locality
uhwloc_current_locality:
    push rbx
    push r12

    mov r12, rdi                    ; R12 = out ptr

    mov edi, [gs:percpu_t.cpu_id]
    mov [r12 + uhwloc_locality_t.cpu_id], edi

    call ucpu_topology_get           ; RDI = cpu_id (still live in EDI)
    test rax, rax
    jz .no_topo
    mov [r12 + uhwloc_locality_t.smt_id], esi
    mov [r12 + uhwloc_locality_t.core_id], edx
    mov [r12 + uhwloc_locality_t.package_id], ecx
    mov ebx, 1
    jmp .topo_done

.no_topo:
    mov dword [r12 + uhwloc_locality_t.smt_id], 0
    mov dword [r12 + uhwloc_locality_t.core_id], 0
    mov dword [r12 + uhwloc_locality_t.package_id], 0
    xor ebx, ebx

.topo_done:
    call unuma_current_node          ; RAX = 1/0, RSI = node_id
    test rax, rax
    jz .no_node

    mov [r12 + uhwloc_locality_t.numa_node], esi
    mov edi, esi
    call uhbm_is_high_bandwidth_node  ; RDI = node_id -> RAX = 1/0
    mov [r12 + uhwloc_locality_t.is_hbm_node], eax
    jmp .done

.no_node:
    mov dword [r12 + uhwloc_locality_t.numa_node], UHWLOC_NODE_UNKNOWN
    mov dword [r12 + uhwloc_locality_t.is_hbm_node], 0

.done:
    mov eax, ebx
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uhwloc_summary — aggregate device/topology counts across every lib/hw
; subsystem, for a single boot-time report
; Input:
;   RDI = pointer to a uhwloc_summary_t to fill
; Output: none
; Clobbers: RAX
; -----------------------------------------------------------------------------
global uhwloc_summary
uhwloc_summary:
    mov eax, [rel smp_active_cores]
    mov [rdi + uhwloc_summary_t.cpu_count], eax

    mov eax, [rel ucpu_cache_level_count]
    mov [rdi + uhwloc_summary_t.cache_level_count], eax

    mov eax, [rel uhbm_node_count]
    mov [rdi + uhwloc_summary_t.numa_node_count], eax

    mov eax, [rel ugpu_device_count]
    mov [rdi + uhwloc_summary_t.gpu_count], eax

    mov eax, [rel ucxl_device_count]
    mov [rdi + uhwloc_summary_t.cxl_count], eax

    ret

%endif ; LIB_HW_UHWLOC_HWLOC_ASM
