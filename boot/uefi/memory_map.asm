; =============================================================================
; Tattva OS — boot/uefi/memory_map.asm
; =============================================================================
; Convert firmware EFI_MEMORY_DESCRIPTOR records into the packed 24-byte
; memory-map ABI consumed by the kernel.  This routine deliberately treats
; loader and Boot Services memory as reserved: the kernel has not yet adopted
; those pages or installed a final direct map.
;
; The converter is firmware-independent and is exercised by a native unit
; harness.  Firmware descriptor order is not trusted: output is inserted in
; physical-address order, while malformed, overlapping, or truncated input
; fails closed rather than publishing a partially trusted map.
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
;   CF=0: EAX = canonical entry count, EDX = 0
;   CF=1: EAX = 0, EDX = rejection class; output must be discarded
;     1=input, 2=span alias/overflow, 3=stride, 4=descriptor,
;     5=ordering/overlap, 6=output capacity
;
; Raw descriptors may arrive in any order.  Output is sorted, overlaps are
; rejected in either direction, and adjacent records coalesce only when their
; canonical type and attributes are identical.
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
    mov r8d, 1

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

    mov r8d, 2
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
    mov r8d, 3
    ; The map must contain a whole number of complete descriptors.
    mov rax, r13
    xor edx, edx
    div r14
    test rdx, rdx
    jnz .invalid
    test rax, rax
    jz .invalid
    mov r13, rax                    ; descriptors remaining

    xor r9d, r9d                    ; canonical output count

.descriptor_loop:
    mov r8d, 4
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

    mov r10, rbx
    add r10, r11                    ; current end (exclusive)
    jc .invalid

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
    ; Find the sorted insertion point. RAX is the number of existing entries
    ; at or after RDI, which also bounds every shift below.
    mov rdi, r15
    mov rax, r9
.find_insertion:
    test rax, rax
    jz .insertion_found
    mov rcx, [rdi]
    cmp rcx, rbx
    jae .insertion_found
    add rdi, UEFI_CANONICAL_ENTRY_SIZE
    dec rax
    jmp .find_insertion

.insertion_found:
    xor esi, esi                    ; bit 0=merge prev, bit 1=merge next
    mov r8d, 5

    ; The predecessor must end at or before the new range.
    cmp rdi, r15
    je .check_successor
    mov rcx, [rdi - UEFI_CANONICAL_ENTRY_SIZE]
    add rcx, [rdi - UEFI_CANONICAL_ENTRY_SIZE + 8]
    jc .invalid
    cmp rbx, rcx
    jb .invalid
    jne .check_successor
    cmp dword [rdi - UEFI_CANONICAL_ENTRY_SIZE + 16], edx
    jne .check_successor
    cmp dword [rdi - UEFI_CANONICAL_ENTRY_SIZE + 20], E820_ATTR_ENABLED
    jne .check_successor
    or esi, 1

.check_successor:
    ; The new range must end at or before the successor. Equal boundaries can
    ; merge only when their canonical semantics match.
    test rax, rax
    jz .apply_merge
    mov rcx, [rdi]
    cmp r10, rcx
    ja .invalid
    jne .apply_merge
    cmp dword [rdi + 16], edx
    jne .apply_merge
    cmp dword [rdi + 20], E820_ATTR_ENABLED
    jne .apply_merge
    or esi, 2

.apply_merge:
    test esi, 1
    jz .maybe_merge_next

    add qword [rdi - UEFI_CANONICAL_ENTRY_SIZE + 8], r11
    jc .invalid
    test esi, 2
    jz .advance

    ; New range bridges two equivalent neighbors. Extend the predecessor with
    ; the successor, then remove that successor from the sorted output.
    mov rcx, [rdi + 8]
    add [rdi - UEFI_CANONICAL_ENTRY_SIZE + 8], rcx
    jc .invalid
    dec rax
    jz .bridge_removed
    mov rcx, rax
    imul rcx, 3                    ; three qwords per packed entry
    lea rsi, [rdi + UEFI_CANONICAL_ENTRY_SIZE]
    cld
    rep movsq
.bridge_removed:
    dec r9
    jmp .advance

.maybe_merge_next:
    test esi, 2
    jz .emit
    mov [rdi], rbx
    add qword [rdi + 8], r11
    jc .invalid
    jmp .advance

.emit:
    mov r8d, 6
    cmp r9, rbp
    jae .invalid

    ; Shift the sorted suffix one entry to the right. Copy backwards because
    ; source and destination overlap.
    mov r8, rax
    test rax, rax
    jz .write_entry
    mov rcx, r9
    imul rcx, UEFI_CANONICAL_ENTRY_SIZE
    lea rsi, [r15 + rcx - 8]
    lea rdi, [rsi + UEFI_CANONICAL_ENTRY_SIZE]
    mov rcx, r8
    imul rcx, 3
    std
    rep movsq
    cld

    mov rcx, r9
    sub rcx, r8
    imul rcx, UEFI_CANONICAL_ENTRY_SIZE
    lea rdi, [r15 + rcx]

.write_entry:
    mov [rdi], rbx
    mov [rdi + 8], r11
    mov [rdi + 16], edx
    mov dword [rdi + 20], E820_ATTR_ENABLED
    add rdi, UEFI_CANONICAL_ENTRY_SIZE
    inc r9

.advance:
    add r12, r14
    dec r13
    jnz .descriptor_loop

    mov rax, r9
    xor edx, edx
    clc
    jmp .done

.invalid:
    xor eax, eax
    mov edx, r8d
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
