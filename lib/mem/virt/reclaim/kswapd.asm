; =============================================================================
; Tattva OS — lib/mem/virt/kswapd.asm
; =============================================================================
; Page-out Daemon (kswapd) implementation for watermark memory reclamation.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_KSWAPD_ASM
%define LIB_MEM_VIRT_KSWAPD_ASM

[BITS 64]

%include "lib/mem/mem.inc"

; Offsets for phys_state_t (locally defined for assembly visibility)
phys_state_t_free_pages_offset     equ 24
phys_state_t_reserved_pages_offset equ 40

section .text

; External symbols


; Watermarks
global kswapd_min_watermark
global kswapd_low_watermark
global kswapd_high_watermark

; -----------------------------------------------------------------------------
; kswapd_init — initializes kswapd watermarks
; -----------------------------------------------------------------------------
global kswapd_init
kswapd_init:
    ; Default watermarks:
    ; Min: 128 pages (512KB)
    ; Low: 256 pages (1MB)
    ; High: 512 pages (2MB)
    mov qword [kswapd_min_watermark], 128
    mov qword [kswapd_low_watermark], 256
    mov qword [kswapd_high_watermark], 512
    mov byte [kswapd_running], 0
    ret

; -----------------------------------------------------------------------------
; kswapd_check_and_reclaim — checks watermarks and evicts pages if necessary
; Input:  none
; Output: RAX = number of pages reclaimed
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global kswapd_check_and_reclaim
kswapd_check_and_reclaim:
    push rbx
    push r12
    push r13

    ; Avoid recursive calls if kswapd allocation itself triggers check
    mov al, [kswapd_running]
    test al, al
    jnz .no_run

    ; Acquire running guard lock
    mov byte [kswapd_running], 1

    ; Get current free page count
    mov rax, phys_state
    mov r12, [rax + phys_state_t_free_pages_offset] ; R12 = free_pages
    
    ; Compare with min watermark
    cmp r12, [kswapd_min_watermark]
    jb .direct_reclaim

    ; Compare with low watermark
    cmp r12, [kswapd_low_watermark]
    jae .done_reclaim                ; free_pages >= low_watermark, exit

    ; RAM has dropped below low watermark! Run sweeps.
    mov rsi, msg_kswapd_wake
    call uart_print_str
    jmp .start_sweeps

.direct_reclaim:
    ; RAM has dropped below min watermark! Run direct reclaim.
    mov rsi, msg_kswapd_direct
    call uart_print_str

.start_sweeps:
    xor r13, r13                    ; R13 = count of pages reclaimed

    ; --- Slab Reaping Pass ---
    xor r14, r14                    ; R14 = count of slabs/pages reaped

    mov rdi, kmem_cache_file
    call kmem_cache_reap
    add r14, rax

    mov rdi, kmem_cache_task
    call kmem_cache_reap
    add r14, rax

    mov rdi, kmem_cache_vma
    call kmem_cache_reap
    add r14, rax

    test r14, r14
    jz .skip_slab_reclaim_update

    ; Update physical telemetry stats
    mov rax, phys_state
    add [rax + phys_state_t_free_pages_offset], r14
    sub [rax + phys_state_t_reserved_pages_offset], r14

    add r13, r14                    ; add to total pages reclaimed count

.skip_slab_reclaim_update:

.sweep_loop:
    ; Check if we hit the high watermark
    mov rax, phys_state
    mov rcx, [rax + phys_state_t_free_pages_offset]
    cmp rcx, [kswapd_high_watermark]
    jae .sweep_done

    ; Evict one page
    call page_replace_clock_evict
    test rax, rax
    jz .sweep_stuck                 ; no more eviction candidates or swap is full

    inc r13
    jmp .sweep_loop

.sweep_stuck:
    mov rsi, msg_kswapd_stuck
    call uart_print_str
    jmp .sweep_done

.sweep_done:
    test r13, r13
    jz .done_reclaim

    mov rsi, msg_kswapd_done
    call uart_print_str
    
.done_reclaim:
    mov byte [kswapd_running], 0
    mov rax, r13                    ; return pages reclaimed
    jmp .exit

.no_run:
    xor rax, rax

.exit:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; kswapd_check_and_reclaim_node — checks watermarks for a specific NUMA node
; Input:
;   RDI = pointer to numa_node_t
;   RSI = direct_reclaim flag (0 = background, 1 = direct)
; Output: RAX = number of pages reclaimed from node
; Clobbers: RAX, RCX, RDX, R8-R11
; -----------------------------------------------------------------------------
global kswapd_check_and_reclaim_node
kswapd_check_and_reclaim_node:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = pointer to numa_node_t
    mov r13, rsi                    ; R13 = direct_reclaim flag
    mov r14d, dword [r12 + numa_node_t.node_id] ; R14 = node_id

    ; Avoid recursive calls if kswapd allocation itself triggers check
    mov al, [kswapd_running]
    test al, al
    jnz .node_no_run

    ; Acquire running guard lock
    mov byte [kswapd_running], 1

    ; Get current free pages for this node
    mov r8, [r12 + numa_node_t.free_pages]

    ; Check if direct reclaim
    test r13, r13
    jnz .node_direct_check

    ; Background check: compare with pages_low
    cmp r8, [r12 + numa_node_t.pages_low]
    jae .node_done_reclaim          ; free_pages >= pages_low, exit

    ; Node free RAM below low watermark! Run sweeps.
    mov rsi, msg_kswapd_node_wake
    call uart_print_str
    mov rax, r14
    call uart_print_dec
    mov rsi, msg_kswapd_node_wake_low
    call uart_print_str
    jmp .node_start_sweeps

