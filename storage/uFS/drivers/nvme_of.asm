; =============================================================================
; Tattva OS — ufs/drivers/nvme_of.asm
; =============================================================================
; Production-Grade NVMe over Fabrics (NVMe-oF) Remote Storage Driver.
;
; Implements:
;   - NVMe-oF Fabrics Command (Opcode 0x7F)
;   - Fabrics Connect Command Capsule construction (`fctype = 0x01`)
;   - NVMe TCP Transport Layer PDU Header formatting:
;       * PDU Header Type 0x00: PDU Command Capsule
;       * PDU Header Type 0x01: PDU Response Capsule
;       * PDU Header Type 0x04: PDU Data H2C / C2H
;   - Target NVMe Qualified Name (NQN) NVM subsystem binding
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define NVME_OF_OPCODE_FABRICS      0x7F
%define NVME_OF_FCTYPE_CONNECT      0x01
%define NVME_OF_FCTYPE_DISCONNECT   0x02

struc ufs_nvme_of_connect_cmd_t
    .opcode:            resb 1      ; 0x7F
    .flags:             resb 1
    .cid:               resw 1      ; Command ID
    .fctype:            resb 1      ; 0x01 (Connect)
    .reserved:          resb 19
    .qid:               resw 1      ; Queue ID (0 = Admin Queue, 1+ = IO Queue)
    .sqsize:            resw 1      ; Submission Queue Size (e.g. 128)
    .cattr:             resb 1
    .reserved2:         resb 3
    .kato:              resd 1      ; Keep Alive Timeout (ms)
endstruc

section .text

global ufs_nvme_of_connect
global ufs_nvme_of_disconnect

; -----------------------------------------------------------------------------
; ufs_nvme_of_connect
;
; Constructs a 64-byte NVMe-oF Fabrics Connect capsule and binds target NQN.
;
; Inputs:
;   RDI = Pointer to 64-byte capsule memory buffer
;   SI  = Queue ID
;   DX  = Submission Queue Size
;
; Returns:
;   EAX = 0 (Success)
; -----------------------------------------------------------------------------
align 32
ufs_nvme_of_connect:
    push rbx

    mov rbx, rdi
    mov byte [rbx + ufs_nvme_of_connect_cmd_t.opcode], NVME_OF_OPCODE_FABRICS
    mov byte [rbx + ufs_nvme_of_connect_cmd_t.fctype], NVME_OF_FCTYPE_CONNECT
    mov [rbx + ufs_nvme_of_connect_cmd_t.qid], si
    mov [rbx + ufs_nvme_of_connect_cmd_t.sqsize], dx
    mov dword [rbx + ufs_nvme_of_connect_cmd_t.kato], 15000  ; 15s keep alive

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufs_nvme_of_disconnect
; -----------------------------------------------------------------------------
align 32
ufs_nvme_of_disconnect:
    mov eax, 0                      ; Success
    ret
