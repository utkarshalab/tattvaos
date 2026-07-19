; =============================================================================
; Tattva OS — boot/stage2/fs/ext2.asm
; =============================================================================
; Minimal read-only EXT2 filesystem driver for boot.
;
; Supports loading kernel.ulf from an EXT2 partition during boot.
; Read-only, minimal implementation:
;   - Reads superblock and validates EXT2 magic (0xEF53)
;   - Walks the root inode (inode 2) directory entries
;   - Reads file data via direct blocks only (no indirect blocks)
;   - 32KB kernel fits in 12 direct blocks × 1KB/4KB = plenty
;
; EXT2 on-disk layout:
;   Block 0:  Boot block (1024 bytes, unused by ext2)
;   Block 1:  Superblock (1024 bytes, always at offset 1024)
;   Block 2+: Block group descriptors
;   ...       Inode tables, data blocks
;
; Superblock key fields (at byte offset from partition start + 1024):
;   0x00  dd  s_inodes_count
;   0x04  dd  s_blocks_count
;   0x18  dd  s_log_block_size      (block_size = 1024 << s_log_block_size)
;   0x28  dd  s_blocks_per_group
;   0x38  dd  s_magic               (must be 0xEF53)
;   0x58  dw  s_inode_size           (usually 128 or 256)
;
; Author:  Utkarsha Labs
; Target:  x86-64, long mode (64-bit)
; =============================================================================

%ifndef EXT2_ASM
%define EXT2_ASM

[BITS 64]

; EXT2 constants
EXT2_MAGIC          equ 0xEF53      ; superblock magic number
EXT2_ROOT_INODE     equ 2           ; root directory is always inode 2
EXT2_SB_OFFSET      equ 1024        ; superblock is always at byte 1024

; Superblock field offsets
EXT2_SB_INODES_COUNT     equ 0x00
EXT2_SB_BLOCKS_COUNT     equ 0x04
EXT2_SB_LOG_BLOCK_SIZE   equ 0x18
EXT2_SB_BLOCKS_PER_GROUP equ 0x28
EXT2_SB_INODES_PER_GROUP equ 0x28 + 0x10  ; offset 0x28 is blocks, 0x38 is unused, 0x28+0x12=0x40
EXT2_SB_MAGIC            equ 0x38
EXT2_SB_INODE_SIZE       equ 0x58

; Actually correct offsets for s_inodes_per_group and s_inode_size:
; s_inodes_per_group is at offset 0x28 + 0x18 = 0x40
EXT2_SB_INODES_PER_GRP  equ 0x40
EXT2_SB_INODE_SZ         equ 0x58

; Inode field offsets (within an inode structure)
EXT2_INODE_MODE     equ 0x00       ; file type + permissions (word)
EXT2_INODE_SIZE     equ 0x04       ; file size in bytes (dword)
EXT2_INODE_BLOCK    equ 0x28       ; array of 15 block pointers (12 direct + 3 indirect)
EXT2_INODE_BLOCKS   equ 12         ; number of direct block pointers

; Directory entry field offsets
EXT2_DIRENT_INODE    equ 0x00      ; inode number (dword)
EXT2_DIRENT_REC_LEN  equ 0x04     ; record length (word)
EXT2_DIRENT_NAME_LEN equ 0x06     ; name length (byte)
EXT2_DIRENT_TYPE     equ 0x07     ; file type (byte)
EXT2_DIRENT_NAME     equ 0x08     ; filename (variable length)

; File types in directory entries
EXT2_FT_REG_FILE    equ 1          ; regular file
EXT2_FT_DIR         equ 2          ; directory

; Block group descriptor offsets
EXT2_BGD_INODE_TABLE equ 0x08      ; starting block of inode table (dword)
EXT2_BGD_SIZE        equ 32        ; size of each block group descriptor

; Temporary buffer for superblock / inode / directory reads
; Uses scratch area at 0x50000 (well below our kernel temp area)
EXT2_SCRATCH         equ 0x50000

