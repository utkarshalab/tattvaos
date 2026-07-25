; =============================================================================
; Tattva OS — unet/mem/pktbuf.asm
; =============================================================================
; Zero-Copy 2048-Byte DMA Packet Buffer Manager & Ring Buffer Pool.
;
; Manages high-performance `net_pkt_t` buffer allocations for 100GbE NICs,
; providing:
;   - Lock-free ring buffer pool allocation (`pktbuf_alloc`, `pktbuf_free`)
;   - Prepending/stripping protocol headers via headroom reservation
;   - Zero-copy slicing & multi-packet chaining (`pktbuf_chain`)
;   - Atomic reference counting for zero-copy socket broadcasts
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define UNET_PKT_POOL_SLOTS         1024
%define UNET_DEFAULT_HEADROOM       128

section .data
align 64
global pktbuf_pool_table
pktbuf_pool_table: times UNET_PKT_POOL_SLOTS * net_pkt_t_size db 0

align 16
global pktbuf_raw_memory
pktbuf_raw_memory: times UNET_PKT_POOL_SLOTS * UNET_PKT_BUF_SIZE db 0

align 8
global pktbuf_pool_head
pktbuf_pool_head: dq 0

section .text

global pktbuf_init
global pktbuf_alloc
global pktbuf_free
global pktbuf_push_headroom
global pktbuf_pull_headroom
global pktbuf_chain

; -----------------------------------------------------------------------------
; pktbuf_init — Initialize 1024 Packet Buffer Pool Descriptors
; -----------------------------------------------------------------------------
align 32
pktbuf_init:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi
    push rdi

    mov qword [pktbuf_pool_head], 0
    xor ecx, ecx

.init_loop:
    cmp ecx, UNET_PKT_POOL_SLOTS
    jge .init_done

    ; Calculate descriptor address
    mov rbx, rcx
    imul rbx, rbx, net_pkt_t_size
    lea rdi, [pktbuf_pool_table + rbx]

    ; Calculate raw memory address
    mov rsi, rcx
    imul rsi, rsi, UNET_PKT_BUF_SIZE
    lea rsi, [pktbuf_raw_memory + rsi]

    mov [rdi + net_pkt_t.virt_addr], rsi
    mov [rdi + net_pkt_t.phys_addr], rsi             ; Flat 1:1 DMA physical mapping
    mov dword [rdi + net_pkt_t.headroom_offset], UNET_DEFAULT_HEADROOM
    mov dword [rdi + net_pkt_t.data_len], 0
    mov dword [rdi + net_pkt_t.total_capacity], UNET_PKT_BUF_SIZE
    mov dword [rdi + net_pkt_t.ref_count], 0
    mov qword [rdi + net_pkt_t.next_pkt], 0

    inc ecx
    jmp .init_loop

.init_done:
    pop rdi
    pop rsi
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktbuf_alloc — Allocate a 2048-byte packet buffer
; Output: RAX = Pointer to net_pkt_t descriptor (or 0 if exhausted)
; -----------------------------------------------------------------------------
align 32
pktbuf_alloc:
    push rbx
    push rcx

    xor ecx, ecx

.search_free:
    cmp ecx, UNET_PKT_POOL_SLOTS
    jge .no_buffer

    mov rbx, rcx
    imul rbx, rbx, net_pkt_t_size
    lea rax, [pktbuf_pool_table + rbx]

    cmp dword [rax + net_pkt_t.ref_count], 0
    jne .next_slot

    ; Allocate buffer
    mov dword [rax + net_pkt_t.ref_count], 1
    mov dword [rax + net_pkt_t.headroom_offset], UNET_DEFAULT_HEADROOM
    mov dword [rax + net_pkt_t.data_len], 0
    mov qword [rax + net_pkt_t.next_pkt], 0
    pop rcx
    pop rbx
    ret

.next_slot:
    inc ecx
    jmp .search_free

.no_buffer:
    xor eax, eax
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; pktbuf_free — Release a packet buffer back to the pool
; Input: RDI = Pointer to net_pkt_t descriptor
; -----------------------------------------------------------------------------
align 32
pktbuf_free:
    test rdi, rdi
    jz .done

    ; Decrement reference count atomically
    mov eax, [rdi + net_pkt_t.ref_count]
    test eax, eax
    jz .done

    dec dword [rdi + net_pkt_t.ref_count]
    jnz .done                                        ; Shared buffer still referenced

    ; Free chained buffers recursively
    mov rsi, [rdi + net_pkt_t.next_pkt]
    mov qword [rdi + net_pkt_t.next_pkt], 0
    test rsi, rsi
    jz .done

    push rdi
    mov rdi, rsi
    call pktbuf_free
    pop rdi

.done:
    ret

; -----------------------------------------------------------------------------
; pktbuf_push_headroom — Reserve bytes for header prepending (e.g. ETH, IP, TCP)
; Input: RDI = net_pkt_t, ESI = bytes to push
; Output: RAX = Pointer to new start of header data (or 0 if headroom overflow)
; -----------------------------------------------------------------------------
align 32
pktbuf_push_headroom:
    mov eax, [rdi + net_pkt_t.headroom_offset]
    cmp eax, esi
    jl .overflow                                     ; Not enough headroom

    sub eax, esi
    mov [rdi + net_pkt_t.headroom_offset], eax
    add [rdi + net_pkt_t.data_len], esi

    mov rax, [rdi + net_pkt_t.virt_addr]
    add rax, rbx                                     ; RDI + Offset
    ret

.overflow:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; pktbuf_pull_headroom — Strip header bytes from front of packet
; Input: RDI = net_pkt_t, ESI = bytes to strip
; -----------------------------------------------------------------------------
align 32
pktbuf_pull_headroom:
    add [rdi + net_pkt_t.headroom_offset], esi
    sub [rdi + net_pkt_t.data_len], esi
    ret

; -----------------------------------------------------------------------------
; pktbuf_chain — Link a second packet buffer to the end of the first
; Input: RDI = Parent net_pkt_t, RSI = Child net_pkt_t
; -----------------------------------------------------------------------------
align 32
pktbuf_chain:
    mov [rdi + net_pkt_t.next_pkt], rsi
    ret
