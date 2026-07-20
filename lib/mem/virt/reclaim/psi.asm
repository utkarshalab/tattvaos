; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/psi.asm
; =============================================================================
; Pressure Stall Information (PSI) Stall Telemetry (Feature 21).
; Monitors active and stalled threads to compute memory pressure stall duration.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_PSI_ASM
%define LIB_MEM_VIRT_RECLAIM_PSI_ASM

[BITS 64]

; Local structures to avoid conflicts
struc thread_t_local
    .thread_id          resq 1      ; Offset 0
    .cpu_affinity_mask  resq 1      ; Offset 8
    .preferred_node     resd 1      ; Offset 16
    .current_cpu        resd 1      ; Offset 20
    .flags              resq 1      ; Offset 24
endstruc

struc psi_memory_tracker
    .some_stall_time:   resq 1
    .full_stall_time:   resq 1
    .last_update_tsc:   resq 1
endstruc

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text



; -----------------------------------------------------------------------------
; psi_update_stalls — scans all threads to update PSI stall telemetry
; Input:  None
; Output: None
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; -----------------------------------------------------------------------------
global psi_update_stalls
psi_update_stalls:
    push rbx
    push rbp
    push r12
    push r13

    mov rcx, [thread_count]
    test rcx, rcx
    jz .exit                        ; No threads, nothing to update

    xor rbx, rbx                    ; RBX = active thread count
    xor r12, r12                    ; R12 = stalled thread count
    xor rsi, rsi                    ; RSI = loop index

.thread_loop:
    cmp rsi, rcx
    jae .loop_done

    ; Calculate pointer to current thread descriptor
    mov rax, rsi
    imul rax, thread_t_local_size
    lea rdi, [thread_table + rax]   ; RDI = thread pointer

    mov rax, [rdi + thread_t_local.flags]
    test rax, 1                     ; bit 0 = Active
    jz .next_thread

    inc rbx                         ; Increment active count

    test rax, 2                     ; bit 1 = Stalled
    jz .next_thread

    inc r12                         ; Increment stalled count

.next_thread:
    inc rsi
    jmp .thread_loop

.loop_done:
    ; Read the current Time Stamp Counter
    rdtsc                           ; EDX:EAX = TSC
    shl rdx, 32
    or rax, rdx                     ; RAX = current TSC

    lea rbp, [global_psi_tracker]
    mov rdi, [rbp + psi_memory_tracker.last_update_tsc]
    test rdi, rdi
    jz .init_tsc                    ; If 0, initialize tracker on first run

    ; Calculate delta cycles
    mov rsi, rax
    sub rsi, rdi                    ; RSI = delta (duration)
    jbe .update_tsc                 ; Ignore if TSC didn't progress

    ; 4. If at least one thread is stalled, add duration to `.some_stall_time`
    test r12, r12
    jz .check_full
    add [rbp + psi_memory_tracker.some_stall_time], rsi

.check_full:
    ; 5. If all active/running threads are stalled, add to `.full_stall_time`
    test rbx, rbx
    jz .update_tsc                  ; No active threads
    cmp r12, rbx
    jne .update_tsc                 ; Not all active threads are stalled
    add [rbp + psi_memory_tracker.full_stall_time], rsi
    jmp .update_tsc

.init_tsc:
    mov [rbp + psi_memory_tracker.last_update_tsc], rax
    jmp .exit

.update_tsc:
    mov [rbp + psi_memory_tracker.last_update_tsc], rax

.exit:
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Section .data
; -----------------------------------------------------------------------------
section .data

align 8
global global_psi_tracker
global_psi_tracker:
    istruc psi_memory_tracker
        at psi_memory_tracker.some_stall_time, dq 0
        at psi_memory_tracker.full_stall_time, dq 0
        at psi_memory_tracker.last_update_tsc, dq 0
    iend

section .text

%endif ; LIB_MEM_VIRT_RECLAIM_PSI_ASM
