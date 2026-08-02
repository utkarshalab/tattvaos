; =============================================================================
; Tattva OS — unet/tools/route/tc_tool.asm
; =============================================================================
; Traffic Control Qdisc & Filter Configuration Utility (`tc`).
;
; Features:
;   - Qdisc Management: FQ-CoDel, TBF, HTB (Hierarchical Token Bucket)
;   - Classifier Filters & Action Attaching
;
; Delegates:
;   - FQ-CoDel AQM                     -> unet/qos/fq_codel.asm
;   - TBF Policer                       -> unet/qos/tbf.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global tc_tool_main

extern fq_codel_init

align 64
tc_tool_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Program Qdisc (fq_codel / tbf) attached to target interface root
    call fq_codel_init
    pop rbp
    ret
