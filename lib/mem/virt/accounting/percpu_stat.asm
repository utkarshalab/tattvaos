%ifndef GUARD_LIB_MEM_VIRT_ACCOUNTING_PERCPU_STAT_ASM
%define GUARD_LIB_MEM_VIRT_ACCOUNTING_PERCPU_STAT_ASM
; =============================================================================
; Tattva OS — lib/mem/virt/percpu_stat.asm
; =============================================================================
; Per-CPU Memory Counters — Subfeature 34.2.
;
; Provides lock-free per-CPU delta counters for vm_stat and vm_event tracking.
; Each logical CPU accumulates increments/decrements in its own cache-line-sized
; slot, completely avoiding cache-line bouncing.  A periodic or on-demand sync
; routine aggregates those per-CPU deltas into the shared global counters.
;
;   vm_stat counters  (signed deltas, represent current quantities):
;     0  nr_pages_free   — free physical pages
;     1  nr_pages_anon   — anonymous mapped pages
;     2  nr_pages_file   — page-cache (file-backed) pages
;     3  nr_pages_slab   — pages held by slab/heap allocators
;
;   vm_event counters  (unsigned monotonic events):
;     0  pgalloc         — physical page allocations
;     1  pgfree          — physical page frees
;     2  pgfault         — page-fault exceptions handled
;     3  pgswapout       — pages swapped out to backing store
;     4  pgswapin        — pages swapped back into RAM
;
; Linux 5.16+ Feature Reference:
;   • lock-free stat updates via per-CPU arrays (zone_page_state, __count_vm_event)
;   • periodic sync to global vm_stat / vm_events via smp_call_function
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_PERCPU_STAT_ASM
%define LIB_MEM_VIRT_PERCPU_STAT_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------

; Maximum supported logical CPU count (must match MAX_CPUS in stack.asm)
PERCPU_MAX_CPUS equ 16

; Number of vm_stat counter slots per CPU
VM_STAT_NR_CPUCOUNTERS equ 4

; Number of vm_event counter slots per CPU
VM_EVENT_NR_CPUCOUNTERS equ 5

; Each per-CPU stat slot is padded to a full 64-byte cache line.
; 8 counters × 8 bytes = 64 bytes; vm_stat uses 4 and vm_event uses 5 —
; we allocate 8 slots per row for uniform cache-line alignment.
PERCPU_SLOTS_PER_ROW equ 8             ; 8 × 8 = 64-byte cache line

; Stride (bytes) between successive CPU rows in the arrays
PERCPU_STAT_STRIDE   equ (PERCPU_SLOTS_PER_ROW * 8)   ; 64 bytes
PERCPU_EVENT_STRIDE  equ (PERCPU_SLOTS_PER_ROW * 8)   ; 64 bytes

; vm_stat index names
VM_STAT_NR_FREE     equ 0
VM_STAT_NR_ANON     equ 1
VM_STAT_NR_FILE     equ 2
VM_STAT_NR_SLAB     equ 3

; vm_event index names
VM_EVENT_PGALLOC    equ 0
VM_EVENT_PGFREE     equ 1
VM_EVENT_PGFAULT    equ 2
VM_EVENT_PGSWAPOUT  equ 3
VM_EVENT_PGSWAPIN   equ 4

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
section .text


; ---------------------------------------------------------------------------
; percpu_stat_init — zeroes all per-CPU delta arrays and global counters.
; Input:  none
; Output: none
; Clobbers: RAX, RCX, RDI
; ---------------------------------------------------------------------------
global percpu_stat_init
percpu_stat_init:
    ; Zero per-CPU vm_stat deltas (PERCPU_MAX_CPUS × PERCPU_STAT_STRIDE bytes)
    lea  rdi, [percpu_stat_deltas]
    xor  rax, rax
    mov  rcx, (PERCPU_MAX_CPUS * PERCPU_STAT_STRIDE) / 8
    rep  stosq

    ; Zero per-CPU vm_event deltas (PERCPU_MAX_CPUS × PERCPU_EVENT_STRIDE bytes)
    lea  rdi, [percpu_event_deltas]
    xor  rax, rax
    mov  rcx, (PERCPU_MAX_CPUS * PERCPU_EVENT_STRIDE) / 8
    rep  stosq

    ; Zero global vm_stat counters
    lea  rdi, [sys_vm_stat]
    xor  rax, rax
    mov  rcx, VM_STAT_NR_CPUCOUNTERS
    rep  stosq

    ; Zero global vm_event counters
    lea  rdi, [sys_vm_event]
    xor  rax, rax
    mov  rcx, VM_EVENT_NR_CPUCOUNTERS
    rep  stosq

    ret

