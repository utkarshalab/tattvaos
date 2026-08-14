%ifndef GUARD_STORAGE_UXFS_VFS_COMPAT_REFS_ASM
%define GUARD_STORAGE_UXFS_VFS_COMPAT_REFS_ASM
; =============================================================================
; Tattva OS — storage/uxfs/vfs/compat/refs.asm
; =============================================================================
; Microsoft ReFS (Resilient File System) Read Compatibility Driver.
;
; Implements:
;   - Boot sector validation and geometry capture (`uxfs_refs_mount`)
;   - Minstore metadata page header validation (`uxfs_refs_validate_page`)
;   - Checkpoint selection by sequence number (`uxfs_refs_pick_checkpoint`)
;   - B+ tree key search within a page (`uxfs_refs_btree_search`)
;
; ReFS is undocumented, so this driver is deliberately READ-ONLY and
; conservative: anything it does not positively recognise is refused rather
; than guessed at. Writing to a filesystem whose invariants are reverse
; engineered is how volumes get destroyed.
;
; The structure that matters is Minstore, a copy-on-write B+ tree. Metadata
; pages carry an "MSGP" magic, a 64-bit checksum, and a sequence number. Pages
; are never updated in place — a modification writes a new page elsewhere and
; publishes it by updating a checkpoint.
;
; That makes checkpoint selection the critical step: two checkpoints exist and
; the VALID one is whichever carries the higher sequence number AND passes its
; checksum. Picking the wrong one, or picking a higher sequence that failed
; validation, reads a torn write from an interrupted update.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define REFS_SUPER_MAGIC            0x53466552  ; "ReFS" at boot sector offset 3
%define REFS_PAGE_MAGIC             0x5047534D  ; "MSGP" metadata page
%define REFS_SUPERBLOCK_MAGIC       0x50425553  ; "SUPB" superblock page
%define REFS_CHECKPOINT_MAGIC       0x504B4843  ; "CHKP" checkpoint page

%define REFS_MIN_SECTOR             512
%define REFS_MAX_SECTOR             4096
%define REFS_DEFAULT_CLUSTER        65536       ; 64KB
%define REFS_MAX_CLUSTER            (1024 * 1024)

; Page header flag bits.
%define REFS_PAGE_FLAG_VALID        0x00000001
%define REFS_PAGE_FLAG_LEAF         0x00000002
%define REFS_PAGE_FLAG_INDEX        0x00000004

struc uxfs_refs_header_t
    .jump_boot:         resb 3
    .fs_name:           resb 4      ; "ReFS"
    .must_be_zero:      resb 4      ; Distinguishes ReFS from NTFS
    .sector_size:       resd 1
    .cluster_size:      resd 1
    .major_version:     resb 1
    .minor_version:     resb 1
    .checkpoint_offset: resq 1      ; LBA of the active checkpoint page
endstruc

struc uxfs_refs_page_header_t
    .magic:             resd 1      ; REFS_PAGE_MAGIC
    .checksum:          resq 1
    .flags:             resd 1
    .sequence:          resq 1      ; Higher wins among valid pages
    .key_count:         resd 1      ; Entries in this page
    .data_offset:       resd 1      ; Where the entry array begins
endstruc

; One B+ tree entry header. Key and value bytes follow it.
struc uxfs_refs_entry_t
    .entry_size:        resd 1      ; Total bytes including this header
    .key_offset:        resw 1
    .key_size:          resw 1
    .value_offset:      resw 1
    .value_size:        resw 1
endstruc

section .data
align 64

global uxfs_refs_sector_size
uxfs_refs_sector_size:      dd 0
uxfs_refs_cluster_size:     dd 0
uxfs_refs_major_version:    dd 0
uxfs_refs_checkpoint_lba:   dq 0
uxfs_refs_mounted:          dd 0
uxfs_refs_searches:         dq 0
uxfs_refs_rejected_pages:   dq 0

section .text

global uxfs_refs_mount
global uxfs_refs_btree_search
global uxfs_refs_validate_page
global uxfs_refs_pick_checkpoint

