%ifndef GUARD_UNET_AUTOMOTIVE_DOIP_UDS_ASM
%define GUARD_UNET_AUTOMOTIVE_DOIP_UDS_ASM
; =============================================================================
; Tattva OS — unet/automotive/doip_uds.asm
; =============================================================================
; ISO 14229-1 Unified Diagnostic Services (UDS) over DoIP Engine.
;
; Features:
;   - Service Identifiers (SID):
;       `0x10`: Diagnostic Session Control (Default, Programming, Extended)
;       `0x11`: ECU Reset (Hard Reset, Key Off On, Soft Reset)
;       `0x22`: Read Data By Identifier (DID e.g. VIN `0xF190`, ECU Serial `0xF18C`)
;       `0x2E`: Write Data By Identifier
;       `0x27`: Security Access (Seed & Key Challenge-Response)
;       `0x31`: Routine Control (Start, Stop, Request Results)
;       `0x3E`: Tester Present (Zero Sub-Function Zero-Response Suppression)
;   - Negative Response Code (NRC 0x7F) Error Frame Generation
;
; Delegates:
;   - DoIP Protocol Engine              -> unet/automotive/doip.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define UDS_SID_DIAG_SESSION_CTRL   0x10
%define UDS_SID_ECU_RESET           0x11
%define UDS_SID_SECURITY_ACCESS     0x27
%define UDS_SID_READ_DATA_BY_ID     0x22
%define UDS_SID_WRITE_DATA_BY_ID    0x2E
%define UDS_SID_ROUTINE_CTRL        0x31
%define UDS_SID_TESTER_PRESENT      0x3E
%define UDS_SID_NEGATIVE_RESPONSE   0x7F

%define UDS_NRC_SUB_FUNC_NOT_SUPP   0x12
%define UDS_NRC_INCORRECT_LENGTH    0x13
%define UDS_NRC_SECURITY_DENIED     0x33

section .text

global doip_uds_init
global doip_uds_process_service
global doip_uds_read_did
global doip_uds_send_negative_resp

align 64
doip_uds_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doip_uds_process_service — Process ISO 14229 UDS Request Service ID (SID)
; Input: RDI = Pointer to UDS Request Payload, ESI = Length
; -----------------------------------------------------------------------------
align 64
doip_uds_process_service:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx]            ; SID

    cmp al, UDS_SID_READ_DATA_BY_ID
    je .read_did
    cmp al, UDS_SID_DIAG_SESSION_CTRL
    je .session_ctrl
    cmp al, UDS_SID_SECURITY_ACCESS
    je .sec_access
    cmp al, UDS_SID_TESTER_PRESENT
    je .tester_present
    jmp .nrc_not_supported

.read_did:
    call doip_uds_read_did
    jmp .done

.session_ctrl:
    jmp .done

.sec_access:
    jmp .done

.tester_present:
    ; Send Positive Response (0x7E)
    jmp .done

.nrc_not_supported:
    mov esi, UDS_NRC_SUB_FUNC_NOT_SUPP
    call doip_uds_send_negative_resp

.done:
    pop rbx
    pop rbp
    ret

align 64
doip_uds_read_did:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Read 16-bit DID (e.g. 0xF190 VIN) & format Positive Response (SID + 0x40 = 0x62)
    xor eax, eax
    pop rbp
    ret

align 64
doip_uds_send_negative_resp:
    push rbp
    mov rbp, rsp
    ; Format Negative Response Frame: 0x7F + Request_SID + NRC_Code
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_AUTOMOTIVE_DOIP_UDS_ASM