; ---------------------------------------------------------------------------
; percpu_stat_inc — lock-free increment of a vm_stat per-CPU delta.
; Input:
;   RDI = cpu_id   (0 … PERCPU_MAX_CPUS-1)
;   RSI = stat_idx (0 … VM_STAT_NR_CPUCOUNTERS-1)
; Output: none
; Clobbers: RAX, RCX, RDX
; ---------------------------------------------------------------------------
global percpu_stat_inc
percpu_stat_inc:
    cmp  rdi, PERCPU_MAX_CPUS
    jae  .out
    cmp  rsi, VM_STAT_NR_CPUCOUNTERS
    jae  .out

    ; slot address = percpu_stat_deltas + cpu_id*PERCPU_STAT_STRIDE + stat_idx*8
    mov  rax, rdi
    imul rax, PERCPU_STAT_STRIDE        ; rax = cpu row offset
    lea  rcx, [percpu_stat_deltas + rax]
    inc  qword [rcx + rsi * 8]          ; lock-free (single CPU owns this slot)
.out:
    ret

; ---------------------------------------------------------------------------
; percpu_stat_dec — lock-free decrement of a vm_stat per-CPU delta.
; Input:
;   RDI = cpu_id
;   RSI = stat_idx
; Output: none
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global percpu_stat_dec
percpu_stat_dec:
    cmp  rdi, PERCPU_MAX_CPUS
    jae  .out
    cmp  rsi, VM_STAT_NR_CPUCOUNTERS
    jae  .out

    mov  rax, rdi
    imul rax, PERCPU_STAT_STRIDE
    lea  rcx, [percpu_stat_deltas + rax]
    dec  qword [rcx + rsi * 8]
.out:
    ret

; ---------------------------------------------------------------------------
; percpu_event_inc — lock-free increment of a vm_event per-CPU delta.
; Input:
;   RDI = cpu_id
;   RSI = event_idx (0 … VM_EVENT_NR_CPUCOUNTERS-1)
; Output: none
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global percpu_event_inc
percpu_event_inc:
    cmp  rdi, PERCPU_MAX_CPUS
    jae  .out
    cmp  rsi, VM_EVENT_NR_CPUCOUNTERS
    jae  .out

    mov  rax, rdi
    imul rax, PERCPU_EVENT_STRIDE
    lea  rcx, [percpu_event_deltas + rax]
    inc  qword [rcx + rsi * 8]
.out:
    ret

; ---------------------------------------------------------------------------
; percpu_sync — flush all per-CPU deltas into the global vm_stat / vm_event
;               counters and reset per-CPU deltas to zero.
;
; This is the "periodic sync" step analogous to Linux's
; refresh_cpu_vm_stats(). On Tattva OS it is called explicitly (e.g. from
; kswapd, from the boot test harness, or by a periodic timer interrupt).
;
; Input:  none
; Output: none
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8, R9, R10, R11
; ---------------------------------------------------------------------------
global percpu_sync
percpu_sync:
    push rbx
    push r12
    push r13
    push r14

    mov  r12d, [smp_active_cores]      ; r12 = number of active CPUs to flush
    cmp  r12d, PERCPU_MAX_CPUS
    jbe  .cpu_count_ok
    mov  r12d, PERCPU_MAX_CPUS
.cpu_count_ok:

    ; -------------------------------------------------------------------------
    ; Phase 1: Aggregate per-CPU vm_stat deltas → sys_vm_stat[]
    ; -------------------------------------------------------------------------
    xor  r13, r13                      ; r13 = cpu_id loop counter

.stat_cpu_loop:
    cmp  r13, r12
    jae  .stat_done

    ; Pointer to this CPU's stat row
    mov  rax, r13
    imul rax, PERCPU_STAT_STRIDE
    lea  rbx, [percpu_stat_deltas + rax] ; rbx = &percpu_stat_deltas[cpu_id][0]

    xor  r14, r14                      ; r14 = stat index
