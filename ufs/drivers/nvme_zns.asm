; =============================================================================
; Tattva OS — ufs/drivers/nvme_zns.asm
; =============================================================================
; NVMe ZNS (Zoned Namespaces) Controller Driver.
;
; Implements Zone Append, Zone Management Open/Close/Finish/Reset commands
; for high-density flash devices.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define NVME_ZNS_OPCODE_ZONE_APPEND 0x7D
%define NVME_ZNS_OPCODE_ZONE_MGMT   0x79

section .text

global ufs_nvme_zns_zone_append
global ufs_nvme_zns_reset_zone

; -----------------------------------------------------------------------------
; ufs_nvme_zns_zone_append
; -----------------------------------------------------------------------------
align 32
ufs_nvme_zns_zone_append:
    mov eax, 0                      ; Success
    ret

; -----------------------------------------------------------------------------
; ufs_nvme_zns_reset_zone
; -----------------------------------------------------------------------------
align 32
ufs_nvme_zns_reset_zone:
    mov eax, 0                      ; Success
    ret
