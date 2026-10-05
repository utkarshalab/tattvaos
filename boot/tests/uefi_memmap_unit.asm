; Native userspace harness for boot/uefi/memory_map.asm.
; Exit status 0 means every checked converter contract passed.

[BITS 64]
default rel

%include "lib/mem/mem.inc"
%include "boot/uefi/memory_map.asm"
%include "lib/mem/phys/map.asm"

section .text
global _start
_start:
    ; 48-byte firmware strides must be honored.  Adjacent conventional ranges
    ; coalesce, while ACPI/NVS/unusable/unknown types retain safe semantics.
    lea rdi, [rel map48]
    mov rsi, map48_end - map48
    mov rdx, 48
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jc .fail_1
    cmp eax, 5
    jne .fail_1
    cmp qword [output + 0], 0x00100000
    jne .fail_1
    cmp qword [output + 8], 0x00003000
    jne .fail_1
    cmp dword [output + 16], E820_USABLE
    jne .fail_1
    cmp dword [output + 20], E820_ATTR_ENABLED
    jne .fail_1
    cmp dword [output + 24 + 16], E820_ACPI_RECLAIM
    jne .fail_1
    cmp dword [output + 48 + 16], E820_ACPI_NVS
    jne .fail_1
    cmp dword [output + 72 + 16], E820_BAD_MEMORY
    jne .fail_1
    cmp dword [output + 96 + 16], E820_RESERVED
    jne .fail_1

    ; Feed emitted bytes to the real kernel parser to lock both sides of the
    ; packed 24-byte ABI together.
    lea rdi, [rel output]
    mov rsi, 5
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    call phys_parse_e820
    jc .fail_1
    cmp rax, 0x00103000
    jne .fail_1
    cmp rcx, 3
    jne .fail_1
    test r8, r8
    jnz .fail_1

    ; Minimum-size descriptors are accepted.  Loader and Boot Services memory
    ; stay reserved until the kernel explicitly adopts those pages.
    lea rdi, [rel map40]
    mov rsi, map40_end - map40
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 4
    call uefi_normalize_memory_map
    jc .fail_2
    cmp eax, 1                     ; adjacent reserved records coalesce
    jne .fail_2
    cmp qword [output + 8], 0x3000
    jne .fail_2
    cmp dword [output + 16], E820_RESERVED
    jne .fail_2

    ; Descriptor stride below the ABI minimum is malformed.
    lea rdi, [rel map40]
    mov rsi, map40_end - map40
    mov rdx, 39
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_3
    test eax, eax
    jnz .fail_3

    ; A partial trailing descriptor must never be silently ignored.
    lea rdi, [rel map40]
    mov rsi, (map40_end - map40) - 1
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_4

    ; Zero-page descriptors are forbidden by the UEFI memory-map contract.
    lea rdi, [rel zero_pages]
    mov rsi, 40
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_5

    ; PhysicalStart must be page aligned.
    lea rdi, [rel unaligned_base]
    mov rsi, 40
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_6

    ; NumberOfPages << 12 must not wrap.
    lea rdi, [rel page_shift_overflow]
    mov rsi, 40
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_7

    ; PhysicalStart + byte length must not wrap.
    lea rdi, [rel end_overflow]
    mov rsi, 40
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_8

    ; Capacity exhaustion is an error, never a truncated success.
    lea rdi, [rel map48]
    mov rsi, map48_end - map48
    mov rdx, 48
    lea rcx, [rel output]
    mov r8, 4
    call uefi_normalize_memory_map
    jnc .fail_9
    test eax, eax
    jnz .fail_9

    ; Overlaps are rejected even when a reserved descriptor follows a usable
    ; one; otherwise the usable view could weaken the reservation.
    lea rdi, [rel overlapping]
    mov rsi, overlapping_end - overlapping
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_10

    ; Unsorted input is equally unsafe and fails closed.
    lea rdi, [rel unsorted]
    mov rsi, unsorted_end - unsorted
    mov rdx, 40
    lea rcx, [rel output]
    mov r8, 8
    call uefi_normalize_memory_map
    jnc .fail_11

    ; Input/output aliasing could overwrite unread descriptors.
    lea rdi, [rel alias_map]
    mov rsi, 40
    mov rdx, 40
    lea rcx, [rel alias_map]
    mov r8, 1
    call uefi_normalize_memory_map
    jnc .fail_12

    xor edi, edi
    jmp .exit

.fail_1:  mov edi, 1
          jmp .exit
.fail_2:  mov edi, 2
          jmp .exit
.fail_3:  mov edi, 3
          jmp .exit
.fail_4:  mov edi, 4
          jmp .exit
.fail_5:  mov edi, 5
          jmp .exit
.fail_6:  mov edi, 6
          jmp .exit
.fail_7:  mov edi, 7
          jmp .exit
.fail_8:  mov edi, 8
          jmp .exit
.fail_9:  mov edi, 9
          jmp .exit
.fail_10: mov edi, 10
          jmp .exit
.fail_11: mov edi, 11
          jmp .exit
.fail_12: mov edi, 12

.exit:
    mov eax, 60
    syscall

%macro EFI_DESC 4
    dd %1, 0
    dq %2, 0, %3, %4
%endmacro

%macro EFI_DESC48 4
    EFI_DESC %1, %2, %3, %4
    dq 0xA5A5A5A5A5A5A5A5
%endmacro

section .data
align 8
map48:
    EFI_DESC48 7,  0x00100000, 1, 0
    EFI_DESC48 7,  0x00101000, 2, 0
    EFI_DESC48 9,  0x00200000, 1, 0
    EFI_DESC48 10, 0x00300000, 1, 0
    EFI_DESC48 8,  0x00400000, 1, 0
    EFI_DESC48 0x80000000, 0x00500000, 1, 0
map48_end:

map40:
    EFI_DESC 1, 0x00600000, 1, 0
    EFI_DESC 2, 0x00601000, 2, 0
map40_end:

zero_pages:
    EFI_DESC 7, 0x00700000, 0, 0
unaligned_base:
    EFI_DESC 7, 0x00700001, 1, 0
page_shift_overflow:
    EFI_DESC 7, 0, 0x0010000000000000, 0
end_overflow:
    EFI_DESC 7, 0xFFFFFFFFFFFFF000, 2, 0

overlapping:
    EFI_DESC 7, 0x00800000, 2, 0
    EFI_DESC 0, 0x00801000, 1, 0
overlapping_end:

unsorted:
    EFI_DESC 7, 0x00901000, 1, 0
    EFI_DESC 7, 0x00900000, 1, 0
unsorted_end:

alias_map:
    EFI_DESC 7, 0x00A00000, 1, 0

section .bss
align 16
output: resb 8 * UEFI_CANONICAL_ENTRY_SIZE
