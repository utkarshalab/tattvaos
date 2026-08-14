%ifndef GUARD_STORAGE_UXFS_CACHE_DAX_ASM
%define GUARD_STORAGE_UXFS_CACHE_DAX_ASM
; =============================================================================
; Tattva OS — storage/uxfs/cache/dax.asm
; =============================================================================
; Direct Access (DAX) Persistent Memory Mapping & Durability Primitives.
;
; Implements:
;   - Persistence-instruction probing (`uxfs_dax_probe`)
;   - PMEM region registration and address translation (`uxfs_dax_register`,
;     `uxfs_dax_map_page`)
;   - Durability barriers: flush, drain, commit (`uxfs_dax_flush/drain/commit`)
;   - Non-temporal stores that bypass the cache (`uxfs_dax_memcpy_nt`)
;
; DAX removes the page cache from the I/O path: a file on NVDIMM or CXL memory
; is addressed directly, so a load is a load. What that removes along with the
; copy is the writeback machinery that used to make data durable.
;
; On persistent memory a plain store lands in the CPU cache and is NOT durable.
; It survives power loss only once it reaches the persistence domain. That
; requires an explicit flush (CLWB, or CLFLUSHOPT on older parts) followed by
; SFENCE to order it. Skipping this is the classic PMEM bug: everything works
; perfectly until the power actually fails, and then recent writes are gone.
;
; CLWB is preferred over CLFLUSHOPT because it writes back while keeping the
; line valid in cache, so a subsequent read does not miss. Platforms with eADR
; flush the cache hierarchy on power failure and need no flush at all, but
; assuming eADR when it is absent is silent data loss, so this always flushes.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM, CLWB/CLFLUSHOPT)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define UXFS_DAX_MAX_REGIONS         8
%define UXFS_DAX_CACHELINE           64
%define UXFS_DAX_PAGE_SIZE           4096

; Persistence capability bits discovered by uxfs_dax_probe.
%define UXFS_DAX_CAP_CLFLUSHOPT      (1 << 0)
%define UXFS_DAX_CAP_CLWB            (1 << 1)
%define UXFS_DAX_CAP_NT_STORES       (1 << 2)

; -----------------------------------------------------------------------------
; A registered persistent memory window.
; -----------------------------------------------------------------------------
struc uxfs_dax_region_t
    .phys_base:         resq 1      ; Physical base address
    .virt_base:         resq 1      ; Virtual base it is mapped at
    .length:            resq 1      ; Window size in bytes
    .flags:             resd 1      ; In-use marker
    .reserved:          resd 1
endstruc

section .data
align 64

global uxfs_dax_caps
uxfs_dax_caps:          dq 0        ; UXFS_DAX_CAP_* bitmask

global uxfs_dax_regions
uxfs_dax_regions:       times UXFS_DAX_MAX_REGIONS * uxfs_dax_region_t_size db 0

uxfs_dax_flush_count:   dq 0        ; Durability barriers issued

section .text

global uxfs_dax_probe
global uxfs_dax_register
global uxfs_dax_map_page
global uxfs_dax_unmap_page
global uxfs_dax_flush
global uxfs_dax_drain
global uxfs_dax_commit
global uxfs_dax_memcpy_nt

; -----------------------------------------------------------------------------
; uxfs_dax_probe
;
; Detects which persistence instructions this CPU implements. Must run before
; any DAX write path, since the flush routine dispatches on the result.
;
; Returns:
;   RAX = UXFS_DAX_CAP_* bitmask
; -----------------------------------------------------------------------------
align 32
uxfs_dax_probe:
    push rbx

    xor rax, rax                    ; Accumulated capabilities
    push rax

    mov eax, 7
    xor ecx, ecx
    cpuid                           ; Structured extended feature leaf

    pop rax

    bt ebx, 23                      ; EBX[23] = CLFLUSHOPT
    jnc .dp_no_clflushopt
    or rax, UXFS_DAX_CAP_CLFLUSHOPT

.dp_no_clflushopt:
    bt ebx, 24                      ; EBX[24] = CLWB
    jnc .dp_no_clwb
    or rax, UXFS_DAX_CAP_CLWB

