; Native hostile-input harness for lib/mem/numa/numa_detect.asm.
; Exit status 0 means every ACPI/NUMA fallback contract passed.

[BITS 64]
default rel

%include "boot/boot_info.inc"
%include "lib/mem/mem.inc"

NUMA_MAX_RANGES equ 32
NUMA_MAX_NODES equ 8
NUMA_DEFAULT_LOCAL_DISTANCE equ 10
NUMA_DEFAULT_REMOTE_DISTANCE equ 20

%include "lib/mem/numa/numa_detect.asm"

RSDP_BYTES equ 36
XSDT_BYTES equ 52
SRAT_ONE_BYTES equ 88
SRAT_TWO_BYTES equ 128
SLIT_ONE_BYTES equ 45

section .text
global _start
_start:
    ; An address beyond the guaranteed direct map must never be dereferenced.
    call reset_valid
    mov rax, 0x0000400000000000
    mov [rel boot_info + BOOT_INFO_ACPI_RSDP_OFF], rax
    call numa_detect_init
    call expect_uma_fallback
    jc .fail_1

    ; The legacy RSDP checksum is mandatory even for ACPI 2.0+ firmware.
    call reset_valid
    xor byte [rel rsdp_table + 10], 1
    call numa_detect_init
    call expect_uma_fallback
    jc .fail_2

    ; Child SDTs are ignored unless their complete declared span checksums.
    call reset_valid
    xor byte [rel srat_table + 20], 1
    call numa_detect_init
    call expect_uma_fallback
    jc .fail_3

    ; A root table shorter than the standard ACPI header is unusable.
    call reset_valid
    mov dword [rel xsdt_table + 4], 35
    lea rdi, [rel xsdt_table]
    mov ecx, 35
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_uma_fallback
    jc .fail_4

    ; Overlapping enabled memory affinities cannot both own the same PFN.
    call reset_valid
    mov dword [rel srat_table + 4], SRAT_TWO_BYTES
    mov byte [rel srat_table + 88], 1
    mov byte [rel srat_table + 89], 40
    mov qword [rel srat_table + 96], 0x4000
    mov qword [rel srat_table + 104], 0x1000
    mov dword [rel srat_table + 116], 1
    lea rdi, [rel srat_table]
    mov ecx, SRAT_TWO_BYTES
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_uma_fallback
    jc .fail_5

    ; A syntactically valid SRAT must cover every PMM-managed page.
    call reset_valid
    mov qword [rel srat_table + 64], 0x4000
    lea rdi, [rel srat_table]
    mov ecx, SRAT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_uma_fallback
    jc .fail_6

    ; A proximity domain must fit the fixed node and distance arrays.
    call reset_valid
    mov dword [rel srat_table + 50], NUMA_MAX_NODES
    lea rdi, [rel srat_table]
    mov ecx, SRAT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_uma_fallback
    jc .fail_7

    ; A two-locality SLIT needs four matrix bytes, not the one declared here.
    call reset_valid
    mov qword [rel slit_table + 36], 2
    lea rdi, [rel slit_table]
    mov ecx, SLIT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_srat_default_distances
    jc .fail_8

    ; Locality-count squaring must reject 64-bit overflow before matrix access.
    call reset_valid
    mov rax, 0x100000000
    mov [rel slit_table + 36], rax
    lea rdi, [rel slit_table]
    mov ecx, SLIT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_srat_default_distances
    jc .fail_9

    ; Revision is an unsigned byte; future values still require the extended
    ; RSDP checksum and may use the valid XSDT.
    call reset_valid
    mov byte [rel rsdp_table + 15], 0x80
    lea rdi, [rel rsdp_table]
    mov ecx, 20
    mov edx, 8
    call fix_checksum
    lea rdi, [rel rsdp_table]
    mov ecx, RSDP_BYTES
    mov edx, 32
    call fix_checksum
    call numa_detect_init
    call expect_srat_slit
    jc .fail_10

    ; ACPI reserves distance values below 10.
    call reset_valid
    mov byte [rel slit_table + 44], 9
    lea rdi, [rel slit_table]
    mov ecx, SLIT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_srat_default_distances
    jc .fail_11

    ; Every SLIT diagonal must be the local distance 10.
    call reset_valid
    mov byte [rel slit_table + 44], 20
    lea rdi, [rel slit_table]
    mov ecx, SLIT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    call numa_detect_init
    call expect_srat_default_distances
    jc .fail_12

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
    jmp .exit
.fail_7:
    mov edi, 7
    jmp .exit
.fail_8:
    mov edi, 8
    jmp .exit
.fail_9:
    mov edi, 9
    jmp .exit
.fail_10:
    mov edi, 10
    jmp .exit
.fail_11:
    mov edi, 11
    jmp .exit
.fail_12:
    mov edi, 12

.exit:
    mov eax, 60
    syscall

