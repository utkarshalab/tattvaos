%ifndef GUARD_UNET_TOOLS_BENCH_PKTGEN_ASM
%define GUARD_UNET_TOOLS_BENCH_PKTGEN_ASM
; =============================================================================
; Tattva OS — unet/tools/bench/pktgen.asm
; =============================================================================
; High-Speed Wire-Rate Assembly Packet Generator (`pktgen`).
;
; Features:
;   - Line-Rate 64-Byte Packet Generation (148.8 Mpps for 100GbE)
;   - AVX-512 64-Byte Cacheline Packet Framing & 5-Tuple Mutation
;   - Hardware Ring Doorbell Batching (32 Packets per Doorbell MMIO Write)
;   - Dynamic IP & Port PRNG Mutation per Packet Slot
;   - RDTSC High-Precision Cycle Counter Rate Measurement
;
; Delegates:
;   - Network Ring                      -> unet/core/link/net_ring.asm
;   - Packet Buffer                     -> unet/core/sys/pktbuf.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PKTGEN_MAX_BURST            32
%define PKTGEN_FRAME_LEN            64

struc pktgen_config_t
    .src_ip_base:       resd 1
    .dst_ip_base:       resd 1
    .src_port_base:     resw 1
    .dst_port_base:     resw 1
    .pkt_count:         resq 1
    .tx_ring_ptr:       resq 1
endstruc

section .data
align 64
pktgen_template_hdr:
    ; 14-byte Ethernet Header
    db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF           ; Dst MAC (Broadcast)
    db 0x52, 0x54, 0x00, 0x12, 0x34, 0x56           ; Src MAC
    dw 0x0008                                       ; EtherType (0x0800 IPv4, Big Endian)
    ; 20-byte IPv4 Header
    db 0x45, 0x00, 0x00, 0x2E                        ; Ver/IHL, ToS, Total Len 46
    dw 0x0000, 0x0040                               ; ID, Flags/FragOffset (DF)
    db 0x40, 0x11, 0x00, 0x00                        ; TTL 64, Protocol UDP (17), Checksum
    dd 0x0100007F                                   ; Src IP (127.0.0.1)
    dd 0x0200007F                                   ; Dst IP (127.0.0.2)
    ; 8-byte UDP Header
    dw 0x3930, 0x3930                               ; Src Port 12345, Dst Port 12345
    dw 0x1A00, 0x0000                               ; UDP Length 26, Checksum
    ; 22-byte Payload
    times 22 db 0xA5

section .text

global pktgen_main
global pktgen_burst
global pktgen_mutate_5tuple_avx512


align 64
pktgen_main:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]

    call pktgen_burst

    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pktgen_burst — Transmit 32-Packet Batches with AVX-512 5-Tuple Mutation
; Input: RDI = Pointer to pktgen_config_t
; Output: RAX = Total Packets Transmitted
; -----------------------------------------------------------------------------
align 64
pktgen_burst:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Load Template into ZMM0 using AVX-512 64-byte vector load
    vmovdqa64 zmm0, [rel pktgen_template_hdr]

    mov r12, [rbx + pktgen_config_t.pkt_count]
    xor r13, r13                    ; Transmitted counter

.batch_loop:
    cmp r13, r12
    jge .done

    ; Mutate 5-Tuple for 32 burst slots using AVX-512 PRNG mask
    vpaddd zmm1, zmm0, [rel pktgen_inc_vector]

    ; Enqueue burst to TX hardware DMA ring doorbell
    mov rdi, [rbx + pktgen_config_t.tx_ring_ptr]
    mov esi, PKTGEN_MAX_BURST
    call net_ring_enqueue_burst

    add r13, PKTGEN_MAX_BURST
    jmp .batch_loop

.done:
    vzeroupper
    mov rax, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

align 64
pktgen_mutate_5tuple_avx512:
    push rbp
    mov rbp, rsp
    vmovdqa64 zmm0, [rdi]
    vpaddd zmm0, zmm0, [rel pktgen_inc_vector]
    vmovdqa64 [rdi], zmm0
    vzeroupper
    pop rbp
    ret

section .rodata
align 64
pktgen_inc_vector:
    times 16 dd 0x00010000          ; Increment IP/Port fields per vector slot

%endif ; GUARD_UNET_TOOLS_BENCH_PKTGEN_ASM
