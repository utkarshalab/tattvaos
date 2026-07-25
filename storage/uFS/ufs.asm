; =============================================================================
; Tattva OS — storage/ufs/ufs.asm
; =============================================================================
; Master uFS (Unikernel Encrypted File System) Dispatcher API (`ufs_init`,
; `ufs_mount`, `ufs_unmount`).
;
; Single-pass NASM included subsystem handler linking all 34 uFS sub-modules.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "storage/ufs/ufs.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

; -----------------------------------------------------------------------------
; uFS Child Subsystem NASM Includes
; -----------------------------------------------------------------------------
%include "storage/ufs/vfs/vfs.asm"
%include "storage/ufs/vfs/overlayfs.asm"
%include "storage/ufs/vfs/clone.asm"
%include "storage/ufs/vfs/snapshot.asm"
%include "storage/ufs/vfs/pseudofs.asm"
%include "storage/ufs/vfs/compat/fat32.asm"
%include "storage/ufs/vfs/compat/ntfs.asm"
%include "storage/ufs/vfs/compat/ext4_compat.asm"
%include "storage/ufs/cache/pagecache.asm"
%include "storage/ufs/cache/arc.asm"
%include "storage/ufs/cache/dax.asm"
%include "storage/ufs/cache/dedup.asm"
%include "storage/ufs/cache/tmpfs.asm"
%include "storage/ufs/crypto/crypto.asm"
%include "storage/ufs/crypto/pqc.asm"
%include "storage/ufs/crypto/fscrypt.asm"
%include "storage/ufs/crypto/verity.asm"
%include "storage/ufs/crypto/vault.asm"
%include "storage/ufs/btree/cow_btree.asm"
%include "storage/ufs/btree/alloc_groups.asm"
%include "storage/ufs/extents/extents.asm"
%include "storage/ufs/compress/compress.asm"
%include "storage/ufs/compress/erofs.asm"
%include "storage/ufs/cluster/cluster.asm"
%include "storage/ufs/cluster/erasure.asm"
%include "storage/ufs/limits/quota.asm"
%include "storage/ufs/drivers/nvme.asm"
%include "storage/ufs/drivers/nvme_zns.asm"
%include "storage/ufs/drivers/usb_storage.asm"
%include "storage/ufs/drivers/ahci.asm"
%include "storage/ufs/drivers/sdhci.asm"
%include "storage/ufs/drivers/virtio_blk.asm"
%include "storage/ufs/drivers/nvme_of.asm"
%include "storage/ufs/journal/journal.asm"
%include "storage/ufs/tests/fuzz.asm"

section .text

global ufs_init
global ufs_mount
global ufs_unmount

; -----------------------------------------------------------------------------
; ufs_init
; -----------------------------------------------------------------------------
align 32
ufs_init:
    push rbp
    mov rbp, rsp

    call vfs_init
    call pagecache_init
    call dedup_init

    mov eax, 0                      ; Success
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ufs_mount
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
    mov eax, -22                    ; EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_unmount
; -----------------------------------------------------------------------------
align 32
ufs_unmount:
    mov eax, 0                      ; Success
    ret
