; =============================================================================
; Tattva OS — lib/mem/virt/mte.asm
; =============================================================================
; Memory Tagging Extension (MTE) — Subfeature 35.5.
;
; Implements hardware memory tagging simulation. MTE allocates 4-bit tags
; for each 16-byte memory granule (allocation tag), and embeds a 4-bit logical
; tag in the top byte of pointers (bits 59:56). Comparisons catch out-of-bounds
; access and use-after-free faults.
;
; Physical Memory Limit covered by tag store: 64 MB (2MB tag store size).
;
; API:
;   mte_detect()                     — Probe MTE capability.
;   mte_init()                       — Zeros the tag store and enables simulation.
;   mte_set_granule_tag(addr, tag)   — Set 4-bit tag for 16-byte granule.
;   mte_get_granule_tag(addr)        — Get 4-bit tag for 16-byte granule.
;   mte_validate_ptr(ptr)            — Compare logical tag in ptr with memory tag.
;                                      Returns 1 if valid, 0 if mismatch (fault).
;   mte_tag_page(addr, tag)          — Set tag for all granules in a 4KB page.
;   mte_tag_free_page(addr)          — Tag page as free (tag 0xF) to catch UAF.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_MTE_ASM
%define LIB_MEM_VIRT_MTE_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
MTE_LIMIT_MEM           equ 67108864    ; 64 MB physical memory limit
MTE_TAG_STORE_SIZE      equ 2097152     ; 2 MB tag store (4 bits per 16B granule)
MTE_FREE_TAG            equ 0x0F        ; Tag 15 marks freed/unallocated memory

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; mte_detect — Probe MTE capability
; Output: RAX = 1 if supported, 0 otherwise
; ---------------------------------------------------------------------------
global mte_detect
mte_detect:
    mov  rax, [sys_mte_supported]
    ret

; ---------------------------------------------------------------------------
; mte_init — Initialise the tag store and enable MTE
; Output: RAX = 1 on success
; Clobbers: RAX, RCX, RDI
; ---------------------------------------------------------------------------
global mte_init
mte_init:
    push rdi
    push rcx

    ; Set MTE supported/active flags for simulation
    mov  qword [sys_mte_supported], 1
    mov  qword [sys_mte_active], 1

    ; Zero out the entire 2MB tag store
    lea  rdi, [mte_tag_store]
    xor  rax, rax
    mov  rcx, MTE_TAG_STORE_SIZE / 8
    rep  stosq

    mov  qword [sys_mte_tagged_pages], 0
    mov  qword [sys_mte_tag_faults], 0

    mov  rax, 1
    pop  rcx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; mte_set_granule_tag — Set 4-bit allocation tag for a 16-byte granule
; Input:
;   RDI = memory address
;   RSI = 4-bit tag (0x00 to 0x0F)
; Output: RAX = 1 on success, 0 on out-of-bounds
; Clobbers: RAX, RCX, RDX, R8
; ---------------------------------------------------------------------------
global mte_set_granule_tag
mte_set_granule_tag:
    ; Strip any logical tags in bits 63:56 of address
    mov  rax, rdi
    and  rax, 0x00FFFFFFFFFFFFFF        ; clear logical tag bits
    cmp  rax, MTE_LIMIT_MEM - 1
    ja   .fail                          ; address out of tag store limit

    ; Compute granule index: index = address / 16
    shr  rax, 4

    ; byte index = index / 2
    mov  rcx, rax
    shr  rcx, 1

    ; check if low or high nibble (index & 1)
    and  rax, 1
    jnz  .high_nibble

    ; Low nibble (even index)
    lea  r8, [mte_tag_store]
    movzx rdx, byte [r8 + rcx]
    and  rdx, 0xF0                      ; clear low nibble
    and  rsi, 0x0F                      ; sanitize tag
    or   rdx, rsi
    mov  [r8 + rcx], dl
    jmp  .success

.high_nibble:
    ; High nibble (odd index)
    lea  r8, [mte_tag_store]
    movzx rdx, byte [r8 + rcx]
    and  rdx, 0x0F                      ; clear high nibble
    and  rsi, 0x0F                      ; sanitize tag
    shl  rsi, 4
    or   rdx, rsi
    mov  [r8 + rcx], dl

