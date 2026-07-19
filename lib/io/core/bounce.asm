; =============================================================================
; lib/io/core/bounce.asm
; DMA bounce buffer management for 32-bit addressing controllers.
;
; When a DMA target buffer resides above the 4GB physical address line and
; the controller only supports 32-bit addressing, this module provides
; intermediate "bounce" buffers allocated below 4GB. Data is copied to/from
; the bounce buffer around the actual DMA transfer.
;
; Flow for a READ with bounce:
;   1. bounce_alloc → get a sub-4GB buffer
;   2. Device DMA reads into the bounce buffer
;   3. bounce_copy_out → memcpy bounce → user buffer
;   4. bounce_free → return the buffer to the pool
;
; Flow for a WRITE with bounce:
;   1. bounce_alloc → get a sub-4GB buffer
;   2. bounce_copy_in → memcpy user buffer → bounce
;   3. Device DMA writes from the bounce buffer
;   4. bounce_free → return the buffer to the pool
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_BOUNCE_ASM
%define IO_CORE_BOUNCE_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

; Bounce pool configuration
BOUNCE_POOL_SIZE    equ 16          ; Number of bounce buffer slots
BOUNCE_BUF_SIZE     equ 4096        ; Each bounce buffer is one 4KB page

; Bounce slot descriptor (24 bytes)
; .phys_addr   resq 1 ; Physical address (guaranteed < 4GB)
; .virt_addr   resq 1 ; Virtual address (kernel-mapped)
; .in_use      resq 1 ; 0 = free, 1 = allocated
BOUNCE_SLOT_PHYS    equ 0
BOUNCE_SLOT_VIRT    equ 8
BOUNCE_SLOT_INUSE   equ 16
BOUNCE_SLOT_SIZE    equ 24

section .bss
global bounce_pool
bounce_pool:        resb BOUNCE_SLOT_SIZE * BOUNCE_POOL_SIZE
global bounce_pool_ready
bounce_pool_ready:  resq 1          ; 1 = pool initialized, 0 = not ready

section .text

; =============================================================================
; bounce_init — Pre-allocate the bounce buffer pool below 4GB
; In : None
; Out: RAX = 0 on success, or negative error code
; =============================================================================
IO_FUNC bounce_init
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12

    xor     r12, r12                ; R12 = slot index

.alloc_loop:
    cmp     r12, BOUNCE_POOL_SIZE
    jae     .alloc_done

    ; Allocate one page below 4GB: dma_alloc(4096, 4096, DMA_32BIT=0x01)
    mov     rdi, BOUNCE_BUF_SIZE    ; Size = 4KB
    mov     rsi, BOUNCE_BUF_SIZE    ; Alignment = 4KB
    mov     rdx, 0x01               ; DMA_32BIT flag
    call    dma_alloc
    IS_ERR  rax
    jae     .err_nomem

    ; Store into slot descriptor
    mov     rcx, r12
    imul    rcx, BOUNCE_SLOT_SIZE
    lea     rdx, [rel bounce_pool]
    add     rdx, rcx                ; RDX = -> bounce slot

    mov     [rdx + BOUNCE_SLOT_PHYS], rax    ; Physical address
    mov     [rdx + BOUNCE_SLOT_VIRT], rbx    ; Virtual address
    mov     qword [rdx + BOUNCE_SLOT_INUSE], 0 ; Mark as free

    inc     r12
    jmp     .alloc_loop

.alloc_done:
    mov     qword [rel bounce_pool_ready], 1
    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_nomem:
    mov     rax, IO_ERR_DMA_NOMEM

.done:
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC bounce_init

; =============================================================================
; bounce_alloc — Acquire a bounce buffer from the pool
; In : None
; Out: RAX = physical address of bounce buffer (< 4GB)
;      RBX = virtual address of bounce buffer
;      Or RAX = negative error code if pool exhausted
; =============================================================================
IO_FUNC bounce_alloc
    push    rcx
    push    rdx

    ; Check pool is initialized
    cmp     qword [rel bounce_pool_ready], 1
    jne     .err_not_ready

    ; Linear scan for a free slot
    xor     rcx, rcx                ; RCX = slot index

.scan:
    cmp     rcx, BOUNCE_POOL_SIZE
    jae     .err_full

    mov     rax, rcx
    imul    rax, BOUNCE_SLOT_SIZE
    lea     rdx, [rel bounce_pool]
    add     rdx, rax                ; RDX = -> slot

    cmp     qword [rdx + BOUNCE_SLOT_INUSE], 0
    jne     .next

    ; Found free slot — mark as in-use
    mov     qword [rdx + BOUNCE_SLOT_INUSE], 1
    mov     rax, [rdx + BOUNCE_SLOT_PHYS]
    mov     rbx, [rdx + BOUNCE_SLOT_VIRT]
    jmp     .done

.next:
    inc     rcx
    jmp     .scan

.err_not_ready:
.err_full:
    mov     rax, IO_ERR_DMA_NOMEM
    xor     rbx, rbx

.done:
    pop     rdx
    pop     rcx
IO_ENDFUNC bounce_alloc

; =============================================================================
; bounce_free — Release a bounce buffer back to the pool
; In : RDI = physical address of the bounce buffer to release
; Out: RAX = 0 on success, or IO_ERR_BADARG if address not found
; =============================================================================
IO_FUNC bounce_free
    push    rcx
    push    rdx

    xor     rcx, rcx

.scan:
    cmp     rcx, BOUNCE_POOL_SIZE
    jae     .err_not_found

    mov     rax, rcx
    imul    rax, BOUNCE_SLOT_SIZE
    lea     rdx, [rel bounce_pool]
    add     rdx, rax

    cmp     [rdx + BOUNCE_SLOT_PHYS], rdi
    jne     .next

    ; Found — mark as free
    mov     qword [rdx + BOUNCE_SLOT_INUSE], 0
    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.next:
    inc     rcx
    jmp     .scan

.err_not_found:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdx
    pop     rcx
IO_ENDFUNC bounce_free

; =============================================================================
; bounce_copy_in — Copy data from user buffer INTO a bounce buffer (pre-write)
; In : RDI = -> bounce virtual address (destination)
;      RSI = -> source buffer (user/kernel virtual)
;      RDX = byte count
; Out: None
; =============================================================================
IO_FUNC bounce_copy_in
    guard_null rdi
    guard_null rsi
    push    rcx
    push    rdi
    push    rsi

    mov     rcx, rdx
    shr     rcx, 3                  ; Count of qwords
    rep     movsq                   ; Copy qwords

    mov     rcx, rdx
    and     rcx, 7                  ; Remaining bytes
    rep     movsb                   ; Copy tail bytes

    pop     rsi
    pop     rdi
    pop     rcx
IO_ENDFUNC bounce_copy_in

; =============================================================================
; bounce_copy_out — Copy data from bounce buffer OUT to user buffer (post-read)
; In : RDI = -> user/kernel destination buffer
;      RSI = -> bounce virtual address (source)
;      RDX = byte count
; Out: None
; =============================================================================
IO_FUNC bounce_copy_out
    guard_null rdi
    guard_null rsi
    push    rcx
    push    rdi
    push    rsi

    mov     rcx, rdx
    shr     rcx, 3
    rep     movsq

    mov     rcx, rdx
    and     rcx, 7
    rep     movsb

    pop     rsi
    pop     rdi
    pop     rcx
IO_ENDFUNC bounce_copy_out

%endif ; IO_CORE_BOUNCE_ASM 