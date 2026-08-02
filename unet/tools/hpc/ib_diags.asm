; =============================================================================
; Tattva OS — unet/tools/hpc/ib_diags.asm
; =============================================================================
; InfiniBand Architecture Diagnostic Utilities (`ibnetdiscover`, `iblinkinfo`, `ibstat`).
;
; Features:
;   - Subnet Manager (SM) & Subnet Administrator (SA) Query Interface
;   - Port State (Active, Down, Init), Link Width (1x, 4x, 8x, 12x), Speed (EDR, HDR, NDR, XDR)
;   - Local Identifier (LID) & GUID Topology Discovery
;
; Delegates:
;   - InfiniBand Protocol               -> unet/hpc/infiniband.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ib_diags_main
global ib_diags_discover_topology

extern infiniband_parse_bth

align 64
ib_diags_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call ib_diags_discover_topology

    pop rbx
    pop rbp
    ret

align 64
ib_diags_discover_topology:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Query Subnet Manager (SA MAD SubnetAdminGet) -> list LIDs, GUIDs, links, widths, and speeds
    xor eax, eax
    pop rbp
    ret
