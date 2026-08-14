%ifndef GUARD_UNET_TOOLS_INDUSTRIAL_DOIP_FLASH_ASM
%define GUARD_UNET_TOOLS_INDUSTRIAL_DOIP_FLASH_ASM
; =============================================================================
; Tattva OS — unet/tools/industrial/doip_flash.asm
; =============================================================================
; Automotive ECU Diagnostic Firmware Flasher Tool (`doip-flash`).
;
; Features:
;   - DoIP ISO 13400 + UDS ISO 14229 Flash Sequence:
;       1. Diagnostic Session Control (`0x10 0x02` Programming Session)
;       2. Security Access (`0x27 0x01` Seed -> Key Calculation -> `0x27 0x02`)
;       3. Request Download (`0x34` Address & Memory Size)
;       4. Transfer Data (`0x36` Firmware Block Transfer)
;       5. Request Transfer Exit (`0x37`)
;       6. ECU Reset (`0x11 0x01`)
;
; Delegates:
;   - DoIP Subsystem                    -> unet/automotive/doip.asm
;   - UDS Subsystem                     -> unet/automotive/doip_uds.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global doip_flash_main
global doip_flash_sequence


align 64
doip_flash_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call doip_flash_sequence

    pop rbx
    pop rbp
    ret

align 64
doip_flash_sequence:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Execute UDS Programming Session (0x10) -> Security Access (0x27) -> Transfer Data (0x36) -> Reset (0x11)
    call doip_uds_process_service
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_INDUSTRIAL_DOIP_FLASH_ASM
