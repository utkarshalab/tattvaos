; =============================================================================
; lib/io/core/align.asm
; Alignment checking and calculation helpers.
;
; Provides unified helper routines to validate and align memory addresses
; and byte lengths to sector, page (4KB), and cache-line (64 bytes) boundaries.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_ALIGN_ASM
%define IO_CORE_ALIGN_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

section .text

global align_is_sector_aligned
global align_is_page_aligned
global align_is_cache_aligned
global align_page_offset
global align_page_round_up
global align_cache_round_up

; =============================================================================
; align_is_sector_aligned — Check if a value is aligned to a sector boundary
; In : RDI = Value to check (e.g. byte length, offset)
;      RSI = Sector size in bytes (e.g. 512, 4096)
; Out: RAX = 1 if aligned, 0 if not
; =============================================================================
IO_FUNC align_is_sector_aligned
    test    rsi, rsi
    jz      .not_aligned            ; Prevent divide-by-zero

    mov     rax, rdi
    xor     rdx, rdx
    div     rsi                     ; RDX = value % sector_size
    test    rdx, rdx
    jnz     .not_aligned

    mov     rax, 1                  ; Aligned
    ret

.not_aligned:
    xor     rax, rax
IO_ENDFUNC align_is_sector_aligned

; =============================================================================
; align_is_page_aligned — Check if a address is page-aligned (4KB boundary)
; In : RDI = Virtual or physical address
; Out: RAX = 1 if aligned, 0 if not
; =============================================================================
IO_FUNC align_is_page_aligned
    mov     rax, rdi
    and     rax, 4095               ; 4KB page mask
    jnz     .not_aligned

    mov     rax, 1
    ret

.not_aligned:
    xor     rax, rax
IO_ENDFUNC align_is_page_aligned

; =============================================================================
; align_is_cache_aligned — Check if a address is cache-line aligned (64 bytes)
; In : RDI = Virtual or physical address
; Out: RAX = 1 if aligned, 0 if not
; =============================================================================
IO_FUNC align_is_cache_aligned
    mov     rax, rdi
    and     rax, 63                 ; 64-byte cache line mask
    jnz     .not_aligned

    mov     rax, 1
    ret

.not_aligned:
    xor     rax, rax
IO_ENDFUNC align_is_cache_aligned

; =============================================================================
; align_page_offset — Retrieve the page offset (offset within 4KB page)
; In : RDI = Address
; Out: RAX = Offset (0-4095)
; =============================================================================
IO_FUNC align_page_offset
    mov     rax, rdi
    and     rax, 4095
IO_ENDFUNC align_page_offset

; =============================================================================
; align_page_round_up — Round an address up to the next 4KB page boundary
; In : RDI = Address
; Out: RAX = Page-aligned address
; =============================================================================
IO_FUNC align_page_round_up
    mov     rax, rdi
    add     rax, 4095
    and     rax, ~4095
IO_ENDFUNC align_page_round_up

; =============================================================================
; align_cache_round_up — Round an address up to the next 64-byte boundary
; In : RDI = Address
; Out: RAX = Cache-line aligned address
; =============================================================================
IO_FUNC align_cache_round_up
    mov     rax, rdi
    add     rax, 63
    and     rax, ~63
IO_ENDFUNC align_cache_round_up

%endif ; IO_CORE_ALIGN_ASM
