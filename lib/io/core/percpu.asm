; =============================================================================
; lib/io/core/percpu.asm
; Per-CPU local core storage primitive.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_PERCPU_ASM
%define IO_CORE_PERCPU_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .data
global io_lapic_base
io_lapic_base: dq 0xFEE00000        ; LAPIC MMIO virtual base, populated by ACPI scan

section .bss
global global_percpu_table
global_percpu_table: resb percpu_t_size * PERCPU_MAX_CORES

section .text

; =============================================================================
; percpu_init — Initialize the Local CPU storage register (GS_BASE)
; In : None
; Out: RAX = 0 on success, or a negative error band code on failure
; RSO: RAX owned-out
; =============================================================================
IO_FUNC percpu_init
    push    rbx
    push    rcx
    push    rdx

    ; 1. Load the mapped LAPIC Base Address
    mov     rcx, [rel io_lapic_base]
    test    rcx, rcx
    jz      .err_null_base

    ; 2. Read the APIC ID from Local APIC (offset LAPIC_ID = 0x0020)
    mov     eax, [rcx + LAPIC_ID]
    shr     eax, 24                 ; APIC ID is in bits [24:31]
    and     eax, 0xFF               ; Mask to isolate APIC ID

    ; 3. Validate APIC ID is within our static table bounds
    cmp     eax, PERCPU_MAX_CORES
    jae     .err_bounds

    ; 4. Calculate the core's percpu_t block address.
    ; The stride is DERIVED from percpu_t_size. It was previously a hardcoded
    ; `shl rax, 6`, so growing the struct would have left the stride at 64 and
    ; overlapped every block with the next one.
    mov     ebx, eax                ; EBX = APIC ID
    imul    rax, rax, percpu_t_size
    lea     rdx, [rel global_percpu_table]
    add     rax, rdx                ; RAX = pointer to percpu_t for this core

    ; 5. Populate percpu_t fields
    mov     [rax + percpu_t.self], rax
    mov     [rax + percpu_t.cpu_id], ebx
    mov     [rax + percpu_t.lapic_id], ebx

    ; 6. Write the percpu_t pointer to IA32_GS_BASE MSR (0xC0000101)
    ; MSR write takes value in EDX:EAX
    mov     rdx, rax
    shr     rdx, 32                 ; RDX = high 32 bits of address
    ; EAX currently holds low 32 bits because RAX <= 48-bit address space
    mov     rcx, 0xC0000101         ; IA32_GS_BASE MSR
    wrmsr                           ; Write base address to GS segment base register

    xor     rax, rax                ; Return 0 (Success)
    jmp     .done

.err_null_base:
    mov     rax, IO_ERR_NULL
    jmp     .done

.err_bounds:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC percpu_init

; =============================================================================
; percpu_get — Get the pointer to the current CPU's percpu_t structure
; In : None
; Out: RAX = -> percpu_t structure for the calling core
; RSO: RAX owned-out
; =============================================================================
IO_FUNC percpu_get
    ; Reads the 'self' pointer at offset 0 of GS segment directly
    mov     rax, [gs:percpu_t.self]
IO_ENDFUNC percpu_get

%endif ; IO_CORE_PERCPU_ASM