.stat_idx_loop:
    cmp  r14, VM_STAT_NR_CPUCOUNTERS
    jae  .stat_cpu_next

    ; Read and clear the per-CPU delta (lock-free: single writer per slot)
    mov  rax, [rbx + r14 * 8]
    test rax, rax
    jz   .stat_idx_next                ; skip zero deltas for efficiency

    ; Atomically add delta to global (lock prefix needed: multiple CPUs may
    ; call percpu_sync concurrently if triggered by different cores' kswapd)
    lock add [sys_vm_stat + r14 * 8], rax

    ; Reset per-CPU slot to 0
    mov  qword [rbx + r14 * 8], 0

.stat_idx_next:
    inc  r14
    jmp  .stat_idx_loop

.stat_cpu_next:
    inc  r13
    jmp  .stat_cpu_loop

.stat_done:

    ; -------------------------------------------------------------------------
    ; Phase 2: Aggregate per-CPU vm_event deltas → sys_vm_event[]
    ; -------------------------------------------------------------------------
    xor  r13, r13

.event_cpu_loop:
    cmp  r13, r12
    jae  .event_done

    mov  rax, r13
    imul rax, PERCPU_EVENT_STRIDE
    lea  rbx, [percpu_event_deltas + rax]

    xor  r14, r14
.event_idx_loop:
    cmp  r14, VM_EVENT_NR_CPUCOUNTERS
    jae  .event_cpu_next

    mov  rax, [rbx + r14 * 8]
    test rax, rax
    jz   .event_idx_next

    lock add [sys_vm_event + r14 * 8], rax
    mov  qword [rbx + r14 * 8], 0

.event_idx_next:
    inc  r14
    jmp  .event_idx_loop

.event_cpu_next:
    inc  r13
    jmp  .event_cpu_loop

.event_done:
    inc  qword [sys_percpu_sync_count]  ; telemetry: count sync cycles

    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    ret

; ---------------------------------------------------------------------------
; percpu_stat_read — read a global vm_stat counter (post-sync value).
; Input:  RDI = stat_idx
; Output: RAX = current global value, or 0 if out-of-range
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global percpu_stat_read
percpu_stat_read:
    cmp  rdi, VM_STAT_NR_CPUCOUNTERS
    jae  .oor
    mov  rax, [sys_vm_stat + rdi * 8]
    ret
.oor:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; percpu_event_read — read a global vm_event counter (post-sync value).
; Input:  RDI = event_idx
; Output: RAX = current global value, or 0 if out-of-range
; Clobbers: RAX
; ---------------------------------------------------------------------------
global percpu_event_read
percpu_event_read:
    cmp  rdi, VM_EVENT_NR_CPUCOUNTERS
    jae  .oor
    mov  rax, [sys_vm_event + rdi * 8]
    ret
.oor:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; percpu_stat_delta_read — read an unsynchronised per-CPU delta (for testing).
; Input:
;   RDI = cpu_id
;   RSI = stat_idx
; Output: RAX = pending delta value (not yet flushed to global), or 0 OOR
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global percpu_stat_delta_read
percpu_stat_delta_read:
    cmp  rdi, PERCPU_MAX_CPUS
    jae  .oor
    cmp  rsi, VM_STAT_NR_CPUCOUNTERS
    jae  .oor

    mov  rax, rdi
    imul rax, PERCPU_STAT_STRIDE
    lea  rcx, [percpu_stat_deltas + rax]
    mov  rax, [rcx + rsi * 8]
    ret
.oor:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; percpu_event_delta_read — read an unsynchronised per-CPU event delta.
; Input:
;   RDI = cpu_id
;   RSI = event_idx
; Output: RAX = pending delta value (not yet flushed to global), or 0 OOR
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global percpu_event_delta_read
percpu_event_delta_read:
    cmp  rdi, PERCPU_MAX_CPUS
    jae  .oor
    cmp  rsi, VM_EVENT_NR_CPUCOUNTERS
    jae  .oor

    mov  rax, rdi
    imul rax, PERCPU_EVENT_STRIDE
    lea  rcx, [percpu_event_deltas + rax]
    mov  rax, [rcx + rsi * 8]
    ret
.oor:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 64
; Global vm_stat counters (authoritative values after sync)
global sys_vm_stat
sys_vm_stat:
    times VM_STAT_NR_CPUCOUNTERS dq 0  ; nr_free, nr_anon, nr_file, nr_slab

align 64
; Global vm_event counters (monotonically increasing events after sync)
global sys_vm_event
sys_vm_event:
    times VM_EVENT_NR_CPUCOUNTERS dq 0 ; pgalloc, pgfree, pgfault, pgswapout, pgswapin

align 8
; Telemetry: how many times percpu_sync has been called
global sys_percpu_sync_count
sys_percpu_sync_count: dq 0

; ---------------------------------------------------------------------------
; BSS — per-CPU delta arrays, 64-byte-aligned to prevent false sharing
; ---------------------------------------------------------------------------
section .bss

alignb 64
; vm_stat deltas: PERCPU_MAX_CPUS rows × PERCPU_STAT_STRIDE bytes each
global percpu_stat_deltas
percpu_stat_deltas:
    resb (PERCPU_MAX_CPUS * PERCPU_STAT_STRIDE)

alignb 64
; vm_event deltas: PERCPU_MAX_CPUS rows × PERCPU_EVENT_STRIDE bytes each
global percpu_event_deltas
percpu_event_deltas:
    resb (PERCPU_MAX_CPUS * PERCPU_EVENT_STRIDE)

section .text

%endif ; LIB_MEM_VIRT_PERCPU_STAT_ASM

%endif ; GUARD_LIB_MEM_VIRT_ACCOUNTING_PERCPU_STAT_ASM
