; =============================================================================
; lib/io/core/handle.asm
; Refcounted handle allocation, generation tracking, and lookup.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_HANDLE_ASM
%define IO_CORE_HANDLE_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

; State constants for fd_t.state
FD_CLOSED           equ 0
FD_OPEN             equ 1
FD_STALE            equ 2

section .text

extern io_fd_table

; =============================================================================
; io_handle_alloc — Register an active descriptor; return an encoded handle.
; In : RDI = -> fd_t source descriptor block
;      RSI = -> generation tracker variable (64-bit in memory)
; Out: RAX = handle (index << 16 | generation), or negative error code on failure
; RSO: RDI, RSI owned-in; RAX owned-out
; =============================================================================
IO_FUNC io_handle_alloc
    guard_null rdi
    guard_null rsi

    push    rbx
    push    rcx
    push    rdx
    push    r8
    push    r9

    ; 1. Bounded scan to find a free descriptor slot (FD_CLOSED = 0)
    lea     r8, [rel io_fd_table]   ; R8 = base of descriptor table
    xor     rcx, rcx                ; RCX = slot index iterator

.scan_loop:
    mov     rax, rcx
    imul    rax, fd_t_size          ; RAX = slot offset
    lea     r9, [r8 + rax]          ; R9 = pointer to slot fd_t

    mov     rdx, [r9 + fd_t.state]
    cmp     rdx, FD_CLOSED
    je      .slot_found             ; Found a free slot!

    inc     rcx
    cmp     rcx, 256
    jl      .scan_loop

    ; No free slots found in the table
    mov     rax, IO_ERR_NOMEM       ; Return general out of memory
    jmp     .done

.slot_found:
    ; 2. Bump generation counter
    mov     rax, [rsi]
    inc     rax                     ; Increment tracker value
    mov     [rsi], rax              ; Save back to generation tracker memory
    and     rax, 0xFFFF             ; Limit generation to 16 bits

    ; 3. Copy source fd_t fields from caller's RDI and populate slot
    mov     rdx, [rdi + fd_t.type]
    mov     [r9 + fd_t.type], rdx

    mov     qword [r9 + fd_t.state], FD_OPEN
    mov     qword [r9 + fd_t.refcount], 1
    mov     [r9 + fd_t.generation], rax

    mov     rdx, [rdi + fd_t.device]
    mov     [r9 + fd_t.device], rdx

    mov     rdx, [rdi + fd_t.vtable]
    mov     [r9 + fd_t.vtable], rdx

    mov     rdx, [rdi + fd_t.priv]
    mov     [r9 + fd_t.priv], rdx

    ; 4. Encode: RAX = (slot_index << 16) | (generation & 0xFFFF)
    shl     rcx, 16                 ; RCX = slot_index << 16
    or      rax, rcx                ; RAX = handle

.done:
    pop     r9
    pop     r8
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC io_handle_alloc

; =============================================================================
; io_handle_lookup — Resolve a handle to its fd_t, validating generation.
; In : RDI = handle (index << 16 | generation)
; Out: RAX = -> fd_t descriptor, or negative error code (ERR_PTR) on failure
; RSO: RAX owned-out
; =============================================================================
IO_FUNC io_handle_lookup
    push    rcx
    push    rdx
    push    r8

    ; 1. Decode the handle
    mov     rcx, rdi
    shr     rcx, 16                 ; RCX = slot index
    movzx   rdx, di                 ; RDX = generation (lower 16 bits of RDI)

    ; 2. Check slot index is within bounds (< 256)
    cmp     rcx, 256
    jae     .err_bad_fd

    ; 3. Resolve the slot pointer
    lea     rax, [rel io_fd_table]
    imul    rcx, fd_t_size
    add     rax, rcx                ; RAX = pointer to target fd_t slot

    ; 4. Verify state is open (not closed or stale)
    mov     r8, [rax + fd_t.state]
    cmp     r8, FD_CLOSED
    je      .err_bad_fd
    cmp     r8, FD_STALE
    je      .err_stale

    ; 5. Verify generation matches
    mov     r8, [rax + fd_t.generation]
    and     r8, 0xFFFF
    cmp     r8, rdx
    jne     .err_stale

    ; Validation passed, RAX already points to the fd_t slot
    jmp     .done

.err_bad_fd:
    mov     rax, IO_ERR_BADFD       ; Return invalid file descriptor code
    jmp     .done

.err_stale:
    mov     rax, IO_ERR_STALE       ; Return stale handle code

.done:
    pop     r8
    pop     rdx
    pop     rcx
    ret
IO_ENDFUNC io_handle_lookup

%endif ; IO_CORE_HANDLE_ASM
