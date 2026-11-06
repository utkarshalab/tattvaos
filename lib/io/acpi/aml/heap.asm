; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/heap.asm
; =============================================================================
; The interpreter's memory: one region given to aml_init, used from both
; ends. Permanent allocations (namespace nodes, stored values) grow up from
; the bottom; temporary ones (call frames, intermediate results) grow down
; from the top and are all released when an evaluation finishes. The two
; never cross: an allocation that would meet the other side fails.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_HEAP_ASM
%define LIB_IO_ACPI_AML_HEAP_ASM

section .bss
alignb 8
aml_heap_base:      resq 1
aml_heap_perm:      resq 1          ; next permanent byte
aml_heap_temp:      resq 1          ; lowest temporary byte
aml_heap_top:       resq 1          ; end of the region
aml_oom:            resd 1          ; an allocation failed this evaluation

section .text

; -----------------------------------------------------------------------------
; aml_heap_init — take a region of memory
; Input:  RDI = base (16-byte aligned), RSI = size
; Clobbers: RAX
; -----------------------------------------------------------------------------
aml_heap_init:
    mov [rel aml_heap_base], rdi
    mov [rel aml_heap_perm], rdi
    lea rax, [rdi + rsi]
    and rax, -16
    mov [rel aml_heap_top], rax
    mov [rel aml_heap_temp], rax
    ret

; -----------------------------------------------------------------------------
; aml_alloc — permanent, zeroed memory
; Input:  RDI = bytes
; Output: RAX = the memory, or 0 when full
; Clobbers: RAX, RCX, RDX, RDI
; -----------------------------------------------------------------------------
aml_alloc:
    add rdi, 15
    and rdi, -16
    mov rax, [rel aml_heap_perm]
    lea rdx, [rax + rdi]
    cmp rdx, [rel aml_heap_temp]
    ja .full
    mov [rel aml_heap_perm], rdx
    jmp aml_zero
.full:
    mov dword [rel aml_oom], 1
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; aml_talloc — temporary, zeroed memory (released by aml_temp_reset)
; Input:  RDI = bytes
; Output: RAX = the memory, or 0 when full
; Clobbers: RAX, RCX, RDX, RDI
; -----------------------------------------------------------------------------
aml_talloc:
    add rdi, 15
    and rdi, -16
    mov rax, [rel aml_heap_temp]
    sub rax, rdi
    jb .full
    cmp rax, [rel aml_heap_perm]
    jb .full
    mov [rel aml_heap_temp], rax
    jmp aml_zero
.full:
    mov dword [rel aml_oom], 1
    xor eax, eax
    ret

; zero RDI bytes at RAX, return RAX
aml_zero:
    push rax
    mov rcx, rdi
    mov rdi, rax
    xor eax, eax
    rep stosb
    pop rax
    ret

; -----------------------------------------------------------------------------
; aml_temp_reset — release every temporary allocation
; Clobbers: RAX
; -----------------------------------------------------------------------------
aml_temp_reset:
    mov rax, [rel aml_heap_top]
    mov [rel aml_heap_temp], rax
    ret

; -----------------------------------------------------------------------------
; aml_err_missing — the error for a node that could not be found or made:
;                   out of memory if an allocation failed, else not found
; Output: EAX
; -----------------------------------------------------------------------------
aml_err_missing:
    mov eax, -AML_ENOTFOUND
    cmp dword [rel aml_oom], 0
    je .out
    mov eax, -AML_ENOMEM
.out:
    ret

; -----------------------------------------------------------------------------
; aml_heap_used — permanent bytes in use (for /sys and tests)
; Output: RAX
; -----------------------------------------------------------------------------
global aml_heap_used
aml_heap_used:
    mov rax, [rel aml_heap_perm]
    sub rax, [rel aml_heap_base]
    ret

%endif ; LIB_IO_ACPI_AML_HEAP_ASM