.success:
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; mte_get_granule_tag — Get 4-bit allocation tag for a 16-byte granule
; Input:
;   RDI = memory address
; Output: RAX = 4-bit tag (0-15), or 0 if OOB
; Clobbers: RAX, RCX, R8
; ---------------------------------------------------------------------------
global mte_get_granule_tag
mte_get_granule_tag:
    mov  rax, rdi
    and  rax, 0x00FFFFFFFFFFFFFF
    cmp  rax, MTE_LIMIT_MEM - 1
    ja   .fail

    shr  rax, 4
    mov  rcx, rax
    shr  rcx, 1                         ; byte index

    and  rax, 1
    jnz  .high_nibble

    ; Low nibble
    lea  r8, [mte_tag_store]
    movzx rax, byte [r8 + rcx]
    and  rax, 0x0F
    ret

.high_nibble:
    ; High nibble
    lea  r8, [mte_tag_store]
    movzx rax, byte [r8 + rcx]
    shr  rax, 4
    and  rax, 0x0F
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; mte_validate_ptr — Validate logical tag in pointer vs memory allocation tag
; Input:
;   RDI = tagged pointer (logical tag in bits 59:56)
; Output: RAX = 1 if valid, 0 if tag mismatch (faults logged)
; Clobbers: RAX, RDX
; ---------------------------------------------------------------------------
global mte_validate_ptr
mte_validate_ptr:
    push rbx
    push rdi

    ; 1. Extract logical tag: logical = (ptr >> 56) & 0x0F
    mov  rax, rdi
    shr  rax, 56
    and  rax, 0x0F
    mov  rbx, rax                       ; RBX = logical tag

    ; 2. Fetch allocation tag at the untagged address
    ; RDI is already the pointer
    call mte_get_granule_tag            ; RAX = allocation tag
    
    ; 3. Compare logical tag (RBX) with allocation tag (RAX)
    cmp  rax, rbx
    je   .valid

    ; Tag mismatch -> log fault
    inc  qword [sys_mte_tag_faults]
    xor  rax, rax                       ; invalid
    jmp  .done

.valid:
    mov  rax, 1                         ; valid

.done:
    pop  rdi
    pop  rbx
    ret

; ---------------------------------------------------------------------------
; mte_tag_page — Set tag for all granules (256 of 16B) in a 4KB page
; Input:
;   RDI = page address (must be 4KB page-aligned)
;   RSI = 4-bit tag (0x00 to 0x0F)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RDI
; ---------------------------------------------------------------------------
global mte_tag_page
mte_tag_page:
    mov  rax, rdi
    and  rax, 0x00FFFFFFFFFFFFFF
    cmp  rax, MTE_LIMIT_MEM - 1
    ja   .fail

    ; A 4KB page maps to exactly 128 bytes in the tag store.
    ; Offset in tag store = (page_address / 16) / 2 = page_address / 32.
    shr  rax, 5                         ; RAX = offset in mte_tag_store

    ; Build byte fill value: (tag & 0xF) | ((tag & 0xF) << 4)
    and  rsi, 0x0F
    mov  rdx, rsi
    shl  rdx, 4
    or   rdx, rsi                       ; RDX = byte value

    ; Set 128 bytes starting at mte_tag_store + RAX
    lea  rdi, [mte_tag_store + rax]
    mov  rax, rdx
    ; replicate byte RAX to RCX = 16 qwords (128 bytes)
    ; AL already contains the byte. Duplicate to make full qword:
    mov  ah, al
    movzx rdx, ax
    shl  rdx, 16
    or   rax, rdx
    mov  rdx, rax
    shl  rdx, 32
    or   rax, rdx                       ; RAX = qword fill pattern

    mov  rcx, 16                        ; 16 qwords = 128 bytes
    rep  stosq

    inc  qword [sys_mte_tagged_pages]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; mte_tag_free_page — Tag all granules in page with MTE_FREE_TAG (0x0F)
; Input:
;   RDI = page address (4KB aligned)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RDI, RSI
; ---------------------------------------------------------------------------
global mte_tag_free_page
mte_tag_free_page:
    mov  rsi, MTE_FREE_TAG
    call mte_tag_page
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_mte_supported
sys_mte_supported:      dq 0        ; set to 1 on initialisation

align 8
global sys_mte_active
sys_mte_active:         dq 0        ; set to 1 on initialisation

align 8
global sys_mte_tagged_pages
sys_mte_tagged_pages:   dq 0        ; statistics

align 8
global sys_mte_tag_faults
sys_mte_tag_faults:     dq 0        ; count of tag mismatch detections

; ---------------------------------------------------------------------------
; BSS — Tag store: 2 MB covering 64 MB of physical memory
; ---------------------------------------------------------------------------
section .bss

align 64
global mte_tag_store
mte_tag_store:          resb MTE_TAG_STORE_SIZE

section .text

%endif ; LIB_MEM_VIRT_MTE_ASM
