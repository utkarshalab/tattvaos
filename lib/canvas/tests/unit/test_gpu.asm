; ============================================================================
; Unit Test — GFX9 PM4 Packets and the Command Ring
;             (src/gpu/family/gfx9.asm, src/gpu/gpu_ring.asm)
; ============================================================================
; test_gpu_suite -> eax = failed cases (each case returns 0 / 1).
; A 16-dword ring in .bss stands in for the DMA buffer; each case resets it.
; Headers: type 3 in bits 31:30, count = payload - 1, the opcode. Copy and
; fill: DMA_DATA dwords, the split at 2 MiB. Fence: RELEASE_MEM written
; across the ring's end, an unaligned address refused. Ring: a write larger
; than the ring refused.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/gpu_ring.inc"

extern gfx9_packet3
extern gfx9_emit_fill
extern gfx9_emit_copy
extern gfx9_emit_fence
extern gpu_ring_write

%define RING_DW 16

section .text

global test_gpu_suite
global test_gpu_main
test_gpu_suite:
test_gpu_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call reset
    call %1
    add ebx, eax
%endmacro
    CASE tg_header
    CASE tg_copy
    CASE tg_fill_split
    CASE tg_fence_wrap
    CASE tg_fence_unaligned
    CASE tg_ring_full
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro
; ring dword %1 equal to %2 -> jump .fail if not
%macro DW_IS 2
    cmp dword [rel ring_buf + (%1) * 4], %2
    jne .fail
%endmacro
%macro WPTR_IS 1
    cmp dword [rel ring + GpuRing.wptr], %1
    jne .fail
%endmacro

; an empty ring over ring_buf, its dwords poisoned
reset:
    lea rdi, [rel ring_buf]
    mov eax, 0xDEADDEAD
    mov ecx, RING_DW
    rep stosd
    lea rax, [rel ring_buf]
    mov [rel ring + GpuRing.buf_cpu], rax
    mov dword [rel ring + GpuRing.size_dw], RING_DW
    mov dword [rel ring + GpuRing.wptr], 0
    ret

tg_header:
    sub rsp, 8
    lea rdi, [rel ring_buf]
    mov esi, 0x10                       ; NOP, one payload dword
    mov edx, 1
    call gfx9_packet3
    cmp eax, 0xC0001000
    jne .fail
    DW_IS 0, 0xC0001000
    lea rdi, [rel ring_buf]
    mov esi, 0x50                       ; DMA_DATA, six
    mov edx, 6
    call gfx9_packet3
    DW_IS 0, 0xC0055000
    PASS

tg_copy:
    sub rsp, 8
    lea rdi, [rel ring]
    mov rsi, 0x123456780                ; destination
    mov rdx, 0xABCDEF0000               ; source
    mov ecx, 0x1000
    call gfx9_emit_copy
    test rax, rax
    jnz .fail
    DW_IS 0, 0xC0055000
    DW_IS 1, 0x80000000                 ; CP_SYNC, source and destination addresses
    DW_IS 2, 0xCDEF0000
    DW_IS 3, 0xAB
    DW_IS 4, 0x23456780
    DW_IS 5, 1
    DW_IS 6, 0x1000
    DW_IS 7, 0xDEADDEAD
    WPTR_IS 7
    PASS

tg_fill_split:
    sub rsp, 8
    lea rdi, [rel ring]
    mov esi, 0x10000000                 ; destination
    mov edx, 0x11223344
    mov ecx, (1 << 21) / 4 + 1          ; 2 MiB and one dword: two packets
    call gfx9_emit_fill
    test rax, rax
    jnz .fail
    DW_IS 0, 0xC0055000
    DW_IS 1, 0xC0000000                 ; CP_SYNC, the source is data
    DW_IS 2, 0x11223344
    DW_IS 3, 0
    DW_IS 4, 0x10000000
    DW_IS 5, 0
    DW_IS 6, 1 << 21
    DW_IS 7, 0xC0055000
    DW_IS 9, 0x11223344
    DW_IS 11, 0x10200000                ; moved on by the first piece
    DW_IS 13, 4
    WPTR_IS 14
    PASS

tg_fence_wrap:
    sub rsp, 8
    mov dword [rel ring + GpuRing.wptr], 12
    lea rdi, [rel ring]
    mov rsi, 0x200001000
    mov rdx, 0x500000007
    call gfx9_emit_fence
    test rax, rax
    jnz .fail
    DW_IS 12, 0xC0064900                ; RELEASE_MEM, seven
    DW_IS 13, 0x514                     ; cache flush + invalidate, end of pipe
    DW_IS 14, 0x40000000                ; 64-bit data to memory
    DW_IS 15, 0x1000
    DW_IS 0, 2                          ; wrapped to the start
    DW_IS 1, 7
    DW_IS 2, 5
    DW_IS 3, 0
    DW_IS 4, 0xDEADDEAD
    WPTR_IS 4
    PASS

tg_fence_unaligned:
    sub rsp, 8
    lea rdi, [rel ring]
    mov esi, 0x1004
    mov edx, 1
    call gfx9_emit_fence
    cmp rax, -(EINVAL)
    jne .fail
    WPTR_IS 0
    DW_IS 0, 0xDEADDEAD
    PASS

tg_ring_full:
    sub rsp, 8
    lea rdi, [rel ring]
    lea rsi, [rel ring_buf]
    mov edx, RING_DW + 1
    call gpu_ring_write
    cmp rax, -(ENOSPC)
    jne .fail
    WPTR_IS 0
    PASS

section .bss
alignb 16
ring:       resb GpuRing_size
alignb 16
ring_buf:   resd RING_DW