.node_direct_check:
    ; Direct check: compare with pages_min
    cmp r8, [r12 + numa_node_t.pages_min]
    jae .node_done_reclaim          ; free_pages >= pages_min, exit

    ; Node free RAM below min watermark! Run direct sweeps.
    mov rsi, msg_kswapd_node_wake
    call uart_print_str
    mov rax, r14
    call uart_print_dec
    mov rsi, msg_kswapd_node_wake_min
    call uart_print_str

.node_start_sweeps:
    xor r15, r15                    ; R15 = count of pages reclaimed from node

    ; --- Slab Reaping Pass (helps global memory pressure) ---
    xor rbp, rbp                    ; RBP = count of slabs/pages reaped globally
    mov rdi, kmem_cache_file
    call kmem_cache_reap
    add rbp, rax
    mov rdi, kmem_cache_task
    call kmem_cache_reap
    add rbp, rax
    mov rdi, kmem_cache_vma
    call kmem_cache_reap
    add rbp, rax

    test rbp, rbp
    jz .node_skip_slab_reclaim_update

    ; Update physical telemetry stats
    mov rax, phys_state
    add [rax + phys_state_t_free_pages_offset], rbp
    sub [rax + phys_state_t_reserved_pages_offset], rbp

.node_skip_slab_reclaim_update:

.node_sweep_loop:
    ; Check if node hit pages_high
    mov rax, [r12 + numa_node_t.free_pages]
    cmp rax, [r12 + numa_node_t.pages_high]
    jae .node_sweep_done

    ; Evict one page from target node
    mov rdi, r14                    ; target node_id
    call page_replace_clock_evict_node ; RAX = 1 (success), 0 (failed)
    test rax, rax
    jz .node_sweep_stuck

    inc r15
    jmp .node_sweep_loop

.node_sweep_stuck:
    mov rsi, msg_kswapd_node_stuck
    call uart_print_str
    mov rax, r14
    call uart_print_dec
    mov rsi, msg_kswapd_node_stuck_suffix
    call uart_print_str
    jmp .node_sweep_done

.node_sweep_done:
    test r15, r15
    jz .node_done_reclaim

    mov rsi, msg_kswapd_node_done
    call uart_print_str
    mov rax, r14
    call uart_print_dec
    mov rsi, msg_kswapd_node_done_suffix
    call uart_print_str

.node_done_reclaim:
    mov byte [kswapd_running], 0
    mov rax, r15                    ; return pages reclaimed from this node
    jmp .node_exit

.node_no_run:
    xor rax, rax

.node_exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_proactive_reclaim — proactively reclaims a target number of pages
; Input:
;   RDI = target_pages to reclaim
; Output:
;   RAX = actual pages reclaimed
; -----------------------------------------------------------------------------
global virt_proactive_reclaim
virt_proactive_reclaim:
    push rbx
    push r12
    push r13
    
    mov r12, rdi                    ; R12 = target_pages
    xor r13, r13                    ; R13 = actual reclaimed count
    
.loop:
    cmp r13, r12
    jae .done
    
    call page_replace_clock_evict
    test rax, rax
    jz .done
    
    inc r13
    jmp .loop
    
.done:
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; virt_proactive_reclaim_node — proactively reclaims target pages from specific node
; Input:
;   RDI = node_id
;   RSI = target_pages to reclaim
; Output:
;   RAX = actual pages reclaimed
; -----------------------------------------------------------------------------
global virt_proactive_reclaim_node
virt_proactive_reclaim_node:
    push rbx
    push r12
    push r13
    push r14
    
    mov r12, rdi                    ; R12 = node_id
    mov r13, rsi                    ; R13 = target_pages
    xor r14, r14                    ; R14 = actual reclaimed count
    
.loop:
    cmp r14, r13
    jae .done
    
    mov rdi, r12
    call page_replace_clock_evict_node
    test rax, rax
    jz .done
    
    inc r14
    jmp .loop
    
