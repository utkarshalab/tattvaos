; =============================================================================
; lib/io/core/fixed_buf.asm
; Pre-registered and pinned DMA buffers (IO_FIXEDBUF).
;
; Registers and pins memory buffers at startup, compiling their virtual address
; ranges to physical pointers in a static lookup table to eliminate per-request
; address translation overhead on the I/O hot-path.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_FIXED_BUF_ASM
%define IO_CORE_FIXED_BUF_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

; Pools Configuration
FIXED_POOL_SIZE     equ 64          ; Support up to 64 pre-registered buffers
FIXED_SLOT_PHYS     equ 0           ; Offset 0: Physical base address (64-bit)
FIXED_SLOT_LEN      equ 8           ; Offset 8: Buffer length in bytes (64-bit)
FIXED_SLOT_SIZE     equ 16          ; Entry size = 16 bytes (matches spec §13.3.2)

META_SLOT_VIRT      equ 0           ; Offset 0: Virtual base address (64-bit)
META_SLOT_TOKEN     equ 8           ; Offset 8: Pin token from buffer_pin (64-bit)
META_SLOT_SIZE      equ 16          ; Metadata size = 16 bytes

section .data
align 8
global fixed_buffer_table
fixed_buffer_table: dq fixed_buffer_array

section .bss
alignb 16
fixed_buffer_array: resb FIXED_SLOT_SIZE * FIXED_POOL_SIZE
fixed_buffer_meta:  resb META_SLOT_SIZE * FIXED_POOL_SIZE

section .text


; =============================================================================
; fixed_buf_register — Register and pin a virtual buffer
; In : RDI = Virtual base address
;      RSI = Buffer length in bytes
; Out: RAX = buffer_id (0-63 slot index) or negative error code
; RSO: RDI, RSI owned-in; RAX owned-out
; =============================================================================
IO_FUNC fixed_buf_register
    guard_null rdi
    test    rsi, rsi
    jz      .err_badarg

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi
    push    r12
    push    r13
    push    r14

    mov     r12, rdi                ; R12 = virtual_addr
    mov     r13, rsi                ; R13 = length

    ; 1. Pin memory range to freeze pages
    mov     rdi, r12
    mov     rsi, r13
    call    buffer_pin
    IS_ERR  rax
    jae     .err_pin_fail           ; Failed to pin buffer (nomem, badarg)
    mov     r14, rax                ; R14 = pin_token

    ; 2. Resolve physical address
    mov     rdi, r12
    call    virt_to_phys
    test    rax, rax
    jz      .err_unmapped

    ; 3. Scan for a free slot in fixed_buffer_array (represented by 0 physical base)
    lea     rbx, [rel fixed_buffer_array]
    xor     rcx, rcx                ; RCX = index iterator

.scan_slot:
    cmp     rcx, FIXED_POOL_SIZE
    jae     .err_full

    mov     rdx, rcx
    shl     rdx, 4                  ; index * 16
    lea     rsi, [rbx + rdx]

    cmp     qword [rsi + FIXED_SLOT_PHYS], 0
    jz      .populate

    inc     rcx
    jmp     .scan_slot

.populate:
    ; Populate table slot
    mov     [rsi + FIXED_SLOT_PHYS], rax
    mov     [rsi + FIXED_SLOT_LEN], r13

    ; Populate metadata slot
    lea     rbx, [rel fixed_buffer_meta]
    mov     rdx, rcx
    shl     rdx, 4                  ; index * 16
    lea     rsi, [rbx + rdx]

    mov     [rsi + META_SLOT_VIRT], r12
    mov     [rsi + META_SLOT_TOKEN], r14

    mov     rax, rcx                ; Return buffer_id (index)
    jmp     .done

.err_unmapped:
    ; Cleanup pin before returning error
    mov     rdi, r14
    call    buffer_unpin
    mov     rax, IO_ERR_BADARG
    jmp     .done

.err_full:
    ; Cleanup pin
    mov     rdi, r14
    call    buffer_unpin
    mov     rax, IO_ERR_NOMEM
    jmp     .done

