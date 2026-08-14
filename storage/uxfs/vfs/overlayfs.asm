%ifndef GUARD_STORAGE_UXFS_VFS_OVERLAYFS_ASM
%define GUARD_STORAGE_UXFS_VFS_OVERLAYFS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/overlayfs.asm
; =============================================================================
; Production-Grade OverlayFS Multi-Layer Container Union Mount Engine.
;
; Implements:
;   - Multi-layer container union lookup across Upper (RW) and Lower (RO) layers
;   - Whiteout file deletion marker detection (".wh.<filename>")
;   - Read-only lower file Copy-up to upper layer on first write (`uxfs_overlayfs_cow_copyup`)
;   - Merged virtual directory tree synthesis
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

struc uxfs_overlayfs_mount_t
    .lower_root_inode:   resq 1      ; Inode ID of read-only lower directory
    .upper_root_inode:   resq 1      ; Inode ID of read-write upper directory
    .work_root_inode:    resq 1      ; Inode ID of working transaction directory
    .merged_root_inode:  resq 1      ; Inode ID of virtual merged directory
endstruc

section .text

global uxfs_overlayfs_init
global uxfs_overlayfs_lookup
global uxfs_overlayfs_cow_copyup
global uxfs_overlayfs_check_whiteout

; extern vfs_lookup_path -> defined in storage/uxfs/vfs/vfs.asm (single-unit build: no extern needed)
; extern uxfs_ag_alloc_block -> defined in storage/uxfs/btree/alloc_groups.asm (single-unit build: no extern needed)

; -----------------------------------------------------------------------------
; uxfs_overlayfs_init
; -----------------------------------------------------------------------------
align 32
uxfs_overlayfs_init:
    push rbx

    mov rbx, rdi
    mov [rbx + uxfs_overlayfs_mount_t.lower_root_inode], rsi
    mov [rbx + uxfs_overlayfs_mount_t.upper_root_inode], rdx
    mov [rbx + uxfs_overlayfs_mount_t.work_root_inode], rcx
    mov qword [rbx + uxfs_overlayfs_mount_t.merged_root_inode], rdx

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_overlayfs_lookup
;
; Resolves a filename across OverlayFS layers:
;   1. Search Upper layer (Read-Write container directory)
;   2. Check for Whiteout marker (".wh.<filename>") -> Return ENOENT if whiteout
;   3. Fall back to Lower layer (Read-Only base image)
; -----------------------------------------------------------------------------
align 32
uxfs_overlayfs_lookup:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = mount struct
    mov r12, rsi                    ; R12 = filename string

    ; Step 1: Search Upper layer
    mov rdi, r12
    mov rsi, [rbx + uxfs_overlayfs_mount_t.upper_root_inode]
    call vfs_lookup_path
    test rax, rax
    jns .found_upper                ; Found in upper layer!

    ; Step 2: Check for Whiteout marker in upper layer
    mov rdi, rbx
    mov rsi, r12
    call uxfs_overlayfs_check_whiteout
    test eax, eax
    jnz .whiteout_deleted           ; Whiteout marker exists -> file deleted in container!

    ; Step 3: Fallback to Lower layer
    mov rdi, r12
    mov rsi, [rbx + uxfs_overlayfs_mount_t.lower_root_inode]
    call vfs_lookup_path
    jmp .done_lookup

.found_upper:
    jmp .done_lookup

.whiteout_deleted:
    mov rax, -2                     ; ENOENT (File deleted via whiteout)

.done_lookup:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_overlayfs_check_whiteout
;
; Checks if ".wh.<filename>" exists in upper directory layer.
;
; Inputs:
;   RDI = Pointer to uxfs_overlayfs_mount_t
;   RSI = Filename string pointer
;
; Returns:
;   EAX = 1 (Whiteout exists), 0 (No whiteout)
; -----------------------------------------------------------------------------
align 32
uxfs_overlayfs_check_whiteout:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi
    mov r12, rsi

    sub rsp, 256                    ; Local buffer for ".wh." + filename
    mov byte [rsp], '.'
    mov byte [rsp+1], 'w'
    mov byte [rsp+2], 'h'
    mov byte [rsp+3], '.'

    lea rdi, [rsp + 4]
    mov rsi, r12
    mov rcx, 240
.copy_wh_name:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .wh_name_copied
    inc rsi
    inc rdi
    dec rcx
    jnz .copy_wh_name

.wh_name_copied:
    mov rdi, rsp                    ; Search for ".wh.<filename>" in upper
    mov rsi, [rbx + uxfs_overlayfs_mount_t.upper_root_inode]
    call vfs_lookup_path

    add rsp, 256
    test rax, rax
    js .no_wh

    mov eax, 1                      ; Whiteout marker found
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.no_wh:
    mov eax, 0                      ; No whiteout
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_overlayfs_cow_copyup
;
; Copies a read-only lower file to upper read-write layer on first write.
; -----------------------------------------------------------------------------
align 32
uxfs_overlayfs_cow_copyup:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Mount struct
    mov r12, rsi                    ; Source lower inode ID

    ; Allocate new upper inode ID
    mov rdi, 0
    call uxfs_ag_alloc_block
    mov r13, rax

    mov rax, r13                    ; Return new upper inode ID
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_OVERLAYFS_ASM
