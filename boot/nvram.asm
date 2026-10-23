; =============================================================================
; Utkarsha OS — boot/nvram.asm
; =============================================================================
; Persistent Early Console Logging to NVRAM via UEFI Runtime Services.
;
; Author:  Utkarsha Labs
; Target:  x86-64 UEFI PE32+
; =============================================================================

%ifndef NVRAM_ASM
%define NVRAM_ASM

%include "uefi/protocol.asm"

[BITS 64]

section .data

; EFI Global Variable Vendor GUID: 8be4df61-93ca-11d2-aa0d-00e098032b8c
align 8
efi_global_var_guid:
    dd 0x8BE4DF61
    dw 0x93CA, 0x11D2
    db 0xAA, 0x0D, 0x00, 0xE0, 0x98, 0x03, 0x2B, 0x8C

align 8
log_var_name:
    dw 'U', 't', 'k', 'a', 'r', 's', 'h', 'a', 'B', 'o', 'o', 't', 'L', 'o', 'g', 0

; =============================================================================
; uefi_write_boot_log — Write early boot diagnostic log to UEFI NVRAM
; Input:  RCX = pointer to System Table
;         RDX = pointer to Log Data (ASCII/Unicode buffer)
;         R8  = size of Log Data in bytes
; Output: RAX = EFI_STATUS (0 = success)
; =============================================================================
section .text
uefi_write_boot_log:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    ; Save inputs before they are clobbered
    ; RCX = System Table, RDX = Log Data, R8 = Log Size
    mov r12, rdx                     ; R12 = LogData pointer
    mov r13, r8                      ; R13 = LogSize

    ; Get RuntimeServices table pointer
    mov rbx, [rcx + SYS_TABLE_RUNTIME_SERVICES]
    test rbx, rbx
    jz .err_exit

    mov r11, [rbx + RT_SET_VARIABLE]
    test r11, r11
    jz .err_exit

    ; At this point RSP is 8 mod 16. Forty bytes supplies the 32-byte home
    ; area plus the fifth argument and restores 16-byte call alignment.
    sub rsp, 40

    ; SetVariable(VariableName, VendorGuid, Attributes, DataSize, Data)
    lea rcx, [rel log_var_name]      ; RCX = VariableName
    lea rdx, [rel efi_global_var_guid] ; RDX = VendorGuid
    mov r8d, 0x07                    ; R8 = Attributes (NV | BS | RT)
    mov r9, r13                      ; R9 = DataSize
    mov [rsp + 32], r12              ; 5th param on stack = Data pointer

    call r11

    add rsp, 40                      ; clean up shadow space
    jmp .exit

.err_exit:
    mov rax, EFI_UNSUPPORTED

.exit:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

%endif ; NVRAM_ASM
