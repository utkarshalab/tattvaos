; UTM Collector - Ring Buffer
; Pure Assembly Implementation

%ifndef _UTM_RING_BUFFER_ASM_
%define _UTM_ENTERPRISE_RING_BUFFER_ASM_

%include "constants.inc"
%include "structures.inc"
%include "syscalls.inc"

section .text

global utm_ring_create
global utm_ring_init
global utm_ring_push
global utm_ring_pop
global utm_ring_peek
global utm_ring_read_at
global utm_ring_get_count
global utm_ring_get_capacity
global utm_ring_get_overruns
global utm_ring_clear
global utm_ring_iterate

utm_ring_init:
utm_ring_create:
    mov rax, RING_MAGIC
    mov [rdi + RingBufferHeader.magic], rax
    mov dword [rdi + RingBufferHeader.version], 1
    mov [rdi + RingBufferHeader.record_size], esi
    mov [rdi + RingBufferHeader.capacity], rdx
    mov qword [rdi + RingBufferHeader.head], 0
    mov qword [rdi + RingBufferHeader.tail], 0
    mov qword [rdi + RingBufferHeader.count], 0
    mov qword [rdi + RingBufferHeader.overruns], 0
    mov qword [rdi + RingBufferHeader.flags], 0
    ret

utm_ring_push:
    mov rax, [rdi + RingBufferHeader.head]
    mov rcx, [rdi + RingBufferHeader.capacity]
    mov r8, [rdi + RingBufferHeader.record_size]
    
    mov r9, [rdi + RingBufferHeader.count]
    cmp r9, rcx
    jae .full
    
    mul r8
    add rax, rdi
    add rax, RING_HEADER_SIZE
    mov r10, rax
    
    mov rcx, r8
    shr rcx, 3
    rep movsq
    mov rcx, r8
    and rcx, 7
    rep movsb
    
    lock inc qword [rdi + RingBufferHeader.head]
    lock inc qword [rdi + RingBufferHeader.count]
    
    mov rax, [rdi + RingBufferHeader.head]
    cmp rax, [rdi + RingBufferHeader.capacity]
    jne .done
    mov qword [rdi + RingBufferHeader.head], 0
    
.done:
    xor rax, rax
    ret

.full:
    lock inc qword [rdi + RingBufferHeader.overruns]
    mov rax, -1
    ret

utm_ring_pop:
    mov rax, [rdi + RingBufferHeader.tail]
    mov rcx, [rdi + RingBufferHeader.count]
    test rcx, rcx
    jz .empty
    
    mov r8, [rdi + RingBufferHeader.record_size]
    mul r8
    add rax, rdi
    add rax, RING_HEADER_SIZE
    mov r9, rax
    
    mov rcx, r8
    shr rcx, 3
    rep movsq
    mov rcx, r8
    and rcx, 7
    rep movsb
    
    lock inc qword [rdi + RingBufferHeader.tail]
    lock dec qword [rdi + RingBufferHeader.count]
    
    mov rax, [rdi + RingBufferHeader.tail]
    cmp rax, [rdi + RingBufferHeader.capacity]
    jne .done
    mov qword [rdi + RingBufferHeader.tail], 0
    
.done:
    xor rax, rax
    ret

.empty:
    mov rax, -1
    ret

utm_ring_peek:
    mov rax, [rdi + RingBufferHeader.tail]
    mov rcx, [rdi + RingBufferHeader.count]
    test rcx, rcx
    jz .empty2
    
    mov r8, [rdi + RingBufferHeader.record_size]
    mul r8
    add rax, rdi
    add rax, RING_HEADER_SIZE
    mov r9, rax
    
    mov rcx, r8
    shr rcx, 3
    rep movsq
    mov rcx, r8
    and rcx, 7
    rep movsb
    
    xor rax, rax
    ret

.empty2:
    mov rax, -1
    ret

utm_ring_read_at:
    mov rax, [rdi + RingBufferHeader.count]
    cmp rsi, rax
    jae .invalid
    
    mov rax, [rdi + RingBufferHeader.tail]
    add rax, rsi
    cmp rax, [rdi + RingBufferHeader.capacity]
    jb .no_wrap
    sub rax, [rdi + RingBufferHeader.capacity]
.no_wrap:
    
    mov r8, [rdi + RingBufferHeader.record_size]
    mul r8
    add rax, rdi
    add rax, RING_HEADER_SIZE
    mov r9, rax
    
    mov rcx, r8
    shr rcx, 3
    rep movsq
    mov rcx, r8
    and rcx, 7
    rep movsb
    
    xor rax, rax
    ret

.invalid:
    mov rax, -1
    ret

utm_ring_get_count:
    mov rax, [rdi + RingBufferHeader.count]
    ret

utm_ring_get_capacity:
    mov rax, [rdi + RingBufferHeader.capacity]
    ret

utm_ring_get_overruns:
    mov rax, [rdi + RingBufferHeader.overruns]
    ret

utm_ring_clear:
    mov qword [rdi + RingBufferHeader.head], 0
    mov qword [rdi + RingBufferHeader.tail], 0
    mov qword [rdi + RingBufferHeader.count], 0
    mov qword [rdi + RingBufferHeader.overruns], 0
    ret

utm_ring_iterate:
    mov rcx, [rdi + RingBufferHeader.count]
    test rcx, rcx
    jz .done
    
    mov r8, [rdi + RingBufferHeader.record_size]
    mov r9, [rdi + RingBufferHeader.tail]
    add r9, rcx
    dec r9
    cmp r9, [rdi + RingBufferHeader.capacity]
    jb .no_wrap_iter
    sub r9, [rdi + RingBufferHeader.capacity]
.no_wrap_iter:
    
.iter_loop:
    push rcx
    push r9
    
    mov rax, r9
    mul r8
    add rax, rdi
    add rax, RING_HEADER_SIZE
    mov rdi, rax
    
    call rsi
    
    pop r9
    pop rcx
    
    test rax, rax
    jnz .done
    
    test r9, r9
    jnz .prev
    mov r9, [rdi + RingBufferHeader.capacity]
.prev:
    dec r9
    
    loop .iter_loop
    
.done:
    ret

%endif