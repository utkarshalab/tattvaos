; =============================================================================
; Tattva OS — lib/mem/virt/ras/ras_mce.asm
; =============================================================================
; Machine Check Exception (MCE) Handler — Subfeature 38.2 & Feature 20.
;
; Intercepts hardware-level memory errors. If an uncorrectable ECC error
; occurs within user-space context, the handler quarantines/poisons the affected
; physical page and terminates the faulting thread, enabling graceful degradation
; and preventing kernel-wide panic.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RAS_MCE_ASM
%define LIB_MEM_VIRT_RAS_MCE_ASM

[BITS 64]

; Local structures for structure offsets
struc vma_t_local
    .start      resq 1
    .end        resq 1
    .flags      resq 1
    .next       resq 1
endstruc

struc thread_t_local
    .thread_id          resq 1
    .cpu_affinity_mask  resq 1
    .preferred_node     resd 1
    .current_cpu        resd 1
    .flags              resq 1
endstruc

struc page_t_local
    .flags              resq 1
    .lock               resq 1
endstruc

; ---------------------------------------------------------------------------
; Section .text
; ---------------------------------------------------------------------------
section .text

extern ras_poison_page
extern pages_array
extern buddy_start_addr
extern vma_list_head
extern virt_walk_table
extern sched_get_current_thread

; ---------------------------------------------------------------------------
; ras_mce_init — Setup MCE monitoring variables
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global ras_mce_init
ras_mce_init:
    mov  qword [sys_ras_mce_occurred], 0
    mov  qword [sys_ras_mce_recovered], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; ras_mce_handler — Intercept and handle physical memory exceptions
; Input:
;   RDI = Faulting physical address
;   RSI = Uncorrectable flag (1 = Uncorrectable/Double-bit, 0 = Correctable)
; Output: RAX = 1 if gracefully recovered, 0 if fatal (requires kernel panic)
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global ras_mce_handler
ras_mce_handler:
    inc  qword [sys_ras_mce_occurred]

    test rsi, rsi
    jz   .graceful_correctable      ; correctable is always recovered

    ; Uncorrectable error. Check if address is within user space memory zone.
    cmp  rdi, 0x10000000
    jb   .fatal_kernel_mce          ; kernel space error = fatal panic!

    ; User space page error! Attempt recovery by poisoning the physical page
    push rdi
    call ras_poison_page            ; offlines page
    pop  rdi
    test rax, rax
    jz   .fatal_kernel_mce

    ; Gracefully recovered! (The scheduler will kill the faulting process)
    inc  qword [sys_ras_mce_recovered]
    mov  rax, 1
    ret

.graceful_correctable:
    inc  qword [sys_ras_mce_recovered]
    mov  rax, 1
    ret

.fatal_kernel_mce:
    xor  rax, rax                   ; recovery failed, panic!
    ret

; -----------------------------------------------------------------------------
; mce_poison_recovery_handler — Handles MCE error recovery by poisoning the page,
;                               clearing translation entries, and signaling SIGBUS.
; Input:  None (reads from IA32_MC0_ADDR MSR 0x402)
; Output: RAX = 1 if recovered, 0 if fatal (requires panic)
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global mce_poison_recovery_handler
mce_poison_recovery_handler:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    ; 1. Intercept the MCE interrupt. Read the failing memory address from IA32_MC0_ADDR MSR (0x402)
    mov ecx, 0x402
    rdmsr                           ; EDX = high 32 bits, EAX = low 32 bits
    shl rdx, 32
    or rdx, rax                     ; RDX = physical address of memory error
    and rdx, ~0xFFF                 ; Align to 4KB page boundary
    mov r15, rdx                    ; R15 = poisoned physical page address

    ; 2. Poison the physical page: call ras_poison_page
    mov rdi, r15
    call ras_poison_page            ; RAX = 1 on success, 0 on failure
    test rax, rax
    jz .fail

    ; 3. Mark page_t.flags bit 14 (PAGE_POISONED) of that physical address
    mov r8, [pages_array]
    test r8, r8
    jz .skip_page_t                 ; Skip if pages_array is NULL
    mov r9, [buddy_start_addr]
    mov rax, r15
    sub rax, r9
    cmp rax, 0
    jl .skip_page_t                 ; Sanity check
    shr rax, 12                     ; RAX = PFN
    imul rax, 16                    ; RAX = PFN * page_t_size (16 bytes)
    lea rbp, [r8 + rax]             ; RBP = page_t* pointer
    
    ; Acquire page lock
.lock_page:
    lock bts qword [rbp + page_t_local.lock], 0
    jc .lock_pause
    jmp .lock_acquired
.lock_pause:
    pause
    test qword [rbp + page_t_local.lock], 1
    jnz .lock_pause
    jmp .lock_page
.lock_acquired:
    or qword [rbp + page_t_local.flags], (1 << 14) ; set PAGE_POISONED flag
    mov qword [rbp + page_t_local.lock], 0         ; unlock

.skip_page_t:
    ; 4. Traverse the reverse-mapping list
    ; Walk vma_list_head. For each page, resolve the PTE.
    mov r12, [vma_list_head]        ; R12 = VMA node pointer
.vma_loop:
    test r12, r12
    jz .vma_done

    mov r13, [r12 + vma_t_local.start]    ; R13 = current virtual address (start)
    mov r14, [r12 + vma_t_local.end]      ; R14 = end address (exclusive)

.page_loop:
    cmp r13, r14
    jae .next_vma

    mov rdi, r13
    xor rsi, rsi                    ; Use active CR3
    call virt_walk_table            ; RAX = leaf PTE ptr, RDX = level
    test rax, rax
    jz .skip_page

    mov rcx, [rax]
    test rcx, 1                     ; Check present flag
    jz .skip_page

    ; Check if physical address in PTE matches poisoned page (R15)
    mov rdx, rcx
    mov r8, 0x000FFFFFFFFFF000
    and rdx, r8
    cmp rdx, r15
    jne .skip_page

    ; Match found! Clear the PTE entry and invalidate TLB
    mov qword [rax], 0
    invlpg [r13]

.skip_page:
    add r13, 4096                   ; Next page virtual address
    jmp .page_loop

.next_vma:
    mov r12, [r12 + vma_t_local.next]
    jmp .vma_loop

.vma_done:
    ; 5. Issue simulated SIGBUS to the affected tasks:
    ; Clear Active bit (bit 0) in the thread flags to kill it, and set bit 3 (THREAD_SIGBUS_PENDING)
    call sched_get_current_thread   ; RAX = current thread pointer
    test rax, rax
    jz .success                     ; If no current thread, complete gracefully

    and qword [rax + thread_t_local.flags], ~1     ; Clear Active bit (bit 0)
    or qword [rax + thread_t_local.flags], 8       ; Set THREAD_SIGBUS_PENDING (bit 3)

.success:
    mov rax, 1                      ; Gracefully recovered
    jmp .exit

.fail:
    xor rax, rax                    ; Recovery failed, requires panic

.exit:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_ras_mce_occurred
sys_ras_mce_occurred:           dq 0

align 8
global sys_ras_mce_recovered
sys_ras_mce_recovered:          dq 0

section .text

%endif ; LIB_MEM_VIRT_RAS_MCE_ASM
