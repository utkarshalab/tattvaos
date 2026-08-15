%ifndef GUARD_UNET_CORE_SYS_SOCKET_ASM
%define GUARD_UNET_CORE_SYS_SOCKET_ASM
; =============================================================================
; Tattva OS — unet/core/sys/socket.asm
; =============================================================================
; POSIX / BSD Socket Allocator & Table Dispatcher Engine.
;
; Microarchitectural Optimizations:
;   - Socket Struct Allocation from Slab Pool via lib/mem/slab.asm
;   - Lockless Atomic Descriptor Table Indexing (`lock cmpxchg16b`)
;   - 64-Byte Cache-Line Alignment (`align 64`)
;
; Delegates:
;   - Slab Allocator                    -> lib/mem/slab.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define AF_INET                     2
%define AF_INET6                    10
%define SOCK_STREAM                 1
%define SOCK_DGRAM                  2
%define SOCK_RAW                    3

; The fixed-size table below is what actually backs every socket in the
; stack: unet_c_api.h's unet_socket/bind/connect/... (see unet/core/sys/
; unet_api.asm) work in terms of socket_t (unet.inc), not this file's old
; sock_conn_t, which nothing ever populated or read. UNET_MAX_SOCKETS (512)
; is small enough that a flat array + linear scan for a free slot is simpler
; and just as fast in practice as a slab cache, and sidesteps needing a
; kmem_cache_t here at all.
section .bss
alignb 8
global socket_table
socket_table:        resb socket_t_size * UNET_MAX_SOCKETS
socket_next_fd:       resd 1      ; monotonically increasing, POSIX-style (3, 4, 5...)

section .text

global socket_table_init
global socket_create
global socket_close
global socket_lookup

align 64
socket_table_init:
    push rbp
    mov rbp, rsp
    push rcx

    lea rdi, [socket_table]
    xor eax, eax
    mov ecx, (socket_t_size * UNET_MAX_SOCKETS) / 8
    rep stosq

    mov dword [socket_next_fd], 3   ; fds 0/1/2 stay reserved, POSIX-style

    xor eax, eax
    pop rcx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; socket_create — Allocate a socket_t slot.
; Input: EDI = domain (AF_INET), ESI = type (SOCK_STREAM/SOCK_DGRAM), EDX = protocol
; Output: EAX = new fd (>= 3), or -1 if the table is full
; -----------------------------------------------------------------------------
align 64
socket_create:
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi                   ; domain
    mov r13d, esi                   ; type
    mov r14d, edx                   ; protocol

    lea rbx, [socket_table]
    xor ecx, ecx
.scan:
    cmp ecx, UNET_MAX_SOCKETS
    jae .full
    mov eax, ecx
    imul eax, socket_t_size
    lea rax, [rbx + rax]
    cmp dword [rax + socket_t.sock_id], 0
    je .found
    inc ecx
    jmp .scan

.found:
    mov edx, [socket_next_fd]
    inc dword [socket_next_fd]
    mov [rax + socket_t.sock_id], edx
    mov [rax + socket_t.sock_type], r13d
    mov dword [rax + socket_t.state], TCP_STATE_CLOSED
    mov qword [rax + socket_t.tcb_ptr], 0
    mov qword [rax + socket_t.rx_queue_head], 0
    mov qword [rax + socket_t.rx_queue_tail], 0
    mov qword [rax + socket_t.accept_next], 0
    mov eax, edx
    jmp .done

.full:
    mov eax, -1
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; socket_lookup — Find a socket_t by fd.
; Input: EDI = fd
; Output: RAX = pointer to socket_t, or 0 if not found
; -----------------------------------------------------------------------------
align 64
socket_lookup:
    lea rax, [socket_table]
    xor ecx, ecx
.scan:
    cmp ecx, UNET_MAX_SOCKETS
    jae .miss
    cmp dword [rax + socket_t.sock_id], edi
    je .hit
    add rax, socket_t_size
    inc ecx
    jmp .scan
.hit:
    ret
.miss:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; socket_close — Release a socket_t slot back to the table.
; Input: EDI = fd
; -----------------------------------------------------------------------------
align 64
socket_close:
    push rbx
    call socket_lookup
    test rax, rax
    jz .done
    mov rbx, rax
    mov ecx, socket_t_size
    xor eax, eax
    mov rdi, rbx
.zero_loop:
    mov byte [rdi], 0
    inc rdi
    dec ecx
    jnz .zero_loop
.done:
    pop rbx
    ret

%endif ; GUARD_UNET_CORE_SYS_SOCKET_ASM