.dp_no_clwb:
    ; SSE2 guarantees the non-temporal store forms used below.
    or rax, UXFS_DAX_CAP_NT_STORES

    mov [uxfs_dax_caps], rax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_dax_register
;
; Records a persistent memory window so translations can be bounds-checked.
;
; Inputs:
;   RDI = Physical base address
;   RSI = Virtual base address
;   RDX = Length in bytes
;
; Returns:
;   EAX = 0 on success, POSIX_ENOSPC when the region table is full
; -----------------------------------------------------------------------------
align 32
uxfs_dax_register:
    push rbx
    push r12

    test rdx, rdx
    jz .dr_inval

    lea rbx, [uxfs_dax_regions]
    mov r12, UXFS_DAX_MAX_REGIONS

.dr_scan:
    cmp dword [rbx + uxfs_dax_region_t.flags], 0
    je .dr_claim
    add rbx, uxfs_dax_region_t_size
    dec r12
    jnz .dr_scan

    mov eax, POSIX_ENOSPC
    pop r12
    pop rbx
    ret

.dr_claim:
    mov [rbx + uxfs_dax_region_t.phys_base], rdi
    mov [rbx + uxfs_dax_region_t.virt_base], rsi
    mov [rbx + uxfs_dax_region_t.length], rdx
    mov dword [rbx + uxfs_dax_region_t.flags], 1

    xor eax, eax
    pop r12
    pop rbx
    ret

.dr_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_dax_map_page
;
; Translates a physical PMEM address to its mapped virtual address.
;
; The previous implementation returned the input unchanged, which silently
; handed back a physical address usable only under identity mapping and
; performed no bounds check at all. This validates the address lies inside a
; registered window before returning anything.
;
; Inputs:
;   RDI = Physical PMEM address
;
; Returns:
;   RAX = Mapped virtual address, or 0 when the address is not in any region
; -----------------------------------------------------------------------------
align 32
uxfs_dax_map_page:
    push rbx
    push r12

    lea rbx, [uxfs_dax_regions]
    mov r12, UXFS_DAX_MAX_REGIONS

.dm_scan:
    cmp dword [rbx + uxfs_dax_region_t.flags], 0
    je .dm_next

    mov rax, [rbx + uxfs_dax_region_t.phys_base]
    cmp rdi, rax
    jb .dm_next                     ; Below this window

    mov rcx, rax
    add rcx, [rbx + uxfs_dax_region_t.length]
    cmp rdi, rcx
    jae .dm_next                    ; At or past the end

    ; Inside: virt = virt_base + (phys - phys_base)
    mov rax, rdi
    sub rax, [rbx + uxfs_dax_region_t.phys_base]
    add rax, [rbx + uxfs_dax_region_t.virt_base]
    pop r12
    pop rbx
    ret

.dm_next:
    add rbx, uxfs_dax_region_t_size
    dec r12
    jnz .dm_scan

    xor eax, eax                    ; Unmapped: caller must not dereference
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_dax_unmap_page
;
; Releases a registered window. Any dirty lines are pushed to the persistence
; domain first, so unmapping never discards writes still sitting in cache.
;
; Inputs:
;   RDI = Virtual base address of the region
;
; Returns:
;   EAX = 0 on success, POSIX_ENOENT when no such region is registered
; -----------------------------------------------------------------------------
align 32
uxfs_dax_unmap_page:
    push rbx
    push r12
    push r13

    mov r13, rdi

    lea rbx, [uxfs_dax_regions]
    mov r12, UXFS_DAX_MAX_REGIONS

.du_scan:
    cmp dword [rbx + uxfs_dax_region_t.flags], 0
    je .du_next
    cmp r13, [rbx + uxfs_dax_region_t.virt_base]
    je .du_found

.du_next:
    add rbx, uxfs_dax_region_t_size
    dec r12
    jnz .du_scan

    mov eax, POSIX_ENOENT
    jmp .du_return

.du_found:
    ; Flush before releasing: unmapping must not lose pending stores.
    mov rdi, [rbx + uxfs_dax_region_t.virt_base]
    mov rsi, [rbx + uxfs_dax_region_t.length]
    call uxfs_dax_commit

    mov qword [rbx + uxfs_dax_region_t.phys_base], 0
    mov qword [rbx + uxfs_dax_region_t.virt_base], 0
    mov qword [rbx + uxfs_dax_region_t.length], 0
    mov dword [rbx + uxfs_dax_region_t.flags], 0

    xor eax, eax

