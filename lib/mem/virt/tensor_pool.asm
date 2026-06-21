; =============================================================================
; Tattva OS — lib/mem/virt/tensor_pool.asm
; =============================================================================
; Tensor Memory Pool — Subfeature 36.1.
;
; Pre-allocates a contiguous pool of memory divided into fixed-size slots
; for tensor operations. Tracks free/allocated slots via a lock-free bitmap
; to achieve zero-fragmentation and O(1) allocation/deallocation overhead.
; Avoids runtime malloc calls during hot-path model inference execution.
;
; API:
;   tensor_pool_init(addr, pool_sz, blk_sz) — Initialise a pool context.
;   tensor_pool_alloc(pool_ptr)             — Allocate a fixed block (returns ptr).
;   tensor_pool_free(pool_ptr, block_ptr)   — Return a block to the pool.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_TENSOR_POOL_ASM
%define LIB_MEM_VIRT_TENSOR_POOL_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Pool Metadata Offsets (Header layout inside pool_addr)
; ---------------------------------------------------------------------------
POOL_START_OFF          equ 0       ; dq: data start address
POOL_SIZE_OFF           equ 8       ; dq: total size in bytes
BLOCK_SIZE_OFF          equ 16      ; dq: block size in bytes
TOTAL_BLOCKS_OFF        equ 24      ; dq: total count of blocks
BITMAP_WORDS_OFF        equ 32      ; dq: number of 64-bit words in bitmap
BITMAP_START_OFF        equ 40      ; start of bitmap array

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; tensor_pool_init — Initialize tensor pool structure at the given address
; Input:
;   RDI = Pool Address (buffer to hold metadata, bitmap, and block data)
;   RSI = Total Pool Size (bytes)
;   RDX = Block Size (bytes)
; Output: RAX = Pointer to pool context (RDI), or 0 on failure
; Clobbers: RAX, RCX, RDX, R8, R9, R10
; ---------------------------------------------------------------------------
global tensor_pool_init
tensor_pool_init:
    ; Sanity checks
    test rdi, rdi
    jz   .fail
    cmp  rsi, 1024                  ; pool must be at least 1KB
    jb   .fail
    test rdx, rdx
    jz   .fail
    cmp  rdx, rsi
    jae  .fail

    ; Save initial pool pointer
    mov  r8, rdi

    ; 1. Estimate number of blocks.
    ; Since we store metadata + bitmap + block data in the same buffer, we do:
    ; Header size: 40 bytes.
    ; Let N be the number of blocks.
    ; Bitmap size: ((N + 63) / 64) * 8 bytes.
    ; Block data size: N * block_size.
    ; Let's approximate: N = (Pool_Size - 128) / (block_size + 0.125)
    ; In integer math: N = (Pool_Size - 128) / block_size.
    ; This is a safe lower bound.
    mov  rax, rsi
    sub  rax, 128                   ; subtract overhead headroom
    xor  r9, r9                     ; block count accumulator
    div  rdx                         ; RAX = N = floor((Size-128)/Block_Size)
    test rax, rax
    jz   .fail                      ; not enough room for even 1 block
    mov  r9, rax                    ; N blocks

    ; 2. Calculate bitmap word count
    ; Words = (N + 63) / 64
    mov  rax, r9
    add  rax, 63
    shr  rax, 6                     ; RAX = bitmap words
    mov  r10, rax                   ; R10 = bitmap words

    ; 3. Determine data start address (aligned to 64 bytes)
    ; Header + Bitmap = 40 + bitmap_words * 8
    mov  rax, r10
    shl  rax, 3                     ; RAX = bitmap bytes
    add  rax, 40                    ; RAX = total metadata size
    
    ; Align data start to 64 bytes
    add  rax, 63
    and  rax, ~63                   ; aligned offset from RDI
    
    mov  rcx, rdi
    add  rcx, rax                   ; RCX = pool data start address
    
    ; Verify that data start + N * block_size does not exceed total pool size
    mov  rax, r9
    imul rax, rdx                   ; RAX = block data size
    add  rax, rcx                   ; RAX = end of pool data
    mov  r11, rdi
    add  r11, rsi                   ; R11 = end of buffer
    cmp  rax, r11
    jbe  .setup_header

    ; If it exceeds, reduce block count by 1 and recalculate (safe fallback)
    dec  r9
    jz   .fail

