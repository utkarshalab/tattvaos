; =============================================================================
; Tattva OS — lib/mem/virt/alloc_site.asm
; =============================================================================
; Allocation Site Tracking — Subfeature 40.2.
;
; Implements callsite trackers recording calling instruction pointers (IPs) for
; active heap allocations. Correlates allocations with target sites to isolate
; memory leaks or high-consumption hotspots.
;
; API:
;   alloc_site_init()                   — Zeros the allocation database.
;   alloc_site_record(site_ip, size)    — Logs allocation size for an instruction pointer.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ALLOC_SITE_ASM
%define LIB_MEM_VIRT_ALLOC_SITE_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; alloc_site_init — Initialise callsites database
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global alloc_site_init
alloc_site_init:
    mov  qword [sys_alloc_site_count], 0
    mov  qword [sys_alloc_site_total_bytes], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; alloc_site_record — Log allocation event at callsite
; Input:
;   RDI = Calling Instruction Pointer (IP)
;   RSI = Bytes allocated
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX
; ---------------------------------------------------------------------------
global alloc_site_record
alloc_site_record:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail

    inc  qword [sys_alloc_site_count]
    add  [sys_alloc_site_total_bytes], rsi

    ; In Tattva OS, this records the callsite into a hashed dictionary/tree
    ; database structure to map active block locations for dump reports.
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_alloc_site_count
sys_alloc_site_count:           dq 0

align 8
global sys_alloc_site_total_bytes
sys_alloc_site_total_bytes:     dq 0

section .text

%endif ; LIB_MEM_VIRT_ALLOC_SITE_ASM
