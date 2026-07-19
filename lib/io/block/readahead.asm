; =============================================================================
; lib/io/block/readahead.asm
; Sequential read-ahead prefetching engine and block cache.
;
; Detects sequential sector read sequences and proactively issues asynchronous
; read commands for adjacent subsequent sectors into a temporary memory cache
; before they are explicitly requested by the filesystem.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_READAHEAD_ASM
%define IO_BLOCK_READAHEAD_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; Readahead Tracking Pool Configuration (64 devices max)
TRACK_POOL_SIZE     equ 64
TRACK_ENTRY_DEV     equ 0           ; Offset 0: device_t * (64-bit)
TRACK_ENTRY_LBA     equ 8           ; Offset 8: last LBA read (64-bit)
TRACK_ENTRY_CNT     equ 16          ; Offset 16: last block count read (64-bit)
TRACK_ENTRY_SIZE    equ 24

; Cache Pool Configuration (16 concurrent 4KB slots)
CACHE_POOL_SIZE     equ 16
CACHE_ENTRY_DEV     equ 0           ; Offset 0: device_t * (64-bit)
CACHE_ENTRY_LBA     equ 8           ; Offset 8: start LBA (64-bit)
CACHE_ENTRY_VIRT    equ 16          ; Offset 16: virtual address of 4KB buffer (64-bit)
CACHE_ENTRY_PHYS    equ 24          ; Offset 24: physical address of 4KB buffer (64-bit)
CACHE_ENTRY_STATE   equ 32          ; Offset 32: 0=free, 1=valid, 2=reading (64-bit)
CACHE_ENTRY_SIZE    equ 40

section .bss
align 16
global global_readahead_track
global_readahead_track: resb TRACK_ENTRY_SIZE * TRACK_POOL_SIZE

align 16
global global_prefetch_cache
global_prefetch_cache:  resb CACHE_ENTRY_SIZE * CACHE_POOL_SIZE

; Static allocation pool for prefetch request and iovec structs
; To avoid dynamic allocations during async prefetch dispatches
prefetch_requests:      resb io_request_t_size * CACHE_POOL_SIZE
prefetch_iovecs:        resb iovec_t_size * CACHE_POOL_SIZE
prefetch_rr_index:      resq 1          ; Round-robin index for cache eviction

section .text

extern dma_alloc
extern io_submit_request

; =============================================================================
; bdev_readahead_lookup — Inspect prefetch cache to satisfy reads from RAM
; In : RDI = -> device_t
;      RSI = Requested LBA
;      RDX = Block count (must be <= 8, matching 4KB page size)
;      RCX = -> Destination buffer
; Out: RAX = 1 if hit and served from cache, 0 on miss
; =============================================================================
IO_FUNC bdev_readahead_lookup
    guard_null rdi
    guard_null rcx
    cmp     rdx, 8
    ja      .miss                   ; We only prefetch 8 sectors (4KB) at a time

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; R12 = -> dev
    mov     r13, rsi                ; R13 = requested LBA
    mov     r14, rcx                ; R14 = -> dest buffer

    lea     rbx, [rel global_prefetch_cache]
    xor     rcx, rcx                ; RCX = index iterator

.scan:
    cmp     rcx, CACHE_POOL_SIZE
    jae     .miss_pop

    mov     rax, rcx
    imul    rax, CACHE_ENTRY_SIZE
    lea     rdx, [rbx + rax]        ; RDX = -> slot

    ; Must be valid (state = 1) and match dev + range
    cmp     qword [rdx + CACHE_ENTRY_STATE], 1
    jne     .next

    cmp     [rdx + CACHE_ENTRY_DEV], r12
    jne     .next

    ; Check if requested LBA falls inside the cached LBA page
    mov     rax, [rdx + CACHE_ENTRY_LBA] ; RAX = cached LBA
    cmp     r13, rax
    jb      .next                   ; Requested LBA < cached LBA

    add     rax, 8                  ; Cached range ends at LBA + 8
    cmp     r13, rax
    jae     .next                   ; Requested LBA >= cached LBA + 8

    ; HIT! Calculate offset in bytes: (requested LBA - cached LBA) * 512
    mov     rax, r13
    sub     rax, [rdx + CACHE_ENTRY_LBA]
    shl     rax, 9                  ; offset = diff * 512

    ; Copy data to destination buffer
    mov     rdi, r14                ; dest
    mov     rsi, [rdx + CACHE_ENTRY_VIRT]
    add     rsi, rax                ; src = virtual + offset
    push    rdx
    mov     rdx, [rsp + 16]         ; count of blocks (restored from stack frame)
    shl     rdx, 9                  ; size = count * 512
    call    .memcpy
    pop     rdx

    mov     rax, 1                  ; Return 1 (Hit)
    jmp     .done

