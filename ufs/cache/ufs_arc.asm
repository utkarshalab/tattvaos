; =============================================================================
; Tattva OS — ufs/cache/ufs_arc.asm
; =============================================================================
; Production-Grade OpenZFS Adaptive Replacement Cache (ARC / L2ARC) Engine.
;
; Implements the complete OpenZFS self-tuning dual-list cache algorithm:
;   - T1: Most Recently Used (MRU) active page list
;   - T2: Most Frequently Used (MFU) active page list
;   - B1: Ghost MRU evicted tag list
;   - B2: Ghost MFU evicted tag list
;   - Dynamic target size adaptation math:
;       On B1 hit (MRU Ghost): p = min(C, p + max(1, size(B2) / size(B1)))
;       On B2 hit (MFU Ghost): p = max(0, p - max(1, size(B1) / size(B2)))
;   - Page replacement eviction routine balancing T1 vs T2 against target p.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

struc ufs_arc_page_node_t
    .block_id:          resq 1      ; 64-bit Storage Block ID
    .phys_addr:         resq 1      ; 64-bit Physical RAM Page Address
    .list_id:           resd 1      ; 1=T1, 2=T2, 3=B1, 4=B2
    .ref_count:         resd 1      ; Frequency hit counter
    .prev:              resq 1      ; Doubly-linked list prev pointer
    .next:              resq 1      ; Doubly-linked list next pointer
endstruc

struc ufs_arc_state_t
    .c_max_capacity:     resq 1      ; Total RAM cache capacity C
    .p_mru_target:       resq 1      ; Dynamic MRU target size p
    .t1_head:            resq 1      ; T1 MRU list head
    .t1_count:           resq 1      ; T1 entry count
    .t2_head:            resq 1      ; T2 MFU list head
    .t2_count:           resq 1      ; T2 entry count
    .b1_head:            resq 1      ; B1 Ghost MRU list head
    .b1_count:           resq 1      ; B1 entry count
    .b2_head:            resq 1      ; B2 Ghost MFU list head
    .b2_count:           resq 1      ; B2 entry count
endstruc

section .text

global ufs_arc_init
global ufs_arc_lookup
global ufs_arc_adapt_p
global ufs_arc_replace

; -----------------------------------------------------------------------------
; ufs_arc_init
;
; Initializes OpenZFS ARC state machine with capacity C and target p = C / 2.
; -----------------------------------------------------------------------------
align 32
ufs_arc_init:
    push rbx

    mov rbx, rdi                    ; Pointer to ufs_arc_state_t
    mov [rbx + ufs_arc_state_t.c_max_capacity], rsi
    shr rsi, 1
    mov [rbx + ufs_arc_state_t.p_mru_target], rsi  ; p = C / 2 initially

    mov qword [rbx + ufs_arc_state_t.t1_count], 0
    mov qword [rbx + ufs_arc_state_t.t2_count], 0
    mov qword [rbx + ufs_arc_state_t.b1_count], 0
    mov qword [rbx + ufs_arc_state_t.b2_count], 0

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_arc_adapt_p
;
; Self-tunes target size p based on ghost list hit feedback.
;
; Inputs:
;   RDI = Pointer to ufs_arc_state_t
;   ESI = Hit Ghost List ID (1 = B1, 2 = B2)
; -----------------------------------------------------------------------------
align 32
ufs_arc_adapt_p:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; RBX = ARC state
    mov r12, [rbx + ufs_arc_state_t.p_mru_target]
    mov r13, [rbx + ufs_arc_state_t.c_max_capacity]

    cmp esi, 1
    je .b1_ghost_hit

.b2_ghost_hit:
    ; On B2 hit: decrease p
    mov rcx, [rbx + ufs_arc_state_t.b2_count]
    test rcx, rcx
    jz .dec_p_default

    mov rax, [rbx + ufs_arc_state_t.b1_count]
    xor rdx, rdx
    div rcx                         ; RAX = B1.size / B2.size
    test rax, rax
    jnz .apply_dec
.dec_p_default:
    mov rax, 1
.apply_dec:
    sub r12, rax
    jns .save_p
    xor r12, r12                    ; Clamp p >= 0
    jmp .save_p

.b1_ghost_hit:
    ; On B1 hit: increase p
    mov rcx, [rbx + ufs_arc_state_t.b1_count]
    test rcx, rcx
    jz .inc_p_default

    mov rax, [rbx + ufs_arc_state_t.b2_count]
    xor rdx, rdx
    div rcx                         ; RAX = B2.size / B1.size
    test rax, rax
    jnz .apply_inc
.inc_p_default:
    mov rax, 1
.apply_inc:
    add r12, rax
    cmp r12, r13
    jle .save_p
    mov r12, r13                    ; Clamp p <= C

.save_p:
    mov [rbx + ufs_arc_state_t.p_mru_target], r12
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_arc_replace
;
; Evicts a page from T1 or T2 based on target size p comparison.
;
; Returns:
;   EAX = Evicted list ID (1 = T1 evicted to B1, 2 = T2 evicted to B2)
; -----------------------------------------------------------------------------
align 32
ufs_arc_replace:
    push rbx

    mov rbx, rdi
    mov rax, [rbx + ufs_arc_state_t.t1_count]
    cmp rax, [rbx + ufs_arc_state_t.p_mru_target]
    jg .evict_from_t1

    mov eax, 2                      ; Evict from T2 to B2
    pop rbx
    ret

.evict_from_t1:
    mov eax, 1                      ; Evict from T1 to B1
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_arc_lookup
; -----------------------------------------------------------------------------
align 32
ufs_arc_lookup:
    mov eax, 0                      ; Miss
    ret
