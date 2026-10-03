; =============================================================================
; Tattva OS — boot/survive/checksum.asm
; =============================================================================
; CRC32 checksum calculator and verifier for the hardware snapshot page.
; Standard IEEE 802.3 CRC32 implemented in software (tableless, compact).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (Long Mode)
; =============================================================================

%ifndef SURVIVE_CHECKSUM_ASM
%define SURVIVE_CHECKSUM_ASM

[BITS 64]

; The immutable snapshot consists of the saved CPU state (0x000..0x0FF)
; followed by the 1536-byte stack image (0x100..0x6FF).  Panic diagnostics
; deliberately live at 0x800 and 0xA00 and therefore must not be included in
; this checksum: wakeup writes those areas before asking us to verify the
; pristine state.
SURVIVE_IMMUTABLE_BYTES equ 0x700
SURVIVE_MAGIC_OFFSET    equ 0xFF0
SURVIVE_CRC_OFFSET      equ 0xFFC
SURVIVE_MAGIC           equ 0x504E535654544154 ; "TATTVSNP"

; =============================================================================
; survive_checksum_save — checksum immutable state and stamp the CRC slot
; Input:  none
; Clobbers: none
; =============================================================================
survive_checksum_save:
    push rsi
    push rcx
    push rbx
    push rdx
    push r10
    push rax

    mov rsi, SURVIVE_PAGE
    mov rcx, SURVIVE_IMMUTABLE_BYTES
    call helper_crc32
    
    mov [SURVIVE_PAGE + SURVIVE_CRC_OFFSET], eax

    pop rax
    pop r10
    pop rdx
    pop rbx
    pop rcx
    pop rsi
    ret

; =============================================================================
; survive_checksum_verify — recomputes CRC32 and compares to stored value
; Input:  none
; Output: RAX = 1 if matches, 0 if mismatch
; Clobbers: none (except RAX)
; =============================================================================
survive_checksum_verify:
    push rsi
    push rcx
    push rbx
    push rdx
    push r10

    ; The magic is outside the CRC-covered prefix so the mutable diagnostic
    ; regions can remain between the snapshot and its trailer.  Check it
    ; explicitly before trusting any saved control state.
    mov rax, SURVIVE_MAGIC
    cmp qword [SURVIVE_PAGE + SURVIVE_MAGIC_OFFSET], rax
    jne .mismatch

    mov rsi, SURVIVE_PAGE
    mov rcx, SURVIVE_IMMUTABLE_BYTES
    call helper_crc32
    
    cmp eax, [SURVIVE_PAGE + SURVIVE_CRC_OFFSET]
    jne .mismatch
    
    mov rax, 1
    jmp .done
    
.mismatch:
    xor rax, rax

.done:
    pop r10
    pop rdx
    pop rbx
    pop rcx
    pop rsi
    ret

; =============================================================================
; helper_crc32 — bit-by-bit software CRC32
; Input:  RSI = buffer pointer
;         RCX = buffer length
; Output: EAX = 32-bit CRC32 checksum
; =============================================================================
helper_crc32:
    mov eax, 0xFFFFFFFF             ; initial CRC
.loop_bytes:
    test rcx, rcx
    jz .done
    movzx r10d, byte [rsi]
    xor al, r10b
    mov edx, 8
.loop_bits:
    shr eax, 1
    jnc .no_carry
    xor eax, 0xEDB88320             ; standard CRC32-IEEE polynomial
.no_carry:
    dec edx
    jnz .loop_bits
    inc rsi
    dec rcx
    jmp .loop_bytes
.done:
    not eax
    ret

%endif ; SURVIVE_CHECKSUM_ASM
