; =============================================================================
; Tattva OS — lib/mem/virt/bw_sat.asm
; =============================================================================
; Memory Bandwidth Saturation Detector — Subfeature 40.5.
;
; Monitors memory bus traffic rates, raising active warnings and recommending
; page relocations/rebalancing if bandwidth usage exceeds the 80% saturation threshold.
;
; API:
;   bw_sat_init()                       — Zeros active saturation warnings.
;   bw_sat_check(current_bw_mbps)       — Evaluates bandwidth against threshold.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_BW_SAT_ASM
%define LIB_MEM_VIRT_BW_SAT_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
; Max link rate is 64000 MB/s. 80% threshold = 51200 MB/s.
%define BW_SATURATION_THRESHOLD 51200

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; bw_sat_init — Reset warning states
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global bw_sat_init
bw_sat_init:
    mov  qword [sys_bw_sat_alerts], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; bw_sat_check — Match bandwidth rate against threshold limit
; Input:  RDI = Bandwidth in MB/s
; Output: RAX = 1 if saturated (alert raised), 0 if within normal limits
; Clobbers: RAX
; ---------------------------------------------------------------------------
global bw_sat_check
bw_sat_check:
    cmp  rdi, BW_SATURATION_THRESHOLD
    jg   .saturated

    xor  rax, rax
    ret

.saturated:
    inc  qword [sys_bw_sat_alerts]
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_bw_sat_alerts
sys_bw_sat_alerts:              dq 0

section .text

%endif ; LIB_MEM_VIRT_BW_SAT_ASM
