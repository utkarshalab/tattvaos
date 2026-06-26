; =============================================================================
; umath - unified math library
; memory/stats.asm - robust allocator statistics and profiling histogram
; =============================================================================
; Layout of the UmathAllocStats structure:
;
;   +-----------------------------+-----------------------------+
;   | total_allocated (8 bytes)   | total_freed (8 bytes)       |
;   +-----------------------------+-----------------------------+
;   Offset 0                      Offset 8
;
;   +-----------------------------+-----------------------------+
;   | current_bytes (8 bytes)     | peak_bytes (8 bytes)        |
;   +-----------------------------+-----------------------------+
;   Offset 16                     Offset 24
;
;   +-----------------------------+-----------------------------+
;   | alloc_count (8 bytes)       | free_count (8 bytes)        |
;   +-----------------------------+-----------------------------+
;   Offset 32                     Offset 40
;
;   +-----------------------------------------------------------+
;   | allocation_sizes_histogram (16 bins * 8 bytes = 128 bytes)|
;   +-----------------------------------------------------------+
;   Offset 48
;
; Size of structure = 176 bytes.
;
; Histogram Bins mapping:
;   Bin 0:  1 .. 8 bytes
;   Bin 1:  9 .. 16 bytes
;   Bin 2:  17 .. 32 bytes
;   Bin 3:  33 .. 64 bytes
;   Bin 4:  65 .. 128 bytes
;   Bin 5:  129 .. 256 bytes
;   Bin 6:  257 .. 512 bytes
;   Bin 7:  513 .. 1024 bytes
;   Bin 8:  1025 .. 2048 bytes
;   Bin 9:  2049 .. 4096 bytes (4KB page)
;   Bin 10: 4097 .. 8192 bytes
;   Bin 11: 8193 .. 16384 bytes
;   Bin 12: 16385 .. 32768 bytes
;   Bin 13: 32769 .. 65536 bytes
;   Bin 14: 65537 .. 1048576 bytes (1MB)
;   Bin 15: > 1048576 bytes (large heap block)
;
; Targets 64-bit AMD64 System V ABI calling conventions.
; =============================================================================

bits 64
section .text

; Struct offsets
STATS_TOT_ALLOC equ 0
STATS_TOT_FREE  equ 8
STATS_CUR_BYTES equ 16
STATS_PEAK_BYTES equ 24
STATS_ALL_CNT   equ 32
STATS_FREE_CNT  equ 40
STATS_HIST_START equ 48

; -----------------------------------------------------------------------------
; umath_stats_init - initialize allocator statistics descriptor to all zeros
; args:    rdi = pointer to UmathAllocStats struct
; returns: void
; -----------------------------------------------------------------------------
global umath_stats_init
umath_stats_init:
    test    rdi, rdi
    jz      .done

    ; zero out 176 bytes of structure
    mov     rcx, 22             ; 22 * 8 bytes = 176 bytes
    xor     rax, rax
    rep     stosq
.done:
    ret

; -----------------------------------------------------------------------------
; umath_stats_record_alloc - record an allocation event
; args:    rdi = pointer to UmathAllocStats struct
;          rsi = allocated size in bytes
; returns: void
; -----------------------------------------------------------------------------
global umath_stats_record_alloc
umath_stats_record_alloc:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done               ; ignore zero-sized records

    ; 1. Update general sizes and counts
    add     [rdi + STATS_TOT_ALLOC], rsi  ; total_allocated += size
    add     [rdi + STATS_CUR_BYTES], rsi  ; current_bytes += size
    inc     qword [rdi + STATS_ALL_CNT]   ; alloc_count++

    ; 2. Check and update peak usage
    mov     rax, [rdi + STATS_CUR_BYTES]
    mov     rcx, [rdi + STATS_PEAK_BYTES]
    cmp     rax, rcx
    jbe     .update_histogram

    mov     [rdi + STATS_PEAK_BYTES], rax ; peak_bytes = current_bytes

.update_histogram:
    ; 3. Determine histogram bin based on size (rsi)
    ; we can count leading zeros to quickly locate power-of-2 ranges
    bsr     rax, rsi            ; rax = index of highest set bit (0-63)
    jz      .bin_0              ; if size is 0 (handled, but safety check)

    ; Map highest set bit to bin index
    ; Bit index mapping table:
    ;   bits 0..3 (1-8)     -> Bin 0
    ;   bit 4     (9-16)    -> Bin 1
    ;   bit 5     (17-32)   -> Bin 2
    ;   bit 6     (33-64)   -> Bin 3
    ;   bit 7     (65-128)  -> Bin 4
    ;   bit 8     (129-256) -> Bin 5
    ;   bit 9     (257-512) -> Bin 6
    ;   bit 10    (513-1024)-> Bin 7
    ;   bit 11    (1025-2048)-> Bin 8
    ;   bit 12    (2049-4096)-> Bin 9
    ;   bit 13    (4097-8192)-> Bin 10
    ;   bit 14    (8193-16384)-> Bin 11
    ;   bit 15    (16385-32768)-> Bin 12
    ;   bit 16    (32769-65536)-> Bin 13
    ;   bits 17..20 (65537-1048576) -> Bin 14
    ;   bits 21..63 (> 1048576)    -> Bin 15

    cmp     rax, 3
    jbe     .bin_0
    cmp     rax, 4
    je      .bin_1
    cmp     rax, 5
    je      .bin_2
    cmp     rax, 6
    je      .bin_3
    cmp     rax, 7
    je      .bin_4
    cmp     rax, 8
    je      .bin_5
    cmp     rax, 9
    je      .bin_6
    cmp     rax, 10
    je      .bin_7
    cmp     rax, 11
    je      .bin_8
    cmp     rax, 12
    je      .bin_9
    cmp     rax, 13
    je      .bin_10
    cmp     rax, 14
    je      .bin_11
    cmp     rax, 15
    je      .bin_12
    cmp     rax, 16
    je      .bin_13
    cmp     rax, 20
    jbe     .bin_14
    jmp     .bin_15