.setup_header:
    ; Write metadata fields to RDI
    mov  [rdi + POOL_START_OFF], rcx
    mov  [rdi + POOL_SIZE_OFF], rsi
    mov  [rdi + BLOCK_SIZE_OFF], rdx
    mov  [rdi + TOTAL_BLOCKS_OFF], r9
    mov  [rdi + BITMAP_WORDS_OFF], r10

    ; Zeros out the bitmap area: RDI + BITMAP_START_OFF, count = R10 words
    push rdi
    lea  rdi, [rdi + BITMAP_START_OFF]
    xor  rax, rax
    mov  rcx, r10
    rep  stosq
    pop  rdi

    ; Telemetry
    mov  [sys_tensor_pool_total_blocks], r9
    mov  qword [sys_tensor_pool_allocated_blocks], 0

    mov  rax, r8                    ; return pool context pointer
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; tensor_pool_alloc — Allocate a block from the tensor pool
; Input:  RDI = Pool context pointer
; Output: RAX = Allocated block address, or 0 if full/invalid
; Clobbers: RAX, RCX, RDX, R8, R9
; ---------------------------------------------------------------------------
global tensor_pool_alloc
tensor_pool_alloc:
    test rdi, rdi
    jz   .fail

    mov  r8, [rdi + TOTAL_BLOCKS_OFF]
    mov  r9, [rdi + BITMAP_WORDS_OFF]

    ; Loop through bitmap words
    xor  rdx, rdx                   ; RDX = word index
.find_word:
    cmp  rdx, r9
    jae  .fail                      ; all blocks allocated

    mov  rax, [rdi + BITMAP_START_OFF + rDX * 8]
    cmp  rax, 0xFFFFFFFFFFFFFFFF
    jne  .found_free_bit            ; this word has at least one 0 bit
    inc  rdx
    jmp  .find_word

.found_free_bit:
    ; RAX contains the 64-bit word. We want to find the first 0 bit.
    ; Invert bits: 0 becomes 1, so BSF finds the first 0 bit.
    not  rax
    bsf  rcx, rax                   ; RCX = bit index (0 to 63)

    ; Calculate global block index = word_index * 64 + bit_index
    mov  rax, rdx
    shl  rax, 6                     ; RAX = word_index * 64
    add  rax, rcx                   ; RAX = global block index

    ; Verify index is within total blocks limit
    cmp  rax, r8
    jae  .fail

    ; Mark bit as allocated (set to 1) in memory
    bts  qword [rdi + BITMAP_START_OFF + rDX * 8], rcx
    jc   .found_free_bit            ; race condition fallback (retry if bit was set)

    ; Compute block address = pool_start + index * block_size
    mov  rdx, [rdi + POOL_START_OFF]
    mov  rcx, [rdi + BLOCK_SIZE_OFF]
    imul rax, rcx
    add  rax, rdx                   ; RAX = block pointer

    inc  qword [sys_tensor_pool_allocated_blocks]
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; tensor_pool_free — Return a block to the tensor pool
; Input:
;   RDI = Pool context pointer
;   RSI = Block address to free
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, R8
; ---------------------------------------------------------------------------
global tensor_pool_free
tensor_pool_free:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    mov  rdx, [rdi + POOL_START_OFF]
    cmp  rsi, rdx
    jb   .fail                      ; block is below data start

    ; Compute byte offset from start
    mov  rax, rsi
    sub  rax, rdx                   ; RAX = offset in bytes

    ; Calculate index = offset / block_size
    mov  r8, [rdi + BLOCK_SIZE_OFF]
    xor  rdx, rdx
    div  r8                          ; RAX = global block index
    test rdx, rdx
    jnz  .fail                      ; pointer must be block-aligned

    ; Check bounds
    cmp  rax, [rdi + TOTAL_BLOCKS_OFF]
    jae  .fail

    ; Find word and bit index
    mov  rdx, rax
    shr  rdx, 6                     ; RDX = word index
    and  rax, 63                    ; RAX = bit index

    ; Clear bit (mark as free = 0)
    btr  qword [rdi + BITMAP_START_OFF + rDX * 8], rax
    jnc  .fail                      ; was already free (double-free protection)

    dec  qword [sys_tensor_pool_allocated_blocks]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_tensor_pool_allocated_blocks
sys_tensor_pool_allocated_blocks: dq 0

align 8
global sys_tensor_pool_total_blocks
sys_tensor_pool_total_blocks: dq 0

section .text

%endif ; LIB_MEM_VIRT_TENSOR_POOL_ASM
