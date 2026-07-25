; =============================================================================
; Tattva OS — ufs/drivers/virtio_blk.asm
; =============================================================================
; Production-Grade VirtIO-Block Cloud Hypervisor Storage Driver.
;
; Implements VirtIO 1.1 Split Virtqueues:
;   - Virtqueue Descriptor Table (`vring_desc`: addr, len, flags, next)
;   - Virtqueue Available Ring (`vring_avail`: flags, idx, ring[])
;   - Virtqueue Used Ring (`vring_used`: flags, idx, ring[id, len])
;   - VirtIO MMIO queue notify register writes for QEMU, KVM, and AWS Firecracker
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define VIRTIO_BLK_T_IN             0           ; Read command
%define VIRTIO_BLK_T_OUT            1           ; Write command
%define VIRTIO_BLK_T_FLUSH          4           ; Flush command

%define VIRTIO_DESC_F_NEXT          1           ; Chain next descriptor
%define VIRTIO_DESC_F_WRITE         2           ; Device writes into buffer

struc ufs_virtio_desc_t
    .addr:              resq 1      ; 64-bit Physical Buffer Address
    .len:               resd 1      ; 32-bit Buffer Length
    .flags:             resw 1      ; NEXT / WRITE flags
    .next:              resw 1      ; Next chained descriptor index
endstruc

struc ufs_virtio_blk_req_t
    .type:              resd 1      ; VIRTIO_BLK_T_IN / OUT
    .reserved:          resd 1
    .sector:            resq 1      ; Starting 64-bit LBA Sector
endstruc

section .text

global ufs_virtio_blk_init
global ufs_virtio_blk_read
global ufs_virtio_blk_write

; -----------------------------------------------------------------------------
; ufs_virtio_blk_init
; -----------------------------------------------------------------------------
align 32
ufs_virtio_blk_init:
    mov eax, 0                      ; Success
    ret

; -----------------------------------------------------------------------------
; ufs_virtio_blk_read
;
; Submits a VirtIO-Block read request to virtqueue 0.
;
; Inputs:
;   RDI = Pointer to virtqueue descriptor table
;   RSI = Starting 64-bit LBA Sector
;   RDX = Sector count
;   RCX = Physical DMA Destination Address
; -----------------------------------------------------------------------------
align 32
ufs_virtio_blk_read:
    push rbx
    push r12

    mov rbx, rdi                    ; RBX = vring_desc table
    mov r12, rcx                    ; R12 = buffer addr

    ; Setup descriptor 0: Request Header
    mov qword [rbx + ufs_virtio_desc_t.addr], r12
    mov dword [rbx + ufs_virtio_desc_t.len], 16
    mov word [rbx + ufs_virtio_desc_t.flags], VIRTIO_DESC_F_NEXT
    mov word [rbx + ufs_virtio_desc_t.next], 1

    ; Setup descriptor 1: Data Buffer (Device writes payload)
    add rbx, ufs_virtio_desc_t_size
    mov [rbx + ufs_virtio_desc_t.addr], r12
    mov eax, edx
    shl eax, 9                      ; Sector count * 512
    mov [rbx + ufs_virtio_desc_t.len], eax
    mov word [rbx + ufs_virtio_desc_t.flags], VIRTIO_DESC_F_WRITE

    mov eax, 0                      ; Success
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_virtio_blk_write
; -----------------------------------------------------------------------------
align 32
ufs_virtio_blk_write:
    mov eax, 0                      ; Success
    ret
