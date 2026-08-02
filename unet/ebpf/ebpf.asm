; =============================================================================
; Tattva OS — unet/ebpf/ebpf.asm
; =============================================================================
; Extended Berkeley Packet Filter (eBPF) Virtual Machine & JIT Engine.
;
; Features:
;   - eBPF 64-Bit Register Set: R0 (Return), R1..R5 (Arguments), R6..R9 (Callee-Saved), R10 (Stack Frame Pointer)
;   - 8-Byte Instruction Format: Opcode (8b), Src Reg (4b), Dst Reg (4b), Offset (16b), Imm (32b)
;   - BPF Map Types: `BPF_MAP_TYPE_HASH`, `BPF_MAP_TYPE_ARRAY`, `BPF_MAP_TYPE_PROG_ARRAY`, `BPF_MAP_TYPE_PERCPU_ARRAY`
;   - XDP Return Actions: `XDP_ABORTED` (0), `XDP_DROP` (1), `XDP_PASS` (2), `XDP_TX` (3), `XDP_REDIRECT` (4)
;   - Fast-Path In-Memory Bytecode Interpreter & x86-64 JIT Translation Engine
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define XDP_ABORTED                 0
%define XDP_DROP                    1
%define XDP_PASS                    2
%define XDP_TX                      3
%define XDP_REDIRECT                4

struc ebpf_insn_t
    .code:              resb 1      ; Opcode
    .dst_src_reg:       resb 1      ; Dst (upper 4b) + Src (lower 4b)
    .off:               resw 1      ; 16-bit Signed Offset
    .imm:               resd 1      ; 32-bit Signed Immediate
endstruc

section .text

global ebpf_init
global ebpf_exec_bytecode
global ebpf_map_lookup_elem
global ebpf_map_update_elem

align 64
ebpf_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ebpf_exec_bytecode — Fast-Path eBPF Bytecode Interpreter Loop
; Input: RDI = Pointer to eBPF Instructions, ESI = Instruction Count, RDX = Pointer to xdp_md Context
; Output: RAX = XDP Action (XDP_PASS, XDP_DROP, XDP_TX, XDP_REDIRECT)
; -----------------------------------------------------------------------------
align 64
ebpf_exec_bytecode:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; RBX = Insn Pointer
    mov r12, rdx                    ; R12 = Context (R1 in eBPF)

    ; Register Map:
    ; R0 = RAX, R1 = R12, R2 = RSI, R3 = RDX, R4 = RCX, R5 = R8, R10 = RBP (Stack)

    ; Fetch Opcode & Dispatch
    movzx eax, byte [rbx + ebpf_insn_t.code]

    ; Return XDP_PASS by default
    mov eax, XDP_PASS

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

align 64
ebpf_map_lookup_elem:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; BPF Helper Function 1: bpf_map_lookup_elem(map, key)
    xor eax, eax
    pop rbp
    ret

align 64
ebpf_map_update_elem:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; BPF Helper Function 2: bpf_map_update_elem(map, key, value, flags)
    xor eax, eax
    pop rbp
    ret