.du_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_dax_flush
;
; Writes back every cache line covering a range. This does NOT order the
; flushes — pair it with uxfs_dax_drain, or use uxfs_dax_commit which does both.
;
; Inputs:
;   RDI = Start virtual address
;   RSI = Length in bytes
;
; Returns:
;   RAX = Cache lines flushed
; -----------------------------------------------------------------------------
align 32
uxfs_dax_flush:
    push rbx
    push r12
    push r13

    test rsi, rsi
    jz .df_none

    ; Align the start down so a partially-covered first line is included.
    mov rbx, rdi
    and rbx, ~(UXFS_DAX_CACHELINE - 1)

    mov r12, rdi
    add r12, rsi                    ; End address, exclusive

    xor r13, r13                    ; Lines flushed
    mov rax, [uxfs_dax_caps]

    test rax, UXFS_DAX_CAP_CLWB
    jnz .df_clwb
    test rax, UXFS_DAX_CAP_CLFLUSHOPT
    jnz .df_clflushopt
    jmp .df_clflush

    ; CLWB keeps the line resident, so a read-after-write still hits.
.df_clwb:
    cmp rbx, r12
    jae .df_done
    clwb [rbx]
    add rbx, UXFS_DAX_CACHELINE
    inc r13
    jmp .df_clwb

.df_clflushopt:
    cmp rbx, r12
    jae .df_done
    clflushopt [rbx]
    add rbx, UXFS_DAX_CACHELINE
    inc r13
    jmp .df_clflushopt

    ; Baseline CLFLUSH is serialising; correct but markedly slower.
.df_clflush:
    cmp rbx, r12
    jae .df_done
    clflush [rbx]
    add rbx, UXFS_DAX_CACHELINE
    inc r13
    jmp .df_clflush

.df_done:
    mov rax, r13
    pop r13
    pop r12
    pop rbx
    ret

.df_none:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_dax_drain
;
; Orders previously issued flushes and non-temporal stores. CLWB and
; CLFLUSHOPT are weakly ordered, so without this they may still be in flight.
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_dax_drain:
    sfence
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; uxfs_dax_commit
;
; Flush plus drain: on return the range is durable against power loss. This is
; the call a journal or metadata update must make before reporting success.
;
; Inputs:
;   RDI = Start virtual address
;   RSI = Length in bytes
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uxfs_dax_commit:
    push rbx

    call uxfs_dax_flush
    sfence

    inc qword [uxfs_dax_flush_count]

    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_dax_memcpy_nt
;
; Copies into persistent memory with non-temporal stores, bypassing the cache
; so no flush is needed for the bulk payload — only a drain to order it.
;
; This is the right path for large writes: a normal copy would evict useful
; cache lines and then require flushing every one of them back out again.
;
; Inputs:
;   RDI = Destination (persistent memory)
;   RSI = Source
;   RDX = Length in bytes
;
; Returns:
;   RAX = Bytes copied
; -----------------------------------------------------------------------------
align 32
uxfs_dax_memcpy_nt:
    push rbx
    push r12
    push r13

    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx

    test r13, r13
    jz .mn_done

.mn_bulk:
    cmp r13, 16
    jb .mn_tail

    movdqu xmm0, [r12]
    movntdq [rbx], xmm0             ; Non-temporal: straight past the cache

    add rbx, 16
    add r12, 16
    sub r13, 16
    jmp .mn_bulk

.mn_tail:
    test r13, r13
    jz .mn_fence

    mov al, byte [r12]
    mov byte [rbx], al
    inc rbx
    inc r12
    dec r13
    jmp .mn_tail

.mn_fence:
    ; Non-temporal stores are weakly ordered; fence before anyone observes them.
    sfence

    ; The byte-wise tail went through the cache, so push those lines out too.
    mov rdi, rbx
    sub rdi, rdx
    and rdi, ~(UXFS_DAX_CACHELINE - 1)
    mov rsi, rdx
    call uxfs_dax_flush
    sfence

.mn_done:
    mov rax, rdx
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UXFS_CACHE_DAX_ASM
