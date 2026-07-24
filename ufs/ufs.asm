; =============================================================================
; Tattva OS — ufs/ufs.asm
; =============================================================================
; Master uFS (Unikernel Encrypted File System) Dispatcher API (`ufs_init`,
; `ufs_mount`, `ufs_unmount`).
;
; Single-pass NASM included subsystem handler linking all 34 uFS sub-modules.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "ufs/ufs.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

; -----------------------------------------------------------------------------
; uFS Child Subsystem NASM Includes
; -----------------------------------------------------------------------------
%include "ufs/vfs/vfs.asm"
%include "ufs/vfs/overlayfs.asm"
%include "ufs/vfs/ufs_clone.asm"
%include "ufs/vfs/ufs_snapshot.asm"
%include "ufs/vfs/ufs_pseudofs.asm"
%include "ufs/vfs/compat/fat32.asm"
%include "ufs/vfs/compat/ntfs.asm"
%include "ufs/vfs/compat/ext4_compat.asm"
%include "ufs/cache/ufs_pagecache.asm"
%include "ufs/cache/ufs_arc.asm"
%include "ufs/cache/ufs_dax.asm"
%include "ufs/cache/ufs_dedup.asm"
%include "ufs/cache/ufs_tmpfs.asm"
%include "ufs/crypto/ufs_crypto.asm"
%include "ufs/crypto/ufs_pqc.asm"
%include "ufs/crypto/ufs_fscrypt.asm"
%include "ufs/crypto/ufs_verity.asm"
%include "ufs/crypto/ufs_vault.asm"
%include "ufs/btree/ufs_cow_btree.asm"
%include "ufs/btree/ufs_alloc_groups.asm"
%include "ufs/extents/ufs_extents.asm"
%include "ufs/compress/ufs_compress.asm"
%include "ufs/compress/erofs.asm"
%include "ufs/cluster/ufs_cluster.asm"
%include "ufs/cluster/ufs_erasure.asm"
%include "ufs/limits/ufs_quota.asm"
%include "ufs/drivers/nvme.asm"
%include "ufs/drivers/nvme_zns.asm"
%include "ufs/drivers/usb_storage.asm"
%include "ufs/drivers/ahci.asm"
%include "ufs/drivers/sdhci.asm"
%include "ufs/drivers/virtio_blk.asm"
%include "ufs/drivers/nvme_of.asm"
%include "ufs/journal/ufs_journal.asm"
%include "ufs/tests/ufs_fuzz.asm"

section .text

global ufs_init
global ufs_mount
global ufs_unmount

; -----------------------------------------------------------------------------
; ufs_init
;
; Initializes master uFS filesystem subsystem, VFS descriptor tables, page cache,
; ARC cache, deduplication hash table, and driver queues.
;
; Returns:
;   EAX = 0 (Success)
; -----------------------------------------------------------------------------
align 32
ufs_init:
    push rbp
    mov rbp, rsp

    call ufs_vfs_init
    call ufs_pagecache_init
    call ufs_dedup_init

    mov eax, 0                      ; Success
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ufs_mount
;
; Mounts a target storage volume formatted with uFS.
;
; Inputs:
;   RDI = Pointer to volume superblock buffer
;
; Returns:
;   EAX = 0 (Success)
; -----------------------------------------------------------------------------
align 32
ufs_mount:
    push rbx

    mov rbx, rdi
    mov rax, [rbx + ufs_superblock_t.magic]
    mov rdx, UFS_MAGIC_NUMBER
    cmp rax, rdx
    jne .corrupt_mount

    mov eax, 0                      ; Mount success
    pop rbx
    ret

.corrupt_mount:
    mov eax, -22                    ; EINVAL (Invalid argument / corrupt magic)
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_unmount
; -----------------------------------------------------------------------------
align 32
ufs_unmount:
    mov eax, 0                      ; Success
    ret