; Restore one valid node-0 SRAT and one valid 1x1 SLIT behind an XSDT.
reset_valid:
    cld
    lea rdi, [rel test_arena]
    mov rcx, test_arena_end - test_arena
    xor eax, eax
    rep stosb
    lea rdi, [rel numa_ranges]
    mov rcx, NUMA_MAX_RANGES * numa_range_t_size
    rep stosb
    lea rdi, [rel numa_distance_matrix]
    mov rcx, NUMA_MAX_NODES * NUMA_MAX_NODES
    rep stosb
    mov qword [rel numa_range_count], 0
    mov qword [rel numa_node_count], 0
    mov qword [rel numa_srat_phys_addr], 0
    mov qword [rel numa_slit_phys_addr], 0
    mov qword [rel numa_hmat_phys_addr], 0

    lea rax, [rel rsdp_table]
    mov [rel boot_info + BOOT_INFO_ACPI_RSDP_OFF], rax
    mov qword [rel phys_state + phys_state_t.max_phys_addr], 0x8000
    mov qword [rel phys_state + phys_state_t.total_pages], 8
    lea rax, [rel test_arena_end]
    mov [rel phys_state + phys_state_t.direct_map_limit], rax

    mov rax, 0x2052545020445352
    mov [rel rsdp_table], rax
    mov byte [rel rsdp_table + 15], 2
    mov dword [rel rsdp_table + 20], RSDP_BYTES
    lea rax, [rel xsdt_table]
    mov [rel rsdp_table + 24], rax

    mov dword [rel xsdt_table], 0x54445358
    mov dword [rel xsdt_table + 4], XSDT_BYTES
    lea rax, [rel srat_table]
    mov [rel xsdt_table + 36], rax
    lea rax, [rel slit_table]
    mov [rel xsdt_table + 44], rax

    mov dword [rel srat_table], 0x54415253
    mov dword [rel srat_table + 4], SRAT_ONE_BYTES
    mov byte [rel srat_table + 48], 1
    mov byte [rel srat_table + 49], 40
    mov qword [rel srat_table + 56], 0
    mov qword [rel srat_table + 64], 0x8000
    mov dword [rel srat_table + 76], 1

    mov dword [rel slit_table], 0x54494C53
    mov dword [rel slit_table + 4], SLIT_ONE_BYTES
    mov qword [rel slit_table + 36], 1
    mov byte [rel slit_table + 44], NUMA_DEFAULT_LOCAL_DISTANCE

    lea rdi, [rel srat_table]
    mov ecx, SRAT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    lea rdi, [rel slit_table]
    mov ecx, SLIT_ONE_BYTES
    mov edx, 9
    call fix_checksum
    lea rdi, [rel xsdt_table]
    mov ecx, XSDT_BYTES
    mov edx, 9
    call fix_checksum
    lea rdi, [rel rsdp_table]
    mov ecx, 20
    mov edx, 8
    call fix_checksum
    lea rdi, [rel rsdp_table]
    mov ecx, RSDP_BYTES
    mov edx, 32
    call fix_checksum
    ret

; RDI=table, RCX=declared bytes, RDX=checksum-byte offset.
fix_checksum:
    push rbx
    mov byte [rdi + rdx], 0
    xor eax, eax
    xor ebx, ebx
.sum:
    add bl, [rdi + rax]
    inc rax
    cmp rax, rcx
    jb .sum
    neg bl
    mov [rdi + rdx], bl
    pop rbx
    ret

expect_uma_fallback:
    cmp qword [rel numa_range_count], 1
    jne .bad
    cmp qword [rel numa_node_count], 1
    jne .bad
    cmp qword [rel numa_srat_phys_addr], 0
    jne .bad
    cmp qword [rel numa_slit_phys_addr], 0
    jne .bad
    cmp qword [rel numa_ranges + numa_range_t.base], 0
    jne .bad
    cmp qword [rel numa_ranges + numa_range_t.length], 0x8000
    jne .bad
    cmp dword [rel numa_ranges + numa_range_t.node_id], 0
    jne .bad
    cmp dword [rel numa_ranges + numa_range_t.flags], 1
    jne .bad
    cmp byte [rel numa_distance_matrix], NUMA_DEFAULT_LOCAL_DISTANCE
    jne .bad
    clc
    ret
.bad:
    stc
    ret

expect_srat_default_distances:
    cmp qword [rel numa_range_count], 1
    jne .bad
    cmp qword [rel numa_node_count], 1
    jne .bad
    lea rax, [rel srat_table]
    cmp [rel numa_srat_phys_addr], rax
    jne .bad
    cmp qword [rel numa_slit_phys_addr], 0
    jne .bad
    cmp qword [rel numa_ranges + numa_range_t.length], 0x8000
    jne .bad
    cmp byte [rel numa_distance_matrix], NUMA_DEFAULT_LOCAL_DISTANCE
    jne .bad
    clc
    ret
.bad:
    stc
    ret

expect_srat_slit:
    cmp qword [rel numa_range_count], 1
    jne .bad
    cmp qword [rel numa_node_count], 1
    jne .bad
    lea rax, [rel srat_table]
    cmp [rel numa_srat_phys_addr], rax
    jne .bad
    lea rax, [rel slit_table]
    cmp [rel numa_slit_phys_addr], rax
    jne .bad
    cmp byte [rel numa_distance_matrix], NUMA_DEFAULT_LOCAL_DISTANCE
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; The synthetic SRAT describes an entirely usable eight-page PMM span.
numa_count_usable_pages:
    mov rax, rsi
    sub rax, rdi
    ret

uart_print_str:
    ret

section .data
align 8
boot_info_ptr: dq boot_info

section .bss
alignb 8
boot_info: resb 64
phys_state: resb phys_state_t_size
numa_ranges: resb NUMA_MAX_RANGES * numa_range_t_size
numa_range_count: resq 1
numa_node_count: resq 1
numa_distance_matrix: resb NUMA_MAX_NODES * NUMA_MAX_NODES

alignb 8
test_arena:
rsdp_table: resb RSDP_BYTES
alignb 8
xsdt_table: resb XSDT_BYTES
alignb 8
srat_table: resb SRAT_TWO_BYTES
alignb 8
slit_table: resb 64
test_arena_end:
