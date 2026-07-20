; =============================================================================
; Tattva OS — lib/mem/virt/meminfo.asm
; =============================================================================
; Memory Map Statistics — Subfeature 34.3.
;
; Provides a /proc/meminfo-equivalent snapshot of system memory state.
; Fields match the Linux kernel meminfo semantics:
;
;   MemTotal      — Total usable physical RAM (pages × 4096)
;   MemFree       — Unallocated physical pages
;   Buffers       — Pages used for block-device read buffers
;   Cached        — Pages held in the unified page cache
;   Mapped        — Pages mapped into any process VMA
;   Shmem         — Pages used for IPC shared memory / tmpfs
;   Slab          — Pages consumed by slab/heap kernel allocators
;   KernelStack   — Pages reserved for kernel stack frames
;
; Usage:
;   1. Call meminfo_snapshot() to latch a coherent point-in-time view.
;   2. Call meminfo_get_field(idx) to read individual fields.
;   3. Call meminfo_get_snapshot_ptr() to read the whole struct directly.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_MEMINFO_ASM
%define LIB_MEM_VIRT_MEMINFO_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Field indices for meminfo_get_field()
; ---------------------------------------------------------------------------
MEMINFO_TOTAL       equ 0
MEMINFO_FREE        equ 1
MEMINFO_BUFFERS     equ 2
MEMINFO_CACHED      equ 3
MEMINFO_MAPPED      equ 4
MEMINFO_SHMEM       equ 5
MEMINFO_SLAB        equ 6
MEMINFO_KSTACK      equ 7
MEMINFO_NR_FIELDS   equ 8

; ---------------------------------------------------------------------------
; meminfo_t — snapshot structure (8 × 8 = 64 bytes)
; ---------------------------------------------------------------------------
struc meminfo_t
    .mem_total      resq 1      ; Total usable RAM in bytes
    .mem_free       resq 1      ; Free RAM in bytes
    .buffers        resq 1      ; Buffer-cache bytes
    .cached         resq 1      ; Page-cache bytes
    .mapped         resq 1      ; Mapped bytes
    .shmem          resq 1      ; Shared-memory bytes
    .slab           resq 1      ; Slab/heap bytes
    .kstack         resq 1      ; Kernel stack bytes
endstruc

; ---------------------------------------------------------------------------
; External symbols
; ---------------------------------------------------------------------------
section .text



; VM_STAT indices (must match percpu_stat.asm)
%define VM_STAT_NR_SLAB 3

; Kernel stack pages per AP core (16 KB = 4 pages; BSP uses static stack)
KSTACK_PAGES_PER_CORE equ 4

; ---------------------------------------------------------------------------
; meminfo_snapshot — latch a coherent point-in-time meminfo view.
; Input:  none
; Output: none  (writes into meminfo_current)
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global meminfo_snapshot
meminfo_snapshot:
    push rbx
    push rcx

    ; MemTotal = phys_state.total_pages × 4096
    mov rax, [phys_state + phys_state_t.total_pages]
    shl rax, 12                         ; × 4096
    mov [meminfo_current + meminfo_t.mem_total], rax

    ; MemFree = phys_state.free_pages × 4096
    mov rax, [phys_state + phys_state_t.free_pages]
    shl rax, 12
    mov [meminfo_current + meminfo_t.mem_free], rax

    ; Buffers — block-device read buffers (tracked via sys_buf_pages counter)
    mov rax, [sys_buf_pages]
    shl rax, 12
    mov [meminfo_current + meminfo_t.buffers], rax

    ; Cached — unified page-cache entry count × 4096
    mov rax, [sys_page_cache_count]
    shl rax, 12
    mov [meminfo_current + meminfo_t.cached], rax

    ; Mapped — pages mapped into at least one process VMA (sys_mapped_pages)
    mov rax, [sys_mapped_pages]
    shl rax, 12
    mov [meminfo_current + meminfo_t.mapped], rax

    ; Shmem — IPC shared memory pages × 4096 (tracked via meminfo_shmem_inc/dec)
    mov rax, [sys_shmem_pages]
    shl rax, 12
    mov [meminfo_current + meminfo_t.shmem], rax

    ; Slab — kernel slab/heap pages from per-CPU vm_stat[VM_STAT_NR_SLAB]
    ; sys_vm_stat is an array of 4 qwords; index 3 = nr_slab
    mov rax, [sys_vm_stat + VM_STAT_NR_SLAB * 8]
    shl rax, 12
    mov [meminfo_current + meminfo_t.slab], rax

    ; KernelStack — smp_active_cores × KSTACK_PAGES_PER_CORE × 4096
    ; BSP stack is static (kernel_stack_size); APs each get 16 KB
    mov eax, dword [smp_active_cores]
    test  rax, rax
    jz    .kstack_done
    dec   rax                           ; exclude BSP (static stack)
    imul  rax, KSTACK_PAGES_PER_CORE
    shl   rax, 12
    add   rax, 4096 * 4                 ; add BSP's 4-page static stack
