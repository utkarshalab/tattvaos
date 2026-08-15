; =============================================================================
; Tattva OS — lib/hw/ucpu/topology.asm
; =============================================================================
; SMT / core / package topology decode via CPUID leaf 0x1F (V2 Extended
; Topology) with fallback to leaf 0x0B, plus cache-hierarchy enumeration via
; CPUID leaf 0x04.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_HW_UCPU_TOPOLOGY_ASM
%define LIB_HW_UCPU_TOPOLOGY_ASM

%include "lib/percpu.inc"

[BITS 64]

; -----------------------------------------------------------------------------
; Per-core decoded topology, indexed by percpu_t.cpu_id. Mirrors the sizing
; of global_percpu_table (lib/io/core/percpu.asm) — same PERCPU_MAX_CORES.
; -----------------------------------------------------------------------------
struc ucpu_topology_t
    .smt_id         resd 1      ; +00  thread index within core
    .core_id        resd 1      ; +04  core index within package
    .package_id     resd 1      ; +08  socket/package index
    .valid          resd 1      ; +12  1 once decoded for this cpu_id
endstruc

; Cache level entry (CPUID leaf 0x04 sub-leaf)
struc ucpu_cache_t
    .level          resd 1      ; +00  1, 2, 3...
    .type           resd 1      ; +04  1=data, 2=instruction, 3=unified
    .size_bytes     resq 1      ; +08  ways * partitions * line_size * sets
    .line_size      resd 1      ; +16
    .ways           resd 1      ; +20
    .sharing_width  resd 1      ; +24  ceil(log2(max_ids_sharing)); cores sharing = 1 << width
endstruc

UCPU_MAX_CACHE_LEVELS  equ 8

section .bss
global ucpu_topology_table
global ucpu_cache_levels
global ucpu_cache_level_count

ucpu_topology_table:  resb ucpu_topology_t_size * PERCPU_MAX_CORES
ucpu_cache_levels:    resb ucpu_cache_t_size * UCPU_MAX_CACHE_LEVELS
ucpu_cache_level_count: resq 1

section .text

; -----------------------------------------------------------------------------
; ucpu_topology_leaf — picks the extended-topology CPUID leaf to use
; Output:
;   RAX = 0x1F, 0x0B, or 0 (unsupported)
; Clobbers: RAX, RBX, RCX, RDX
; -----------------------------------------------------------------------------
global ucpu_topology_leaf
ucpu_topology_leaf:
    push rbx
    push rcx
    push rdx

    xor eax, eax
    cpuid                           ; EAX = highest standard leaf
    cmp eax, 0x1F
    jb .try_0b

    ; Leaf 0x1F, sub-leaf 0 must report a non-zero level type to be usable
    mov eax, 0x1F
    xor ecx, ecx
    cpuid
    shr ecx, 8
    and ecx, 0xFF                   ; ECX[15:8] = level type
    test ecx, ecx
    jz .try_0b
    mov rax, 0x1F
    jmp .done

.try_0b:
    mov eax, 0
    cpuid
    cmp eax, 0x0B
    jb .unsupported

    mov eax, 0x0B
    xor ecx, ecx
    cpuid
    shr ecx, 8
    and ecx, 0xFF
    test ecx, ecx
    jz .unsupported
    mov rax, 0x0B
    jmp .done

.unsupported:
    xor rax, rax

.done:
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ucpu_topology_decode_current — decodes SMT/core/package IDs for the
; currently executing logical processor and records them, keyed by
; gs:percpu_t.cpu_id. Must run after percpu_init (GS base must be live).
; Input:  none
; Output: RAX = 1 on success, 0 if the topology leaf is unsupported
; Clobbers: RAX, RBX, RCX, RDX, RSI, RDI, R8-R11
; -----------------------------------------------------------------------------
global ucpu_topology_decode_current
ucpu_topology_decode_current:
    push rbx
    push r12
    push r13
    push r14
    push r15

    call ucpu_topology_leaf
    test rax, rax
    jz .unsupported
    mov r12, rax                    ; R12 = leaf (0x1F or 0x0B)

    xor r13d, r13d                  ; R13D = smt_mask_width
    xor r14d, r14d                  ; R14D = core_mask_width (cumulative)
    xor r15d, r15d                  ; R15D = x2APIC ID of current processor
    xor rbx, rbx                    ; RBX = sub-leaf index

