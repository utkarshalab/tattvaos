; =============================================================================
; Tattva OS — lib/mem/virt/paging/coredump.asm
; =============================================================================
; Selective & Sparse Core Dumping (Feature 22).
; Saves disk space and IO time by dumping only anonymous private heap/stack pages.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PAGING_COREDUMP_ASM
%define LIB_MEM_VIRT_PAGING_COREDUMP_ASM

[BITS 64]

; Local structures to avoid conflicts
struc vma_t_local
    .start      resq 1
    .end        resq 1
    .flags      resq 1
    .next       resq 1
endstruc

VMA_SHARED      equ (1 << 0)
VMA_READONLY    equ (1 << 1)

; -----------------------------------------------------------------------------
; Section .text
; -----------------------------------------------------------------------------
section .text


; -----------------------------------------------------------------------------
; sys_coredump_sparse — dumps private anonymous pages to a target file
; Input:
;   RDI = file_ptr (mock_file_t*)
; Output:
;   RAX = total bytes written to the core dump file, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global sys_coredump_sparse
sys_coredump_sparse:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi                    ; R12 = file_ptr
    test r12, r12
    jz .fail

    xor r13, r13                    ; R13 = current_offset = 0
    mov r14, [vma_list_head]        ; R14 = vma_list_head

.vma_loop:
    test r14, r14
    jz .success

    ; Check if the VMA is marked as VMA_SHARED or VMA_READONLY
    mov rax, [r14 + vma_t_local.flags]
    test rax, (VMA_SHARED | VMA_READONLY)
    jnz .next_vma                   ; Skip this VMA range

    mov r15, [r14 + vma_t_local.start]  ; R15 = page loop virtual address
    mov rbx, [r14 + vma_t_local.end]    ; RBX = VMA end address (exclusive)

.page_loop:
    cmp r15, rbx
    jae .next_vma

    ; Walk page tables to locate leaf PTE for current page
    mov rdi, r15
    mov rsi, 0                      ; use current CR3
    call virt_walk_table            ; RAX = leaf PTE pointer, RDX = level
    test rax, rax
    jz .skip_page                   ; page not mapped

    mov rcx, [rax]
    test rcx, 1                     ; present bit (bit 0)
    jz .skip_page                   ; page not present in RAM

    ; Write only present anonymous private pages (4KB)
    mov rdi, r12                    ; file_ptr
    mov rsi, r13                    ; starting file offset
    mov rdx, r15                    ; source buffer (virtual address)
    mov rcx, 4096                   ; 4KB size
    call virt_file_write            ; RAX = actual bytes written
    test rax, rax
    jz .skip_page                   ; skip offset update on write failure

    add r13, rax                    ; increment sequential file offset

.skip_page:
    add r15, 4096                   ; move to next 4KB page
    jmp .page_loop

.next_vma:
    mov r14, [r14 + vma_t_local.next]
    jmp .vma_loop

.success:
    mov rax, r13                    ; Return total bytes written
    jmp .exit

.fail:
    xor rax, rax

.exit:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_PAGING_COREDUMP_ASM