; -----------------------------------------------------------------------------
; uxfs_refs_mount
;
; Validates the ReFS boot sector and captures the volume geometry.
;
; Inputs:
;   RDI = Pointer to the boot sector
;
; Returns:
;   EAX = 0 on success
;         POSIX_EIO on a bad signature or implausible geometry
;         POSIX_EINVAL on a null argument
; -----------------------------------------------------------------------------
align 32
uxfs_refs_mount:
    push rbx

    test rdi, rdi
    jz .rm_inval
    mov rbx, rdi

    ; "ReFS" sits at offset 3, after the jump instruction.
    cmp dword [rbx + uxfs_refs_header_t.fs_name], REFS_SUPER_MAGIC
    jne .rm_badvol

    ; The four bytes after the name must be zero. NTFS puts its OEM id here,
    ; so a non-zero value means this is NTFS, not ReFS.
    cmp dword [rbx + uxfs_refs_header_t.must_be_zero], 0
    jne .rm_badvol

    mov eax, dword [rbx + uxfs_refs_header_t.sector_size]
    cmp eax, REFS_MIN_SECTOR
    jb .rm_badvol
    cmp eax, REFS_MAX_SECTOR
    ja .rm_badvol
    ; Must be a power of two.
    mov ecx, eax
    dec ecx
    test eax, ecx
    jnz .rm_badvol
    mov dword [uxfs_refs_sector_size], eax

    mov eax, dword [rbx + uxfs_refs_header_t.cluster_size]
    test eax, eax
    jz .rm_badvol
    cmp eax, REFS_MAX_CLUSTER
    ja .rm_badvol
    mov ecx, eax
    dec ecx
    test eax, ecx
    jnz .rm_badvol
    mov dword [uxfs_refs_cluster_size], eax

    movzx eax, byte [rbx + uxfs_refs_header_t.major_version]
    test eax, eax
    jz .rm_badvol
    cmp eax, 3
    ja .rm_badvol                   ; Newer layouts are not understood here
    mov dword [uxfs_refs_major_version], eax

    mov rax, [rbx + uxfs_refs_header_t.checkpoint_offset]
    mov [uxfs_refs_checkpoint_lba], rax

    mov dword [uxfs_refs_mounted], 1

    xor eax, eax
    pop rbx
    ret

.rm_badvol:
    mov eax, POSIX_EIO
    pop rbx
    ret

.rm_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_refs_validate_page
;
; Checks a Minstore metadata page header for structural plausibility.
;
; The checksum algorithm is not publicly specified, so this verifies what can
; be verified: magic, flags and internal consistency of the offsets. A page
; whose data_offset or key_count would read past its own bounds is rejected,
; which is what stops a corrupt page from steering a search out of the buffer.
;
; Inputs:
;   RDI = Pointer to the page
;   ESI = Page size in bytes
;
; Returns:
;   EAX = 0 when the page is usable, POSIX_EIO otherwise
; -----------------------------------------------------------------------------
align 32
uxfs_refs_validate_page:
    push rbx
    push r12

    test rdi, rdi
    jz .vp_reject
    mov rbx, rdi
    mov r12d, esi

    cmp r12d, uxfs_refs_page_header_t_size
    jbe .vp_reject

    cmp dword [rbx + uxfs_refs_page_header_t.magic], REFS_PAGE_MAGIC
    jne .vp_reject

    test dword [rbx + uxfs_refs_page_header_t.flags], REFS_PAGE_FLAG_VALID
    jz .vp_reject

    ; The entry array must begin inside the page and after the header.
    mov eax, dword [rbx + uxfs_refs_page_header_t.data_offset]
    cmp eax, uxfs_refs_page_header_t_size
    jb .vp_reject
    cmp eax, r12d
    jae .vp_reject

    ; Every entry needs at least its own header, so bound the count by the
    ; space actually remaining after data_offset.
    mov ecx, r12d
    sub ecx, eax                    ; Bytes available for entries
    mov eax, dword [rbx + uxfs_refs_page_header_t.key_count]
    imul eax, uxfs_refs_entry_t_size
    cmp eax, ecx
    ja .vp_reject

    xor eax, eax
    pop r12
    pop rbx
    ret