.subleaf_loop:
    mov eax, r12d
    mov ecx, ebx
    cpuid                           ; EAX=shift width, ECX[15:8]=level type, EDX=x2APIC ID

    mov r15d, edx                   ; current logical processor's x2APIC ID (stable across sub-leaves)

    mov r9d, ecx
    shr r9d, 8
    and r9d, 0xFF                   ; R9D = level type (0=invalid, 1=SMT, 2=Core)
    test r9d, r9d
    jz .decode                      ; invalid level marks end of the list

    and eax, 0x1F                   ; EAX = shift width at this level

    cmp r9d, 1                      ; SMT level
    jne .check_core
    mov r13d, eax                   ; smt_mask_width = shift at SMT level
    jmp .next_subleaf

.check_core:
    cmp r9d, 2                      ; Core level
    jne .next_subleaf
    mov r14d, eax                   ; core_mask_width = cumulative shift at Core level

.next_subleaf:
    inc ebx
    cmp ebx, 16                     ; sanity bound on sub-leaf count
    jb .subleaf_loop

.decode:
    ; If no Core level was ever reported (single-thread-per-core parts),
    ; core_mask_width defaults to smt_mask_width so core_id is always 0.
    cmp r14d, r13d
    jae .widths_ok
    mov r14d, r13d
.widths_ok:

    ; smt_id = x2apic_id & ((1 << smt_mask_width) - 1)
    mov ecx, r13d
    mov eax, 1
    shl eax, cl
    dec eax
    mov r8d, r15d
    and r8d, eax                    ; R8D = smt_id

    ; core_id = (x2apic_id >> smt_mask_width) & ((1 << (core_mask_width - smt_mask_width)) - 1)
    mov ecx, r13d
    mov r9d, r15d
    shr r9d, cl                     ; R9D = x2apic_id >> smt_mask_width
    mov ecx, r14d
    sub ecx, r13d                   ; ECX = core-only width
    mov eax, 1
    shl eax, cl
    dec eax
    and r9d, eax                    ; R9D = core_id

    ; package_id = x2apic_id >> core_mask_width
    mov ecx, r14d
    mov r10d, r15d
    shr r10d, cl                    ; R10D = package_id

    ; Store into ucpu_topology_table[gs:percpu_t.cpu_id]
    mov eax, [gs:percpu_t.cpu_id]
    cmp eax, PERCPU_MAX_CORES
    jae .unsupported                ; out of table bounds — should not happen
    imul rax, ucpu_topology_t_size
    lea rbx, [rel ucpu_topology_table + rax]

    mov [rbx + ucpu_topology_t.smt_id], r8d
    mov [rbx + ucpu_topology_t.core_id], r9d
    mov [rbx + ucpu_topology_t.package_id], r10d
    mov dword [rbx + ucpu_topology_t.valid], 1

    mov rax, 1
    jmp .done

.unsupported:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ucpu_topology_get — reads a decoded topology entry
; Input:
;   RDI = cpu_id
; Output:
;   RAX = 1 if valid, 0 if out of range or not yet decoded
;   RSI = smt_id, RDX = core_id, RCX = package_id (only meaningful if RAX=1)
; Clobbers: RAX, RSI, RDX, RCX, R8
; -----------------------------------------------------------------------------
global ucpu_topology_get
ucpu_topology_get:
    cmp rdi, PERCPU_MAX_CORES
    jae .not_found

    mov rax, rdi
    imul rax, ucpu_topology_t_size
    lea r8, [rel ucpu_topology_table + rax]

    cmp dword [r8 + ucpu_topology_t.valid], 0
    je .not_found

    mov esi, [r8 + ucpu_topology_t.smt_id]
    mov edx, [r8 + ucpu_topology_t.core_id]
    mov ecx, [r8 + ucpu_topology_t.package_id]
    mov rax, 1
    ret

