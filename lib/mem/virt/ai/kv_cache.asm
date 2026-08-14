%ifndef GUARD_LIB_MEM_VIRT_AI_KV_CACHE_ASM
%define GUARD_LIB_MEM_VIRT_AI_KV_CACHE_ASM
; =============================================================================
; Tattva OS — lib/mem/virt/kv_cache.asm
; =============================================================================
; KV Cache Physical Allocator — Subfeature 36.3.
;
; Manages physically contiguous allocations for Key-Value (KV) cache blocks
; to guarantee compatibility with PagedAttention engines.
; Implements a 16MB contiguous block area (4096 pages) tracked via a bitmap.
;
; TurboQuant 3.5-bit Packing Layout:
;   Packs 8 elements (0-11 values) into a 28-bit structure inside a 32-bit dword.
;   Each element E_i is split into a 3-bit base (E_i & 7) and a 1-bit fraction (E_i >> 3).
;   - Bits 0-23: Eight 3-bit bases (8 * 3 = 24 bits)
;   - Bits 24-31: Eight 1-bit fractions (8 * 1 = 8 bits)
;   - Total = 32 bits (4 bytes) per 8 elements (exactly 3.5 bits average active space).
;
; API:
;   kv_cache_init()                     — Initialise the KV Cache allocator.
;   kv_cache_alloc_block(pages)         — Allocate contiguous physical pages.
;   kv_cache_free_block(addr, pages)    — Free contiguous physical pages.
;   kv_cache_pack_turboquant(src, dst, cnt)  — Pack bytes into 3.5-bit TurboQuant.
;   kv_cache_unpack_turboquant(src, dst, cnt)— Unpack 3.5-bit TurboQuant to bytes.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_KV_CACHE_ASM
%define LIB_MEM_VIRT_KV_CACHE_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
KV_CACHE_BASE_ADDR      equ 0x20000000  ; 512 MB physical base
KV_CACHE_TOTAL_PAGES    equ 4096        ; 16 MB size (4096 * 4096)
KV_CACHE_BITMAP_QWORDS  equ 64          ; 64 * 64 bits = 4096 pages

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; kv_cache_init — Initialize the KV Cache allocator bitmap
; Output: RAX = 1
; Clobbers: RAX, RCX, RDI
; ---------------------------------------------------------------------------
global kv_cache_init
kv_cache_init:
    push rdi
    push rcx

    lea  rdi, [kv_cache_bitmap]
    xor  rax, rax
    mov  rcx, KV_CACHE_BITMAP_QWORDS
    rep  stosq

    mov  qword [sys_kv_cache_allocated_blocks], 0
    mov  qword [sys_kv_cache_contiguous_pages], 0

    mov  rax, 1
    pop  rcx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; kv_cache_alloc_block — Allocate contiguous pages from the KV cache pool
; Input:  RDI = Page count (contiguous block size requested)
; Output: RAX = Physical base address of the allocated block, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, R8, R9, R10
; ---------------------------------------------------------------------------
global kv_cache_alloc_block
kv_cache_alloc_block:
    test rdi, rdi
    jz   .fail
    cmp  rdi, KV_CACHE_TOTAL_PAGES
    ja   .fail

    mov  r8, rdi                    ; R8 = requested page count
    lea  r9, [kv_cache_bitmap]

    ; Scan bitmap for R8 contiguous 0 bits
    xor  rax, rax                   ; RAX = current bit index
.scan_loop:
    mov  rbx, rax
    add  rbx, r8
    cmp  rbx, KV_CACHE_TOTAL_PAGES
    ja   .fail                      ; out of bounds

    ; Check if all bits from RAX to RAX+R8-1 are 0
    xor  rcx, rcx                   ; RCX = index in block
.check_block:
    mov  rdx, rax
    add  rdx, rcx                   ; bit index to check
    mov  r10, rdx
    shr  r10, 6                     ; word index (rdx / 64)
    and  rdx, 63                    ; bit index in word
    bt   [r9 + r10 * 8], rdx
    jc   .block_failed              ; bit is 1, not free

    inc  rcx
    cmp  rcx, r8
    jb   .check_block

    ; Found contiguous free block starting at RAX!
    ; Mark them all as 1
    xor  rcx, rcx
.mark_allocated:
    mov  rdx, rax
    add  rdx, rcx
    mov  r10, rdx
    shr  r10, 6
    and  rdx, 63
    bts  [r9 + r10 * 8], rdx
    inc  rcx
    cmp  rcx, r8
    jb   .mark_allocated

    ; Calculate physical address: Base + start_bit * 4096
    mov  rcx, rax
    shl  rcx, 12                    ; start_bit * 4096
    mov  rax, KV_CACHE_BASE_ADDR
    add  rax, rcx                   ; RAX = physical address

    inc  qword [sys_kv_cache_allocated_blocks]
    add  [sys_kv_cache_contiguous_pages], r8

    ret

.block_failed:
    ; Increment search pointer to next scan point
    add  rax, rcx                   ; skip past the checked failed bit
    inc  rax
    jmp  .scan_loop

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; kv_cache_free_block — Release a contiguous block
; Input:
;   RDI = Physical base address
;   RSI = Page count
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, R8, R9, R10
; ---------------------------------------------------------------------------
global kv_cache_free_block
kv_cache_free_block:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    ; Calculate starting page index
    mov  rax, rdi
    mov  rdx, KV_CACHE_BASE_ADDR
    cmp  rax, rdx
    jb   .fail
    sub  rax, rdx
    test rax, 4095
    jnz  .fail                      ; must be page-aligned

    shr  rax, 12                    ; RAX = start page index
    mov  r8, rax
    add  rax, rsi
    cmp  rax, KV_CACHE_TOTAL_PAGES
    ja   .fail

    lea  r9, [kv_cache_bitmap]

    ; Unmark bits as 0
    xor  rcx, rcx
