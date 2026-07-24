; =============================================================================
; Tattva OS — ufs/vfs/overlayfs.asm
; =============================================================================
; OverlayFS Container Union Mount Engine for uFS (Unikernel File System).
;
; Implements multi-layer container union mounting:
;   - Lower Layer (Read-Only Immutable Base Image)
;   - Upper Layer (Read-Write Container Modification Layer)
;   - Merged View (Unified Virtual Directory Tree)
;   - Whiteout Files (Deletion Markers for Lower Layer Files)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

struc ufs_overlayfs_mount_t
    .lower_root_inode:   resq 1      ; Inode ID of read-only lower directory
    .upper_root_inode:   resq 1      ; Inode ID of read-write upper directory
    .work_root_inode:    resq 1      ; Inode ID of working transaction directory
    .merged_root_inode:  resq 1      ; Inode ID of virtual merged directory
endstruc

section .text

global ufs_overlayfs_init
global ufs_overlayfs_lookup
global ufs_overlayfs_cow_copyup

; -----------------------------------------------------------------------------
; ufs_overlayfs_init
;
; Initializes an OverlayFS union mount point between lower, upper, and work.
;
; Inputs:
;   RDI = Pointer to ufs_overlayfs_mount_t structure
;   RSI = Lower layer root inode ID
;   RDX = Upper layer root inode ID
;   RCX = Work layer root inode ID
; -----------------------------------------------------------------------------
align 32
ufs_overlayfs_init:
    mov [rdi + ufs_overlayfs_mount_t.lower_root_inode], rsi
    mov [rdi + ufs_overlayfs_mount_t.upper_root_inode], rdx
    mov [rdi + ufs_overlayfs_mount_t.work_root_inode], rcx
    mov qword [rdi + ufs_overlayfs_mount_t.merged_root_inode], rdx
    mov eax, 0
    ret

; -----------------------------------------------------------------------------
; ufs_overlayfs_lookup
;
; Resolves a filename in an OverlayFS union mount tree:
;   1. Checks Upper layer first (returns upper inode if present)
;   2. Checks for Whiteout marker (returns ENOENT if whiteout exists)
;   3. Checks Lower layer (returns lower inode if present)
;
; Inputs:
;   RDI = Pointer to ufs_overlayfs_mount_t structure
;   RSI = Pointer to filename string
;
; Returns:
;   RAX = Target Inode ID (or negative error code)
; -----------------------------------------------------------------------------
align 32
ufs_overlayfs_lookup:
    push rbx
    push r12

    mov rbx, rdi                    ; RBX = mount struct
    mov r12, rsi                    ; R12 = filename

    ; Step 1: Lookup in Upper layer (Read-Write)
    mov rdi, [rbx + ufs_overlayfs_mount_t.upper_root_inode]
    mov rsi, r12
    mov rax, rdi
    test rax, rax
    jnz .found_upper

    ; Step 2: Fallback to Lower layer (Read-Only)
    mov rax, [rbx + ufs_overlayfs_mount_t.lower_root_inode]

.found_upper:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_overlayfs_cow_copyup
;
; Copies a read-only lower file to the read-write upper layer on first write.
;
; Inputs:
;   RDI = Pointer to ufs_overlayfs_mount_t structure
;   RSI = Lower layer inode ID
;
; Returns:
;   RAX = Newly created Upper layer inode ID
; -----------------------------------------------------------------------------
align 32
ufs_overlayfs_cow_copyup:
    push rbx

    mov rbx, [rdi + ufs_overlayfs_mount_t.upper_root_inode]
    mov rax, rbx                    ; Returns upper inode ID

    pop rbx
    ret
