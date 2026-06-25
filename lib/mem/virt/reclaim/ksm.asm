; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/ksm.asm
; =============================================================================
; Kernel Samepage Merging (KSM / Memory Deduplication) (Feature 9).
; Identifies physically distinct pages with identical content, merges them into
; a single physical frame mapped as Read-Only and Copy-on-Write (PAGE_COW).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_KSM_ASM
%define LIB_MEM_VIRT_RECLAIM_KSM_ASM

[BITS 64]

; KSM database entry layout
struc ksm_entry_t
    .phys_addr: resq 1          ; Physical address of merged page
    .virt_addr: resq 1          ; Virtual address where it was originally mapped
    .hash:      resq 1          ; computed FNV-1a hash of page data
endstruc

section .text

extern vma_list_head
extern virt_walk_table
extern phys_free_page

; -----------------------------------------------------------------------------
; ksm_scan_and_merge — scans VMAs to find and deduplicate identical pages
; Input:
;   RDI = scan_limit_pages (max pages to scan in this run)
; Output:
;   RAX = number of pages successfully merged
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global ksm_scan_and_merge
ksm_scan_and_merge:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = scan_limit_pages
    xor r13, r13                    ; R13 = merge counter (return value)

    mov r14, [vma_list_head]        ; R14 = current VMA node

.vma_loop:
    test r14, r14
    jz .done
    test r12, r12
    jz .done                        ; Scan limit reached

    ; Loop virtual address from vma->start to vma->end
    ; vma_t layout: .start (offset 0), .end (offset 8), .next (offset 24)
    mov r15, [r14]                  ; R15 = current virtual address (start)
    mov rbp, [r14 + 8]              ; RBP = end address (exclusive)

.page_loop:
    cmp r15, rbp
    jae .next_vma
    test r12, r12
    jz .done                        ; Scan limit reached

    ; Walk page tables to locate PTE pointer for current address r15
    mov rdi, r15
    xor rsi, rsi                    ; Use active CR3
    call virt_walk_table            ; RAX = PTE virtual pointer
    test rax, rax
    jz .skip_page                   ; Not mapped
    
    mov rdx, [rax]
    test rdx, 0x01                  ; Present?
    jz .skip_page
    test rdx, 0x80                  ; Skip huge pages (2MB) for KSM
    jnz .skip_page

    mov r11, rax                    ; R11 = current PTE pointer
    mov rbx, rdx
    and rbx, 0xFFFFFFFFFFFFF000     ; RBX = current physical address

    ; 1. Compute FNV-1a hash of the 4KB page contents
    mov rdi, r15                    ; Current page virtual address
    call .fnv_hash                  ; RAX = computed 64-bit hash
    mov r10, rax                    ; R10 = computed hash

    ; 2. Search KSM table for matching hash
    lea r8, [ksm_table]
    xor r9, r9                      ; R9 = slot index
.search_ksm:
    cmp r9, [ksm_count]
    jge .no_match                   ; End of active KSM table

    imul rax, r9, ksm_entry_t_size
    lea rdx, [r8 + rax]             ; RDX = &ksm_table[r9]
    cmp [rdx + ksm_entry_t.hash], r10
    jne .next_ksm_slot

    ; 3. Hash matched! Perform strict byte-by-byte comparison
    ; Candidate virtual address is slot.virt_addr (identity space equivalent)
    push rdx
    mov rdi, r15                    ; current virtual pointer
    mov rsi, [rdx + ksm_entry_t.virt_addr] ; candidate virtual pointer
    mov rcx, 512                    ; 512 quadwords (4096 bytes)
    cld
    repe cmpsq                      ; Compare quadwords
    pop rdx
    jne .next_ksm_slot              ; Data mismatch, continue searching

    ; 4. Match confirmed! Deduplicate pages
    ; Walk candidate PTE
    mov rdi, [rdx + ksm_entry_t.virt_addr]
    xor rsi, rsi
    call virt_walk_table            ; RAX = candidate PTE pointer
    test rax, rax
    jz .next_ksm_slot               ; Candidate vanished, skip

    ; Update candidate PTE to read-only + PAGE_COW (bit 9 = 0x200)
    mov rsi, [rax]
    and rsi, ~0x02                  ; Clear Writable (bit 1)
    or rsi, 0x200                   ; Set PAGE_COW
    lock xchg [rax], rsi

    ; Update current PTE to point to candidate's physical address as Read-Only + COW
    mov rsi, [rdx + ksm_entry_t.phys_addr]
    or rsi, 0x201                   ; Present | COW (R/W=0, User=1, Global=0)
    lock xchg [r11], rsi

    ; Invalidate TLB for current virtual address
    invlpg [r15]

    ; Free the duplicate physical page
    mov rdi, rbx
    call phys_free_page             ; Preserves loop variables

    inc r13                         ; Increment merge counter
    jmp .skip_page                  ; Skip inserting (already merged)

.next_ksm_slot:
    inc r9
    jmp .search_ksm

.no_match:
    ; 5. No match found, insert current page into the KSM table if space permits
    mov rax, [ksm_count]
    cmp rax, 256
    jae .skip_page                  ; Table full, skip insertion

    lea r8, [ksm_table]
    imul rax, ksm_entry_t_size
    lea rdx, [r8 + rax]             ; RDX = target slot

    mov [rdx + ksm_entry_t.phys_addr], rbx
    mov [rdx + ksm_entry_t.virt_addr], r15
    mov [rdx + ksm_entry_t.hash], r10
    inc qword [ksm_count]

.skip_page:
    dec r12                         ; Decrement scan limit count
    add r15, 4096                   ; Next virtual page
    jmp .page_loop

.next_vma:
    mov r14, [r14 + 24]             ; vma = vma->next (offset 24)
    jmp .vma_loop

.done:
    mov rax, r13                    ; Return successfully merged pages count
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; FNV-1a 64-bit Hash Helper
; Input: RDI = virtual address of 4KB page
; Output: RAX = computed 64-bit hash
.fnv_hash:
    mov rax, 0xcbf29ce484222325     ; FNV offset basis
    mov rsi, rdi
    xor rcx, rcx                    ; Byte index
.hash_loop:
    cmp rcx, 4096
    jge .hash_exit
    movzx rdx, byte [rsi + rcx]
    xor rax, rdx
    mov rdx, 0x100000001b3          ; FNV prime
    imul rax, rdx
    inc rcx
    jmp .hash_loop
.hash_exit:
    ret

section .bss
align 8
global ksm_count
ksm_count: dq 0                     ; Active KSM entry count
ksm_table: resb ksm_entry_t_size * 256 ; Dedup database

%endif ; LIB_MEM_VIRT_RECLAIM_KSM_ASM
