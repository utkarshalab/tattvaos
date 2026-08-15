; =============================================================================
; Tattva OS — lib/ulog/record/record_checksum.asm
; =============================================================================
; CRC32 (Castagnoli, via the SSE4.2 CRC32 instruction — every x86-64 target
; this OS ships on has it) over the first 52 bytes of a log_record_t, i.e.
; everything except the .checksum field itself. journald-style: catches a
; torn write if a segment gets written mid-record across an unclean reset.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RECORD_CHECKSUM_ASM
%define LIB_ULOG_RECORD_RECORD_CHECKSUM_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"

section .text

; -----------------------------------------------------------------------------
; record_checksum_compute — CRC32C over log_record_t bytes [0, 52)
; Input:  RDI = log_record_t*
; Output: EAX = crc32
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global record_checksum_compute
record_checksum_compute:
    push rdi
    push rcx

    xor eax, eax
    not eax                          ; CRC32 init value 0xFFFFFFFF
    xor rcx, rcx

.word_loop:
    cmp rcx, 48                      ; 6 qwords = 48 bytes, then 4 tail bytes
    jae .tail
    mov rdx, [rdi + rcx]
    crc32 rax, rdx
    add rcx, 8
    jmp .word_loop

.tail:
    mov edx, [rdi + rcx]             ; bytes [48, 52)
    crc32 eax, edx

    not eax

    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; record_checksum_stamp — compute and write into the record's .checksum field
; Input:  RDI = log_record_t*
; Output: none
; -----------------------------------------------------------------------------
global record_checksum_stamp
record_checksum_stamp:
    push rdi
    call record_checksum_compute     ; preserves RDI internally; EAX = crc on return
    pop rdi
    mov [rdi + log_record_t.checksum], eax
    ret

%endif ; LIB_ULOG_RECORD_RECORD_CHECKSUM_ASM
