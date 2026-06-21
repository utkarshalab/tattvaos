; =============================================================================
; Tattva OS — lib/mem/virt/ras_poison.asm
; =============================================================================
; Poison Page Handling — Subfeature 38.3.
;
; Isolates hardware-faulty physical memory frames by setting their index in a
; persistent poison bitmap. The page allocator checks this bitmap before vending
; any frame, ensuring faulty pages are never reallocated.
;
; Capacity: Up to 65536 physical pages (256MB range).
;
; API:
;   ras_poison_page(phys_addr)      — Permanently mark page as poisoned.
;   ras_is_poisoned(phys_addr)      — Query if a physical page is poisoned.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RAS_POISON_ASM
%define LIB_MEM_VIRT_RAS_POISON_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
POISON_BITMAP_SIZE      equ 8192    ; 8192 bytes = 65536 bits (covers 256MB)

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; ras_poison_page — Quarantine a hardware-faulty physical page
; Input:  RDI = Physical address (page-aligned)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RDX
; ---------------------------------------------------------------------------
global ras_poison_page
ras_poison_page:
    mov  rax, rdi
    cmp  rax, 0x100000000           ; check limits (4GB)
    jae  .fail

    shr  rax, 12                    ; RAX = page index
    cmp  rax, (POISON_BITMAP_SIZE * 8)
    jae  .fail                      ; index out of bitmap boundary

    mov  rbx, rax
    shr  rbx, 6                     ; RBX = Qword index
    and  rax, 63                    ; RAX = bit index inside Qword

    lea  rdx, [sys_ras_poison_bitmap]
    bts  qword [rdx + rbx * 8], rax
    jc   .already_poisoned          ; already set

    inc  qword [sys_ras_poisoned_pages]

.already_poisoned:
    ; Simulates permanent removal from the buddy allocator availability arrays:
    ; In Tattva OS, we could query the buddy free list block and mark it allocated/unavailable.
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; ras_is_poisoned — Query if a page is marked as hardware-faulty
; Input:  RDI = Physical address
; Output: RAX = 1 if poisoned, 0 if healthy
; Clobbers: RAX, RBX, RDX
; ---------------------------------------------------------------------------
global ras_is_poisoned
ras_is_poisoned:
    mov  rax, rdi
    shr  rax, 12                    ; RAX = page index
    cmp  rax, (POISON_BITMAP_SIZE * 8)
    jae  .not_poisoned

    mov  rbx, rax
    shr  rbx, 6                     ; RBX = Qword index
    and  rax, 63                    ; RAX = bit index inside Qword

    lea  rdx, [sys_ras_poison_bitmap]
    bt   [rdx + rbx * 8], rax
    jc   .poisoned

.not_poisoned:
    xor  rax, rax
    ret

.poisoned:
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_ras_poisoned_pages
sys_ras_poisoned_pages:         dq 0

; ---------------------------------------------------------------------------
; BSS — Poison bitmap
; ---------------------------------------------------------------------------
section .bss

align 64
sys_ras_poison_bitmap:          resb POISON_BITMAP_SIZE

section .text

%endif ; LIB_MEM_VIRT_RAS_POISON_ASM