.bin_0:
    xor     rax, rax
    jmp     .commit_bin
.bin_1:
    mov     rax, 1
    jmp     .commit_bin
.bin_2:
    mov     rax, 2
    jmp     .commit_bin
.bin_3:
    mov     rax, 3
    jmp     .commit_bin
.bin_4:
    mov     rax, 4
    jmp     .commit_bin
.bin_5:
    mov     rax, 5
    jmp     .commit_bin
.bin_6:
    mov     rax, 6
    jmp     .commit_bin
.bin_7:
    mov     rax, 7
    jmp     .commit_bin
.bin_8:
    mov     rax, 8
    jmp     .commit_bin
.bin_9:
    mov     rax, 9
    jmp     .commit_bin
.bin_10:
    mov     rax, 10
    jmp     .commit_bin
.bin_11:
    mov     rax, 11
    jmp     .commit_bin
.bin_12:
    mov     rax, 12
    jmp     .commit_bin
.bin_13:
    mov     rax, 13
    jmp     .commit_bin
.bin_14:
    mov     rax, 14
    jmp     .commit_bin
.bin_15:
    mov     rax, 15

.commit_bin:
    ; increment bin: stats->allocation_sizes_histogram[rax]++
    inc     qword [rdi + STATS_HIST_START + rax * 8]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_stats_record_free - record a free event
; args:    rdi = pointer to UmathAllocStats struct
;          rsi = freed size in bytes
; returns: void
; -----------------------------------------------------------------------------
global umath_stats_record_free
umath_stats_record_free:
    test    rdi, rdi
    jz      .done
    test    rsi, rsi
    jz      .done

    ; update general free sizes and counts
    add     [rdi + STATS_TOT_FREE], rsi
    inc     qword [rdi + STATS_FREE_CNT]

    ; decrement current bytes with underflow guard
    mov     rax, [rdi + STATS_CUR_BYTES]
    cmp     rax, rsi
    jb      .underflow
    sub     rax, rsi
    mov     [rdi + STATS_CUR_BYTES], rax
    ret

.underflow:
    mov     qword [rdi + STATS_CUR_BYTES], 0 ; clamp to 0 on underflow (e.g. double-frees or untracked allocation)
.done:
    ret

; -----------------------------------------------------------------------------
; umath_stats_get_current - get current allocated bytes
; args:    rdi = pointer to UmathAllocStats struct
; returns: rax = current allocated bytes
; -----------------------------------------------------------------------------
global umath_stats_get_current
umath_stats_get_current:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    mov     rax, [rdi + STATS_CUR_BYTES]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_stats_get_peak - get peak allocated bytes
; args:    rdi = pointer to UmathAllocStats struct
; returns: rax = peak allocated bytes
; -----------------------------------------------------------------------------
global umath_stats_get_peak
umath_stats_get_peak:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    mov     rax, [rdi + STATS_PEAK_BYTES]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_stats_get_average - get average allocation size in bytes
; args:    rdi = pointer to UmathAllocStats struct
; returns: rax = average allocation size, or 0 if no allocations recorded
; -----------------------------------------------------------------------------
global umath_stats_get_average
umath_stats_get_average:
    xor     rax, rax
    test    rdi, rdi
    jz      .done

    mov     rcx, [rdi + STATS_ALL_CNT]
    test    rcx, rcx
    jz      .done               ; division by zero guard

    mov     rax, [rdi + STATS_TOT_ALLOC]
    xor     rdx, rdx
    div     rcx                 ; rax = total_allocated / alloc_count
.done:
    ret

; -----------------------------------------------------------------------------
; umath_stats_get_bin_count - get count in specific histogram bin
; args:    rdi = pointer to UmathAllocStats struct
;          rsi = bin index (0-15)
; returns: rax = count, or 0 if invalid index
; -----------------------------------------------------------------------------
global umath_stats_get_bin_count
umath_stats_get_bin_count:
    xor     rax, rax
    test    rdi, rdi
    jz      .done
    cmp     rsi, 15
    ja      .done               ; invalid index

    mov     rax, [rdi + STATS_HIST_START + rsi * 8]
.done:
    ret

; -----------------------------------------------------------------------------
; umath_stats_verify - verify integrity of stats (checks invariants)
; args:    rdi = pointer to UmathAllocStats struct
; returns: rax = 1 (valid) or 0 (invalid/inconsistent)
; -----------------------------------------------------------------------------
global umath_stats_verify
umath_stats_verify:
    xor     rax, rax
    test    rdi, rdi
    jz      .done

    mov     rcx, [rdi + STATS_TOT_ALLOC]
    mov     rdx, [rdi + STATS_TOT_FREE]
    mov     rsi, [rdi + STATS_CUR_BYTES]
    mov     r8, [rdi + STATS_PEAK_BYTES]

    ; invariant 1: total_allocated >= total_freed
    cmp     rcx, rdx
    jb      .done

    ; invariant 2: current_bytes <= total_allocated
    cmp     rsi, rcx
    ja      .done

    ; invariant 3: current_bytes <= peak_bytes
    cmp     rsi, r8
    ja      .done

    ; invariant 4: peak_bytes <= total_allocated
    cmp     r8, rcx
    ja      .done

    mov     rax, 1
.done:
    ret
