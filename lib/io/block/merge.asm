; =============================================================================
; lib/io/block/merge.asm
; Block I/O request merging and SGL contiguous fusion.
;
; Coalesces adjacent logical block address (LBA) requests targeting the same
; device into single large physical transactions. This reduces descriptors
; pressure and doorbell notifications overhead under streaming workloads.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_MERGE_ASM
%define IO_BLOCK_MERGE_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; Map capacity config
MERGE_POOL_SIZE     equ 128         ; Support up to 128 concurrently merged requests
MERGE_ENTRY_PARENT  equ 0           ; Offset 0: Parent request pointer (64-bit)
MERGE_ENTRY_CHILD   equ 8           ; Offset 8: Child request pointer (64-bit)
MERGE_ENTRY_SIZE    equ 16          ; Descriptor size = 16 bytes

section .bss
alignb 16
global global_merge_map
global_merge_map:   resb MERGE_ENTRY_SIZE * MERGE_POOL_SIZE

section .text

; =============================================================================
; bdev_merge_requests — Try to merge a second contiguous request into the first
; In : RDI = -> io_request_t (parent request)
;      RSI = -> io_request_t (child request to merge)
; Out: RAX = 0 on success (merged), or negative error code (IO_ERR_BADARG)
; RSO: RDI, RSI owned-in; RAX owned-out
; =============================================================================
IO_FUNC bdev_merge_requests
    guard_null rdi
    guard_null rsi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     r12, rdi                ; R12 = -> req1 (parent)
    mov     r13, rsi                ; R13 = -> req2 (child)

    ; 1. Verification checks: Must target same device
    mov     rax, [r12 + io_request_t.device]
    cmp     rax, [r13 + io_request_t.device]
    jne     .err_incompatible

    ; Must have same opcode (read vs write)
    mov     rax, [r12 + io_request_t.opcode]
    cmp     rax, [r13 + io_request_t.opcode]
    jne     .err_incompatible

    ; Must be contiguous: req1.lba + req1.nblocks == req2.lba
    mov     rax, [r12 + io_request_t.lba]
    add     rax, [r12 + io_request_t.nblocks]
    cmp     rax, [r13 + io_request_t.lba]
    jne     .err_incompatible

    ; Check Combined scatter-gather list limits (max IOVEC_MAX_ENTRIES = 64)
    mov     rax, [r12 + io_request_t.iov_cnt]
    add     rax, [r13 + io_request_t.iov_cnt]
    cmp     rax, 64
    ja      .err_incompatible       ; Exceeds combined SGL descriptors limit

    ; 2. Scan for a free slot in the merge relationship map
    lea     rbx, [rel global_merge_map]
    xor     rcx, rcx                ; RCX = index iterator

.scan_free:
    cmp     rcx, MERGE_POOL_SIZE
    jae     .err_full

    mov     rdx, rcx
    shl     rdx, 4                  ; index * 16
    lea     rax, [rbx + rdx]        ; RAX = -> slot

    cmp     qword [rax + MERGE_ENTRY_PARENT], 0
    jz      .populate

    inc     rcx
    jmp     .scan_free

.populate:
    ; Record parent-child relationship
    mov     [rax + MERGE_ENTRY_PARENT], r12
    mov     [rax + MERGE_ENTRY_CHILD], r13

    ; 3. Perform buffer/SGL fusion: Copy iovec_t array elements from child into parent
    mov     rbx, [r12 + io_request_t.iov]      ; RBX = parent iov array base
    mov     rdx, [r12 + io_request_t.iov_cnt]  ; RDX = parent current count
    imul    rdx, iovec_t_size
    add     rbx, rdx                           ; RBX = parent target offset pointer

    mov     rsi, [r13 + io_request_t.iov]      ; RSI = child source iov base
    mov     rcx, [r13 + io_request_t.iov_cnt]  ; RCX = child count
    imul    rcx, iovec_t_size                  ; RCX = total bytes to copy

    rep     movsb                              ; Copy descriptors array

    ; Update parent stats
    mov     rax, [r13 + io_request_t.iov_cnt]
    add     [r12 + io_request_t.iov_cnt], rax

    mov     rax, [r13 + io_request_t.nblocks]
    add     [r12 + io_request_t.nblocks], rax

    xor     rax, rax                           ; Return 0 (Success)
    jmp     .done

.err_full:
    mov     rax, IO_ERR_NOMEM
    jmp     .done

.err_incompatible:
    mov     rax, IO_ERR_BADARG

.done:
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC bdev_merge_requests

; =============================================================================
; bdev_complete_merged_children — Walk merge map and complete child requests
; In : RDI = -> parent io_request_t structure
;      RSI = Status code (0 on success, negative on error)
;      RDX = Result code (transferred count)
; =============================================================================
IO_FUNC bdev_complete_merged_children
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; R12 = -> parent request
    mov     r13, rsi                ; R13 = status
    mov     r14, rdx                ; R14 = result

    lea     rbx, [rel global_merge_map]
    xor     rcx, rcx                ; RCX = index iterator

.scan_loop:
    cmp     rcx, MERGE_POOL_SIZE
    jae     .done

    mov     rdx, rcx
    shl     rdx, 4                  ; index * 16
    lea     rax, [rbx + rdx]

    cmp     [rax + MERGE_ENTRY_PARENT], r12
    jne     .next

    ; Found child request!
    mov     rdi, [rax + MERGE_ENTRY_CHILD] ; RDI = child request pointer
    
    ; Clear slot relationship first to prevent loops
    mov     qword [rax + MERGE_ENTRY_PARENT], 0
    mov     qword [rax + MERGE_ENTRY_CHILD], 0

    ; Recursively complete the child request
    mov     rsi, r13
    mov     rdx, r14
    call    io_complete_request

.next:
    inc     rcx
    jmp     .scan_loop

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC bdev_complete_merged_children

%endif ; IO_BLOCK_MERGE_ASM
