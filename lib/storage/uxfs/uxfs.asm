%ifndef GUARD_STORAGE_UXFS_UXFS_ASM
%define GUARD_STORAGE_UXFS_UXFS_ASM
; =============================================================================
; Utkarsha OS — lib/storage/uxfs/uxfs.asm
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

%include "lib/storage/uxfs/uxfs.inc"
%include "lib/crypto/ucrypt/guards/ct_guard.asm"

; -----------------------------------------------------------------------------
; VFS Subsystem & Multi-OS Compatibility Drivers
; -----------------------------------------------------------------------------
%include "lib/storage/uxfs/vfs/vfs.asm"
%include "lib/storage/uxfs/vfs/overlayfs.asm"
%include "lib/storage/uxfs/vfs/clone.asm"
%include "lib/storage/uxfs/vfs/snapshot.asm"
%include "lib/storage/uxfs/vfs/pseudofs.asm"

; Universal Multi-OS Compatibility Suite
%include "lib/storage/uxfs/vfs/compat/ntfs.asm"
%include "lib/storage/uxfs/vfs/compat/exfat.asm"
%include "lib/storage/uxfs/vfs/compat/fat32.asm"
%include "lib/storage/uxfs/vfs/compat/refs.asm"
%include "lib/storage/uxfs/vfs/compat/apfs.asm"
%include "lib/storage/uxfs/vfs/compat/hfsplus.asm"
%include "lib/storage/uxfs/vfs/compat/ext4_compat.asm"
%include "lib/storage/uxfs/vfs/compat/btrfs_compat.asm"
%include "lib/storage/uxfs/vfs/compat/xfs_compat.asm"
%include "lib/storage/uxfs/vfs/compat/ufs2_compat.asm"
%include "lib/storage/uxfs/vfs/compat/zfs_compat.asm"
%include "lib/storage/uxfs/vfs/compat/squashfs.asm"
%include "lib/storage/uxfs/vfs/compat/iso9660.asm"

; 2025 Krapivin Tiny-Pointer Cache & Page Cache Suite
%include "lib/storage/uxfs/cache/pagecache.asm"
%include "lib/storage/uxfs/cache/arc.asm"
%include "lib/storage/uxfs/cache/dax.asm"
%include "lib/storage/uxfs/cache/dedup.asm"
%include "lib/storage/uxfs/cache/tinypointer_hash.asm"
%include "lib/storage/uxfs/cache/tmpfs.asm"

; Post-Quantum & AES-256-XTS Storage Encryption Suite
%include "lib/storage/uxfs/crypto/crypto.asm"
%include "lib/storage/uxfs/crypto/pqc.asm"
%include "lib/storage/uxfs/crypto/fscrypt.asm"
%include "lib/storage/uxfs/crypto/verity.asm"
%include "lib/storage/uxfs/crypto/vault.asm"

; Master CoW B-Tree Engine & Sub-modules
%include "lib/storage/uxfs/btree/cow.asm"
%include "lib/storage/uxfs/btree/alloc_groups.asm"
%include "lib/storage/uxfs/btree/prefix.asm"
%include "lib/storage/uxfs/btree/rcu.asm"
%include "lib/storage/uxfs/btree/simd.asm"

%include "lib/storage/uxfs/extents/extents.asm"
%include "lib/storage/uxfs/compress/compress.asm"
%include "lib/storage/uxfs/compress/erofs.asm"
%include "lib/storage/uxfs/cluster/cluster.asm"
%include "lib/storage/uxfs/cluster/erasure.asm"
%include "lib/storage/uxfs/limits/quota.asm"

; -----------------------------------------------------------------------------
; Security — extended attributes and POSIX ACLs. The forthcoming auth module
; builds on these rather than on raw mode bits.
; -----------------------------------------------------------------------------
%include "lib/storage/uxfs/security/xattr.asm"
%include "lib/storage/uxfs/security/acl.asm"

; Storage Hardware Driver Aggregator Module
%include "lib/storage/uxfs/drivers/drivers.asm"
%include "lib/storage/uxfs/journal/journal.asm"

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

%endif ; GUARD_STORAGE_UXFS_UXFS_ASM
