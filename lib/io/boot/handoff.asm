; =============================================================================
; lib/io/boot/handoff.asm
; Bootloader parameter handoff ingestion.
;
; Deep-copies bootloader parameters (boot_handoff_t) from temporary memory
; into permanent kernel-managed tables before the bootloader memory pages
; are reclaimed by the physical memory allocator.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BOOT_HANDOFF_ASM
%define IO_BOOT_HANDOFF_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .bss
global global_handoff_magic
global_handoff_magic:    resq 1
global global_handoff_rsdp
global_handoff_rsdp:     resq 1
global global_handoff_fb
global_handoff_fb:       resq 1
global global_handoff_boot_dev
global_handoff_boot_dev: resq 1
global global_handoff_pml4
global_handoff_pml4:     resq 1

; Static memory map storage (supports up to 128 entries)
global global_mem_map_count
global_mem_map_count:    resq 1
global global_mem_map_table
global_mem_map_table:    resb mem_map_entry_t_size * 128

section .text

; =============================================================================
; handoff_ingest — Deep-copy boot loader parameters to permanent storage
; In : RDI = -> boot_handoff_t structure (in temporary bootloader memory)
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG / IO_ERR_NOMEM)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC handoff_ingest
    guard_null rdi

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; 1. Copy scalar parameters
    mov     rax, [rdi + boot_handoff_t.magic]
    mov     [rel global_handoff_magic], rax
    
    mov     rax, [rdi + boot_handoff_t.rsdp]
    mov     [rel global_handoff_rsdp], rax

    mov     rax, [rdi + boot_handoff_t.framebuffer]
    mov     [rel global_handoff_fb], rax

    mov     rax, [rdi + boot_handoff_t.boot_device]
    mov     [rel global_handoff_boot_dev], rax

    mov     rax, [rdi + boot_handoff_t.pml4]
    mov     [rel global_handoff_pml4], rax

    ; 2. Deep-copy the memory map array
    mov     rsi, [rdi + boot_handoff_t.mem_map]     ; Source mem_map array
    mov     rcx, [rdi + boot_handoff_t.mem_map_cnt] ; Entry count

    test    rsi, rsi
    jz      .err_badarg

    cmp     rcx, 128
    ja      .err_too_many

    mov     [rel global_mem_map_count], rcx

    lea     rdi, [rel global_mem_map_table]         ; Destination
    imul    rcx, mem_map_entry_t_size               ; Total byte size to copy
    rep     movsb                                   ; Perform copy

    xor     rax, rax                                ; Return 0 (Success)
    jmp     .done

.err_too_many:
    mov     rax, IO_ERR_NOMEM                       ; Exceeded static limit
    jmp     .done

.err_badarg:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC handoff_ingest

%endif ; IO_BOOT_HANDOFF_ASM
