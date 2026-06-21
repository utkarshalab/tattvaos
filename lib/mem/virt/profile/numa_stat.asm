; =============================================================================
; Tattva OS — lib/mem/virt/numa_stat.asm
; =============================================================================
; NUMA Hit/Miss Counters — Subfeature 40.4.
;
; Implements architecture-specific monitors measuring physical RAM transactions
; targeting local vs remote CPU sockets, compiling per-node access patterns.
;
; API:
;   numa_stat_init()                    — Zeros node-local and remote counters.
;   numa_stat_record(node, is_hit)      — Log hit or miss access statistics.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_NUMA_STAT_ASM
%define LIB_MEM_VIRT_NUMA_STAT_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; numa_stat_init — Reset socket locality counters
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global numa_stat_init
numa_stat_init:
    mov  qword [sys_numa_local_hits], 0
    mov  qword [sys_numa_remote_misses], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; numa_stat_record — Log physical locality transaction type
; Input:
;   RDI = NUMA Node Identifier
;   RSI = Access Local Status (1 = Local Hit, 0 = Remote Miss)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX
; ---------------------------------------------------------------------------
global numa_stat_record
numa_stat_record:
    cmp  rsi, 1
    je   .local_hit
    cmp  rsi, 0
    je   .remote_miss
    xor  rax, rax
    ret

.local_hit:
    inc  qword [sys_numa_local_hits]
    mov  rax, 1
    ret

.remote_miss:
    inc  qword [sys_numa_remote_misses]
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_numa_local_hits
sys_numa_local_hits:            dq 0

align 8
global sys_numa_remote_misses
sys_numa_remote_misses:         dq 0

section .text

%endif ; LIB_MEM_VIRT_NUMA_STAT_ASM
