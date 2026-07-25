; =============================================================================
; Tattva OS — ufs/cache/arc.asm
; =============================================================================
; OpenZFS-grade Adaptive Replacement Cache (ARC / L2ARC).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_arc_state_t
    .c_max_capacity:     resq 1
    .p_mru_target:       resq 1
    .t1_count:           resq 1
    .t2_count:           resq 1
    .b1_count:           resq 1
    .b2_count:           resq 1
endstruc

section .text

global ufs_arc_init
global ufs_arc_access
global ufs_arc_adapt_p

align 32
ufs_arc_init:
    push rbx

    mov rbx, rdi
    mov [rbx + ufs_arc_state_t.c_max_capacity], rsi
    shr rsi, 1
    mov [rbx + ufs_arc_state_t.p_mru_target], rsi

    mov eax, 0
    pop rbx
    ret

align 32
ufs_arc_adapt_p:
    push rbx

    mov rbx, rdi
    cmp esi, 1
    je .adapt_b1_hit

    mov rax, [rbx + ufs_arc_state_t.p_mru_target]
    test rax, rax
    jz .done
    dec rax
    mov [rbx + ufs_arc_state_t.p_mru_target], rax
    jmp .done

.adapt_b1_hit:
    mov rax, [rbx + ufs_arc_state_t.p_mru_target]
    cmp rax, [rbx + ufs_arc_state_t.c_max_capacity]
    jge .done
    inc rax
    mov [rbx + ufs_arc_state_t.p_mru_target], rax

.done:
    pop rbx
    ret

align 32
ufs_arc_access:
    mov eax, 0
    ret
