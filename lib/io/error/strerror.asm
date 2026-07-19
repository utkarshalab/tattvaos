; =============================================================================
; lib/io/error/strerror.asm
; Maps lib/io negative error codes to human-readable ASCIIZ diagnostic strings.
;
; Usage: mov rdi, <negative_error_code>
;        call io_strerror
;        ; RAX -> null-terminated string (or "Unknown error" if unmapped)
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_ERROR_STRERROR_ASM
%define IO_ERROR_STRERROR_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/error/codes.asm"

section .rodata

; ---- Foundation / Core Band (0x000) ----
.str_null:          db "Null pointer where non-null expected", 0
.str_badarg:        db "Invalid function argument", 0
.str_no_device:     db "Device not detected or present", 0
.str_nomem:         db "Out of memory", 0

; ---- Descriptor / Handle Band (0x100) ----
.str_badfd:         db "Invalid or closed file descriptor", 0
.str_stale:         db "Stale handle (use-after-free detected)", 0

; ---- DMA & Buffers Band (0x200) ----
.str_dma_nomem:     db "Contiguous DMA memory exhausted", 0
.str_page_cross:    db "Scatter-gather split limit exceeded", 0

; ---- Interrupts Band (0x300) ----
.str_vec_limit:     db "Dynamic interrupt vector pool exhausted", 0

; ---- PCI / PCIe Band (0x400) ----
.str_pci_bar:       db "PCI BAR configuration or mapping conflict", 0

; ---- Block Device Band (0x500) ----
.str_qfull:         db "Submission queue or ring full", 0
.str_media:         db "Media or hardware I/O transfer error", 0

; ---- Async Band (0x600) ----
.str_timeout:       db "Controller command timeout expired", 0
.str_cancel:        db "I/O operation cancelled", 0

; ---- Fallback ----
.str_unknown:       db "Unknown I/O error code", 0
.str_success:       db "Success", 0

; ---- Dispatch table: pairs of (negative_code, string_pointer) ----
; Terminated by a zero-code sentinel.
align 8
.dispatch_table:
    dq IO_ERR_NULL,       .str_null
    dq IO_ERR_BADARG,     .str_badarg
    dq IO_ERR_NO_DEVICE,  .str_no_device
    dq IO_ERR_NOMEM,      .str_nomem
    dq IO_ERR_BADFD,      .str_badfd
    dq IO_ERR_STALE,      .str_stale
    dq IO_ERR_DMA_NOMEM,  .str_dma_nomem
    dq IO_ERR_PAGE_CROSS, .str_page_cross
    dq IO_ERR_VEC_LIMIT,  .str_vec_limit
    dq IO_ERR_PCI_BAR,    .str_pci_bar
    dq IO_ERR_QFULL,      .str_qfull
    dq IO_ERR_MEDIA,      .str_media
    dq IO_ERR_TIMEOUT,    .str_timeout
    dq IO_ERR_CANCEL,     .str_cancel
    dq 0, 0               ; Sentinel

section .text

; =============================================================================
; io_strerror — Map a negative error code to a descriptive string
; In : RDI = error code (negative, e.g. -0x601)
; Out: RAX = -> null-terminated ASCIIZ string
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC io_strerror
    push    rcx
    push    rdx

    ; Fast path: code == 0 means success
    test    rdi, rdi
    jz      .success

    ; Walk dispatch table: pairs of (code, string_ptr), sentinel = (0, 0)
    lea     rcx, [rel .dispatch_table]

.scan:
    mov     rax, [rcx]              ; RAX = table code entry
    test    rax, rax
    jz      .unknown                ; Sentinel reached — code not found

    cmp     rax, rdi
    je      .found

    add     rcx, 16                 ; Next pair (2 qwords = 16 bytes)
    jmp     .scan

.found:
    mov     rax, [rcx + 8]          ; RAX = corresponding string pointer
    jmp     .done

.success:
    lea     rax, [rel .str_success]
    jmp     .done

.unknown:
    lea     rax, [rel .str_unknown]

.done:
    pop     rdx
    pop     rcx
IO_ENDFUNC io_strerror

%endif ; IO_ERROR_STRERROR_ASM