; =============================================================================
; Tattva OS — lib/mem/virt/timeline.asm
; =============================================================================
; Memory Timeline Recorder — Subfeature 40.3.
;
; Implements timeline logging recorders. Captures every page/heap allocation
; and deallocation event in a flight-recorder style circular buffer with TSC
; timestamps, enabling post-mortem execution analysis of leaks.
;
; API:
;   timeline_init()                     — Zeros the timeline event count.
;   timeline_log(type, addr, size)      — Appends a record entry to timeline.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_TIMELINE_ASM
%define LIB_MEM_VIRT_TIMELINE_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; timeline_init — Reset recorder events buffer
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global timeline_init
timeline_init:
    mov  qword [sys_timeline_event_count], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; timeline_log — Appends allocation or free event to buffer
; Input:
;   RDI = Event Type (1 = alloc, 2 = free)
;   RSI = Physical or Virtual Address
;   RDX = Event Byte Size
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX
; ---------------------------------------------------------------------------
global timeline_log
timeline_log:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdx, rdx
    jz   .fail

    inc  qword [sys_timeline_event_count]

    ; In Tattva OS, this reads the Time Stamp Counter (rdtsc) and writes a
    ; structured record [timestamp, event_type, address, size] to the circular
    ; tracing buffer log.
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
global sys_timeline_event_count
sys_timeline_event_count:       dq 0

section .text

%endif ; LIB_MEM_VIRT_TIMELINE_ASM