; =============================================================================
; ext2_mount — read and validate superblock
; Input:  RAX = starting LBA of EXT2 partition
; Output: CF clear = valid EXT2, CF set = invalid or not EXT2
;         [ext2_part_lba] = partition start LBA
;         [ext2_block_size] = block size in bytes
;         [ext2_inodes_per_group] = inodes per block group
;         [ext2_inode_size] = size of each inode
; Clobbers: RAX, RCX, RDX, RSI
; =============================================================================
ext2_mount:
    push rbx
    push rdi

    mov [ext2_part_lba], rax        ; store partition start

    ; Read superblock: it's at byte 1024 from partition start
    ; = LBA + 2 (since each LBA sector is 512 bytes, 1024/512 = 2 sectors)
    add rax, 2                      ; LBA of superblock sector
    mov rdi, EXT2_SCRATCH           ; read buffer
    mov ecx, 2                      ; read 2 sectors (1024 bytes)
    call ext2_read_sectors
    jc .mount_fail

    ; Validate magic number at offset 0x38
    mov rsi, EXT2_SCRATCH
    movzx eax, word [rsi + EXT2_SB_MAGIC]
    cmp ax, EXT2_MAGIC
    jne .mount_fail

    ; Extract block size: 1024 << s_log_block_size
    mov ecx, [rsi + EXT2_SB_LOG_BLOCK_SIZE]
    mov eax, 1024
    shl eax, cl
    mov [ext2_block_size], eax

    ; Extract inodes per group
    mov eax, [rsi + EXT2_SB_INODES_PER_GRP]
    mov [ext2_inodes_per_group], eax

    ; Extract inode size (EXT2 rev 0 = 128, rev 1+ = field at 0x58)
    movzx eax, word [rsi + EXT2_SB_INODE_SZ]
    test eax, eax                   ; if 0, assume rev 0 default
    jnz .got_inode_size
    mov eax, 128                    ; default inode size
.got_inode_size:
    mov [ext2_inode_size], eax

    ; Extract blocks per group
    mov eax, [rsi + EXT2_SB_BLOCKS_PER_GROUP]
    mov [ext2_blocks_per_group], eax

    pop rdi
    pop rbx
    clc                              ; success
    ret

.mount_fail:
    pop rdi
    pop rbx
    stc                              ; failure
    ret

; =============================================================================
; ext2_find_file — search root directory for a filename
; Input:  RSI = pointer to null-terminated filename (e.g. "kernel.ulf")
;         RCX = filename length
; Output: EAX = inode number of found file (0 if not found)
; Clobbers: RBX, RCX, RDX, RDI
;
; Reads the root inode (inode 2), then iterates its directory entries.
; =============================================================================
ext2_find_file:
    push rsi
    push r12
    push r13

    mov r12, rsi                    ; R12 = filename pointer
    mov r13d, ecx                   ; R13D = filename length

    ; Step 1: Read root inode (inode 2)
    mov eax, EXT2_ROOT_INODE
    call ext2_read_inode            ; inode data at EXT2_SCRATCH
    jc .file_not_found

    ; Step 2: Read root directory data (first direct block)
    mov rsi, EXT2_SCRATCH
    mov eax, [rsi + EXT2_INODE_BLOCK]    ; first direct block pointer

    ; Convert block number to LBA
    call ext2_block_to_lba
    mov rdi, EXT2_SCRATCH + 4096    ; use offset buffer for directory data
    mov ecx, [ext2_block_size]
    shr ecx, 9                      ; / 512 = sectors per block
    call ext2_read_sectors
    jc .file_not_found

    ; Step 3: Scan directory entries
    mov rsi, EXT2_SCRATCH + 4096    ; start of directory data
    mov ecx, [ext2_block_size]      ; bytes to scan

.scan_dirent:
    test ecx, ecx
    jz .file_not_found              ; exhausted directory block

    ; Read entry fields
    mov eax, [rsi + EXT2_DIRENT_INODE]
    test eax, eax                   ; inode 0 = deleted entry
    jz .next_dirent

    movzx edx, byte [rsi + EXT2_DIRENT_NAME_LEN]
    cmp edx, r13d                   ; name length match?
    jne .next_dirent

    ; Compare filename
    push rsi
    push rcx
    push rdi
    lea rdi, [rsi + EXT2_DIRENT_NAME]
    mov rsi, r12                    ; filename to search for
    mov ecx, edx                    ; length
    repe cmpsb
    pop rdi
    pop rcx
    pop rsi
    jne .next_dirent

    ; Match found — return inode number
    mov eax, [rsi + EXT2_DIRENT_INODE]

    pop r13
    pop r12
    pop rsi
    ret

.next_dirent:
    movzx edx, word [rsi + EXT2_DIRENT_REC_LEN]
    test edx, edx                   ; safety: rec_len must be > 0
    jz .file_not_found
    add rsi, rdx                    ; advance to next entry
    sub ecx, edx
    jmp .scan_dirent

.file_not_found:
    xor eax, eax                    ; return 0 = not found

    pop r13
    pop r12
    pop rsi
    ret

