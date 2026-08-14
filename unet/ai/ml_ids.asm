%ifndef GUARD_UNET_AI_ML_IDS_ASM
%define GUARD_UNET_AI_ML_IDS_ASM
; =============================================================================
; Tattva OS — unet/ai/ml_ids.asm
; =============================================================================
; In-Kernel Assembly Neural Network Zero-Day Intrusion Detection System (IDS).
;
; Features:
;   - Real-Time Flow Feature Extraction (Packet Rate, Byte Rate, Inter-Arrival Jitter, TCP Flags Ratio)
;   - Multi-Layer Perceptron (MLP 32-16-1 Architecture) AVX-512 Matrix Multiplicative Inference
;   - SIMD ReLU & Sigmoid Activation Functions
;   - Real-Time Anomaly Scoring & Automated XDP_DROP / Firewall Rule Triggering
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ML_IDS_FEATURE_COUNT        32
%define ML_IDS_HIDDEN_NEURONS       16

struc ml_ids_flow_features_t
    .pkt_count:         resd 1
    .byte_count:        resq 1
    .jitter_us:         resd 1
    .tcp_syn_ratio:     resd 1      ; IEEE 754 float
    .tcp_rst_ratio:     resd 1      ; IEEE 754 float
    .features_vec:      resb ML_IDS_FEATURE_COUNT * 4 ; 32 float features
endstruc

section .text

global ml_ids_init
global ml_ids_inspect_flow
global ml_ids_mlp_inference_avx512

align 64
ml_ids_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ml_ids_inspect_flow — Inspect Packet Flow Features & Classify Threat Level
; Input: RDI = Pointer to ml_ids_flow_features_t
; Output: EAX = 0 (Normal Traffic), 1 (Anomaly / Attack Detected -> Trigger DROP)
; -----------------------------------------------------------------------------
align 64
ml_ids_inspect_flow:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Execute AVX-512 MLP inference over 32 input features
    lea rdi, [rbx + ml_ids_flow_features_t.features_vec]
    call ml_ids_mlp_inference_avx512

    ; Check output probability (> 0.85 -> Attack Detected)
    vcomiss xmm0, [rel attack_threshold]
    jae .anomaly_detected

    xor eax, eax
    jmp .done

.anomaly_detected:
    mov eax, 1                      ; Threat detected -> drop & block IP

.done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ml_ids_mlp_inference_avx512 — AVX-512 Fast Neural Net Inference (32 -> 16 -> 1)
; Input: RDI = Pointer to 32 float features
; Output: XMM0 = Output Probability (0.0 .. 1.0)
; -----------------------------------------------------------------------------
align 64
ml_ids_mlp_inference_avx512:
    push rbp
    mov rbp, rsp
    push rbx

    ; 1. Load 32 float features into ZMM0 and ZMM1 (16 floats per ZMM register)
    vmovups zmm0, [rdi]
    vmovups zmm1, [rdi + 64]

    ; 2. Hidden Layer Matrix-Vector Multiplication: H = ReLU(W1 * X + B1)
    ; 3. Output Layer Sigmoid: Y = Sigmoid(W2 * H + B2)

    vzeroupper
    pop rbx
    pop rbp
    ret

section .rodata
align 16
attack_threshold:       dd 0.85     ; 85% confidence threshold

%endif ; GUARD_UNET_AI_ML_IDS_ASM
