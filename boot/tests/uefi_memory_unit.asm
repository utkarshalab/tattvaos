; Native userspace harness for firmware-sized UEFI memory-map ownership.

[BITS 64]
default rel

%include "boot/uefi/memory.asm"

MODE_SIMPLE   equ 0
MODE_GROW     equ 1
MODE_OVERSIZE equ 2
SIMPLE_BYTES  equ 48 * 2
GROWN_BYTES   equ 48 * 180

section .text
global _start
_start:
    lea rax, [rel boot_services]
    mov [rel system_table + SYS_TABLE_BOOT_SERVICES], rax
    lea rax, [rel fake_get_memory_map]
    mov [rel boot_services + BS_GET_MEMORY_MAP], rax
    lea rax, [rel fake_allocate_pool]
    mov [rel boot_services + BS_ALLOCATE_POOL], rax
    lea rax, [rel fake_free_pool]
    mov [rel boot_services + BS_FREE_POOL], rax

    ; A normal probe receives descriptor slack and rounds to a page.
    mov dword [rel map_mode], MODE_SIMPLE
    call reset_mock_counts
    lea rcx, [rel system_table]
    call uefi_memory_map_acquire
    test rax, rax
    jnz .fail_1
    lea rax, [rel map_buffer_a]
    cmp [rel uefi_mem_map_buf], rax
    jne .fail_1
    cmp qword [rel uefi_mem_map_capacity], 4096
    jne .fail_1
    cmp qword [rel uefi_map_size], SIMPLE_BYTES
    jne .fail_1
    cmp qword [rel uefi_desc_size], 48
    jne .fail_1
    cmp dword [rel uefi_desc_version], EFI_MEMORY_DESCRIPTOR_VERSION
    jne .fail_1
    cmp qword [rel uefi_map_key], 0x1234
    jne .fail_1

    ; Refresh reuses the allocation and performs no AllocatePool call.
    lea rcx, [rel system_table]
    call uefi_memory_map_refresh
    test rax, rax
    jnz .fail_2
    cmp dword [rel allocate_calls], 1
    jne .fail_2
    cmp dword [rel fill_calls], 2
    jne .fail_2

    lea rcx, [rel system_table]
    call uefi_memory_map_release
    test rax, rax
    jnz .fail_3
    cmp dword [rel free_calls], 1
    jne .fail_3
    cmp qword [rel uefi_mem_map_buf], 0
    jne .fail_3
    cmp qword [rel uefi_mem_map_capacity], 0
    jne .fail_3

    ; If allocation itself grows the map past the slack, acquire frees it,
    ; re-probes, and succeeds on a bounded second attempt.
    mov dword [rel map_mode], MODE_GROW
    call reset_mock_counts
    lea rcx, [rel system_table]
    call uefi_memory_map_acquire
    test rax, rax
    jnz .fail_4
    lea rax, [rel map_buffer_b]
    cmp [rel uefi_mem_map_buf], rax
    jne .fail_4
    cmp qword [rel uefi_mem_map_capacity], 12288
    jne .fail_4
    cmp qword [rel uefi_map_size], GROWN_BYTES
    jne .fail_4
    cmp dword [rel probe_calls], 2
    jne .fail_4
    cmp dword [rel allocate_calls], 2
    jne .fail_4
    cmp dword [rel fill_calls], 2
    jne .fail_4
    cmp dword [rel free_calls], 1
    jne .fail_4

    lea rcx, [rel system_table]
    call uefi_memory_map_release
    test rax, rax
    jnz .fail_4
    cmp dword [rel free_calls], 2
    jne .fail_4

    ; A hostile firmware size cannot escape the 1 MiB loader policy.
    mov dword [rel map_mode], MODE_OVERSIZE
    call reset_mock_counts
    lea rcx, [rel system_table]
    call uefi_memory_map_acquire
    mov r10, EFI_COMPROMISED_DATA
    cmp rax, r10
    jne .fail_5
    cmp dword [rel allocate_calls], 0
    jne .fail_5
    cmp qword [rel uefi_mem_map_buf], 0
    jne .fail_5

    cmp dword [rel callback_bad], 0
    jne .fail_6
    xor edi, edi
    jmp .exit