.done:
    mov rax, r14
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; kswapd_proactive_reclaim — runs proactive sweeps if free RAM below headroom
; -----------------------------------------------------------------------------
global kswapd_proactive_reclaim
kswapd_proactive_reclaim:
    push rbx
    push r12
    push r13

    mov al, [kswapd_running]
    test al, al
    jnz .no_run

    mov rax, [sys_proactive_reclaim_headroom]
    test rax, rax
    jz .no_run

    mov byte [kswapd_running], 1

    ; Check if free pages < headroom
    mov rax, phys_state
    mov r12, [rax + phys_state_t_free_pages_offset]
    cmp r12, [sys_proactive_reclaim_headroom]
    jae .done_reclaim

    mov rsi, msg_kswapd_proactive
    call uart_print_str

    xor r13, r13
.sweep_loop:
    ; Check if we hit headroom + 256
    mov rax, phys_state
    mov rcx, [rax + phys_state_t_free_pages_offset]
    mov rdx, [sys_proactive_reclaim_headroom]
    add rdx, 256
    cmp rcx, rdx
    jae .sweep_done

    call page_replace_clock_evict
    test rax, rax
    jz .sweep_done

    inc r13
    jmp .sweep_loop

.sweep_done:
    test r13, r13
    jz .done_reclaim
    mov rsi, msg_kswapd_done
    call uart_print_str

.done_reclaim:
    mov byte [kswapd_running], 0
.no_run:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; kswapd_proactive_reclaim_node — runs proactive sweeps on node if below headroom
; Input:
;   RDI = pointer to numa_node_t
; -----------------------------------------------------------------------------
global kswapd_proactive_reclaim_node
kswapd_proactive_reclaim_node:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = numa_node_t pointer
    mov r14d, dword [r12 + numa_node_t.node_id] ; R14 = node_id

    mov al, [kswapd_running]
    test al, al
    jnz .no_run

    mov rax, [r12 + numa_node_t.proactive_reclaim_headroom]
    test rax, rax
    jz .no_run

    mov byte [kswapd_running], 1

    ; Check if free pages < headroom
    mov r8, [r12 + numa_node_t.free_pages]
    cmp r8, [r12 + numa_node_t.proactive_reclaim_headroom]
    jae .done_reclaim

    mov rsi, msg_kswapd_node_wake
    call uart_print_str
    mov rax, r14
    call uart_print_dec
    mov rsi, msg_kswapd_node_proactive_suffix
    call uart_print_str

    xor r15, r15
.sweep_loop:
    ; Check if node hit headroom + 256
    mov rax, [r12 + numa_node_t.free_pages]
    mov rcx, [r12 + numa_node_t.proactive_reclaim_headroom]
    add rcx, 256
    cmp rax, rcx
    jae .sweep_done

    mov rdi, r14
    call page_replace_clock_evict_node
    test rax, rax
    jz .sweep_done

    inc r15
    jmp .sweep_loop

.sweep_done:
    test r15, r15
    jz .done_reclaim
    mov rsi, msg_kswapd_node_done
    call uart_print_str
    mov rax, r14
    call uart_print_dec
    mov rsi, msg_kswapd_node_done_suffix
    call uart_print_str

.done_reclaim:
    mov byte [kswapd_running], 0
.no_run:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .data

align 8
global sys_proactive_reclaim_headroom
sys_proactive_reclaim_headroom: dq 0
kswapd_min_watermark:  dq 0
kswapd_low_watermark:  dq 0
kswapd_high_watermark: dq 0
kswapd_running:        db 0

msg_kswapd_wake:    db "[kswapd] Free RAM below low watermark. Running page-out sweeps...", 0x0D, 0x0A, 0
msg_kswapd_direct:  db "[kswapd] Free RAM below min watermark. Running direct reclaim...", 0x0D, 0x0A, 0
msg_kswapd_proactive: db "[kswapd] Free RAM below proactive headroom. Running proactive reclaim sweeps...", 0x0D, 0x0A, 0
msg_kswapd_stuck:   db "[kswapd] Sweeps halted: no more eviction candidates or swap is full.", 0x0D, 0x0A, 0
msg_kswapd_done:    db "[kswapd] Sweeps complete. Free RAM restored above high watermark.", 0x0D, 0x0A, 0

msg_kswapd_node_wake:          db "[kswapd] Node ", 0
msg_kswapd_node_wake_low:      db " Free RAM below low watermark. Running page-out sweeps...", 0x0D, 0x0A, 0
msg_kswapd_node_wake_min:      db " Free RAM below min watermark. Running direct reclaim...", 0x0D, 0x0A, 0
msg_kswapd_node_proactive_suffix: db " Free RAM below proactive headroom. Running proactive reclaim sweeps...", 0x0D, 0x0A, 0
msg_kswapd_node_stuck:         db "[kswapd] Node ", 0
msg_kswapd_node_stuck_suffix:  db " sweeps halted: no more eviction candidates or swap is full.", 0x0D, 0x0A, 0
msg_kswapd_node_done:          db "[kswapd] Node ", 0
msg_kswapd_node_done_suffix:   db " sweeps complete. Free RAM restored above high watermark.", 0x0D, 0x0A, 0

%endif ; LIB_MEM_VIRT_KSWAPD_ASM
