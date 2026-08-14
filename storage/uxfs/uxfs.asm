; =============================================================================
; Tattva OS — storage/uxfs/uxfs.asm
; =============================================================================
; Master UXFS (Unikernel Extended File System & Universal Multi-OS Storage).
;
; Single-pass NASM included subsystem handler linking all UXFS sub-modules
; and the Universal Multi-OS Filesystem Compatibility Drivers:
;   - Windows: NTFS, exFAT, FAT32, ReFS
;   - macOS: APFS, HFS+
;   - Linux: EXT4, Btrfs, XFS, SquashFS, EROFS
;   - FreeBSD/Unix: UFS2, ZFS
;   - Cloud-Init: ISO9660
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "storage/uxfs/uxfs.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

; -----------------------------------------------------------------------------
; VFS Subsystem & Multi-OS Compatibility Drivers
; -----------------------------------------------------------------------------
%include "storage/uxfs/vfs/vfs.asm"
%include "storage/uxfs/vfs/overlayfs.asm"
%include "storage/uxfs/vfs/clone.asm"
%include "storage/uxfs/vfs/snapshot.asm"
%include "storage/uxfs/vfs/pseudofs.asm"

; Universal Multi-OS Compatibility Suite
%include "storage/uxfs/vfs/compat/ntfs.asm"
%include "storage/uxfs/vfs/compat/exfat.asm"
%include "storage/uxfs/vfs/compat/fat32.asm"
%include "storage/uxfs/vfs/compat/refs.asm"
%include "storage/uxfs/vfs/compat/apfs.asm"
%include "storage/uxfs/vfs/compat/hfsplus.asm"
%include "storage/uxfs/vfs/compat/ext4_compat.asm"
%include "storage/uxfs/vfs/compat/btrfs_compat.asm"
%include "storage/uxfs/vfs/compat/xfs_compat.asm"
%include "storage/uxfs/vfs/compat/ufs2_compat.asm"
%include "storage/uxfs/vfs/compat/zfs_compat.asm"
%include "storage/uxfs/vfs/compat/squashfs.asm"
%include "storage/uxfs/vfs/compat/iso9660.asm"

; 2025 Krapivin Tiny-Pointer Cache & Page Cache Suite
%include "storage/uxfs/cache/pagecache.asm"
%include "storage/uxfs/cache/arc.asm"
%include "storage/uxfs/cache/dax.asm"
%include "storage/uxfs/cache/dedup.asm"
%include "storage/uxfs/cache/tinypointer_hash.asm"
%include "storage/uxfs/cache/tmpfs.asm"

; Post-Quantum & AES-256-XTS Storage Encryption Suite
%include "storage/uxfs/crypto/crypto.asm"
%include "storage/uxfs/crypto/pqc.asm"
%include "storage/uxfs/crypto/fscrypt.asm"
%include "storage/uxfs/crypto/verity.asm"
%include "storage/uxfs/crypto/vault.asm"

; Master CoW B-Tree Engine & Sub-modules
%include "storage/uxfs/btree/cow.asm"
%include "storage/uxfs/btree/alloc_groups.asm"
%include "storage/uxfs/btree/prefix.asm"
%include "storage/uxfs/btree/rcu.asm"
%include "storage/uxfs/btree/simd.asm"

%include "storage/uxfs/extents/extents.asm"
%include "storage/uxfs/compress/compress.asm"
%include "storage/uxfs/compress/erofs.asm"
%include "storage/uxfs/cluster/cluster.asm"
%include "storage/uxfs/cluster/erasure.asm"
%include "storage/uxfs/limits/quota.asm"

; -----------------------------------------------------------------------------
; Security — extended attributes and POSIX ACLs. The forthcoming auth module
; builds on these rather than on raw mode bits.
; -----------------------------------------------------------------------------
%include "storage/uxfs/security/xattr.asm"
%include "storage/uxfs/security/acl.asm"

; Storage Hardware Driver Aggregator Module
%include "storage/uxfs/drivers/drivers.asm"
%include "storage/uxfs/journal/journal.asm"

section .text

global uxfs_init
global uxfs_mount
global uxfs_unmount

; -----------------------------------------------------------------------------
; uxfs_init
; -----------------------------------------------------------------------------
align 32
uxfs_init:
    push rbp
    mov rbp, rsp

    call vfs_init
    call uxfs_pagecache_init
    call uxfs_dedup_init
    call uxfs_arc_init
    call uxfs_ag_init
    call uxfs_btree_prefix_init
    call uxfs_rcu_init
    call uxfs_nvme_init

    mov eax, 0                      ; Success
    pop rbp
    ret

; -----------------------------------------------------------------------------
; uxfs_mount
; -----------------------------------------------------------------------------
align 32
uxfs_mount:
    push rbx

    mov rbx, rdi
    mov rax, [rbx + uxfs_superblock_t.magic]
    mov rdx, UXFS_MAGIC_NUMBER
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
; uxfs_unmount
; -----------------------------------------------------------------------------
align 32
uxfs_unmount:
    mov eax, 0                      ; Success
    ret