.fail_1:
    mov edi, 1
    jmp .exit
.fail_2:
    mov edi, 2
    jmp .exit
.fail_3:
    mov edi, 3
    jmp .exit
.fail_4:
    mov edi, 4
    jmp .exit
.fail_5:
    mov edi, 5
    jmp .exit
.fail_6:
    mov edi, 6
.exit:
    mov eax, 60
    syscall

reset_mock_counts:
    mov dword [rel probe_calls], 0
    mov dword [rel fill_calls], 0
    mov dword [rel allocate_calls], 0
    mov dword [rel free_calls], 0
    mov dword [rel callback_bad], 0
    ret

; EFI_STATUS GetMemoryMap(Size, Buffer, Key, DescriptorSize, Version).
fake_get_memory_map:
    mov r10, [rsp + 40]
    test r10, r10
    jz .bad
    mov qword [r9], 48
    mov dword [r10], EFI_MEMORY_DESCRIPTOR_VERSION
    mov qword [r8], 0x1234

    test rdx, rdx
    jnz .fill
    inc dword [rel probe_calls]
    mov eax, [rel map_mode]
    cmp eax, MODE_OVERSIZE
    je .probe_oversize
    cmp eax, MODE_GROW
    jne .probe_simple
    cmp dword [rel probe_calls], 1
    je .probe_simple
    mov qword [rcx], GROWN_BYTES
    jmp .too_small
.probe_simple:
    mov qword [rcx], SIMPLE_BYTES
    jmp .too_small
.probe_oversize:
    mov qword [rcx], UEFI_MEMORY_MAP_MAX_BYTES
.too_small:
    mov rax, EFI_BUFFER_TOO_SMALL
    ret

.fill:
    inc dword [rel fill_calls]
    mov eax, [rel map_mode]
    cmp eax, MODE_GROW
    jne .fill_simple
    cmp dword [rel fill_calls], 1
    jne .fill_grown
    mov qword [rcx], GROWN_BYTES
    mov rax, EFI_BUFFER_TOO_SMALL
    ret
.fill_grown:
    cmp qword [rcx], GROWN_BYTES
    jb .bad
    mov qword [rcx], GROWN_BYTES
    xor eax, eax
    ret
.fill_simple:
    cmp qword [rcx], SIMPLE_BYTES
    jb .bad
    mov qword [rcx], SIMPLE_BYTES
    xor eax, eax
    ret
.bad:
    mov dword [rel callback_bad], 1
    mov rax, EFI_INVALID_PARAMETER
    ret

; EFI_STATUS AllocatePool(Type, Size, BufferOut).
fake_allocate_pool:
    cmp ecx, EFI_LOADER_DATA
    jne .bad
    mov [rel last_allocate_size], rdx
    mov eax, [rel allocate_calls]
    inc dword [rel allocate_calls]
    test eax, eax
    jnz .use_b
    lea rax, [rel map_buffer_a]
    jmp .publish
.use_b:
    lea rax, [rel map_buffer_b]
.publish:
    mov [r8], rax
    xor eax, eax
    ret
.bad:
    mov dword [rel callback_bad], 1
    mov rax, EFI_INVALID_PARAMETER
    ret

fake_free_pool:
    lea rax, [rel map_buffer_a]
    cmp rcx, rax
    je .valid
    lea rax, [rel map_buffer_b]
    cmp rcx, rax
    jne .bad
.valid:
    inc dword [rel free_calls]
    xor eax, eax
    ret
.bad:
    mov dword [rel callback_bad], 1
    mov rax, EFI_INVALID_PARAMETER
    ret

section .data
map_mode:          dd 0
probe_calls:       dd 0
fill_calls:        dd 0
allocate_calls:    dd 0
free_calls:        dd 0
callback_bad:      dd 0
last_allocate_size:dq 0

section .bss align=16
system_table:  resb 128
boot_services: resb 384
map_buffer_a:  resb 16384
map_buffer_b:  resb 16384