.next:
    inc     rcx
    jmp     .scan

.miss_pop:
.miss:
    xor     rax, rax                ; Return 0 (Miss)

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

; Local memcpy helper
.memcpy:
    push    rcx
    push    rdi
    push    rsi
    mov     rcx, rdx
    shr     rcx, 3                  ; Qwords
    rep     movsq
    mov     rcx, rdx
    and     rcx, 7                  ; Remainder bytes
    rep     movsb
    pop     rsi
    pop     rdi
    pop     rcx
    ret
IO_ENDFUNC bdev_readahead_lookup

; =============================================================================
; bdev_readahead_eval — Detect sequential reads and dispatch prefetch command
; In : RDI = -> device_t
;      RSI = Current LBA
;      RDX = Block count
; =============================================================================
IO_FUNC bdev_readahead_eval
    guard_null rdi
    test    rdx, rdx
    jz      .done

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; R12 = -> dev
    mov     r13, rsi                ; R13 = LBA
    mov     r14, rdx                ; R14 = count

    ; 1. Find device slot in the readahead tracking pool
    lea     rbx, [rel global_readahead_track]
    xor     rcx, rcx

.scan_track:
    cmp     rcx, TRACK_POOL_SIZE
    jae     .allocate_track

    mov     rax, rcx
    imul    rax, TRACK_ENTRY_SIZE
    lea     rdx, [rbx + rax]

    cmp     [rdx + TRACK_ENTRY_DEV], r12
    je      .evaluate

    inc     rcx
    jmp     .scan_track

.allocate_track:
    ; Scan for a free slot (dev pointer = NULL)
    xor     rcx, rcx
.scan_free_track:
    cmp     rcx, TRACK_POOL_SIZE
    jae     .done_pop

    mov     rax, rcx
    imul    rax, TRACK_ENTRY_SIZE
    lea     rdx, [rbx + rax]

    cmp     qword [rdx + TRACK_ENTRY_DEV], 0
    jz      .populate_track

    inc     rcx
    jmp     .scan_free_track

.populate_track:
    mov     [rdx + TRACK_ENTRY_DEV], r12
    mov     [rdx + TRACK_ENTRY_LBA], r13
    mov     [rdx + TRACK_ENTRY_CNT], r14
    jmp     .done_pop               ; First read, track but don't prefetch yet

.evaluate:
    ; Check if sequential: current LBA == last LBA + last count
    mov     rax, [rdx + TRACK_ENTRY_LBA]
    add     rax, [rdx + TRACK_ENTRY_CNT]
    cmp     r13, rax
    jne     .reset_track            ; Random read jump, update track and skip prefetch

    ; Sequential read detected! Update tracking stats first
    mov     [rdx + TRACK_ENTRY_LBA], r13
    mov     [rdx + TRACK_ENTRY_CNT], r14

    ; 2. Determine target prefetch LBA: next contiguous sector sequence
    mov     r15, r13
    add     r15, r14                ; R15 = target_lba = LBA + count

    ; Trigger prefetch of 8 blocks (4KB page size)
    mov     rdi, r12                ; dev
    mov     rsi, r15                ; target_lba
    call    .prefetch_dispatch
    jmp     .done_pop

