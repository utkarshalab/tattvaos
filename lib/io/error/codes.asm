; =============================================================================
; lib/io/error/codes.asm
; Subsystem semantic error code constants for Tattva OS lib/io.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ERROR_CODES_ASM
%define IO_ERROR_CODES_ASM

; ---- Foundation / Core Band (Base 0x000) ----
IO_ERR_NULL         equ -0x001      ; Null pointer encountered where non-null expected
IO_ERR_BADARG       equ -0x002      ; Invalid function argument
IO_ERR_NO_DEVICE    equ -0x003      ; Device not detected or present
IO_ERR_NOMEM        equ -0x004      ; General out of memory

; ---- Descriptor / Handle Band (Base 0x100) ----
IO_ERR_BADFD        equ -0x101      ; Invalid or closed file descriptor
IO_ERR_STALE        equ -0x102      ; Use-after-free detected via stale handle/generation

; ---- DMA & Buffers Band (Base 0x200) ----
IO_ERR_DMA_NOMEM    equ -0x201      ; Contiguous DMA memory exhausted
IO_ERR_PAGE_CROSS   equ -0x202      ; Scatter-gather split limit exceeded

; ---- Interrupts Band (Base 0x300) ----
IO_ERR_VEC_LIMIT    equ -0x301      ; Dynamic interrupt vector allocation limit reached

; ---- PCI / PCIe Band (Base 0x400) ----
IO_ERR_PCI_BAR      equ -0x401      ; PCI BAR configuration or mapping conflict

; ---- Block Device Band (Base 0x500) ----
IO_ERR_QFULL        equ -0x501      ; Submission queue or request block ring full
IO_ERR_MEDIA        equ -0x502      ; Media / hardware I/O transfer error

; ---- Async Subsystem Band (Base 0x600) ----
IO_ERR_TIMEOUT      equ -0x601      ; Controller command timeout expired
IO_ERR_CANCEL       equ -0x602      ; I/O operation cancelled

%endif ; IO_ERROR_CODES_ASM
