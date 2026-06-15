; =============================================================================
; Tattva OS — lib/mem/virt/zpool.asm
; =============================================================================
; Dynamic Zpool Balancing (Subfeature 28.2).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ZPOOL_ASM
%define LIB_MEM_VIRT_ZPOOL_ASM

[BITS 64]

section .text

; External VMM and physical memory symbols
extern phys_state

; -----------------------------------------------------------------------------
; zpool_balance — dynamically scales zswap and zram maximum slots
;                  based on free physical memory levels.
; -----------------------------------------------------------------------------
global zpool_balance
zpool_balance:
    push rax
    push rcx
    push rdx

    ; Calculate: percentage = (phys_state.free_pages * 100) / phys_state.total_pages
    mov rax, [phys_state + phys_state_t.free_pages]
    imul rax, 100
    mov rcx, [phys_state + phys_state_t.total_pages]
    test rcx, rcx
    jz .fallback

    xor rdx, rdx
    div rcx                     ; RAX = free percentage (0-100)

    ; Scale compression pools based on free memory percentage:
    ; - free memory > 50%: 100% capacity (256 slots)
    ; - 20% < free memory <= 50%: 50% capacity (128 slots)
    ; - free memory <= 20%: 25% capacity (64 slots)
    cmp rax, 50
    ja .high_mem

    cmp rax, 20
    ja .mid_mem

.low_mem:
    mov qword [zswap_max_slots], 64
    mov qword [zram_max_slots], 64
    jmp .done

.mid_mem:
    mov qword [zswap_max_slots], 128
    mov qword [zram_max_slots], 128
    jmp .done

.high_mem:
.fallback:
    mov qword [zswap_max_slots], 256
    mov qword [zram_max_slots], 256

.done:
    pop rdx
    pop rcx
    pop rax
    ret

section .data

global zswap_max_slots
global zram_max_slots

align 8
zswap_max_slots: dq 256
zram_max_slots:  dq 256

%endif ; LIB_MEM_VIRT_ZPOOL_ASM