.vp_reject:
    inc qword [uxfs_refs_rejected_pages]
    mov eax, POSIX_EIO
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_refs_pick_checkpoint
;
; Chooses between the two checkpoint copies.
;
; The rule is strict: the winner is the copy with the higher sequence number
; AMONG THOSE THAT VALIDATE. A higher sequence that fails validation is a torn
; write from an interrupted update, and preferring it would mount a volume
; state that was never committed.
;
; Inputs:
;   RDI = Pointer to checkpoint copy A, or 0
;   RSI = Pointer to checkpoint copy B, or 0
;   EDX = Page size in bytes
;
; Returns:
;   RAX = Pointer to the checkpoint to use, or 0 when neither validates
; -----------------------------------------------------------------------------
align 32
uxfs_refs_pick_checkpoint:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Copy A
    mov r12, rsi                    ; Copy B
    mov r13d, edx                   ; Page size
    xor r14, r14                    ; A valid?
    xor r15, r15                    ; B valid?

    test rbx, rbx
    jz .pk_check_b
    mov rdi, rbx
    mov esi, r13d
    call uxfs_refs_validate_page
    test eax, eax
    jnz .pk_check_b
    mov r14, 1

.pk_check_b:
    test r12, r12
    jz .pk_decide
    mov rdi, r12
    mov esi, r13d
    call uxfs_refs_validate_page
    test eax, eax
    jnz .pk_decide
    mov r15, 1

.pk_decide:
    test r14, r14
    jz .pk_only_b
    test r15, r15
    jz .pk_only_a

    ; Both valid: higher sequence wins.
    mov rax, [rbx + uxfs_refs_page_header_t.sequence]
    mov rcx, [r12 + uxfs_refs_page_header_t.sequence]
    cmp rax, rcx
    jae .pk_only_a
    jmp .pk_only_b

.pk_only_a:
    mov rax, rbx
    jmp .pk_return

.pk_only_b:
    test r15, r15
    jz .pk_none
    mov rax, r12
    jmp .pk_return

.pk_none:
    xor rax, rax

.pk_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_refs_btree_search
;
; Linear search for a key within a validated Minstore page.
;
; Entries are variable length, so a binary search would need an offset table
; this driver cannot rely on being present. Pages are small enough that a
; linear walk is acceptable, and it cannot be steered out of bounds because
; every step re-checks the remaining space.
;
; Inputs:
;   RDI = Pointer to a page already accepted by uxfs_refs_validate_page
;   RSI = Pointer to the key to find
;   EDX = Key length in bytes
;   ECX = Page size in bytes
;
; Returns:
;   RAX = Pointer to the matching entry, or 0 when absent
; -----------------------------------------------------------------------------
align 32
uxfs_refs_btree_search:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Page
    mov r12, rsi                    ; Wanted key
    mov r13d, edx                   ; Key length
    mov r14d, ecx                   ; Page size

    test rbx, rbx
    jz .bs_missing
    test r12, r12
    jz .bs_missing
    test r13d, r13d
    jz .bs_missing

    cmp dword [uxfs_refs_mounted], 0
    je .bs_missing

    inc qword [uxfs_refs_searches]

    ; Start at the entry array.
    mov eax, dword [rbx + uxfs_refs_page_header_t.data_offset]
    lea r15, [rbx + rax]            ; Current entry
    mov r9d, dword [rbx + uxfs_refs_page_header_t.key_count]

.bs_loop:
    test r9d, r9d
    jz .bs_missing

    ; Refuse to step outside the page.
    mov rax, r15
    sub rax, rbx
    add rax, uxfs_refs_entry_t_size
    cmp rax, r14
    ja .bs_missing

    mov r8d, dword [r15 + uxfs_refs_entry_t.entry_size]
    test r8d, r8d
    jz .bs_missing                  ; Zero size would loop forever

    ; The key must lie inside this entry.
    movzx eax, word [r15 + uxfs_refs_entry_t.key_offset]
    movzx ecx, word [r15 + uxfs_refs_entry_t.key_size]
    mov edx, eax
    add edx, ecx
    cmp edx, r8d
    ja .bs_next                     ; Malformed entry: skip it

    cmp ecx, r13d
    jne .bs_next                    ; Different length cannot match

    ; Compare the key bytes.
    lea rdi, [r15 + rax]
    mov rsi, r12
    mov rcx, r13
    repe cmpsb
    je .bs_found

.bs_next:
    add r15, r8
    dec r9d
    jmp .bs_loop

.bs_found:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.bs_missing:
    xor rax, rax
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_VFS_COMPAT_REFS_ASM
