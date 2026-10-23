; =============================================================================
; Utkarsha OS — lib/mem/virt/tlb_shootdown.asm
; =============================================================================
; Multi-Core TLB Shootdown — sends Inter-Processor Interrupts (IPIs) to
; all other active cores, forcing them to invalidate stale TLB entries
; when page mappings or permissions change.
;
; Design:
;   1. The caller serializes and publishes one request (address + count).
;   2. It sends fixed-vector IPI 0xFB to all-excluding-self.
;   3. Each remote CPU performs invlpg or a global/full flush, then atomically
;      increments the ACK counter.
;   4. The caller waits, with a hard timeout, for active_cores - 1 ACKs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_TLB_SHOOTDOWN_ASM
%define LIB_MEM_VIRT_TLB_SHOOTDOWN_ASM

[BITS 64]

%include "lib/percpu.inc"

; IPI vector used for TLB shootdowns
TLB_SHOOTDOWN_VEC   equ 0xFB

; Shootdown mode constants
TLB_SHOOTDOWN_PAGE  equ 0           ; invalidate specific page(s)
TLB_SHOOTDOWN_FULL  equ 1           ; full CR3 reload

section .text

; -----------------------------------------------------------------------------
; tlb_shootdown — request all other cores to invalidate TLB entries
; Input:
;   RDI = virtual address to invalidate (page-aligned)
;   RSI = number of pages to invalidate (0 = full flush)
; Output: none
; Clobbers: RAX, RCX, RDX, RDI, RSI
; Multicore callers must enter with IF=1. This lets lock waiters service the
; current owner's IPI and avoids an unsafe STI/CLI restoration race. Exception
; entries that can mutate mappings must explicitly restore saved interruptible
; context before calling this routine.
; -----------------------------------------------------------------------------
global tlb_shootdown
tlb_shootdown:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r14, rdi
    mov r15, rsi
    mov r12d, [rel smp_active_cores]
    cmp r12d, 1
    jbe .local_direct

    ; ponytail: one lock is sufficient for boot-time/global mappings. Replace
    ; it with per-CPU generations only if measured mapping concurrency needs it.
    pushfq
    pop rax
    test eax, 1 << 9
    jz .irq_disabled_fatal
    mov r13d, [gs:percpu_t.cpu_id]
    inc r13d                        ; owner token; zero remains unlocked
.lock_wait:
    xor eax, eax
    lock cmpxchg [rel tlb_sd_lock], r13d
    jz .locked
    cmp eax, r13d
    je .recursive_fatal
    pause
    jmp .lock_wait
.locked:
    ; The released CPU set is immutable during normal runtime, so the count
    ; sampled before taking the lock remains the expected rendezvous set.

.publish:
    mov [rel tlb_sd_vaddr], r14
    mov [rel tlb_sd_count], r15

    ; Determine mode: if count == 0, do full flush
    test r15, r15
    jz .set_full
    mov byte [rel tlb_sd_mode], TLB_SHOOTDOWN_PAGE
    jmp .send_ipi
.set_full:
    mov byte [rel tlb_sd_mode], TLB_SHOOTDOWN_FULL

