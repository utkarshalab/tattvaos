%ifndef GUARD_LIB_UMATH_MEMORY_PREFETCH_ASM
%define GUARD_LIB_UMATH_MEMORY_PREFETCH_ASM
; =============================================================================
; umath - unified math library
; memory/prefetch.asm - hardware prefetch cache hints for arrays and tensors
; =============================================================================
; Targets 64-bit AMD64 System V ABI calling conventions.
;
; Core Concepts:
;   - Cache line size on x86_64 is 64 bytes.
;   - Prefetch instructions load data into cache before it is used by normal instructions,
;     allowing memory latency hiding.
;   - Prefetch Hints:
;       - PREFETCHT0: load data into L1/L2/L3 caches (all levels, temporal).
;       - PREFETCHT1: load data into L2/L3 caches (non-L1).
;       - PREFETCHT2: load data into L3 cache (non-L1/L2).
;       - PREFETCHNTA: load data into non-temporal cache structure (use once,
;         minimizes cache pollution).
;       - PREFETCHW: load data with intent-to-write (marks cache line as Modified in MESI).
; =============================================================================

bits 64
section .text

; -----------------------------------------------------------------------------
; umath_prefetch_t0 - prefetch cache line into all cache levels (L1, L2, L3)
; args:    rdi = pointer
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_t0
umath_prefetch_t0:
    prefetcht0 [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_prefetch_t1 - prefetch cache line into L2 and L3 caches (bypasses L1)
; args:    rdi = pointer
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_t1
umath_prefetch_t1:
    prefetcht1 [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_prefetch_t2 - prefetch cache line into L3 cache only
; args:    rdi = pointer
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_t2
umath_prefetch_t2:
    prefetcht2 [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_prefetch_nta - prefetch cache line with non-temporal (NTA) hint
; args:    rdi = pointer
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_nta
umath_prefetch_nta:
    prefetchnta [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_prefetch_w - prefetch cache line with write intent (Modified state)
; args:    rdi = pointer
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_w
umath_prefetch_w:
    ; check if CPU supports prefetchw (part of PRFCHW CPUID bit).
    ; if unsupported, it executes as a NOP.
    prefetchw [rdi]
    ret

; -----------------------------------------------------------------------------
; umath_prefetch_range - prefetch a range of memory using cache line strides
; args:    rdi = start pointer
;          rsi = size of range in bytes
;          rdx = hint type (0 = T0, 1 = T1, 2 = T2, 3 = NTA, 4 = W)
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_range
umath_prefetch_range:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    mov     rcx, rsi
    add     rcx, rdi            ; rcx = end pointer
    jc      .done               ; overflow check

    ; determine prefetch instruction to branch to
    cmp     rdx, 0
    je      .loop_t0
    cmp     rdx, 1
    je      .loop_t1
    cmp     rdx, 2
    je      .loop_t2
    cmp     rdx, 3
    je      .loop_nta
    cmp     rdx, 4
    je      .loop_w
    jmp     .loop_t0            ; default to T0

    ; --- T0 Loop ---
.loop_t0:
    prefetcht0 [rdi]
    add     rdi, 64             ; stride by 64 bytes (cache line size)
    cmp     rdi, rcx
    jb      .loop_t0
    ret

    ; --- T1 Loop ---
.loop_t1:
    prefetcht1 [rdi]
    add     rdi, 64
    cmp     rdi, rcx
    jb      .loop_t1
    ret

    ; --- T2 Loop ---
.loop_t2:
    prefetcht2 [rdi]
    add     rdi, 64
    cmp     rdi, rcx
    jb      .loop_t2
    ret

    ; --- NTA Loop ---
.loop_nta:
    prefetchnta [rdi]
    add     rdi, 64
    cmp     rdi, rcx
    jb      .loop_nta
    ret

    ; --- Write Intent Loop ---
.loop_w:
    prefetchw [rdi]
    add     rdi, 64
    cmp     rdi, rcx
    jb      .loop_w
.done:
    ret

; -----------------------------------------------------------------------------
; umath_prefetch_range_2d - prefetch a 2D block of row-major data (tensors, GEMM)
; args:    rdi = start pointer of 2D grid
;          rsi = row pitch/stride in bytes (distance between start of rows)
;          rdx = column/row segment width in bytes
;          rcx = number of rows
;          r8  = hint type (0 = T0, 1 = T1, 2 = T2, 3 = NTA, 4 = W)
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_range_2d
umath_prefetch_range_2d:
    test    rdi, rdi
    jz      .done_2d
    test    rsi, rsi
    jz      .done_2d
    test    rdx, rdx
    jz      .done_2d
    test    rcx, rcx
    jz      .done_2d

    push    rbx
    push    r12
    push    r13
    push    r14

    mov     rbx, rdi            ; rbx = current row pointer
    mov     r12, rsi            ; r12 = row pitch
    mov     r13, rdx            ; r13 = row width
    mov     r14, rcx            ; r14 = row count

.row_loop:
    ; prefetch row from rbx to rbx + r13
    mov     rdi, rbx            ; arg0 = start of row
    mov     rsi, r13            ; arg1 = size of row
    mov     rdx, r8             ; arg2 = hint type
    call    umath_prefetch_range

    ; step to next row
    add     rbx, r12            ; rbx = rbx + row_pitch
    jc      .overflow_2d
    dec     r14
    jnz     .row_loop

.overflow_2d:
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.done_2d:
    ret

; -----------------------------------------------------------------------------
; umath_prefetch_block_transposed - prefetch column segments (column-major/transposed data)
; args:    rdi = start pointer
;          rsi = row pitch/stride in bytes
;          rdx = block height (number of rows)
;          rcx = block width in bytes (number of columns to prefetch)
;          r8  = hint type
; returns: void
; -----------------------------------------------------------------------------
global umath_prefetch_block_transposed
umath_prefetch_block_transposed:
    test    rdi, rdi
    jz      .done_t
    test    rsi, rsi
    jz      .done_t
    test    rdx, rdx
    jz      .done_t
    test    rcx, rcx
    jz      .done_t

    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi            ; base pointer
    mov     r12, rsi            ; row pitch
    mov     r13, rdx            ; height (rows)
    mov     r14, rcx            ; width (cols/bytes)
    mov     r15, r8             ; hint type

    ; we prefetch in cacheline chunks (64 bytes).
    ; for transposed layout, we loop columns with 64-byte column strides.
    xor     r9, r9              ; r9 = column offset

.col_loop:
    ; for current column chunk, we walk down the rows
    mov     r10, rbx
    add     r10, r9             ; r10 = column start pointer
    
    mov     r11, r13            ; r11 = row loop counter

.row_walk:
    ; prefetch the address
    cmp     r15, 0
    je      .pf_t0
    cmp     r15, 1
    je      .pf_t1
    cmp     r15, 2
    je      .pf_t2
    cmp     r15, 3
    je      .pf_nta
    cmp     r15, 4
    je      .pf_w
    jmp     .pf_t0

.pf_t0:
    prefetcht0 [r10]
    jmp     .step_row
.pf_t1:
    prefetcht1 [r10]
    jmp     .step_row
.pf_t2:
    prefetcht2 [r10]
    jmp     .step_row
.pf_nta:
    prefetchnta [r10]
    jmp     .step_row
.pf_w:
    prefetchw [r10]

.step_row:
    add     r10, r12            ; r10 = r10 + row_pitch
    jc      .overflow_t
    dec     r11
    jnz     .row_walk

    add     r9, 64              ; stride column by 64 bytes (cache line)
    cmp     r9, r14
    jb      .col_loop

.overflow_t:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
.done_t:
    ret

%endif ; GUARD_LIB_UMATH_MEMORY_PREFETCH_ASM
