; =============================================================================
; Tattva OS — lib/hw/ucpu/pinning.asm
; =============================================================================
; Topology-aware core selection: SMT sibling queries, LLC-domain grouping,
; and affinity-mask construction — built on the decode table populated by
; ucpu_topology_decode_current (topology.asm). Carries no NUMA or scheduler
; dependency; callers combine this with lib/mem/numa for memory-aware
; placement and with kernel/sched for the actual context switch.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UCPU_PINNING_ASM
%define LIB_HW_UCPU_PINNING_ASM

%include "lib/percpu.inc"
%include "lib/hw/ucpu/topology.asm"

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; ucpu_are_smt_siblings — checks whether two CPUs are SMT threads of one core
; Input:
;   RDI = cpu_a, RSI = cpu_b
; Output:
;   RAX = 1 if same core_id and package_id with differing smt_id, else 0
; Clobbers: RAX, RCX, RDX, R8-R11
; -----------------------------------------------------------------------------
global ucpu_are_smt_siblings
ucpu_are_smt_siblings:
    push rbx
    push r12

    mov r12, rsi                    ; R12 = cpu_b (RDI/RSI get clobbered by the first call)

    call ucpu_topology_get          ; RDI = cpu_a
    test rax, rax
    jz .no
    ; ucpu_topology_get clobbers R8 internally, so the saved smt_id_a must
    ; live in a register outside its own clobber list (R9-R11 are safe).
    mov r9, rsi                     ; R9 = smt_id_a
    mov r10, rdx                    ; R10 = core_id_a
    mov r11, rcx                    ; R11 = package_id_a

    mov rdi, r12
    call ucpu_topology_get          ; RDI = cpu_b
    test rax, rax
    jz .no

    cmp rdx, r10                    ; core_id_b == core_id_a ?
    jne .no
    cmp rcx, r11                    ; package_id_b == package_id_a ?
    jne .no
    cmp rsi, r9                     ; smt_id_b != smt_id_a (distinct threads)
    je .no

    mov rax, 1
    jmp .done

.no:
    xor rax, rax

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ucpu_share_llc — approximates whether two CPUs share a last-level cache
; domain. Scoped to package granularity: correct for single-LLC-domain-per-
; socket parts; multi-die/CCX packages need a finer per-cluster ID that leaf
; 0x1F's Module/Tile levels would supply if decoded (topology.asm currently
; decodes SMT/Core/Package only — see uhwloc for a future extension point).
; Input:
;   RDI = cpu_a, RSI = cpu_b
; Output:
;   RAX = 1 if same package_id, else 0
; Clobbers: RAX, RCX, RDX, R8-R11
; -----------------------------------------------------------------------------
global ucpu_share_llc
ucpu_share_llc:
    push r12

    mov r12, rsi

    call ucpu_topology_get          ; RDI = cpu_a
    test rax, rax
    jz .no
    mov r9, rcx                     ; R9 = package_id_a (R8 is clobbered by the second call below)

    mov rdi, r12
    call ucpu_topology_get          ; RDI = cpu_b
    test rax, rax
    jz .no

    cmp rcx, r9
    jne .no

    mov rax, 1
    jmp .done

.no:
    xor rax, rax

.done:
    pop r12
    ret

; -----------------------------------------------------------------------------
; ucpu_package_mask — builds the affinity bitmask of every decoded CPU that
; belongs to a given package
; Input:
;   RDI = package_id
; Output:
;   RAX = 64-bit bitmask (bit N set iff cpu_id N is valid and in this package)
; Clobbers: RAX, RCX, RDX, RSI, R8-R11
; -----------------------------------------------------------------------------
global ucpu_package_mask
ucpu_package_mask:
    push rbx
    push r12
    push r13

    mov r12, rdi                    ; R12 = target package_id
    xor r13, r13                    ; R13 = accumulated mask
    xor rbx, rbx                    ; RBX = cpu_id iterator

.loop:
    cmp rbx, PERCPU_MAX_CORES
    jae .done

    mov rdi, rbx
    call ucpu_topology_get
    test rax, rax
    jz .next
    cmp rcx, r12                    ; package_id match?
    jne .next

    mov rcx, rbx
    mov rax, 1
    shl rax, cl
    or r13, rax

.next:
    inc rbx
    jmp .loop

.done:
    mov rax, r13

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ucpu_first_free_in_package — finds the lowest-numbered decoded CPU in a
; package that is not set in an exclusion mask
; Input:
;   RDI = package_id, RSI = exclude_mask (bit N set = cpu N unavailable)
; Output:
;   RAX = cpu_id, or -1 if none available
; Clobbers: RAX, RCX, RDX, R8-R11
; -----------------------------------------------------------------------------
global ucpu_first_free_in_package
ucpu_first_free_in_package:
    push rbx
    push r12
    push r13

    mov r12, rsi                    ; R12 = exclude_mask
    call ucpu_package_mask          ; RDI = package_id (unchanged)
    mov r13, rax                    ; R13 = package_mask

    not r12                         ; R12 = allowed_mask (bits NOT excluded)
    and r13, r12                    ; R13 = package_mask & allowed_mask

    test r13, r13
    jz .none

    bsf rax, r13                    ; lowest set bit = lowest free cpu_id
    jmp .done

.none:
    mov rax, -1

.done:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_HW_UCPU_PINNING_ASM
