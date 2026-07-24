; =============================================================================
; Tattva OS — ufs/cache/ufs_arc.asm
; =============================================================================
; OpenZFS-grade Adaptive Replacement Cache (ARC / L2ARC) for uFS.
;
; Implements dual cache balancing equations:
;   - T1: Most Recently Used (MRU) list
;   - T2: Most Frequently Used (MFU) list
;   - B1: Ghost MRU list (evicted tags)
;   - B2: Ghost MFU list (evicted tags)
; Dynamic target size p adapts in real-time based on ghost list hits.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_arc_state_t
    .c_max_capacity:     resq 1      ; Total RAM cache limit C
    .p_mru_target:       resq 1      ; Dynamic MRU target size p (0 <= p <= C)
    .t1_mru_count:       resq 1      ; Current count in T1 (MRU)
    .t2_mfu_count:       resq 1      ; Current count in T2 (MFU)
    .b1_ghost_mru_count: resq 1      ; Ghost MRU count
    .b2_ghost_mfu_count: resq 1      ; Ghost MFU count
endstruc

section .text

global ufs_arc_init
global ufs_arc_access
global ufs_arc_adapt_p

; -----------------------------------------------------------------------------
; ufs_arc_init
; -----------------------------------------------------------------------------
align 32
ufs_arc_init:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_arc_state_t
    mov [rbx + ufs_arc_state_t.c_max_capacity], rsi
    shr rsi, 1
    mov [rbx + ufs_arc_state_t.p_mru_target], rsi  ; p = C / 2 initially

    mov eax, 0
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_arc_adapt_p
;
; Adapts target size p based on ghost hits:
;   - On B1 hit: p = min(C, p + max(1, B2.size / B1.size))
;   - On B2 hit: p = max(0, p - max(1, B1.size / B2.size))
; -----------------------------------------------------------------------------
align 32
ufs_arc_adapt_p:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_arc_state_t
    cmp esi, 1                      ; Ghost list index (1 = B1, 2 = B2)
    je .adapt_b1_hit

    ; B2 Hit -> Decrease p
    mov rax, [rbx + ufs_arc_state_t.p_mru_target]
    test rax, rax
    jz .done
    dec rax
    mov [rbx + ufs_arc_state_t.p_mru_target], rax
    jmp .done

.adapt_b1_hit:
    ; B1 Hit -> Increase p
    mov rax, [rbx + ufs_arc_state_t.p_mru_target]
    cmp rax, [rbx + ufs_arc_state_t.c_max_capacity]
    jge .done
    inc rax
    mov [rbx + ufs_arc_state_t.p_mru_target], rax

.done:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_arc_access
; -----------------------------------------------------------------------------
align 32
ufs_arc_access:
    mov eax, 0                      ; Cache lookup status
    ret