.not_found:
    xor rax, rax
    xor rsi, rsi
    xor rdx, rdx
    xor rcx, rcx
    ret

; -----------------------------------------------------------------------------
; ucpu_cache_topology_scan — enumerates the cache hierarchy via CPUID leaf 4
; Input:  none
; Output: RAX = number of cache levels recorded into ucpu_cache_levels
; Clobbers: RAX, RBX, RCX, RDX, RSI, R8-R11
; -----------------------------------------------------------------------------
global ucpu_cache_topology_scan
ucpu_cache_topology_scan:
    push rbx
    push r12
    push r13

    xor r12d, r12d                  ; R12D = sub-leaf index
    xor r13d, r13d                  ; R13D = recorded count

.loop:
    cmp r13d, UCPU_MAX_CACHE_LEVELS
    jae .done

    mov eax, 4
    mov ecx, r12d
    cpuid                           ; EAX/EBX/ECX/EDX = cache descriptor for this sub-leaf

    mov r8d, eax
    and r8d, 0x1F                   ; R8D = cache type (0 = no more caches)
    test r8d, r8d
    jz .done

    mov r9d, eax
    shr r9d, 5
    and r9d, 0x07                   ; R9D = cache level (1, 2, 3...)

    ; sharing_width = ceil(log2(max_ids_sharing)); EAX[25:14] already holds n-1
    mov edx, eax
    shr edx, 14
    and edx, 0xFFF                  ; EDX = max_ids_sharing - 1
    jz .width_zero                  ; n - 1 == 0  ->  n == 1  ->  width 0
    bsr edx, edx
    inc edx
    jmp .width_done
.width_zero:
    xor edx, edx
.width_done:                        ; EDX = sharing_width (saved; EBX/ECX still hold line/partition/way/set fields)

    mov r10d, ebx
    shr r10d, 22
    and r10d, 0x3FF
    inc r10d                        ; R10D = ways of associativity (EBX[31:22] + 1)

    mov r11d, ebx
    shr r11d, 12
    and r11d, 0x3FF
    inc r11d                        ; R11D = physical line partitions (EBX[21:12] + 1)

    and ebx, 0xFFF
    inc ebx                         ; EBX = system coherency line size (EBX[11:0] + 1)

    inc ecx                         ; ECX = number of sets (ECX + 1)

    ; size_bytes = ways * partitions * line_size * sets
    mov eax, r10d
    imul eax, r11d
    imul eax, ebx
    imul eax, ecx

    ; Record entry. RCX (the exhausted "sets" value) is free to reuse as the
    ; table-entry pointer without disturbing EAX/R8D/R9D/R10D/EBX/EDX.
    mov ecx, r13d
    imul rcx, ucpu_cache_t_size
    lea rcx, [rel ucpu_cache_levels + rcx]

    mov [rcx + ucpu_cache_t.level], r9d
    mov [rcx + ucpu_cache_t.type], r8d
    mov dword [rcx + ucpu_cache_t.size_bytes], eax
    mov dword [rcx + ucpu_cache_t.size_bytes + 4], 0
    mov [rcx + ucpu_cache_t.line_size], ebx
    mov [rcx + ucpu_cache_t.ways], r10d
    mov [rcx + ucpu_cache_t.sharing_width], edx

    inc r12d
    inc r13d
    jmp .loop

.done:
    mov [rel ucpu_cache_level_count], r13
    mov eax, r13d

    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_HW_UCPU_TOPOLOGY_ASM
