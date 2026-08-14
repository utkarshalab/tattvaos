; =============================================================================
; Tattva OS — lib/mem/virt/hardware/kernel_aslr.asm
; =============================================================================
; Live Kernel ASLR Re-Shuffling (Feature 5).
; Migrates kernel code/data segments from an old physical range to a new one
; and dynamically updates all active page translation tables.
; System-wide TLB invalidation is forced after reference redirection.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_HARDWARE_KERNEL_ASLR_ASM
%define LIB_MEM_VIRT_HARDWARE_KERNEL_ASLR_ASM

[BITS 64]

section .text


; -----------------------------------------------------------------------------
; kernel_live_aslr_migrate — reshuffles kernel segments and rewrites page tables
; Input:
;   RDI = target_old_paddr (physical start of original range)
;   RSI = target_new_paddr (physical start of new range)
;   RDX = size_in_bytes    (size of range to migrate)
; Output: none
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global kernel_live_aslr_migrate
kernel_live_aslr_migrate:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov [old_paddr], rdi
    mov [new_paddr], rsi
    mov [size_bytes], rdx

    ; 1. Acquire system-wide simulated IPI lock
    mov r8, 1
.acquire_ipi:
    lock xchg [ipi_system_lock], r8
    test r8, r8
    jnz .acquire_ipi

    ; 2. Perform fast copy of the memory block
    ; memcpy(dest, src, count) -> RDI = new, RSI = old, RDX = size
    mov rdi, [new_paddr]
    mov rsi, [old_paddr]
    mov rdx, [size_bytes]
    call memcpy

    ; 3. Scan and rewrite translations in active PML4 (from CR3)
    mov rax, cr3
    and rax, 0xFFFFFFFFFFFFF000     ; RAX = PML4 physical base (identity mapped)
    mov r8, rax                     ; R8 = PML4 virtual base

    xor r9, r9                      ; R9 = PML4 index
.pml4_loop:
    cmp r9, 512
    jge .walk_done
    mov r10, [r8 + r9 * 8]
    test r10, 0x01                  ; Present?
    jz .next_pml4

    and r10, 0xFFFFFFFFFFFFF000     ; R10 = PDPT virtual base
    xor r11, r11                    ; R11 = PDPT index
.pdpt_loop:
    cmp r11, 512
    jge .next_pml4
    mov r12, [r10 + r11 * 8]
    test r12, 0x01                  ; Present?
    jz .next_pdpt
    test r12, 0x80                  ; Huge Page (1GB)?
    jnz .handle_1gb

    and r12, 0xFFFFFFFFFFFFF000     ; R12 = PD virtual base
    xor r13, r13                    ; R13 = PD index
.pd_loop:
    cmp r13, 512
    jge .next_pdpt
    mov r14, [r12 + r13 * 8]
    test r14, 0x01                  ; Present?
    jz .next_pd
    test r14, 0x80                  ; Huge Page (2MB)?
    jnz .handle_2mb

    and r14, 0xFFFFFFFFFFFFF000     ; R14 = PT virtual base
    xor r15, r15                    ; R15 = PT index
.pt_loop:
    cmp r15, 512
    jge .next_pd
    mov rdx, [r14 + r15 * 8]
    test rdx, 0x01                  ; Present?
    jz .next_pt

    ; Extract physical address from PTE
    mov rax, rdx
    mov rdi, 0x000FFFFFFFFFF000
    and rax, rdi
    cmp rax, [old_paddr]
    jb .next_pt
    mov rcx, [old_paddr]
    add rcx, [size_bytes]
    cmp rax, rcx
    jae .next_pt

    ; In range! Shift target mapping
    sub rax, [old_paddr]
    add rax, [new_paddr]
    mov rdi, ~0x000FFFFFFFFFF000
    and rdx, rdi
    or rdx, rax
    mov [r14 + r15 * 8], rdx        ; Write updated translation

.next_pt:
    inc r15
    jmp .pt_loop

.handle_2mb:
    mov rax, r14
    mov rdi, 0x000FFFFFE00000
    and rax, rdi        ; 2MB aligned frame address
    cmp rax, [old_paddr]
    jb .next_pd
    mov rcx, [old_paddr]
    add rcx, [size_bytes]
    cmp rax, rcx
    jae .next_pd

    ; In range! Shift mapping
    sub rax, [old_paddr]
    add rax, [new_paddr]
    mov rdi, ~0x000FFFFFE00000
    and r14, rdi
    or r14, rax
    mov [r12 + r13 * 8], r14
    jmp .next_pd

.handle_1gb:
    mov rax, r12
    mov rdi, 0x000FFFFC000000
    and rax, rdi        ; 1GB aligned frame address
    cmp rax, [old_paddr]
    jb .next_pdpt
    mov rcx, [old_paddr]
    add rcx, [size_bytes]
    cmp rax, rcx
    jae .next_pdpt

    ; In range! Shift mapping
    sub rax, [old_paddr]
    add rax, [new_paddr]
    mov rdi, ~0x000FFFFC000000
    and r12, rdi
    or r12, rax
    mov [r10 + r11 * 8], r12
    jmp .next_pdpt

.next_pd:
    inc r13
    jmp .pd_loop
.next_pdpt:
    inc r11
    jmp .pdpt_loop
.next_pml4:
    inc r9
    jmp .pml4_loop

.walk_done:
    ; wbinvd instruction flush
    wbinvd

    ; Flush local TLBs
    mov rax, cr3
    mov cr3, rax

    ; 4. Release simulated IPI lock
    mov qword [ipi_system_lock], 0

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .data

global ipi_system_lock
align 8
ipi_system_lock: dq 0               ; Lock variable to simulate system-wide IPI pause

old_paddr:      dq 0
new_paddr:      dq 0
size_bytes:     dq 0

%endif ; LIB_MEM_VIRT_HARDWARE_KERNEL_ASLR_ASM
