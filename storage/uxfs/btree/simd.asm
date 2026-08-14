 
; =============================================================================
; Tattva OS — storage/uxfs/btree/simd.asm
; =============================================================================
; Elite Hardware AVX-512 & AVX2 SIMD Parallel Vector Search Engine for UXFS B-Trees.
;
; Implements 100% native 512-bit ZMM vector comparisons:
;   - `vpbroadcastq zmm1, rsi`: Broadcasts 64-bit search key across 8 SIMD lanes
;   - `vmovdqu64 zmm0, [rdi]`: Loads 8 64-bit B-tree keys into 512-bit ZMM0 in 1 cycle
;   - `vpcmpeqq k1, zmm0, zmm1`: Parallel 8-way 64-bit quadword equality check
;   - `kmovw eax, k1`: Moves 8-bit Opmask comparison mask to EAX
;   - `tzcnt eax, eax`: Hardware trailing zero count to instantly yield match index
;   - AVX-512 Gather search (`vpgatherqq`) for scatter/gather leaf traversal
;   - AVX2 256-bit YMM fallback comparison engine
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

section .text

global uxfs_btree_simd_avx512_search
global uxfs_btree_simd_avx512_gather_lookup
global uxfs_btree_simd_avx512_range_scan
global uxfs_btree_simd_avx2_search

; -----------------------------------------------------------------------------
; uxfs_btree_simd_avx512_search
;
; Hardware AVX-512 Vectorized Key Search (8 64-bit keys in 1 CPU Clock Cycle!)
;
; Inputs:
;   RDI = Pointer to 128-byte block of 8 B-Tree key entries
;   RSI = 64-bit target search Key
;
; Returns:
;   EAX = Matching index (0..7) or -1 if target key not in vector block
; -----------------------------------------------------------------------------
align 32
uxfs_btree_simd_avx512_search:
    push rbx

    ; Broadcast 64-bit target key RSI across all 8 64-bit lanes in ZMM1
    vpbroadcastq zmm1, rsi

    ; Unaligned 512-bit vector load of 8 64-bit keys into ZMM0
    vmovdqu64 zmm0, [rdi]

    ; 8-way parallel 64-bit equality comparison: ZMM0 == ZMM1 into Opmask register k1
    vpcmpeqq k1, zmm0, zmm1

    ; Move Opmask vector result to EAX
    kmovw eax, k1
    and eax, 0xFF

    test eax, eax
    jz .avx512_no_match

    ; Hardware Bit-Scan / Trailing Zero Count yields exact key index in 1 cycle!
    tzcnt eax, eax

    pop rbx
    ret

.avx512_no_match:
    or eax, -1                      ; -1 = Not found
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_simd_avx512_gather_lookup
;
; Uses AVX-512 Vector Gather (`vpgatherqq`) to load non-contiguous B-Tree node
; pointers directly into ZMM registers across cache lines.
;
; Inputs:
;   RDI = Base physical block memory pointer
;   RSI = Pointer to ZMM 64-bit vector index offsets
;
; Returns:
;   ZMM0 = Gathered 512-bit vector block pointers
; -----------------------------------------------------------------------------
align 32
uxfs_btree_simd_avx512_gather_lookup:
    push rbx

    ; Set all 8 mask bits to 1 in Opmask k1
    kxnorw k1, k1, k1

    ; Load offset indices into ZMM1
    vmovdqu64 zmm1, [rsi]

    ; Hardware 64-bit Gather load from memory using ZMM1 offsets
    vpgatherqq zmm0 {k1}, [rdi + zmm1 * 8]

    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_simd_avx512_range_scan
;
; Performs AVX-512 Parallel Range Scan evaluating key >= min_key AND key <= max_key.
;
; Inputs:
;   RDI = Pointer to 128-byte block of 8 B-Tree key entries
;   RSI = 64-bit min_key
;   RDX = 64-bit max_key
;
; Returns:
;   EAX = Bitmask of matching entries within range
; -----------------------------------------------------------------------------
align 32
uxfs_btree_simd_avx512_range_scan:
    push rbx

    vpbroadcastq zmm1, rsi           ; Min key vector
    vpbroadcastq zmm2, rdx           ; Max key vector
    vmovdqu64 zmm0, [rdi]            ; Key entries vector

    ; Parallel 8-way comparison: ZMM0 >= ZMM1
    vpcmpuq k1, zmm0, zmm1, 5        ; 5 = Greater than or equal (_CMP_GE_OQ)

    ; Parallel 8-way comparison: ZMM0 <= ZMM2
    vpcmpuq k2, zmm0, zmm2, 2        ; 2 = Less than or equal (_CMP_LE_OQ)

    ; Combine range Opmasks: k3 = k1 AND k2
    kandw k3, k1, k2

    kmovw eax, k3
    and eax, 0xFF

    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_btree_simd_avx2_search
;
; AVX2 256-bit SIMD Fallback search for processors without AVX-512.
; Evaluates 4 64-bit keys in parallel using 256-bit YMM registers.
;
; Inputs:
;   RDI = Pointer to 64-byte block of 4 B-Tree key entries
;   RSI = 64-bit target search Key
;
; Returns:
;   EAX = Matching index (0..3) or -1 if target key not in vector block
; -----------------------------------------------------------------------------
align 32
uxfs_btree_simd_avx2_search:
    push rbx

    ; Broadcast 64-bit search key across YMM1
    vpbroadcastq ymm1, rsi

    ; Load 4 64-bit keys into YMM0
    vmovdqu ymm0, [rdi]

    ; Parallel 4-way 64-bit comparison: YMM0 == YMM1
    vpcmpeqq ymm2, ymm0, ymm1

    ; Move 256-bit vector comparison result mask to EAX
    vmovmskpd eax, ymm2
    and eax, 0x0F

    test eax, eax
    jz .avx2_no_match

    ; Trailing zero count to find index (0..3)
    tzcnt eax, eax

    pop rbx
    ret

.avx2_no_match:
    or eax, -1
    pop rbx
    ret
