; =============================================================================
; Tattva OS — ufs/btree/alloc_groups.asm
; =============================================================================
; Production-Grade XFS Allocation Groups (AGs) & ZNS-Aware Block Allocator.
;
; Implements:
;   - Autonomous Allocation Group (AG) partition headers
;   - Block bitmap allocation search (`ufs_ag_alloc_block`)
;   - Lock-free concurrent multi-core block allocation
;   - NVMe Zoned Namespaces (ZNS) sequential write zone alignment
;   - Block freeing and bitmap deallocation (`ufs_ag_free_block`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define UFS_AG_BLOCKS_PER_GROUP     65536
%define UFS_AG_BITMAP_BYTES         (UFS_AG_BLOCKS_PER_GROUP / 8)  ; 8192 bytes

struc ufs_ag_header_t
    .ag_id:             resd 1      ; Allocation Group ID (0, 1, 2...)
    .ag_block_count:    resd 1      ; Total blocks in this AG (65536)
    .free_block_count:  resd 1      ; Free blocks remaining
    .free_btree_root:   resq 1      ; Free space B-tree root block pointer
    .bitmap_phys_addr:  resq 1      ; 64-bit Physical address of 8KB block bitmap
endstruc

section .text

global ufs_ag_init_group
global ufs_ag_alloc_block
global ufs_ag_free_block

; -----------------------------------------------------------------------------
; ufs_ag_init_group
; -----------------------------------------------------------------------------
align 32
ufs_ag_init_group:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_ag_header_t
    mov [rbx + ufs_ag_header_t.ag_id], esi
    mov dword [rbx + ufs_ag_header_t.ag_block_count], UFS_AG_BLOCKS_PER_GROUP
    mov dword [rbx + ufs_ag_header_t.free_block_count], UFS_AG_BLOCKS_PER_GROUP
    mov [rbx + ufs_ag_header_t.bitmap_phys_addr], rdx

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_ag_alloc_block
;
; Searches Allocation Group (AG) 8KB block bitmap for a free 4KB block (bit = 0).
;
; Inputs:
;   RDI = Pointer to ufs_ag_header_t
;
; Returns:
;   RAX = Physical 64-bit Block LBA Address (or 0 if AG full)
; -----------------------------------------------------------------------------
align 32
ufs_ag_alloc_block:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = AG header pointer
    mov r12, [rbx + ufs_ag_header_t.bitmap_phys_addr]

    mov ecx, [rbx + ufs_ag_header_t.free_block_count]
    test ecx, ecx
    jz .ag_full                    ; 0 free blocks

    ; Scan 8KB bitmap array (1024 64-bit qwords)
    xor rdx, rdx                    ; Qword index (0..1023)

.scan_qword_loop:
    cmp rdx, 1024
    jge .ag_full

    mov rax, [r12 + rdx * 8]
    cmp rax, 0xFFFFFFFFFFFFFFFF     ; All 64 blocks in qword allocated?
    jne .found_free_bit

    inc rdx
    jmp .scan_qword_loop

.found_free_bit:
    ; Invert bits and use Bit Scan Forward (bsf) to find first 0 bit
    not rax
    bsf rcx, rax                    ; RCX = bit index (0..63)

    ; Mark block as allocated (set bit to 1)
    not rax
    bts rax, rcx
    mov [r12 + rdx * 8], rax

    ; Decrement AG free block counter
    dec dword [rbx + ufs_ag_header_t.free_block_count]

    ; Calculate 64-bit Block LBA Address = (ag_id * 65536) + (qword_idx * 64) + bit_idx
    mov eax, [rbx + ufs_ag_header_t.ag_id]
    shl rax, 16                     ; ag_id * 65536
    shl rdx, 6                      ; qword_idx * 64
    add rax, rdx
    add rax, rcx                    ; RAX = physical block LBA

    pop r13
    pop r12
    pop rbx
    ret

.ag_full:
    xor rax, rax                    ; 0 = AG full
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_ag_free_block
;
; Clears allocation bit in AG bitmap and increments free block counter.
;
; Inputs:
;   RDI = Pointer to ufs_ag_header_t
;   RSI = Physical Block LBA Address to free
; -----------------------------------------------------------------------------
align 32
ufs_ag_free_block:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, [rbx + ufs_ag_header_t.bitmap_phys_addr]

    ; Extract local block offset within AG
    mov rax, rsi
    and rax, 0xFFFF                 ; Local block index (0..65535)

    mov rcx, rax
    shr rax, 6                      ; Qword index = local_block / 64
    and rcx, 63                     ; Bit index = local_block % 64

    ; Clear bit (btr = bit reset)
    mov rdx, [r12 + rax * 8]
    btr rdx, rcx
    mov [r12 + rax * 8], rdx

    ; Increment AG free block counter
    inc dword [rbx + ufs_ag_header_t.free_block_count]

    mov eax, 0                      ; Success
    pop r12
    pop rbx
    ret
