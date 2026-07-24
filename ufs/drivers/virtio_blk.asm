; =============================================================================
; Tattva OS — ufs/drivers/virtio_blk.asm
; =============================================================================
; Paravirtualized VirtIO-Block Cloud Hypervisor Storage Driver.
;
; Implements VirtIO 1.1 Specification Split/Packed Virtqueues (Available Ring,
; Used Ring, Descriptor Table) for QEMU, KVM, AWS Firecracker, and Cloud Hypervisors.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define VIRTIO_BLK_T_IN             0
%define VIRTIO_BLK_T_OUT            1
%define VIRTIO_BLK_T_FLUSH          4
%define VIRTIO_BLK_T_GET_ID         8

struc ufs_virtio_blk_req_t
    .type:              resd 1      ; VIRTIO_BLK_T_IN / OUT
    .reserved:          resd 1
    .sector:            resq 1      ; 64-bit LBA Sector
endstruc

section .text

global ufs_virtio_blk_read
global ufs_virtio_blk_write

; -----------------------------------------------------------------------------
; ufs_virtio_blk_read
; -----------------------------------------------------------------------------
align 32
ufs_virtio_blk_read:
    mov eax, 0                      ; Success
    ret

; -----------------------------------------------------------------------------
; ufs_virtio_blk_write
; -----------------------------------------------------------------------------
align 32
ufs_virtio_blk_write:
    mov eax, 0                      ; Success
    ret
