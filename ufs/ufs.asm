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
%include "ufs/vfs/clone.asm"
%include "ufs/vfs/snapshot.asm"
%include "ufs/vfs/pseudofs.asm"
%include "ufs/vfs/compat/fat32.asm"
%include "ufs/vfs/compat/ntfs.asm"
%include "ufs/vfs/compat/ext4_compat.asm"
%include "ufs/cache/pagecache.asm"
%include "ufs/cache/arc.asm"
%include "ufs/cache/dax.asm"
%include "ufs/cache/dedup.asm"
%include "ufs/cache/tmpfs.asm"
%include "ufs/crypto/crypto.asm"
%include "ufs/crypto/pqc.asm"
%include "ufs/crypto/fscrypt.asm"
%include "ufs/crypto/verity.asm"
%include "ufs/crypto/vault.asm"
%include "ufs/btree/cow_btree.asm"
%include "ufs/btree/alloc_groups.asm"
%include "ufs/extents/extents.asm"
%include "ufs/compress/compress.asm"
%include "ufs/compress/erofs.asm"
%include "ufs/cluster/cluster.asm"
%include "ufs/cluster/erasure.asm"
%include "ufs/limits/quota.asm"
%include "ufs/drivers/nvme.asm"
%include "ufs/drivers/nvme_zns.asm"
%include "ufs/drivers/usb_storage.asm"
%include "ufs/drivers/ahci.asm"
%include "ufs/drivers/sdhci.asm"
%include "ufs/drivers/virtio_blk.asm"
%include "ufs/drivers/nvme_of.asm"
%include "ufs/journal/journal.asm"
%include "ufs/tests/fuzz.asm"

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
