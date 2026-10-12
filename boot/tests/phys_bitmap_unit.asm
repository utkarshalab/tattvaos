; Native userspace harness for lib/mem/phys/bitmap.asm.
; Covers qword boundaries, final-PFN bounds, ownership, and local bitmaps.

[BITS 64]
default rel

%include "lib/mem/mem.inc"
%include "lib/mem/phys/bitmap.asm"

BITMAP_BYTES equ 24                 ; ceil(130 / 64) * 8
GUARD_VALUE  equ 0xA55AA55ADEADBEEF

section .text
global _start
_start:
    lea rax, [rel global_bitmap]
    mov [phys_state + phys_state_t.bitmap_addr], rax
    mov qword [phys_state + phys_state_t.bitmap_size], BITMAP_BYTES
    mov qword [phys_state + phys_state_t.frame_count], 130
    lea rax, [rel ownership_bitmap]
    mov [phys_state + phys_state_t.alloc_bitmap_addr], rax

    ; Global occupancy operations must not alias PFNs 63 and 64.
    mov rdi, 63
    call bitmap_set_bit
    mov rdi, 64
    call bitmap_set_bit
    mov rdx, 0x8000000000000000
    cmp qword [global_bitmap], rdx
    jne .fail_1
    cmp qword [global_bitmap + 8], 1
    jne .fail_1
    mov rdi, 63
    call bitmap_clear_bit
    mov rdi, 64
    call bitmap_test_bit
    cmp rax, 1
    jne .fail_1

    ; The ownership bitmap has the same independent qword geometry.
    mov rdi, 64
    call alloc_bitmap_set_bit
    mov rdi, 64
    call alloc_bitmap_test_bit
    cmp rax, 1
    jne .fail_2
    mov rdi, 64
    call alloc_bitmap_clear_bit
    mov rdi, 64
    call alloc_bitmap_test_bit
    test rax, rax
    jnz .fail_2

    ; A four-page free run may cross the qword boundary at 63/64.
    mov qword [global_bitmap], -1
    mov qword [global_bitmap + 8], -1
    mov qword [global_bitmap + 16], -1
    mov rdi, 62
    call bitmap_clear_bit
    mov rdi, 63
    call bitmap_clear_bit
    mov rdi, 64
    call bitmap_clear_bit
    mov rdi, 65
    call bitmap_clear_bit
    mov rdi, 4
    call bitmap_find_free
    cmp rax, 62
    jne .fail_3

    ; PFN 129 is valid; a two-page request starting there must not pass 130.
    mov qword [global_bitmap], -1
    mov qword [global_bitmap + 8], -1
    mov qword [global_bitmap + 16], -1
    mov rdi, 129
    call bitmap_clear_bit
    mov rdi, 129
    call bitmap_test_bit
    test rax, rax
    jnz .fail_4
    mov rdi, 2
    call bitmap_find_free
    cmp rax, -1
    jne .fail_4

    ; Node-local helpers must obey the same 63/64 boundary and final bound.
    lea rax, [rel local_bitmap]
    mov [test_node + numa_node_t.bitmap_addr], rax
    mov qword [test_node + numa_node_t.bitmap_size], BITMAP_BYTES
    mov qword [test_node + numa_node_t.start_page], 0
    mov qword [test_node + numa_node_t.end_page], 130
    mov rdi, test_node
    mov rsi, 63
    call bitmap_set_bit_local
    mov rdi, test_node
    mov rsi, 64
    call bitmap_set_bit_local
    mov rdx, 0x8000000000000000
    cmp qword [local_bitmap], rdx
    jne .fail_5
    cmp qword [local_bitmap + 8], 1
    jne .fail_5

    mov qword [local_bitmap], -1
    mov qword [local_bitmap + 8], -1
    mov qword [local_bitmap + 16], -1
    mov rdi, test_node
    mov rsi, 129
    call bitmap_clear_bit_local
    mov rdi, test_node
    mov rsi, 2
    call bitmap_find_free_local
    cmp rax, -1
    jne .fail_5

    ; No helper may write into the guard qwords after either bitmap.
    mov rdx, GUARD_VALUE
    cmp qword [global_guard], rdx
    jne .fail_6
    cmp qword [ownership_guard], rdx
    jne .fail_6
    cmp qword [local_guard], rdx
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

section .data
align 8
global_bitmap:    times BITMAP_BYTES db 0
global_guard:     dq GUARD_VALUE
ownership_bitmap: times BITMAP_BYTES db 0
ownership_guard:  dq GUARD_VALUE
local_bitmap:     times BITMAP_BYTES db 0
local_guard:      dq GUARD_VALUE
phys_state:       times phys_state_t_size db 0
test_node:        times numa_node_t_size db 0
