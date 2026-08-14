; =============================================================================
; Tattva OS — lib/mem/virt/paging/hotpatch.asm
; =============================================================================
; Live-Patching Memory Redirection (Feature 23).
; Hot-fixes active functions in memory without stopping services via JMP rel32.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PAGING_HOTPATCH_ASM
%define LIB_MEM_VIRT_PAGING_HOTPATCH_ASM

[BITS 64]

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text


; -----------------------------------------------------------------------------
; kernel_apply_hotpatch — diverts execution from target function to patch function
; Input:
;   RDI = target_function_addr (address of active function to patch)
;   RSI = patch_function_addr  (address of hotpatch patch code)
; Output:
;   RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global kernel_apply_hotpatch
kernel_apply_hotpatch:
    push rbx
    push r12
    push r13

    mov r12, rdi                    ; R12 = target_function_addr
    mov r13, rsi                    ; R13 = patch_function_addr

    ; 1. Locate the page table entry containing target_function_addr
    mov rdi, r12
    mov rsi, 0                      ; use current CR3
    call virt_walk_table            ; RAX = leaf PTE pointer, RDX = level
    test rax, rax
    jz .fail

    ; Set PAGE_WRITABLE bit (bit 1) to 1 in target's PTE
    or qword [rax], 2

    ; Invalidate TLB for the target virtual address
    invlpg [r12]

    ; 2. Clear write protection override register CR0.WP (bit 16)
    mov rax, cr0
    and rax, ~0x10000               ; clear WP bit (bit 16)
    mov cr0, rax

    ; 3. Calculate 32-bit relative jump offset: (patch_addr - target_addr - 5)
    mov rax, r13
    sub rax, r12
    sub rax, 5                      ; RAX = offset32

    ; Write jump instruction (0xE9 offset32) at target_function_addr
    mov byte [r12], 0xE9            ; JMP opcode
    mov dword [r12 + 1], eax        ; JMP relative offset

    ; 4. Restore CR0.WP
    mov rax, cr0
    or rax, 0x10000                 ; set WP bit (bit 16)
    mov cr0, rax

    ; Clear CPU instruction cache for patched memory address
    clflush [r12]

    mov rax, 1                      ; Return success
    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PAGING_HOTPATCH_ASM
