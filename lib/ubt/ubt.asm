; =============================================================================
; Utkarsha OS — lib/ubt/ubt.asm — Bluetooth as one translation unit
; =============================================================================
; Needs lib/usb (and so lib/input) first. ROADMAP.md has the plan; this is
; the start of Phase 1: the USB transport and the HCI core.
; =============================================================================

%ifndef LIB_UBT_UBT_ASM
%define LIB_UBT_UBT_ASM

%include "lib/usb/usb.asm"
%include "lib/ubt/ubt.inc"
%include "lib/ubt/hci/core.asm"
%include "lib/ubt/tr/usb.asm"

%endif ; LIB_UBT_UBT_ASM