.err_pin_fail:
    ; RAX already holds the error code
    jmp     .done

.err_badarg:
    mov     rax, IO_ERR_BADARG
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

.done:
    pop     r14
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC fixed_buf_register

; =============================================================================
; fixed_buf_unregister — Unregister a pre-registered buffer
; In : RDI = buffer_id (index 0-63)
; Out: RAX = 0 on success, or negative error code (IO_ERR_STALE / IO_ERR_BADARG)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC fixed_buf_unregister
    cmp     rdi, FIXED_POOL_SIZE
    jae     .err_badarg

    push    rbx
    push    rcx
    push    rdx
    push    rsi

    mov     rbx, rdi                ; RBX = buffer_id

    ; Verify that the slot is registered (phys_addr > 0)
    mov     rax, rbx
    shl     rax, 4                  ; index * 16
    lea     rcx, [rel fixed_buffer_array]
    add     rcx, rax                ; RCX = -> array entry

    cmp     qword [rcx + FIXED_SLOT_PHYS], 0
    jz      .err_badarg_pop

    ; Fetch metadata entry
    lea     rdx, [rel fixed_buffer_meta]
    add     rdx, rax                ; RDX = -> meta entry
    mov     rsi, [rdx + META_SLOT_TOKEN] ; RSI = pin_token

    ; §12.5 Security Invariant check:
    ; Verify that the pin refcount inside global_pin_table is exactly 1.
    ; If the count is > 1, then a transaction is in progress, return IO_ERR_STALE.
    mov     rax, rsi
    dec     rax                     ; 0-based index of slot in global_pin_table
    shl     rax, 5                  ; index * 32 (PIN_SLOT_SIZE)
    lea     rsi, [rel global_pin_table]
    add     rsi, rax                ; RSI = -> global_pin_table entry

    ; PIN_SLOT_COUNT is at offset 24
    cmp     qword [rsi + 24], 1
    ja      .err_stale              ; Active I/O pending, block unregister!

    ; Safe to clear: unpin memory range
    mov     rdi, [rdx + META_SLOT_TOKEN]
    call    buffer_unpin

    ; Clear lookup entries
    mov     qword [rcx + FIXED_SLOT_PHYS], 0
    mov     qword [rcx + FIXED_SLOT_LEN], 0
    mov     qword [rdx + META_SLOT_VIRT], 0
    mov     qword [rdx + META_SLOT_TOKEN], 0

    xor     rax, rax                ; Return 0
    jmp     .done

.err_stale:
    mov     rax, IO_ERR_STALE
    jmp     .done

.err_badarg_pop:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

.err_badarg:
    mov     rax, IO_ERR_BADARG
IO_ENDFUNC fixed_buf_unregister

; =============================================================================
; fixed_buf_resolve — Resolve physical memory address from registered buffer
; In : RDI = buffer_id (index 0-63)
;      RSI = Offset inside buffer
; Out: RAX = physical target address, or 0 if invalid / out of bounds
; =============================================================================
IO_FUNC fixed_buf_resolve
    cmp     rdi, FIXED_POOL_SIZE
    jae     .invalid

    push    rbx
    push    rcx

    mov     rax, rdi
    shl     rax, 4                  ; index * 16
    lea     rbx, [rel fixed_buffer_array]
    add     rbx, rax                ; RBX = -> entry

    mov     rax, [rbx + FIXED_SLOT_PHYS] ; RAX = physical base
    test    rax, rax
    jz      .invalid_pop            ; Entry not active

    mov     rcx, [rbx + FIXED_SLOT_LEN]  ; RCX = length
    cmp     rsi, rcx
    jae     .invalid_pop            ; Offset out of bounds

    add     rax, rsi                ; RAX = physical base + offset
    jmp     .done

.invalid_pop:
    xor     rax, rax

.done:
    pop     rcx
    pop     rbx
    ret

.invalid:
    xor     rax, rax
IO_ENDFUNC fixed_buf_resolve

%endif ; IO_CORE_FIXED_BUF_ASM
