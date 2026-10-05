; =============================================================================
; Tattva OS — boot/uefi/memory_map.asm
; =============================================================================
; Convert firmware EFI_MEMORY_DESCRIPTOR records into the packed 24-byte
; memory-map ABI consumed by the kernel.  This routine deliberately treats
; loader and Boot Services memory as reserved: the kernel has not yet adopted
; those pages or installed a final direct map.
;
; The converter is firmware-independent and is exercised by a native unit
; harness.  It fails closed on malformed, overlapping, unsorted, or truncated
; input rather than publishing a partially trusted map.
; =============================================================================

%ifndef UEFI_MEMORY_MAP_ASM
%define UEFI_MEMORY_MAP_ASM

[BITS 64]

EFI_MEMORY_DESCRIPTOR_MIN_SIZE equ 40
UEFI_CANONICAL_ENTRY_SIZE       equ 24

EFI_CONVENTIONAL_MEMORY        equ 7
EFI_UNUSABLE_MEMORY            equ 8
EFI_ACPI_RECLAIM_MEMORY        equ 9
EFI_ACPI_MEMORY_NVS            equ 10

E820_USABLE                    equ 1
E820_RESERVED                  equ 2
E820_ACPI_RECLAIM              equ 3
E820_ACPI_NVS                  equ 4
E820_BAD_MEMORY                equ 5
E820_ATTR_ENABLED              equ 1

section .text

; -----------------------------------------------------------------------------
; uefi_normalize_memory_map
; Input (internal/native ABI):
;   RDI = raw EFI memory-map address
;   RSI = raw map size in bytes
;   RDX = firmware-reported descriptor stride
;   RCX = canonical output address
;   R8  = output capacity in 24-byte entries
; Output:
;   CF=0: EAX = canonical entry count
;   CF=1: EAX = 0; output must be discarded
;
; The raw descriptors must be ordered and non-overlapping.  Adjacent records
; are coalesced only when their canonical type and attributes are identical.
; -----------------------------------------------------------------------------
global uefi_normalize_memory_map
uefi_normalize_memory_map:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; current raw descriptor
    mov r13, rsi                    ; raw byte count, then descriptor count
    mov r14, rdx                    ; descriptor stride
    mov r15, rcx                    ; canonical output base
    mov rbp, r8                     ; canonical output capacity

    test r12, r12
    jz .invalid
    test r15, r15
    jz .invalid
    test r13, r13
    jz .invalid
    test rbp, rbp
    jz .invalid
    cmp r14, EFI_MEMORY_DESCRIPTOR_MIN_SIZE
    jb .invalid

    ; Validate both spans before touching either.  Reject aliasing so output
    ; writes can never corrupt descriptors that have not yet been consumed.
    mov r10, r12
    add r10, r13                    ; raw end (exclusive)
    jc .invalid

    mov rax, rbp
    mov rdx, UEFI_CANONICAL_ENTRY_SIZE
    mul rdx                         ; RDX:RAX = capacity * entry size
    test rdx, rdx
    jnz .invalid
    mov r11, r15
    add r11, rax                    ; output end (exclusive)
    jc .invalid

    cmp r15, r10
    jae .spans_disjoint
    cmp r12, r11
    jb .invalid

.spans_disjoint:
    ; The map must contain a whole number of complete descriptors.
    mov rax, r13
    xor edx, edx
    div r14
    test rdx, rdx
    jnz .invalid
    test rax, rax
    jz .invalid
    mov r13, rax                    ; descriptors remaining

    mov rdi, r15                    ; next canonical output record
    xor r9d, r9d                    ; canonical output count
    xor r10d, r10d                  ; previous raw descriptor end

.descriptor_loop:
    mov rbx, [r12 + 8]              ; PhysicalStart
    test rbx, 0xFFF
    jnz .invalid

    mov r11, [r12 + 24]             ; NumberOfPages
    test r11, r11
    jz .invalid
    mov rax, 0x000FFFFFFFFFFFFF     ; largest count safe to shift by 12
    cmp r11, rax
    ja .invalid
    shl r11, 12                     ; canonical byte length

    mov rcx, rbx
    add rcx, r11                    ; current end (exclusive)
    jc .invalid

    ; An overlap—regardless of type—could make reserved memory allocatable if
    ; the kernel later sees an overlapping usable descriptor.  Reject it.
    test r9, r9
    jz .map_type
    cmp rbx, r10
    jb .invalid

.map_type:
    mov eax, [r12]
    mov edx, E820_RESERVED
    cmp eax, EFI_CONVENTIONAL_MEMORY
    je .type_usable
    cmp eax, EFI_UNUSABLE_MEMORY
    je .type_bad
    cmp eax, EFI_ACPI_RECLAIM_MEMORY
    je .type_acpi
    cmp eax, EFI_ACPI_MEMORY_NVS
    je .type_nvs
    jmp .type_ready

.type_usable:
    mov edx, E820_USABLE
    jmp .type_ready
.type_bad:
    mov edx, E820_BAD_MEMORY
    jmp .type_ready
.type_acpi:
    mov edx, E820_ACPI_RECLAIM
    jmp .type_ready
.type_nvs:
    mov edx, E820_ACPI_NVS

.type_ready:
    ; Coalesce only exact adjacency with identical semantics.  Gaps remain
    ; explicit, and overlaps were rejected above.
    test r9, r9
    jz .emit
    cmp rbx, r10
    jne .emit
    cmp dword [rdi - 8], edx        ; prior entry type
    jne .emit
    cmp dword [rdi - 4], E820_ATTR_ENABLED
    jne .emit
    add [rdi - 16], r11             ; extend prior entry length
    jmp .advance

.emit:
    cmp r9, rbp
    jae .invalid
    mov [rdi], rbx
    mov [rdi + 8], r11
    mov [rdi + 16], edx
    mov dword [rdi + 20], E820_ATTR_ENABLED
    add rdi, UEFI_CANONICAL_ENTRY_SIZE
    inc r9

.advance:
    mov r10, rcx
    add r12, r14
    dec r13
    jnz .descriptor_loop

    mov rax, r9
    clc
    jmp .done

.invalid:
    xor eax, eax
    stc

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

%endif ; UEFI_MEMORY_MAP_ASM