.mark_free:
    mov  rdx, r8
    add  rdx, rcx
    mov  r10, rdx
    shr  r10, 6
    and  rdx, 63
    btr  [r9 + r10 * 8], rdx
    jnc  .fail                      ; was already free (sanity check fail)
    inc  rcx
    cmp  rcx, rsi
    jb   .mark_free

    dec  qword [sys_kv_cache_allocated_blocks]
    sub  [sys_kv_cache_contiguous_pages], rsi
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; kv_cache_pack_turboquant — Pack bytes (8 elements) into 3.5-bit (32-bit dword)
; Input:
;   RDI = Source byte buffer (elements 0 to 11)
;   RSI = Destination dword buffer
;   RDX = Element count (must be multiple of 8)
; Output: RAX = Packed dword count on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
; ---------------------------------------------------------------------------
global kv_cache_pack_turboquant
kv_cache_pack_turboquant:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdx, rdx
    jz   .fail
    test rdx, 7                     ; must be multiple of 8
    jnz  .fail

    mov  rcx, rdx
    shr  rcx, 3                     ; number of 8-element groups
    mov  r11, rcx                   ; save group count
    xor  r10, r10                   ; index of source byte

.group_loop:
    xor  eax, eax                   ; build packed dword in EAX

    ; Process 8 elements (i = 0..7)
    xor  r9, r9                     ; loop index for group (0..7)
.pack_element:
    movzx ebx, byte [rdi + r10]     ; EBX = element value (0-11)
    and  ebx, 0x0F                  ; sanitize
    
    ; 1. Pack 3-bit base into bits [3*i .. 3*i+2]
    mov  r8, rbx
    and  r8, 7                      ; R8 = 3-bit base
    
    push rcx
    ; shift base into position: shift = r9 * 3
    mov  rax, r9
    imul rax, 3
    mov  rcx, rax
    shl  r8, cl
    pop  rcx
    or   eax, r8d                   ; merge base

    ; 2. Pack 1-bit fraction into bits [24 + i]
    mov  r8, rbx
    shr  r8, 3                      ; R8 = 1-bit fraction (bit 3)
    and  r8, 1
    
    push rcx
    ; shift fraction: shift = 24 + r9
    mov  rax, 24
    add  rax, r9
    mov  rcx, rax
    shl  r8, cl
    pop  rcx
    or   eax, r8d                   ; merge fraction

    inc  r10
    inc  r9
    cmp  r9, 8
    jb   .pack_element

    ; Write packed dword to destination
    mov  [rsi], eax
    add  rsi, 4                     ; advance destination by 4 bytes (1 dword)
    loop .group_loop

    mov  rax, r11                   ; return packed dword count
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; kv_cache_unpack_turboquant — Unpack 32-bit dwords into bytes
; Input:
;   RDI = Source packed dword buffer
;   RSI = Destination byte buffer
;   RDX = Element count (must be multiple of 8)
; Output: RAX = Unpacked elements count, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI, R8, R9, R10, R11
; ---------------------------------------------------------------------------
global kv_cache_unpack_turboquant
kv_cache_unpack_turboquant:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdx, rdx
    jz   .fail
    test rdx, 7
    jnz  .fail

    mov  rcx, rdx
    shr  rcx, 3                     ; number of 8-element groups
    mov  r11, rdx                   ; return count
    xor  r10, r10                   ; index of destination byte

.group_loop:
    mov  eax, [rdi]                 ; EAX = packed dword
    add  rdi, 4                     ; advance source pointer

    xor  r9, r9                     ; loop index (0..7)
.unpack_element:
    ; 1. Extract 3-bit base from bits [3*i .. 3*i+2]
    push rcx
    mov  rax, r9
    imul rax, 3
    mov  rcx, rax
    mov  ebx, [rdi - 4]             ; reload dword
    shr  ebx, cl
    and  ebx, 7                     ; EBX = base
    pop  rcx

    ; 2. Extract 1-bit fraction from bits [24 + i]
    push rcx
    mov  rax, 24
    add  rax, r9
    mov  rcx, rax
    mov  r8d, [rdi - 4]             ; reload
    shr  r8d, cl
    and  r8d, 1                     ; R8D = fraction
    pop  rcx

    ; Reconstruct: E = base + (fraction << 3)
    shl  r8d, 3
    or   ebx, r8d                   ; EBX = reconstructed element

    ; Write to destination byte
    mov  [rsi + r10], bl

    inc  r10
    inc  r9
    cmp  r9, 8
    jb   .unpack_element

    loop .group_loop

    mov  rax, r11
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_kv_cache_allocated_blocks
sys_kv_cache_allocated_blocks: dq 0

align 8
global sys_kv_cache_contiguous_pages
sys_kv_cache_contiguous_pages: dq 0

; ---------------------------------------------------------------------------
; BSS — KV Cache bitmap (64 Qwords = 4096 bits)
; ---------------------------------------------------------------------------
section .bss

alignb 64
kv_cache_bitmap:        resb (KV_CACHE_BITMAP_QWORDS * 8)

section .text

%endif ; LIB_MEM_VIRT_KV_CACHE_ASM

%endif ; GUARD_LIB_MEM_VIRT_AI_KV_CACHE_ASM
