; =============================================================================
; Tattva OS — lib/hw/unuma/affinity.asm
; =============================================================================
; NUMA-aware placement decisions built on unuma_node_of_cpu (detect.asm) and
; lib/mem/numa's numa_get_node_by_phys. Scoped to the currently executing
; core: the kernel boots single-core today (kernel/entry/start.asm's
; bsp_cpu_local is one static percpu_t, not a table), so there is no live
; cpu_id -> APIC-ID map for other cores yet to build a multi-core "closest
; free CPU for this address" query on top of. gs:percpu_t.lapic_id is the
; only per-core identity that reliably exists right now.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UNUMA_AFFINITY_ASM
%define LIB_HW_UNUMA_AFFINITY_ASM

%include "lib/percpu.inc"
%include "lib/hw/unuma/detect.asm"

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; unuma_cpu_is_local_to_addr — checks whether a CPU is on the node that owns
; a physical address
; Input:
;   RDI = apic_id (x2APIC ID), RSI = physical address
; Output:
;   RAX = 1 if the CPU's SRAT node matches the address's SRAT node,
;         0 if either is unknown or they differ
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global unuma_cpu_is_local_to_addr
unuma_cpu_is_local_to_addr:
    push rbx
    push r12

    mov rbx, rsi                    ; RBX = physical address (RSI is an
                                     ; output register on the call below)

    call unuma_node_of_cpu          ; RDI = apic_id (unchanged)
    test rax, rax
    jz .no
    mov r12d, esi                   ; R12D = cpu_node_id

    mov rdi, rbx                    ; physical address
    call numa_get_node_by_phys      ; RAX = addr_node_id

    cmp eax, r12d
    jne .no

    mov rax, 1
    jmp .done

.no:
    xor rax, rax

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unuma_current_node — NUMA node of the currently executing core, per SRAT
; Input:  none
; Output:
;   RAX = 1 if known, 0 if this core's APIC ID never appeared in SRAT
;   RSI = node_id (only meaningful if RAX = 1)
; -----------------------------------------------------------------------------
global unuma_current_node
unuma_current_node:
    mov edi, [gs:percpu_t.lapic_id]
    jmp unuma_node_of_cpu           ; tail call: same output contract

; -----------------------------------------------------------------------------
; unuma_alloc_should_prefer_local — should an allocator try the local node
; before falling back to a remote one for this physical address?
; Input:
;   RDI = physical address
; Output:
;   RAX = 1 if the current core's SRAT node matches the address's SRAT node
;         or either is unknown (fail open: no SRAT data means no NUMA
;         penalty is known, so there is nothing to route around), 0 if they
;         are known and differ
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R12
; -----------------------------------------------------------------------------
global unuma_alloc_should_prefer_local
unuma_alloc_should_prefer_local:
    push rbx

    mov ebx, [gs:percpu_t.lapic_id]
    mov rsi, rdi                    ; physical address -> arg 2
    mov rdi, rbx                    ; apic_id -> arg 1
    call unuma_cpu_is_local_to_addr
    test rax, rax
    jnz .yes                        ; confirmed local match

    ; Not a confirmed local match — distinguish "known remote" from
    ; "unknown" (unknown fails open: no SRAT data means no known penalty).
    mov edi, ebx
    call unuma_node_of_cpu
    test rax, rax
    jz .yes                         ; this core's node is unknown -> fail open
    jmp .no                         ; this core's node IS known and the
                                     ; match above already said it differs

.yes:
    mov rax, 1
    jmp .done

.no:
    xor rax, rax

.done:
    pop rbx
    ret

%endif ; LIB_HW_UNUMA_AFFINITY_ASM
