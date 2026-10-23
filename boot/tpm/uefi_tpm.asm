; =============================================================================
; Utkarsha OS — boot/tpm/uefi_tpm.asm
; =============================================================================
; UEFI TPM 2.0 Integration.
; Uses EFI_TCG2_PROTOCOL to measure and extend PCRs in UEFI long mode.
;
; Author:  Utkarsha Labs
; Target:  x86-64 UEFI PE32+
; =============================================================================

%ifndef UEFI_TPM_ASM
%define UEFI_TPM_ASM

%include "uefi/protocol.asm"

[BITS 64]

TCG2_EVENT_PCR_INDEX_OFF equ 10
TCG2_MAX_PCR_INDEX       equ 23

; EFI_TCG2_PROTOCOL_GUID: 607f766c-7455-42be-930b-e4d76db2720f
section .rdata
align 8
efi_tcg2_protocol_guid:
    dd 0x607f766c
    dw 0x7455, 0x42be
    db 0x93, 0x0b, 0xe4, 0xd7, 0x6d, 0xb2, 0x72, 0x0f

; Firmware writes the located interface through tcg2_protocol, and measurement
; updates PCRIndex in tcg2_event.  Both must be in writable PE data, never in
; the executable/read-only section inherited from the including file.
section .data
align 8
tcg2_protocol:      dq 0

; Packed EFI_TCG2_EVENT.  The event payload names what was measured; the data
; passed separately to HashLogExtendEvent remains the exact kernel image.
align 8
tcg2_event:
    dd tcg2_event_end - tcg2_event
tcg2_event_header:
    dd tcg2_event_header_end - tcg2_event_header
    dw 1                            ; EFI_TCG2_EVENT_HEADER_VERSION
    dd 4                            ; PCRIndex (default PCR 4)
    dd 0x0D                         ; EV_IPL (bootloader/OS loader)
tcg2_event_header_end:
    db "Utkarsha kernel", 0
tcg2_event_end:

section .text

; =============================================================================
; uefi_tpm_init — Locate the EFI_TCG2_PROTOCOL interface
; Input:  RCX = pointer to System Table
; Output: RAX = EFI_STATUS (0 = success)
; =============================================================================
uefi_tpm_init:
    push rbp
    mov rbp, rsp
    sub rsp, 32

    mov qword [rel tcg2_protocol], 0
    mov rax, [rcx + SYS_TABLE_BOOT_SERVICES]
    test rax, rax
    jz .unsupported
    mov rax, [rax + BS_LOCATE_PROTOCOL]
    test rax, rax
    jz .unsupported
    
    ; LocateProtocol(GUID*, Registration*, Interface**)
    lea rcx, [rel efi_tcg2_protocol_guid] ; RCX = GUID*
    xor rdx, rdx                     ; RDX = Registration (NULL)
    lea r8, [rel tcg2_protocol]      ; R8 = Interface**
    call rax                         ; execute LocateProtocol
    jmp .done

.unsupported:
    mov rax, EFI_UNSUPPORTED
.done:
    mov rsp, rbp
    pop rbp
    ret

; =============================================================================
; uefi_tpm_measure — Hash data and extend a PCR
; Input:  RCX = pointer to System Table
;         RDX = physical address of buffer to measure
;         R8  = length of buffer to measure (bytes)
;         R9D = PCR index to extend (e.g. 4 or 5)
; Output: RAX = EFI_STATUS (0 = success)
; =============================================================================
uefi_tpm_measure:
    push rbp
    mov rbp, rsp
    sub rsp, 48                      ; shadow space + local variables

    test rdx, rdx
    jz .invalid
    test r8, r8
    jz .invalid
    cmp r9d, TCG2_MAX_PCR_INDEX
    ja .invalid

    ; Check if TCG2 Protocol was successfully located
    mov rax, [rel tcg2_protocol]
    test rax, rax
    jz .no_protocol                  ; if protocol is NULL, fail

    ; Setup parameters for HashLogExtendEvent:
    ; Protocol function offset:
    ; 0: GetCapability
    ; 8: GetEventLog
    ; 16: HashLogExtendEvent
    
    ; Save inputs
    mov [rbp - 8], rdx               ; DataToHash
    mov [rbp - 16], r8               ; DataToHashLen

    ; Update event structure with PCR index
    mov [rel tcg2_event + TCG2_EVENT_PCR_INDEX_OFF], r9d

    ; HashLogExtendEvent(This, Flags, DataToHash, DataToHashLen, EfiTcgEvent)
    mov rcx, [rel tcg2_protocol]     ; RCX = This
    xor rdx, rdx                     ; RDX = Flags (0 = hash and log)
    mov r8, [rbp - 8]                ; R8 = DataToHash
    mov r9, [rbp - 16]               ; R9 = DataToHashLen
    
    lea rax, [rel tcg2_event]
    mov [rsp + 32], rax              ; fifth parameter on stack
    
    mov rax, [rcx + 16]              ; RAX = HashLogExtendEvent function pointer
    test rax, rax
    jz .no_protocol
    call rax                         ; execute HashLogExtendEvent
    jmp .done

.invalid:
    mov rax, EFI_INVALID_PARAMETER
    jmp .done
.no_protocol:
    mov rax, EFI_UNSUPPORTED

.done:
    mov rsp, rbp
    pop rbp
    ret

%endif ; UEFI_TPM_ASM
