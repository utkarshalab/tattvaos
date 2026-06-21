; =============================================================================
; Tattva OS — lib/mem/virt/inf_prof.asm
; =============================================================================
; Inference Memory Profiler — Subfeature 40.6.
;
; Compiles detailed runtime profiling metrics for deep learning model executions,
; separating parameters weights memory, transient activations footprints, and KV
; cache blocks.
;
; API:
;   inf_prof_init()                     — Zeros execution profiling structures.
;   inf_prof_record_layer(id, weight_b, act_b, kv_b) — Accumulates model layer metrics.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_INF_PROF_ASM
%define LIB_MEM_VIRT_INF_PROF_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; inf_prof_init — Clear model profiling values
; Output: RAX = 1
; Clobbers: RAX
; ---------------------------------------------------------------------------
global inf_prof_init
inf_prof_init:
    mov  qword [sys_inf_prof_peak_activation_bytes], 0
    mov  qword [sys_inf_prof_weight_bytes], 0
    mov  qword [sys_inf_prof_kv_cache_bytes], 0
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; inf_prof_record_layer — Log memory utilization metrics for a model layer
; Input:
;   RDI = Layer Identifier Index
;   RSI = Model weight parameters size in bytes
;   RDX = Transient activation size in bytes
;   RCX = Key-Value (KV) cache block size in bytes
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX
; ---------------------------------------------------------------------------
global inf_prof_record_layer
inf_prof_record_layer:
    ; Accumulate weight and KV cache metrics
    add  [sys_inf_prof_weight_bytes], rsi
    add  [sys_inf_prof_kv_cache_bytes], rcx

    ; Update peak activations tracker
    cmp  rdx, [sys_inf_prof_peak_activation_bytes]
    jbe  .done
    mov  [sys_inf_prof_peak_activation_bytes], rdx

.done:
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_inf_prof_peak_activation_bytes
sys_inf_prof_peak_activation_bytes: dq 0

align 8
global sys_inf_prof_weight_bytes
sys_inf_prof_weight_bytes:      dq 0

align 8
global sys_inf_prof_kv_cache_bytes
sys_inf_prof_kv_cache_bytes:    dq 0

section .text

%endif ; LIB_MEM_VIRT_INF_PROF_ASM
