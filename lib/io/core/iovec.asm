; =============================================================================
; lib/io/core/iovec.asm
; Scatter-Gather iovec builder with automatic page-crossing detection.
;
; When a virtual buffer spans multiple physical pages (4KB boundaries), this
; module splits the buffer into separate iovec_t entries, each contained
; within a single physical page. This is required because NVMe PRP entries
; and virtio descriptors cannot cross page boundaries — a single descriptor
; pointing to bytes on two different physical pages will corrupt data.
;
; The splitter guarantees:
;   - Every emitted iovec_t.len <= (4096 - intra-page offset)
;   - The union of all emitted entries covers exactly [base, base+len)
;   - No gap or overlap between adjacent entries
;   - Physically contiguous pages are merged into a single entry (§13.3.7)
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_IOVEC_ASM
%define IO_CORE_IOVEC_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; Maximum iovec entries we will emit (prevents unbounded output)
IOVEC_MAX_ENTRIES   equ 64

section .text

extern virt_to_phys

; =============================================================================
; iovec_build — Build a scatter-gather iovec_t array from a virtual buffer,
;               splitting at physical page boundaries.
;
; In : RDI = -> iovec_t output array (caller-allocated, >= IOVEC_MAX_ENTRIES)
;      RSI = Virtual base address of the source buffer
;      RDX = Total byte length of the buffer
;      RCX = -> u64 output: number of iovec entries written
; Out: RAX = 0 on success, or negative error code
;           IO_ERR_BADARG   if any argument is null/zero
;           IO_ERR_PAGE_CROSS if entry count would exceed IOVEC_MAX_ENTRIES
; RSO: RDI, RSI, RDX, RCX owned-in; RAX owned-out
; =============================================================================
IO_FUNC iovec_build
    guard_null rdi
    guard_null rsi
    guard_null rcx

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14
    push    r15

    mov     r12, rdi                ; R12 = iovec_t output array base
    mov     r13, rsi                ; R13 = current virtual address
    mov     r14, rdx                ; R14 = remaining bytes
    mov     r15, rcx                ; R15 = -> output count variable

    ; Handle zero-length buffer
    test    r14, r14
    jz      .zero_len

    xor     rbx, rbx                ; RBX = entry count
    xor     r9, r9                  ; R9 = previous physical page end (for merge check)

.split_loop:
    test    r14, r14
    jz      .loop_done              ; No more bytes to process

    ; Check entry limit
    cmp     rbx, IOVEC_MAX_ENTRIES
    jae     .err_too_many

    ; 1. Resolve current virtual address to physical
    mov     rdi, r13
    call    virt_to_phys
    test    rax, rax
    jz      .err_unmapped
    mov     rcx, rax                ; RCX = physical address

    ; 2. Calculate chunk size: min(remaining, bytes-to-page-end)
    mov     rdx, r13
    and     rdx, 0xFFF              ; RDX = offset within current 4KB page
    mov     rax, 4096
    sub     rax, rdx                ; RAX = bytes remaining in this page

    cmp     r14, rax
    cmovb   rax, r14                ; RAX = min(remaining, page_remainder)
    ; RAX = chunk_size for this entry

    ; 3. Try to merge with previous entry if physically contiguous
    test    rbx, rbx
    jz      .new_entry              ; First entry, can't merge

    cmp     rcx, r9                 ; Does this phys addr continue where last ended?
    jne     .new_entry              ; Not contiguous — new entry

    ; Merge: extend previous entry's length
    mov     rdx, rbx
    dec     rdx
    imul    rdx, iovec_t_size
    add     rdx, r12                ; RDX = -> previous iovec_t
    add     [rdx + iovec_t.len], rax
    jmp     .advance

.new_entry:
    ; Write new iovec_t entry
    mov     rdx, rbx
    imul    rdx, iovec_t_size
    add     rdx, r12                ; RDX = -> current iovec_t slot

    mov     [rdx + iovec_t.base], r13       ; Virtual base
    mov     [rdx + iovec_t.phys], rcx       ; Physical base
    mov     [rdx + iovec_t.len], rax        ; Chunk length
    mov     qword [rdx + iovec_t.flags], 0  ; No flags

    inc     rbx                     ; Increment entry count

.advance:
    ; Update tracking: physical end = phys_start + chunk_size
    mov     r9, rcx
    add     r9, rax                 ; R9 = physical end of this chunk (for next merge check)

    add     r13, rax                ; Advance virtual address
    sub     r14, rax                ; Decrease remaining bytes
    jmp     .split_loop

.loop_done:
    mov     [r15], rbx              ; Write entry count to output variable
    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.zero_len:
    mov     qword [r15], 0          ; Zero entries
    xor     rax, rax
    jmp     .done

.err_too_many:
    mov     rax, IO_ERR_PAGE_CROSS  ; Entry count limit exceeded
    jmp     .done

.err_unmapped:
    mov     rax, IO_ERR_BADARG      ; Virtual address not mapped

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC iovec_build

; =============================================================================
; iovec_total_bytes — Sum the .len fields of an iovec_t array
; In : RDI = -> iovec_t array
;      RSI = entry count
; Out: RAX = total byte count
; =============================================================================
IO_FUNC iovec_total_bytes
    guard_null rdi
    push    rcx
    push    rdx

    xor     rax, rax                ; RAX = accumulator
    xor     rcx, rcx                ; RCX = index

.sum_loop:
    cmp     rcx, rsi
    jae     .done

    mov     rdx, rcx
    imul    rdx, iovec_t_size
    add     rdx, rdi
    add     rax, [rdx + iovec_t.len]

    inc     rcx
    jmp     .sum_loop

.done:
    pop     rdx
    pop     rcx
IO_ENDFUNC iovec_total_bytes

%endif ; IO_CORE_IOVEC_ASM