; =============================================================================
; ext2_read_inode — read an inode structure into EXT2_SCRATCH
; Input:  EAX = inode number (1-based)
; Output: inode data at EXT2_SCRATCH (ext2_inode_size bytes)
;         CF clear = success, CF set = failure
; Clobbers: RAX, RCX, RDX, RSI, RDI
;
; Inode location:
;   block_group = (inode - 1) / inodes_per_group
;   local_index = (inode - 1) % inodes_per_group
;   Read block group descriptor to find inode table start block
;   inode_offset = local_index * inode_size
; =============================================================================
ext2_read_inode:
    push rbx
    push r14
    push r15

    dec eax                         ; make 0-based
    mov r14d, eax                   ; R14D = inode - 1

    ; Calculate block group
    xor edx, edx
    div dword [ext2_inodes_per_group]
    ; EAX = block group index, EDX = local index within group
    mov r15d, edx                   ; R15D = local index

    ; Read block group descriptor table (starts at block 2 for 1KB blocks,
    ; block 1 for 2KB+ blocks)
    mov ebx, [ext2_block_size]
    cmp ebx, 1024
    ja .bgd_block1
    mov ebx, 2                      ; block 2 for 1KB block size
    jmp .read_bgd
.bgd_block1:
    mov ebx, 1                      ; block 1 for larger block sizes

.read_bgd:
    ; Block group descriptor for group EAX is at:
    ; bgd_block + (group * 32) / block_size
    push rax
    mov eax, ebx                    ; block number of BGD table
    call ext2_block_to_lba
    mov rdi, EXT2_SCRATCH + 8192    ; temporary BGD buffer
    mov ecx, [ext2_block_size]
    shr ecx, 9
    call ext2_read_sectors
    pop rax
    jc .inode_fail

    ; Find inode table block from block group descriptor
    ; BGD entry at offset = group_index * 32
    shl eax, 5                      ; * 32
    mov rsi, EXT2_SCRATCH + 8192
    add rsi, rax
    mov eax, [rsi + EXT2_BGD_INODE_TABLE]  ; starting block of inode table

    ; Calculate byte offset within inode table
    ; offset = local_index * inode_size
    push rax
    mov eax, r15d
    mul dword [ext2_inode_size]     ; EDX:EAX = offset in bytes
    mov r15d, eax                   ; R15D = byte offset
    pop rax

    ; Read the inode table block containing our inode
    ; inode_block = inode_table_start + (byte_offset / block_size)
    push rax
    mov eax, r15d
    xor edx, edx
    div dword [ext2_block_size]     ; EAX = block offset, EDX = offset within block
    mov r15d, edx                   ; R15D = offset within block
    pop rbx                         ; RBX = inode table start block
    add eax, ebx                    ; EAX = actual block number

    call ext2_block_to_lba
    mov rdi, EXT2_SCRATCH           ; read into scratch buffer
    mov ecx, [ext2_block_size]
    shr ecx, 9
    call ext2_read_sectors
    jc .inode_fail

    ; Copy inode data to start of EXT2_SCRATCH
    ; Source: EXT2_SCRATCH + r15d, Dest: EXT2_SCRATCH
    cmp r15d, 0
    je .inode_done                  ; already at offset 0

    push rsi
    push rdi
    push rcx
    lea rsi, [EXT2_SCRATCH + r15]
    mov rdi, EXT2_SCRATCH
    mov ecx, [ext2_inode_size]
    rep movsb
    pop rcx
    pop rdi
    pop rsi

.inode_done:
    pop r15
    pop r14
    pop rbx
    clc
    ret

.inode_fail:
    pop r15
    pop r14
    pop rbx
    stc
    ret

; =============================================================================
; ext2_block_to_lba — convert ext2 block number to disk LBA
; Input:  EAX = ext2 block number
; Output: RAX = absolute LBA sector number
; Clobbers: RDX
; =============================================================================
ext2_block_to_lba:
    push rcx

    ; LBA = partition_start_lba + (block_number * block_size / 512)
    mov ecx, [ext2_block_size]
    shr ecx, 9                      ; sectors per block
    imul rax, rcx                   ; block * sectors_per_block
    add rax, [ext2_part_lba]        ; + partition start

    pop rcx
    ret

; =============================================================================
; ext2_read_sectors — read sectors from disk (wrapper)
; Input:  RAX = starting LBA
;         RDI = destination buffer
;         ECX = number of sectors
; Output: CF clear = success, CF set = failure
;
; This is a stub that must be connected to the disk I/O subsystem.
; In the boot environment, this calls the appropriate BIOS or AHCI
; disk read function.
; =============================================================================
ext2_read_sectors:
    ; TODO: Connect to hw/disk.asm disk_read_sectors_64
    ; For now, return failure
    stc
    ret

; =============================================================================
; Data
; =============================================================================
ext2_part_lba:          dq 0        ; partition start LBA
ext2_block_size:        dd 0        ; block size in bytes
ext2_inodes_per_group:  dd 0        ; inodes per block group
ext2_inode_size:        dd 0        ; size of each inode (128 or 256)
ext2_blocks_per_group:  dd 0        ; blocks per block group

[BITS 16]

%endif ; EXT2_ASM
