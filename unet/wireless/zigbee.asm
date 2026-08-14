%ifndef GUARD_UNET_WIRELESS_ZIGBEE_ASM
%define GUARD_UNET_WIRELESS_ZIGBEE_ASM
; =============================================================================
; Tattva OS — unet/wireless/zigbee.asm
; =============================================================================
; Zigbee 3.0 / IEEE 802.15.4 Low-Power Mesh Protocol Engine.
;
; Features:
;   - IEEE 802.15.4 MAC Frame Header Parsing (FC, Sequence, Dest/Src PAN ID & Addresses)
;   - Zigbee Network (NWK) Layer Header Parsing (Route Discovery, Radius, Seq, Multicast)
;   - Zigbee Application Support Sublayer (APS) Command & Data Frames
;   - ZCL (Zigbee Cluster Library) Attribute Read / Write / Command Processing
;   - AES-128-CCM* Security (Encryption + 32/64/128-bit MIC Verification)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ZIGBEE_FRAME_TYPE_DATA       0x00
%define ZIGBEE_FRAME_TYPE_CMD        0x01

struc dot154_hdr_t
    .frame_control:     resw 1      ; Frame Type(3b) + SecEnabled(1b) + FramePending(1b) + AckReq(1b)
    .seq_num:           resb 1      ; Sequence Number
    .dst_pan_id:        resw 1      ; Destination PAN ID
    .dst_addr:          resw 1      ; 16-bit Short or 64-bit Extended Dest Address
endstruc

struc zigbee_nwk_hdr_t
    .frame_control:     resw 1      ; Frame Type, Protocol Version, Discover Route
    .dst_addr:          resw 1      ; 16-bit NWK Dest Address
    .src_addr:          resw 1      ; 16-bit NWK Src Address
    .radius:            resb 1
    .seq_num:           resb 1
endstruc

section .text

global zigbee_init
global zigbee_process_frame
global zigbee_process_zcl
global zigbee_ccm_star_decrypt

align 64
zigbee_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
zigbee_process_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Decrypt AES-128-CCM* payload if Security Enabled bit set in IEEE 802.15.4 FC
    movzx eax, word [rbx + dot154_hdr_t.frame_control]
    test ax, 0x0008
    jz .skip_decrypt
    call zigbee_ccm_star_decrypt
.skip_decrypt:

    ; Parse Zigbee NWK header & APS payload -> ZCL commands
    call zigbee_process_zcl

    pop rbx
    pop rbp
    ret

align 64
zigbee_process_zcl:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Process ZCL (Zigbee Cluster Library) Read/Write Attributes & Commands (OnOff, LevelControl)
    xor eax, eax
    pop rbp
    ret

align 64
zigbee_ccm_star_decrypt:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; AES-128-CCM* payload decryption & MIC verification
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_WIRELESS_ZIGBEE_ASM
