; =============================================================================
; lib/io/core/buffer.asm
; DMA memory buffer pinning and refcount lifecycle management.
;
; Tracks memory ranges actively mapped to device DMA queues. Pin counts
; prevent in-flight buffers from being recycled or freed by page reclaim.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_BUFFER_ASM
%define IO_CORE_BUFFER_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/error/codes.asm"

; Pin Table Configuration
PIN_POOL_SIZE       equ 256         ; Support up to 256 tracked ranges
PIN_SLOT_VIRT       equ 0           ; Offset 0: Virtual base address (64-bit)
PIN_SLOT_LEN        equ 8           ; Offset 8: Range length in bytes (64-bit)
PIN_SLOT_PHYS       equ 16          ; Offset 16: Mapped physical base address (64-bit)
PIN_SLOT_COUNT      equ 24          ; Offset 24: Active pin refcount (64-bit)
PIN_SLOT_SIZE       equ 32          ; Total descriptor size = 32 bytes

section .bss
global global_pin_table
global_pin_table:   resb PIN_SLOT_SIZE * PIN_POOL_SIZE

section .text

extern virt_to_phys

; =============================================================================
; buffer_pin — Pin a memory range and increment its DMA pin count
; In : RDI = Virtual base address
;      RSI = Length in bytes
; Out: RAX = pin_token (positive non-zero key) or negative error code
; RSO: RDI, RSI owned-in; RAX owned-out
; =============================================================================
IO_FUNC buffer_pin
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

    mov     r12, rdi                ; R12 = virtual_addr
    mov     r13, rsi                ; R13 = length

    ; 1. Scan for an exact match that is already active
    lea     rbx, [rel global_pin_table]
    xor     rcx, rcx                ; RCX = index

.scan_match:
    cmp     rcx, PIN_POOL_SIZE
    jae     .no_match

    mov     rax, rcx
    shl     rax, 5                  ; index * 32
    lea     rdx, [rbx + rax]        ; RDX = slot pointer

    cmp     qword [rdx + PIN_SLOT_COUNT], 0
    jz      .next_match

    cmp     [rdx + PIN_SLOT_VIRT], r12
    jne     .next_match
    cmp     [rdx + PIN_SLOT_LEN], r13
    jne     .next_match

    ; Found exact match! Lock increment the refcount
    lock inc qword [rdx + PIN_SLOT_COUNT]
    inc     rcx                     ; token = index + 1
    mov     rax, rcx
    jmp     .done

.next_match:
    inc     rcx
    jmp     .scan_match

.no_match:
    ; 2. Scan for a free slot to allocate a new range tracking block
    xor     rcx, rcx

.scan_free:
    cmp     rcx, PIN_POOL_SIZE
    jae     .err_full

    mov     rax, rcx
    shl     rax, 5
    lea     rdx, [rbx + rax]

    cmp     qword [rdx + PIN_SLOT_COUNT], 0
    jz      .allocate

    inc     rcx
    jmp     .scan_free

.allocate:
    ; Translate virtual base to physical base address
    mov     rdi, r12
    call    virt_to_phys
    test    rax, rax
    jz      .err_badarg_pop         ; Unmapped address

    ; Populate slot
    mov     [rdx + PIN_SLOT_VIRT], r12
    mov     [rdx + PIN_SLOT_LEN], r13
    mov     [rdx + PIN_SLOT_PHYS], rax
    mov     qword [rdx + PIN_SLOT_COUNT], 1

    inc     rcx                     ; token = index + 1
    mov     rax, rcx
    jmp     .done

.err_badarg_pop:
    mov     rax, IO_ERR_BADARG
    jmp     .done

.err_full:
    mov     rax, IO_ERR_NOMEM
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
    pop     r13
    pop     r12
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC buffer_pin

; =============================================================================
; buffer_unpin — Decrement DMA pin count for a given token
; In : RDI = pin_token (returned by buffer_pin)
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; RSO: RDI owned-in; RAX owned-out
; =============================================================================
IO_FUNC buffer_unpin
    test    rdi, rdi
    jz      .err_badarg
    cmp     rdi, PIN_POOL_SIZE
    ja      .err_badarg

    push    rbx
    push    rcx

    mov     rax, rdi
    dec     rax                     ; RAX = index (0-indexed)
    shl     rax, 5                  ; index * 32
    lea     rbx, [rel global_pin_table]
    add     rbx, rax                ; RBX = -> slot

    ; Verify active slot
    cmp     qword [rbx + PIN_SLOT_COUNT], 0
    jz      .err_badarg_pop

    lock dec qword [rbx + PIN_SLOT_COUNT]
    jnz     .success

    ; Refcount reached 0: clear virtual mapping entries to free slot
    mov     qword [rbx + PIN_SLOT_VIRT], 0
    mov     qword [rbx + PIN_SLOT_LEN], 0
    mov     qword [rbx + PIN_SLOT_PHYS], 0

.success:
    xor     rax, rax                ; Return 0
    jmp     .done

.err_badarg_pop:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rcx
    pop     rbx
    ret

.err_badarg:
    mov     rax, IO_ERR_BADARG
IO_ENDFUNC buffer_unpin

; =============================================================================
; buffer_is_pinned — Detect if any part of a range overlaps a pinned range
; In : RDI = Virtual base address
;      RSI = Length in bytes
; Out: RAX = 1 if pinned (overlap detected), 0 if free
; =============================================================================
IO_FUNC buffer_is_pinned
    guard_null rdi
    test    rsi, rsi
    jz      .not_pinned

    push    rbx
    push    rcx
    push    rdx
    push    rdi
    push    rsi

    mov     r8, rdi                 ; R8 = target_start
    add     rsi, rdi                ; RSI = target_end

    lea     rbx, [rel global_pin_table]
    xor     rcx, rcx                ; RCX = index

.scan:
    cmp     rcx, PIN_POOL_SIZE
    jae     .not_pinned_pop

    mov     rax, rcx
    shl     rax, 5
    lea     rdx, [rbx + rax]

    cmp     qword [rdx + PIN_SLOT_COUNT], 0
    jz      .next

    ; Overlap detection:
    ; (target_start < slot_end) AND (slot_start < target_end)
    mov     rax, [rdx + PIN_SLOT_VIRT]
    add     rax, [rdx + PIN_SLOT_LEN] ; RAX = slot_end

    cmp     r8, rax
    jae     .next                   ; target_start >= slot_end, no overlap

    mov     rax, [rdx + PIN_SLOT_VIRT] ; RAX = slot_start
    cmp     rax, rsi
    jae     .next                   ; slot_start >= target_end, no overlap

    ; Overlap found!
    mov     rax, 1
    jmp     .done

.next:
    inc     rcx
    jmp     .scan

.not_pinned_pop:
    xor     rax, rax

.done:
    pop     rsi
    pop     rdi
    pop     rdx
    pop     rcx
    pop     rbx
    ret

.not_pinned:
    xor     rax, rax
IO_ENDFUNC buffer_is_pinned

; =============================================================================
; buffer_refuse_free — Enforce safety check for deallocators (§12.5)
; In : RDI = Virtual base address
;      RSI = Length in bytes
; Out: RAX = 0 if safe to free, or IO_ERR_STALE (-0x102) if pinned
; =============================================================================
IO_FUNC buffer_refuse_free
    call    buffer_is_pinned
    test    rax, rax
    jz      .safe

    mov     rax, IO_ERR_STALE       ; Range is actively pinned, refuse deallocation
    ret

.safe:
    xor     rax, rax
IO_ENDFUNC buffer_refuse_free

%endif ; IO_CORE_BUFFER_ASM