.kstack_done:
    mov [meminfo_current + meminfo_t.kstack], rax

    inc qword [sys_meminfo_snap_count]

    pop rcx
    pop rbx
    ret

; ---------------------------------------------------------------------------
; meminfo_get_field — read a single field from the last snapshot.
; Input:  RDI = field index (MEMINFO_TOTAL … MEMINFO_KSTACK)
; Output: RAX = field value in bytes, or 0 if out-of-range
; Clobbers: RAX
; ---------------------------------------------------------------------------
global meminfo_get_field
meminfo_get_field:
    cmp rdi, MEMINFO_NR_FIELDS
    jae .oor
    mov rax, [meminfo_current + rdi * 8]
    ret
.oor:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; meminfo_get_snapshot_ptr — return pointer to the current meminfo_t struct.
; Output: RAX = &meminfo_current
; ---------------------------------------------------------------------------
global meminfo_get_snapshot_ptr
meminfo_get_snapshot_ptr:
    lea rax, [meminfo_current]
    ret

; ---------------------------------------------------------------------------
; meminfo_mapped_inc — increment the system mapped-page counter (called by
;                      virt_map / pgtable_map hooks).
; ---------------------------------------------------------------------------
global meminfo_mapped_inc
meminfo_mapped_inc:
    lock inc qword [sys_mapped_pages]
    ret

; ---------------------------------------------------------------------------
; meminfo_mapped_dec — decrement the system mapped-page counter (called by
;                      virt_unmap hooks).
; ---------------------------------------------------------------------------
global meminfo_mapped_dec
meminfo_mapped_dec:
    lock dec qword [sys_mapped_pages]
    ret

; ---------------------------------------------------------------------------
; meminfo_buf_inc — increment buffer-cache page counter.
; ---------------------------------------------------------------------------
global meminfo_buf_inc
meminfo_buf_inc:
    lock inc qword [sys_buf_pages]
    ret

; ---------------------------------------------------------------------------
; meminfo_buf_dec — decrement buffer-cache page counter.
; ---------------------------------------------------------------------------
global meminfo_buf_dec
meminfo_buf_dec:
    lock dec qword [sys_buf_pages]
    ret

; ---------------------------------------------------------------------------
; meminfo_shmem_inc — increment shared-memory page counter.
; ---------------------------------------------------------------------------
global meminfo_shmem_inc
meminfo_shmem_inc:
    lock inc qword [sys_shmem_pages]
    ret

; ---------------------------------------------------------------------------
; meminfo_shmem_dec — decrement shared-memory page counter.
; ---------------------------------------------------------------------------
global meminfo_shmem_dec
meminfo_shmem_dec:
    lock dec qword [sys_shmem_pages]
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global meminfo_current
meminfo_current:
    times MEMINFO_NR_FIELDS dq 0       ; last snapshot (zeroed at boot)

align 8
global sys_meminfo_snap_count
sys_meminfo_snap_count: dq 0           ; telemetry: total snapshot calls

; ---------------------------------------------------------------------------
; BSS — live counters updated by virt_map / virt_unmap hooks
; ---------------------------------------------------------------------------
section .bss

align 8
global sys_mapped_pages
sys_mapped_pages: resq 1               ; pages currently mapped in any VMA

align 8
global sys_buf_pages
sys_buf_pages: resq 1                  ; pages used for block-device buffers

align 8
global sys_shmem_pages
sys_shmem_pages: resq 1                ; pages used for shared memory / IPC

section .text

%endif ; LIB_MEM_VIRT_MEMINFO_ASM
