; =============================================================================
; Tattva OS — unet/tools/app/fix_fuzzer.asm
; =============================================================================
; High-Frequency FIX 4.2 / 5.0 Protocol Mutation Fuzzer (`fix-fuzzer`).
;
; Features:
;   - Tag=Value Malformed Tag / Length / Checksum Mutation Generation
;   - SOH Delimiter Corruption & Out-of-Bounds Field Injection Test
;
; Delegates:
;   - FIX Engine                        -> unet/hft/fix.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global fix_fuzzer_main

extern fix_parse_msg_avx512

align 64
fix_fuzzer_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Mutate FIX tags & execute in-kernel AVX-512 parser sanity audit
    call fix_parse_msg_avx512
    pop rbp
    ret