.reset_track:
    mov     [rdx + TRACK_ENTRY_LBA], r13
    mov     [rdx + TRACK_ENTRY_CNT], r14

.done_pop:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
.done:
    ret

; Local prefetch dispatch logic
.prefetch_dispatch:
    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13

    mov     r12, rdi                ; dev
    mov     r13, rsi                ; target_lba

    ; Find or evict a prefetch cache slot using Round-Robin (index tracked in prefetch_rr_index)
    mov     rcx, [rel prefetch_rr_index]
    inc     qword [rel prefetch_rr_index]
    and     qword [rel prefetch_rr_index], 15  ; Limit index to 0-15 range
    mov     rax, rcx
    imul    rax, CACHE_ENTRY_SIZE
    lea     rbx, [rel global_prefetch_cache]
    add     rbx, rax                ; RBX = selected cache slot pointer

    ; If cache slot is not initialized with virtual memory, allocate a 4KB DMA page
    mov     rax, [rbx + CACHE_ENTRY_VIRT]
    test    rax, rax
    jnz     .has_buffer

    mov     rdi, 4096               ; Size = 4KB
    mov     rsi, 4096               ; Alignment = 4KB
    xor     rdx, rdx                ; No flags
    call    dma_alloc
    IS_ERR  rax
    jae     .alloc_fail
    mov     [rbx + CACHE_ENTRY_PHYS], rax   ; Store physical address
    mov     [rbx + CACHE_ENTRY_VIRT], rbx   ; Store virtual address in slot (note: virtual is in RBX from dma_alloc)

.has_buffer:
    ; Set state to reading (2) to block concurrent lookup accesses
    mov     qword [rbx + CACHE_ENTRY_STATE], 2
    mov     [rbx + CACHE_ENTRY_DEV], r12
    mov     [rbx + CACHE_ENTRY_LBA], r13

    ; Setup pre-allocated request struct
    mov     rax, rcx
    imul    rax, io_request_t_size
    lea     rdi, [rel prefetch_requests]
    add     rdi, rax                ; RDI = target request struct pointer

    ; Setup pre-allocated iovec_t struct
    mov     rax, rcx
    imul    rax, iovec_t_size
    lea     rsi, [rel prefetch_iovecs]
    add     rsi, rax                ; RSI = target iovec struct pointer

    ; Populate iovec
    mov     rax, [rbx + CACHE_ENTRY_VIRT]
    mov     [rsi + iovec_t.base], rax
    mov     rax, [rbx + CACHE_ENTRY_PHYS]
    mov     [rsi + iovec_t.phys], rax
    mov     qword [rsi + iovec_t.len], 4096
    mov     qword [rsi + iovec_t.flags], 0

    ; Populate request
    mov     qword [rdi + io_request_t.opcode], IO_OP_READ
    mov     qword [rdi + io_request_t.flags], 0
    mov     [rdi + io_request_t.device], r12
    mov     [rdi + io_request_t.lba], r13
    mov     qword [rdi + io_request_t.nblocks], 8
    mov     [rdi + io_request_t.iov], rsi
    mov     qword [rdi + io_request_t.iov_cnt], 1
    mov     qword [rdi + io_request_t.state], IO_REQ_INIT
    mov     qword [rdi + io_request_t.waiter], 0

    ; Submit request asynchronously
    ; Since prefetch reads are asynchronous, they execute in the background.
    ; For bring-up, we call the submit handler, which eventually completes and
    ; sets the state to 1 (valid) in the background loop.
    ; To simplify, we trigger the submit function pointer directly.
    mov     rax, [r12 + device_t.submit]
    test    rax, rax
    jz      .alloc_fail
    call    rax                     ; dev->submit(dev, req)

    ; Mark valid immediately for simplified synchronous bring-up polling
    mov     qword [rbx + CACHE_ENTRY_STATE], 1

.alloc_fail:
    pop     r13
    pop     r12
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC bdev_readahead_eval

%endif ; IO_BLOCK_READAHEAD_ASM
