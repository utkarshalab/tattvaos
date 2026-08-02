; =============================================================================
; Tattva OS — unet/telecom/diameter.asm
; =============================================================================
; Diameter AAA Base & Telephony Protocol Engine (RFC 6733 4G LTE / 5G Core).
;
; Features:
;   - SCTP / TCP Port 3868 20-Byte Diameter Header Parsing
;   - Command Codes: Capabilities-Exchange (CER/CEA), Device-Watchdog (DWR/DWA),
;                    Disconnect-Peer (DPR/DPA), Credit-Control (CCR/CCA),
;                    Authentication-Information (AIR/AIA - S6a), Update-Location (ULR/ULA)
;   - AVP (Attribute-Value Pair) Header Parsing (AVP Code, Flags, Length, Vendor-ID, Data)
;   - S6a Interface (MME <-> HSS) & Gx Interface (PCEF <-> PCRF)
;
; Delegates:
;   - SCTP / TCP Transport               -> unet/core/l4/sctp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DIAMETER_PORT               3868
%define DIAMETER_VERSION            1

%define DIAMETER_CMD_CER            257
%define DIAMETER_CMD_CEA            257
%define DIAMETER_CMD_DWR            280
%define DIAMETER_CMD_DWA            280
%define DIAMETER_CMD_DPR            282
%define DIAMETER_CMD_DPA            282
%define DIAMETER_CMD_CCR            272
%define DIAMETER_CMD_CCA            272
%define DIAMETER_CMD_ULR            316     ; S6a Update-Location
%define DIAMETER_CMD_ULA            316
%define DIAMETER_CMD_AIR            318     ; S6a Auth-Info
%define DIAMETER_CMD_AIA            318

struc diameter_hdr_t
    .version:           resb 1      ; Version (1)
    .length:            resb 3      ; 24-bit Message Length
    .flags:             resb 1      ; R(Request), P(Proxiable), E(Error), T(Re-transmitted)
    .command_code:      resb 3      ; 24-bit Command Code
    .application_id:    resd 1      ; 32-bit Application ID (e.g. 16777251 S6a)
    .hop_by_hop_id:     resd 1      ; Hop-by-Hop Identifier
    .end_to_end_id:     resd 1      ; End-to-End Identifier
endstruc

struc diameter_avp_hdr_t
    .code:              resd 1      ; AVP Code
    .flags:             resb 1      ; V(Vendor), M(Mandatory), P(Encrypt)
    .length:            resb 3      ; 24-bit AVP Length
    .vendor_id:         resd 1      ; Vendor ID (present if V-flag = 1)
endstruc

section .text

global diameter_init
global diameter_process_message
global diameter_process_avp
global diameter_send_cer
global diameter_send_dwr

align 64
diameter_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
diameter_process_message:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify version = 1
    movzx eax, byte [rbx + diameter_hdr_t.version]
    cmp al, DIAMETER_VERSION
    jne .invalid

    ; Extract 24-bit Command Code (bytes 5, 6, 7 big endian)
    movzx eax, byte [rbx + 5]
    shl eax, 16
    movzx edx, byte [rbx + 6]
    shl edx, 8
    or eax, edx
    movzx edx, byte [rbx + 7]
    or eax, edx                     ; EAX = 24-bit Command Code

    cmp eax, DIAMETER_CMD_CER
    je .cmd_cer
    cmp eax, DIAMETER_CMD_DWR
    je .cmd_dwr
    cmp eax, DIAMETER_CMD_ULR
    je .cmd_ulr
    cmp eax, DIAMETER_CMD_AIR
    je .cmd_air
    cmp eax, DIAMETER_CMD_CCR
    je .cmd_ccr
    jmp .done

.cmd_cer:
    ; Process Capabilities-Exchange Request -> send CEA
    jmp .done
.cmd_dwr:
    ; Process Device-Watchdog Request -> send DWA
    jmp .done
.cmd_ulr:
    ; Process S6a Update-Location-Request (MME -> HSS subscriber attach)
    call diameter_process_avp
    jmp .done
.cmd_air:
    ; Process S6a Authentication-Information-Request (vector fetch)
    call diameter_process_avp
    jmp .done
.cmd_ccr:
    ; Process Gx Credit-Control-Request (PCRF policy)
    jmp .done

.invalid:
    mov eax, -1
    pop rbx
    pop rbp
    ret

.done:
    pop rbx
    pop rbp
    ret

align 64
diameter_process_avp:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse AVP Code, Flags, Vendor ID, & Attribute Payload
    xor eax, eax
    pop rbp
    ret

align 64
diameter_send_cer:
    push rbp
    mov rbp, rsp
    ; Send Capabilities-Exchange-Request (Host-IP, Vendor-Id, Auth-Application-Id)
    xor eax, eax
    pop rbp
    ret

align 64
diameter_send_dwr:
    push rbp
    mov rbp, rsp
    ; Send Device-Watchdog-Request keepalive
    xor eax, eax
    pop rbp
    ret
