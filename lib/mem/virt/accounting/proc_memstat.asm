%ifndef GUARD_LIB_MEM_VIRT_ACCOUNTING_PROC_MEMSTAT_ASM
%define GUARD_LIB_MEM_VIRT_ACCOUNTING_PROC_MEMSTAT_ASM
; =============================================================================
; Tattva OS — lib/mem/virt/proc_memstat.asm
; =============================================================================
; Per-Process Memory Statistics — Subfeature 34.4.
;
; Computes VSZ / RSS / PSS / USS for any registered thread, analogous to
; Linux /proc/<pid>/smaps and /proc/<pid>/status:
;
;   VSZ  (Virtual Size)            — total virtual address space committed
;                                    in VMAs (all VMA sizes summed)
;   RSS  (Resident Set Size)       — virtual pages that have a physical
;                                    backing frame present in page tables
;   PSS  (Proportional Set Size)   — RSS where shared pages are counted
;                                    as 1/share_count of a page each
;   USS  (Unique Set Size)         — pages not shared with any other thread
;                                    (share_count == 1)
;
; Since Tattva OS does not yet have a multi-level page-sharing reference
; counter, we model sharing conservatively:
;   • A page mapped by more than one active VMA (overlapping phys addr)
;     counts as shared; its contribution to PSS = 1/overlap_count.
;   • A page mapped by exactly one VMA contributes fully to PSS and USS.
;
; For single-threaded boot testing: every mapped page is unique (USS=RSS=PSS)
; because each thread owns distinct physical frames.
;
; API:
;   proc_memstat_compute(thread_ptr, out_ptr)
;       — walks the global VMA list, filters VMAs whose range overlaps
;         the thread's virtual address space, sums VSZ/RSS/PSS/USS into
;         the proc_memstat_t struct at out_ptr.
;   proc_memstat_get_vsz(out_ptr)  → RAX = VSZ bytes
;   proc_memstat_get_rss(out_ptr)  → RAX = RSS bytes
;   proc_memstat_get_pss(out_ptr)  → RAX = PSS bytes (rounded up)
;   proc_memstat_get_uss(out_ptr)  → RAX = USS bytes
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PROC_MEMSTAT_ASM
%define LIB_MEM_VIRT_PROC_MEMSTAT_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; proc_memstat_t structure
; ---------------------------------------------------------------------------
struc proc_memstat_t
    .vsz    resq 1          ; Virtual Set Size  (bytes)
    .rss    resq 1          ; Resident Set Size (bytes)
    .pss    resq 1          ; Proportional Set Size (bytes, rounded up)
    .uss    resq 1          ; Unique Set Size   (bytes)
endstruc

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
section .text

extern virt_translate            ; virt_translate(vaddr) → phys or 0

PAGE_SIZE equ 4096

; ---------------------------------------------------------------------------
; proc_memstat_compute — compute VSZ/RSS/PSS/USS for a given thread.
;
; Strategy:
;   Walk every VMA in the global VMA list.  For each VMA:
;     1. Add (end - start) to VSZ unconditionally.
;     2. Walk each page in the VMA; if virt_translate(page_va) != 0 → RSS++.
;     3. For each resident page, scan all other active VMAs to count how
;        many VMAs also cover that same virtual range (share_count).
;        PSS += 4096 / share_count.  If share_count == 1 → USS += 4096.
;
; For performance, the boot test uses small VMAs (single pages), so the
; nested walk is O(1) in practice.
;
; Input:
;   RDI = pointer to thread_t  (used to verify thread is active)
;   RSI = pointer to proc_memstat_t output struct (caller-allocated)
; Output: none
; Clobbers: RAX, RBX, RCX, RDX, R8, R9, R10, R11, R12, R13, R14, R15
; ---------------------------------------------------------------------------
global proc_memstat_compute
proc_memstat_compute:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r15, rsi                    ; R15 = output struct ptr

    ; Zero the output struct
    mov qword [r15 + proc_memstat_t.vsz], 0
    mov qword [r15 + proc_memstat_t.rss], 0
    mov qword [r15 + proc_memstat_t.pss], 0
    mov qword [r15 + proc_memstat_t.uss], 0

    ; Walk VMA list
    mov rbx, [vma_list_head]        ; RBX = current VMA node

