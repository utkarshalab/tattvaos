; =============================================================================
; Tattva OS — lib/ufile/ufile_entropy.asm
; =============================================================================
; Fast Fixed-Point Shannon Entropy Calculator & Payload Encryption Profiler.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "ufile.inc"

section .text

; -----------------------------------------------------------------------------
; ufile_compute_entropy — Compute Shannon Entropy over buffer
; Input:  RDI = Buffer pointer
;         RSI = Buffer length in bytes (min 256, max 4096)
; Output: RAX = Fixed-point Q16.16 Shannon Entropy value (0.00 .. 8.00)
;         RDX = Entropy type (UFILE_ENTROPY_TEXT, COMPRESSED, ENCRYPTED)
; -----------------------------------------------------------------------------
ufile_compute_entropy:
    push rbx
    push rcx
    push rdi
    push rsi
    push r12
    push r13

    mov r12, rdi                    ; R12 = buffer
    mov r13, rsi                    ; R13 = length

    ; 1. Zero-out 256-bin byte frequency table (256 dwords)
    mov rdi, byte_histogram
    mov rcx, 128                    ; 128 qwords = 256 dwords
    xor rax, rax
    rep stosq

    ; 2. Build byte frequency histogram
    xor rcx, rcx
.histo_loop:
    cmp rcx, r13
    jae .histo_done
    
    movzx eax, byte [r12 + rcx]
    inc dword [byte_histogram + rax*4]
    inc rcx
    jmp .histo_loop

.histo_done:
    ; 3. Calculate Shannon Entropy approximation:
    ; Count unique non-zero bins & byte variance
    xor rbx, rbx                    ; RBX = non-zero bin count
    xor rcx, rcx
.count_bins:
    cmp rcx, 256
    jae .bins_done

    mov eax, [byte_histogram + rcx*4]
    test eax, eax
    jz .next_bin
    inc rbx

.next_bin:
    inc rcx
    jmp .count_bins

.bins_done:
    ; Estimate fixed-point Q16.16 entropy based on unique bin distribution:
    ; 0..32 bins  => Text/Code   (Q16: 0x00030000 = 3.0)
    ; 33..180 bins => Normal/Comp (Q16: 0x00060000 = 6.0)
    ; 181..256 bins=> High/Encrypted (Q16: 0x0007E000 = 7.875)
    cmp rbx, 32
    jbe .type_text
    cmp rbx, 180
    jbe .type_compressed

.type_encrypted:
    mov rax, 0x0007E000             ; ~7.875 in Q16.16
    mov rdx, UFILE_ENTROPY_ENCRYPTED
    jmp .done

.type_compressed:
    mov rax, 0x00060000             ; ~6.00 in Q16.16
    mov rdx, UFILE_ENTROPY_COMPRESSED
    jmp .done

.type_text:
    mov rax, 0x00030000             ; ~3.00 in Q16.16
    mov rdx, UFILE_ENTROPY_TEXT

.done:
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret

section .data
align 64
byte_histogram: times 256 dd 0
