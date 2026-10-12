; Native userspace harness for lib/mem/phys/map.asm.
; Exit status 0 means every checked parser contract passed.

[BITS 64]
default rel

%include "lib/mem/mem.inc"
%include "lib/mem/phys/map.asm"

section .text
global _start
_start:
    ; Sparse map: usable low RAM, a large reserved hole, then usable high RAM.
    lea rdi, [rel sparse_map]
    mov rsi, 3
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    call phys_parse_e820
    jc .fail_1
    cmp rax, 0x10000000
    jne .fail_1
    cmp rcx, 0xFF00
    jne .fail_1
    cmp r8, 0x10000
    jne .fail_1

    ; A high-only page is valid firmware input but has no managed portion yet.
    lea rdi, [rel high_only_map]
    mov rsi, 1
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    call phys_parse_e820
    jc .fail_2
    test rax, rax
    jnz .fail_2
    test rcx, rcx
    jnz .fail_2
    cmp r8, 1
    jne .fail_2

    ; Only complete pages wholly contained in an unaligned range are usable.
    lea rdi, [rel unaligned_map]
    mov rsi, 1
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    call phys_parse_e820
    jc .fail_3
    cmp rax, 0x4000
    jne .fail_3
    cmp rcx, 2
    jne .fail_3
    test r8, r8
    jnz .fail_3

    ; A two-page range straddling 4 GiB splits one managed/one offline page.
    lea rdi, [rel boundary_map]
    mov rsi, 1
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    call phys_parse_e820
    jc .fail_4
    mov rbx, PHYS_BOOTSTRAP_MAP_LIMIT
    cmp rax, rbx
    jne .fail_4
    cmp rcx, 1
    jne .fail_4
    cmp r8, 1
    jne .fail_4

    ; Wrapped base+length is malformed and must fail with cleared outputs.
    lea rdi, [rel overflow_map]
    mov rsi, 1
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    call phys_parse_e820
    jnc .fail_5
    test rax, rax
    jnz .fail_5
    test rcx, rcx
    jnz .fail_5
    test r8, r8
    jnz .fail_5

    ; Overflow is malformed even when the descriptor itself is not usable RAM.
    lea rdi, [rel reserved_overflow_map]
    mov rsi, 1
    mov rdx, PHYS_BOOTSTRAP_MAP_LIMIT
    call phys_parse_e820
    jnc .fail_6
    test rax, rax
    jnz .fail_6
    test rcx, rcx
    jnz .fail_6
    test r8, r8
    jnz .fail_6

    ; Raising the aperture publishes the supported high extent while keeping
    ; the reserved hole out of the managed page count.
    lea rdi, [rel sparse_map]
    mov rsi, 3
    mov rdx, PHYS_IDENTITY_VA_LIMIT
    call phys_parse_e820
    jc .fail_7
    mov rbx, 0x0000000110000000
    cmp rax, rbx
    jne .fail_7
    cmp rcx, 0x1FF00
    jne .fail_7
    test r8, r8
    jnz .fail_7

    ; Pages at/above the collision-free identity ceiling remain offline.
    lea rdi, [rel cap_crossing_map]
    mov rsi, 1
    mov rdx, PHYS_IDENTITY_VA_LIMIT
    call phys_parse_e820
    jc .fail_8
    mov rbx, PHYS_IDENTITY_VA_LIMIT
    cmp rax, rbx
    jne .fail_8
    cmp rcx, 1
    jne .fail_8
    cmp r8, 1
    jne .fail_8

    ; Canonical maps must be ascending and non-overlapping.
    lea rdi, [rel unsorted_map]
    mov rsi, 2
    mov rdx, PHYS_IDENTITY_VA_LIMIT
    call phys_parse_e820
    jnc .fail_9

    lea rdi, [rel overlap_map]
    mov rsi, 2
    mov rdx, PHYS_IDENTITY_VA_LIMIT
    call phys_parse_e820
    jnc .fail_10

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

.exit:
    mov eax, 60
    syscall

section .data
align 8
sparse_map:
    dq 0x0000000000100000, 0x000000000FF00000
    dd 1, 1
    dq 0x0000000010000000, 0x00000000F0000000
    dd 2, 1
    dq 0x0000000100000000, 0x0000000010000000
    dd 1, 1

high_only_map:
    dq 0x0000000100000000, 0x1000
    dd 1, 1

unaligned_map:
    dq 0x1003, 0x2FFE
    dd 1, 1

boundary_map:
    dq 0x00000000FFFFF000, 0x2000
    dd 1, 1

overflow_map:
    dq 0xFFFFFFFFFFFFFF00, 0x200
    dd 1, 1

reserved_overflow_map:
    dq 0xFFFFFFFFFFFFFF00, 0x200
    dd 2, 1

cap_crossing_map:
    dq PHYS_IDENTITY_VA_LIMIT - 0x1000, 0x2000
    dd 1, 1

unsorted_map:
    dq 0x4000, 0x1000
    dd 1, 1
    dq 0x2000, 0x1000
    dd 1, 1

overlap_map:
    dq 0x2000, 0x3000
    dd 2, 1
    dq 0x4000, 0x2000
    dd 1, 1
