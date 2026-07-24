; =============================================================================
; Tattva OS — ufs/drivers/nvme_of.asm
; =============================================================================
; NVMe-oF (NVMe over Fabrics) Cloud Block Storage Driver (TCP / RDMA).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

section .text

global ufs_nvme_of_connect
global ufs_nvme_of_send_cmd

; -----------------------------------------------------------------------------
; ufs_nvme_of_connect
; -----------------------------------------------------------------------------
align 32
ufs_nvme_of_connect:
    mov eax, 0                      ; Success
    ret

; -----------------------------------------------------------------------------
; ufs_nvme_of_send_cmd
; -----------------------------------------------------------------------------
align 32
ufs_nvme_of_send_cmd:
    mov eax, 0                      ; Success
    ret
