; =============================================================================
; Tattva OS — lib/hw/unuma/distance.asm
; =============================================================================
; CPU-granularity distance queries. Wraps lib/mem/numa's numa_get_distance
; (SLIT-derived node-to-node matrix) with unuma_node_of_cpu's real
; SRAT-derived APIC-ID-to-node map, instead of the hardcoded cpu_to_node
; placeholder in lib/mem/virt/rt_safe/sched_affinity.asm.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UNUMA_DISTANCE_ASM
%define LIB_HW_UNUMA_DISTANCE_ASM

%include "lib/percpu.inc"
%include "lib/hw/unuma/detect.asm"

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; unuma_cpu_distance — relative memory distance between two CPUs' home nodes
; Input:
;   RDI = apic_id_a, RSI = apic_id_b
; Output:
;   RAX = 1 if both CPUs' nodes are known, 0 otherwise
;   RSI = distance (only meaningful if RAX = 1; see numa_get_distance for
;         the scale — 10 local, 20 default remote, 255 unreachable)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8
; -----------------------------------------------------------------------------
global unuma_cpu_distance
unuma_cpu_distance:
    push rbx
    push r12

    mov rbx, rsi                    ; RBX = apic_id_b (RSI is an output
                                     ; register on the first call below)

    call unuma_node_of_cpu          ; RDI = apic_id_a (unchanged)
    test rax, rax
    jz .unknown
    mov r12, rsi                    ; R12 = node_a

    mov rdi, rbx
    call unuma_node_of_cpu          ; RDI = apic_id_b; out RSI = node_b
    test rax, rax
    jz .unknown

    mov rdi, r12                    ; node_from = node_a
                                     ; RSI already holds node_to = node_b
    call numa_get_distance          ; RAX = distance
    mov rsi, rax
    mov rax, 1
    jmp .done

.unknown:
    xor rax, rax
    xor rsi, rsi

.done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; unuma_best_node_for_current_cpu — active NUMA node closest to the
; currently executing core, per SRAT (home) + SLIT (distance)
; Input:  none
; Output:
;   RAX = 1 if found, 0 if this core's node is unknown or no active nodes
;         are recorded
;   RSI = best node_id (only meaningful if RAX = 1)
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8, R12-R14
; -----------------------------------------------------------------------------
global unuma_best_node_for_current_cpu
unuma_best_node_for_current_cpu:
    push rbx
    push r12
    push r13
    push r14

    mov edi, [gs:percpu_t.lapic_id]
    call unuma_node_of_cpu          ; RAX = flag, RSI = home_node
    test rax, rax
    jz .unknown
    mov r12, rsi                    ; R12 = home_node

    mov r13, [rel numa_node_count]
    test r13, r13
    jz .unknown

    mov r14, 255                    ; R14 = best_distance
    xor rbx, rbx                    ; RBX = best_node
    xor rcx, rcx                    ; RCX = loop index

.loop:
    cmp rcx, r13
    jae .found

    mov rdi, r12
    mov rsi, rcx
    call numa_get_distance          ; RAX = distance; preserves RCX/RBX/R12-R14
    cmp rax, r14
    jae .next
    mov r14, rax
    mov rbx, rcx

.next:
    inc rcx
    jmp .loop

.found:
    mov rsi, rbx
    mov rax, 1
    jmp .done

.unknown:
    xor rax, rax
    xor rsi, rsi

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_HW_UNUMA_DISTANCE_ASM
