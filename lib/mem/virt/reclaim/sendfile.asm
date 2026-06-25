; =============================================================================
; Tattva OS — lib/mem/virt/reclaim/sendfile.asm
; =============================================================================
; Zero-Copy Network & Storage Unified Buffer Pool (Feature 13).
; Passes page cache pages directly to network sockets without copying,
; pinning the page frame descriptor during DMA transmission.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_RECLAIM_SENDFILE_ASM
%define LIB_MEM_VIRT_RECLAIM_SENDFILE_ASM

[BITS 64]

; Mock file structure definition
struc mock_file_t
    .size       resq 1
    .blocks     resq 32
endstruc

; page_t structure definition (matching zone_movable.asm)
struc page_t
    .flags:     resq 1          ; Bit 12 = PAGE_MOVABLE, Bit 13 = PAGE_PINNED
    .lock:      resq 1          ; Spinlock (0 = free, 1 = locked)
endstruc

section .text

extern buddy_start_addr
extern pages_array
extern virt_page_cache_find

; -----------------------------------------------------------------------------
; sys_sendfile — transfers data from file directly to socket descriptor
; Input:
;   RDI = file_ptr   (mock_file_t*)
;   RSI = socket_ptr (mock socket destination)
;   RDX = offset     (file offset in bytes)
;   RCX = count      (number of bytes to transmit)
; Output:
;   RAX = bytes sent on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global sys_sendfile
sys_sendfile:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; R12 = file_ptr
    mov r13, rsi                    ; R13 = socket_ptr
    mov r14, rdx                    ; R14 = offset
    mov r15, rcx                    ; R15 = count

    test r12, r12
    jz .fail
    test r15, r15
    jz .fail

    ; 1. Retrieve the filesystem buffer page matching the offset from cache
    mov rdi, r12                    ; file_ptr
    mov rsi, r14                    ; offset
    call virt_page_cache_find       ; RAX = physical page address (or 0)
    test rax, rax
    jnz .found_page

    ; Cache miss, fallback to looking up in the file block array directly
    mov rax, r14
    shr rax, 12                     ; block index = offset / 4096
    cmp rax, 32
    jae .fail                       ; Offset out of range
    
    mov rax, [r12 + mock_file_t.blocks + rax * 8]
    test rax, rax
    jz .fail                        ; Block not allocated/present

.found_page:
    ; RAX = physical page address of file buffer page
    mov rbx, rax                    ; RBX = physical page address

    ; 2. Lock page metadata descriptor (page_t) to set page.pinned = 1
    ; Calculate PFN = (physical page - buddy_start_addr) / 4096
    mov rax, rbx
    sub rax, [buddy_start_addr]
    shr rax, 12                     ; RAX = PFN

    ; Locate the page_t pointer in pages_array
    mov r8, [pages_array]
    test r8, r8
    jz .simulate_dma                ; If pages_array is NULL, skip pinning lock and do DMA

    imul rax, 16                    ; RAX = PFN * page_t_size (16 bytes)
    lea rbp, [r8 + rax]             ; RBP = &pages_array[PFN]

    ; Acquire page_t spinlock
.lock_page_spin:
    lock bts qword [rbp + page_t.lock], 0
    jc .lock_page_pause
    jmp .lock_page_acquired

.lock_page_pause:
    pause
    test qword [rbp + page_t.lock], 1
    jnz .lock_page_pause
    jmp .lock_page_spin

.lock_page_acquired:
    ; Pin the page by setting PAGE_PINNED (bit 13) in flags to 1
    or qword [rbp + page_t.flags], (1 << 13)

    ; Release spinlock on descriptor
    mov qword [rbp + page_t.lock], 0

.simulate_dma:
    ; 3. Map physical address directly into network card's DMA descriptor ring
    ; (Simulate DMA transfer of 'count' bytes from the physical page to socket)
    ; Update bytes sent telemetry
    add [sys_sendfile_bytes_sent], r15

    ; 4. Simulate network hardware transmit completion interrupt
    ; Decrement/clear the pin count/ref flag
    mov r8, [pages_array]
    test r8, r8
    jz .success                     ; Skip unpinning if no pages_array

    ; Acquire spinlock again to modify flags
.lock_page_spin_unpin:
    lock bts qword [rbp + page_t.lock], 0
    jc .lock_page_pause_unpin
    jmp .lock_page_acquired_unpin

.lock_page_pause_unpin:
    pause
    test qword [rbp + page_t.lock], 1
    jnz .lock_page_pause_unpin
    jmp .lock_page_spin_unpin

.lock_page_acquired_unpin:
    ; Unpin the page: clear PAGE_PINNED (bit 13) flag
    and qword [rbp + page_t.flags], ~(1 << 13)

    ; Release spinlock
    mov qword [rbp + page_t.lock], 0

.success:
    mov rax, r15                    ; Return number of bytes successfully sent
    jmp .exit

.fail:
    xor rax, rax                    ; Return 0 (failure)

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

section .data
global sys_sendfile_bytes_sent
sys_sendfile_bytes_sent: dq 0        ; Total zero-copy bytes transmitted

%endif ; LIB_MEM_VIRT_RECLAIM_SENDFILE_ASM
