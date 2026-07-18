; =============================================================================
; lib/io/dma/sg.asm
; Scatter-Gather DMA list translation and page table walking.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_DMA_SG_ASM
%define IO_DMA_SG_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; =============================================================================
; dma_sg_init — Translate a virtual address range into physical iovec_t scatter list
; In : RDI = -> iovec_t destination array
;      RSI = Virtual base address of the buffer
;      RDX = Buffer size in bytes
;      RCX = -> iovec_cnt output variable (returns count)
; Out: RAX = 0 on success, or a negative error band code (IO_ERR_BADARG) on failure
; =============================================================================
IO_FUNC dma_sg_init
    guard_null rdi
    guard_null rsi
    guard_null rcx

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; R12 = iovec_t array pointer
    mov     r13, rsi                ; R13 = virtual base pointer
    mov     r14, rdx                ; R14 = remaining size in bytes
    mov     r15, rcx                ; R15 = pointer to count output

    xor     r8, r8                  ; R8 = iovec element index counter
    xor     r9, r9                  ; R9 = previous physical page base address

.translate_loop:
    test    r14, r14
    jz      .loop_done              ; Reached end of buffer

    ; 1. Resolve current virtual address to physical
    mov     rdi, r13
    call    virt_to_phys
    test    rax, rax
    jz      .err_unmapped           ; Page not mapped, error!

    mov     rbx, rax                ; RBX = physical address

    ; 2. Determine size of chunk within current page
    mov     rcx, r13
    and     rcx, 4095               ; RCX = offset within page
    mov     rdx, 4096
    sub     rdx, rcx                ; RDX = space remaining in current page

    cmp     r14, rdx
    cmovg   rax, rdx
    cmovle  rax, r14                ; RAX = bytes to consume in this page

    ; 3. Check if we can merge with the previous iovec element
    test    r8, r8
    jz      .new_element            ; First element, cannot merge

    ; Merge criteria:
    ; a. Current virtual address matches last virtual end: iov[r8-1].base + iov[r8-1].len == r13
    ; b. Current physical address matches last physical end: iov[r8-1].phys + iov[r8-1].len == rbx
    mov     rcx, r8
    dec     rcx
    imul    rcx, iovec_t_size
    add     rcx, r12                ; RCX = -> iov[r8-1]

    mov     r10, [rcx + iovec_t.base]
    add     r10, [rcx + iovec_t.len]
    cmp     r10, r13
    jne     .new_element

    mov     r10, [rcx + iovec_t.phys]
    add     r10, [rcx + iovec_t.len]
    cmp     r10, rbx
    jne     .new_element

    ; Contiguous, merge: add bytes to last element's length
    add     [rcx + iovec_t.len], rax
    jmp     .advance

.new_element:
    ; Non-contiguous, write new iovec_t entry
    mov     rcx, r8
    imul    rcx, iovec_t_size
    add     rcx, r12                ; RCX = pointer to current iovec_t slot

    mov     [rcx + iovec_t.base], r13
    mov     [rcx + iovec_t.phys], rbx
    mov     [rcx + iovec_t.len], rax
    mov     qword [rcx + iovec_t.flags], 0

    inc     r8                      ; Increment iovec element count

.advance:
    add     r13, rax                ; Advance virtual address pointer
    sub     r14, rax                ; Reduce remaining bytes count
    jmp     .translate_loop

.loop_done:
    ; Save count to output variable
    mov     [r15], r8
    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_unmapped:
    mov     rax, IO_ERR_BADARG

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC dma_sg_init

; =============================================================================
; virt_to_phys — Walk x86-64 page tables to resolve virtual address to physical.
; In : RDI = Virtual Address
; Out: RAX = Physical Address (or 0 if not mapped)
; =============================================================================
global virt_to_phys
virt_to_phys:
    push    rbx
    push    rcx
    push    rdx

    ; Load mask to strip NX (bit 63) and reserved bits
    mov     rbx, 0x000FFFFFFFFFF000

    ; 1. Load CR3 physical base address
    mov     rdx, cr3
    and     rdx, rbx                ; RDX = PML4 physical base address

    ; 2. Traverse PML4 (bits 39-47)
    mov     rcx, rdi
    shr     rcx, 39
    and     rcx, 0x1FF              ; RCX = PML4 Index
    mov     rax, [rdx + rcx * 8]    ; RAX = PML4 Entry
    test    al, 0x01                ; Present bit
    jz      .not_mapped
    and     rax, rbx
    mov     rdx, rax                ; RDX = PDPT physical base address

    ; 3. Traverse PDPT (bits 30-38)
    mov     rcx, rdi
    shr     rcx, 30
    and     rcx, 0x1FF              ; RCX = PDPT Index
    mov     rax, [rdx + rcx * 8]    ; RAX = PDPT Entry
    test    al, 0x01
    jz      .not_mapped
    
    ; Check if 1GB huge page (bit 7 PS = Page Size)
    test    al, 0x80
    jnz     .huge_1gb
    
    and     rax, rbx
    mov     rdx, rax                ; RDX = PD physical base address

    ; 4. Traverse PD (bits 21-29)
    mov     rcx, rdi
    shr     rcx, 21
    and     rcx, 0x1FF              ; RCX = PD Index
    mov     rax, [rdx + rcx * 8]    ; RAX = PD Entry
    test    al, 0x01
    jz      .not_mapped

    ; Check if 2MB huge page (bit 7 PS)
    test    al, 0x80
    jnz     .huge_2mb

    and     rax, rbx
    mov     rdx, rax                ; RDX = PT physical base address

    ; 5. Traverse PT (bits 12-20)
    mov     rcx, rdi
    shr     rcx, 12
    and     rcx, 0x1FF              ; RCX = PT Index
    mov     rax, [rdx + rcx * 8]    ; RAX = PT Entry
    test    al, 0x01
    jz      .not_mapped

    ; 4KB Page resolve: physical page address + offset in page
    and     rax, rbx
    mov     rcx, rdi
    and     rcx, 0xFFF              ; Offset in 4KB page
    add     rax, rcx
    jmp     .done

.huge_1gb:
    ; 1GB Page resolve: physical page address + offset in 1GB
    and     rax, rbx
    and     rax, ~0x3FFFFFFF        ; Clear lower 30 bits
    mov     rcx, rdi
    mov     rdx, 0x3FFFFFFF         ; 1GB offset mask
    and     rcx, rdx
    add     rax, rcx
    jmp     .done

.huge_2mb:
    ; 2MB Page resolve: physical page address + offset in 2MB
    and     rax, rbx
    and     rax, ~0x1FFFFF          ; Clear lower 21 bits
    mov     rcx, rdi
    mov     rdx, 0x1FFFFF           ; 2MB offset mask
    and     rcx, rdx
    add     rax, rcx
    jmp     .done

.not_mapped:
    xor     rax, rax

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret

%endif ; IO_DMA_SG_ASM