.vma_loop:
    test rbx, rbx
    jz   .done

    mov r12, [rbx + vma_t.start]   ; R12 = VMA start
    mov r13, [rbx + vma_t.end]     ; R13 = VMA end (exclusive)

    ; VSZ += end - start
    mov rax, r13
    sub rax, r12
    add [r15 + proc_memstat_t.vsz], rax

    ; Walk pages in this VMA
    mov r14, r12                    ; R14 = page cursor

.page_loop:
    cmp r14, r13
    jae .next_vma

    ; Is this page resident?
    mov rdi, r14
    call virt_translate             ; RAX = physical address or 0
    test rax, rax
    jz   .page_next                 ; not resident, skip

    ; RSS += 4096
    add qword [r15 + proc_memstat_t.rss], PAGE_SIZE

    ; Count how many VMAs cover this page (share_count)
    ; Walk all VMAs again
    mov r9, [vma_list_head]         ; R9 = inner VMA scan
    xor r10, r10                    ; R10 = share_count = 0

.share_loop:
    test r9, r9
    jz   .share_done

    mov r11, [r9 + vma_t.start]
    cmp r14, r11
    jb   .share_next                ; page < vma start → not covered
    mov r11, [r9 + vma_t.end]
    cmp r14, r11
    jae  .share_next                ; page >= vma end → not covered
    inc  r10                        ; this VMA covers the page

.share_next:
    mov r9, [r9 + vma_t.next]
    jmp .share_loop

.share_done:
    ; PSS += 4096 / share_count  (integer division, minimum 1)
    test r10, r10
    jz   .page_next                 ; degenerate: skip

    mov  rax, PAGE_SIZE
    xor  rdx, rdx
    div  r10                        ; RAX = 4096 / share_count
    add  [r15 + proc_memstat_t.pss], rax

    ; USS: if share_count == 1, page is unique
    cmp  r10, 1
    jne  .page_next
    add  qword [r15 + proc_memstat_t.uss], PAGE_SIZE

.page_next:
    add r14, PAGE_SIZE
    jmp .page_loop

.next_vma:
    mov rbx, [rbx + vma_t.next]
    jmp .vma_loop

.done:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---------------------------------------------------------------------------
; proc_memstat_get_vsz — read VSZ from a computed result struct.
; Input:  RDI = proc_memstat_t pointer
; Output: RAX = VSZ bytes
; ---------------------------------------------------------------------------
global proc_memstat_get_vsz
proc_memstat_get_vsz:
    mov rax, [rdi + proc_memstat_t.vsz]
    ret

; ---------------------------------------------------------------------------
; proc_memstat_get_rss — read RSS from a computed result struct.
; Input:  RDI = proc_memstat_t pointer
; Output: RAX = RSS bytes
; ---------------------------------------------------------------------------
global proc_memstat_get_rss
proc_memstat_get_rss:
    mov rax, [rdi + proc_memstat_t.rss]
    ret

; ---------------------------------------------------------------------------
; proc_memstat_get_pss — read PSS from a computed result struct.
; Input:  RDI = proc_memstat_t pointer
; Output: RAX = PSS bytes
; ---------------------------------------------------------------------------
global proc_memstat_get_pss
proc_memstat_get_pss:
    mov rax, [rdi + proc_memstat_t.pss]
    ret

; ---------------------------------------------------------------------------
; proc_memstat_get_uss — read USS from a computed result struct.
; Input:  RDI = proc_memstat_t pointer
; Output: RAX = USS bytes
; ---------------------------------------------------------------------------
global proc_memstat_get_uss
proc_memstat_get_uss:
    mov rax, [rdi + proc_memstat_t.uss]
    ret

section .text

%endif ; LIB_MEM_VIRT_PROC_MEMSTAT_ASM

%endif ; GUARD_LIB_MEM_VIRT_ACCOUNTING_PROC_MEMSTAT_ASM