.send_ipi:
    ; 2. Reset ACK counter to 0
    mov dword [rel tlb_sd_ack], 0

    ; Memory fence — ensure request is visible before IPI
    mfence

    ; 3. Calculate expected ACKs = active_cores - 1 (BSP doesn't ACK itself)
    ; Checked *before* decrementing, not after: smp_active_cores is supposed
    ; to always hold at least 1 (kernel_init defaults it there), but this is
    ; the one place in the tree where getting that wrong is unrecoverable —
    ; a stray 0 here used to become 0xFFFFFFFF after the decrement and the
    ; wait loop below would then spin forever for ACKs from cores that were
    ; never sent an IPI (there is no dest-known-bad path to fall back to, the
    ; way an allocator falls back to OOM). smp_stacks_init guards the same
    ; value the same way for the same reason.
    cmp r12d, 1
    jbe .local_only                 ; 0 or 1 active cores: nothing to wait for
    dec r12d                        ; R12 = expected ACK count

    ; 4. Send fixed-vector IPI to all-excluding-self
    ;    ICR format:
    ;      [31:20] = 0 (destination, ignored for shorthand)
    ;      [19:18] = 11b (all excluding self)
    ;      [15]    = 0 (edge triggered)
    ;      [14]    = 1 (assert)
    ;      [10:8]  = 000 (fixed delivery)
    ;      [7:0]   = vector (0xFB)
    mov edi, 0x000C4000 | TLB_SHOOTDOWN_VEC
    call smp_send_all_others

    ; 5. Perform local invalidation on BSP as well
    call tlb_do_local_flush

    ; 6. Wait at most 100 ms. Returning with stale remote translations would
    ; be memory corruption, so timeout is deliberately fail-stop.
    mov ebx, 100
.wait_loop:
    mov eax, [rel tlb_sd_ack]
    cmp eax, r12d
    jae .remote_done
    mov rdi, 1000
    call udelay
    dec ebx
    jnz .wait_loop
    cli
    lea rsi, [rel msg_tlb_shootdown_timeout]
    call uart_print_str
.fatal:
    hlt
    jmp .fatal

.remote_done:
    mfence
    mov dword [rel tlb_sd_lock], 0
    jmp .done

.local_direct:
    ; With no remote CPUs, avoid the shared request record entirely so even a
    ; nested single-core invalidation cannot overwrite the outer operation.
    mov rdi, r14
    mov rsi, r15
    call tlb_do_local_request
    jmp .done

.local_only:
    ; Defensive path if the sampled active count ever changes unexpectedly.
    call tlb_do_local_flush
    jmp .done

.irq_disabled_fatal:
    cli
    lea rsi, [rel msg_tlb_shootdown_irq_disabled]
    jmp .print_fatal

.recursive_fatal:
    cli
    lea rsi, [rel msg_tlb_shootdown_recursive]
.print_fatal:
    call uart_print_str
.contract_fatal:
    hlt
    jmp .contract_fatal

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; tlb_do_local_flush — perform TLB invalidation on the current core
; Uses the shared shootdown request fields to decide what to flush.
; -----------------------------------------------------------------------------
tlb_do_local_flush:
    cmp byte [rel tlb_sd_mode], TLB_SHOOTDOWN_FULL
    je tlb_do_local_full

    ; Page-level invalidation
    mov rdi, [rel tlb_sd_vaddr]
    mov rsi, [rel tlb_sd_count]

; RDI=virtual address, RSI=page count (zero means full/global flush).
tlb_do_local_request:
    test rsi, rsi
    jz tlb_do_local_full
    mov rax, rdi
    mov rcx, rsi

.flush_page_loop:
    test rcx, rcx
    jz .flush_done
    invlpg [rax]
    add rax, 4096
    dec rcx
    jmp .flush_page_loop

.flush_done:
    ret

tlb_do_local_full:
    ; Replacing a huge/global mapping requires evicting global translations.
    ; Changing CR4.PGE flushes every TLB entry, including global entries.
    mov rax, cr4
    test rax, 1 << 7
    jz .flush_non_global
    mov rdx, rax
    and rax, ~(1 << 7)
    mov cr4, rax
    mov cr4, rdx
    ret
.flush_non_global:
    mov rax, cr3
    mov cr3, rax
    ret

; -----------------------------------------------------------------------------
; tlb_shootdown_isr — ISR handler for vector 0xFB (called on each AP)
; Must be installed in the IDT at vector TLB_SHOOTDOWN_VEC.
; Performs the requested TLB invalidation and ACKs the shootdown.
; -----------------------------------------------------------------------------
global tlb_shootdown_isr
tlb_shootdown_isr:
    cld
    push rax
    push rcx
    push rdx

    call tlb_do_local_flush

.isr_ack:
    ; Atomically increment ACK counter
    lock inc dword [rel tlb_sd_ack]

    ; Send End-Of-Interrupt through the active xAPIC/x2APIC backend.
    call smp_lapic_eoi

    pop rdx
    pop rcx
    pop rax
    iretq

; -----------------------------------------------------------------------------
; Data — Shootdown request structure
; -----------------------------------------------------------------------------
section .data

align 8
tlb_sd_vaddr:   dq 0               ; virtual address to invalidate
tlb_sd_count:   dq 0               ; number of pages (0 = full flush)
tlb_sd_mode:    db 0                ; 0 = page, 1 = full
align 4
tlb_sd_ack:     dd 0                ; atomic ACK counter from remote cores
tlb_sd_lock:    dd 0                ; zero or logical owner CPU ID + 1

align 4
global smp_active_cores
smp_active_cores: dd 1              ; default to 1 core (BSP)
msg_tlb_shootdown_timeout:
    db "KERNEL PANIC: TLB shootdown rendezvous timed out", 0x0D, 0x0A, 0
msg_tlb_shootdown_irq_disabled:
    db "KERNEL PANIC: multicore TLB shootdown requires IF=1", 0x0D, 0x0A, 0
msg_tlb_shootdown_recursive:
    db "KERNEL PANIC: recursive TLB shootdown on request owner", 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_TLB_SHOOTDOWN_ASM
