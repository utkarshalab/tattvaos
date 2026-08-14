; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/numa_balance.asm
; =============================================================================
; Dynamic Tiering across N-Tier Fabrics / NUMA Balancing (Feature 10).
; Monitors page access patterns, identifies 'cold' pages in DDR5 (Node 0),
; and migrates them dynamically to slow/capacity fabric memory (Node 1 / CXL).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_NUMA_BALANCE_ASM
%define LIB_MEM_VIRT_RECLAIM_NUMA_BALANCE_ASM

[BITS 64]

; NUMA Node structure offsets (from numa_node_t)
numa_node_t.start_page equ 8
numa_node_t.end_page   equ 16

section .text




; -----------------------------------------------------------------------------
; numa_balance_tiers — scans processes, identifies cold pages, migrates Node 0 -> Node 1
; Input: none
; Output:
;   RAX = number of pages migrated
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global numa_balance_tiers
numa_balance_tiers:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    xor r13, r13                    ; R13 = migration counter

    ; 1. Allocate coldness counters if NULL
    mov rax, [coldness_counters]
    test rax, rax
    jnz .have_counters

    mov rax, [buddy_end_addr]
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = total page count N
    mov r12, rax                    ; R12 = N

    mov rdi, r12                    ; Allocate 1 byte per page
    call heap_alloc
    test rax, rax
    jz .done                        ; OOM, exit

    mov [coldness_counters], rax
    
    ; Zero out counter array
    mov rdi, rax
    mov rsi, r12
    call memzero

.have_counters:
    mov r14, [vma_list_head]        ; R14 = VMA linked list head

.vma_loop:
    test r14, r14
    jz .done

    ; vma_t: .start (offset 0), .end (offset 8), .next (offset 24)
    mov r15, [r14]                  ; R15 = start vaddr
    mov rbp, [r14 + 8]              ; RBP = end vaddr (exclusive)

.page_loop:
    cmp r15, rbp
    jae .next_vma

    ; Locate PTE pointer for r15
    mov rdi, r15
    xor rsi, rsi                    ; CR3
    call virt_walk_table            ; RAX = PTE pointer
    test rax, rax
    jz .skip_page
    
    mov rdx, [rax]
    test rdx, 0x01                  ; Present?
    jz .skip_page
    test rdx, 0x80                  ; Skip huge pages (2MB) for page-level migration
    jnz .skip_page

    mov r8, rax                     ; R8 = PTE pointer
    mov rbx, rdx
    and rbx, 0xFFFFFFFFFFFFF000     ; RBX = physical page address

    ; Calculate PFN relative to buddy start
    mov rax, rbx
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = PFN (index into counter array)
    
    ; Verify PFN is within Node 0 range to check if it's on Node 0
    ; Node 0 start_page is at numa_nodes + 8
    ; Node 0 end_page is at numa_nodes + 16
    lea rcx, [numa_nodes]
    mov r9, [rcx + numa_node_t.start_page]
    cmp rax, r9
    jb .skip_page
    mov r9, [rcx + numa_node_t.end_page]
    cmp rax, r9
    jae .skip_page

    ; PFN is on Node 0! Retrieve its coldness counter pointer
    mov rsi, [coldness_counters]
    lea rsi, [rsi + rax]            ; RSI = counter_ptr

    ; 2. Check Accessed bit (bit 5) in PTE value
    test rdx, (1 << 5)
    jz .is_cold

    ; Page is active (Accessed bit is set). Reset coldness and clear Accessed bit.
    and qword [r8], ~(1 << 5)       ; Clear accessed bit
    mov byte [rsi], 0
    invlpg [r15]                    ; Invalidate TLB line
    jmp .skip_page

.is_cold:
    inc byte [rsi]                  ; Increment coldness counter
    cmp byte [rsi], 5               ; Cold threshold = 5 consecutive cycles
    jb .skip_page

    ; 3. Page is COLD! Migrate to Node 1 (CXL)
    ; Save loop variables on stack before function call
    push rsi
    push r8

    mov rdi, 1                      ; Allocate page on Node 1 (CXL)
    call phys_alloc_page_node       ; RAX = physical address (Node 1)
    
    pop r8
    pop rsi
    test rax, rax
    jz .skip_page                   ; OOM on Node 1, abort migration

    mov r12, rax                    ; R12 = physical page (Node 1)

    ; Copy 4KB data from Node 0 frame to Node 1 frame
    ; rep movsq clobbers RSI, RDI, RCX.
    ; Source = RBX (identity mapped), Dest = R12 (identity mapped)
    push rsi
    mov rsi, rbx
    mov rdi, r12
    mov rcx, 512                    ; 512 qwords
    cld
    rep movsq
    pop rsi

    ; Update PTE: swap physical base pointer with Node 1 address, keep other flags
    mov rdx, [r8]
    mov rcx, 0xFFF0000000000FFF
    and rdx, rcx                    ; RDX = flags only
    or rdx, r12                     ; RDX = Node 1 address + flags
    mov [r8], rdx                   ; Write new PTE!

    ; Invalidate TLB
    invlpg [r15]

    ; Free old Node 0 physical frame
    push rsi
    mov rdi, rbx
    call phys_free_page
    pop rsi

    mov byte [rsi], 0               ; Reset coldness counter
    inc r13                         ; Increment migration count

.skip_page:
    add r15, 4096                   ; Next page
    jmp .page_loop

.next_vma:
    mov r14, [r14 + 24]             ; vma = vma->next (offset 24)
    jmp .vma_loop

.done:
    mov rax, r13                    ; Return successfully migrated pages count
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .bss
alignb 8
global coldness_counters
coldness_counters: resq 1           ; Array of coldness counter bytes

%endif ; LIB_MEM_VIRT_RECLAIM_NUMA_BALANCE_ASM
