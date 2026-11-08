; =============================================================================
; Utkarsha OS — lib/ubt/ubt.asm — Bluetooth as one translation unit
; =============================================================================
; Needs lib/usb (and so lib/input) first. ROADMAP.md has the plan; this is
; Phase 1's USB transport and HCI core, ACL links, and L2CAP.
; =============================================================================

%ifndef LIB_UBT_UBT_ASM
%define LIB_UBT_UBT_ASM

%include "lib/usb/usb.asm"
%include "lib/ubt/ubt.inc"
%include "lib/ubt/l2cap/l2cap.inc"
%include "lib/ubt/hci/core.asm"
%include "lib/ubt/hci/conn.asm"
%include "lib/ubt/l2cap/core.asm"
%include "lib/ubt/l2cap/sig.asm"
%include "lib/ubt/l2cap/ertm.asm"
%include "lib/ubt/l2cap/credit.asm"
%include "lib/ubt/tr/usb.asm"
%include "lib/ubt/tr/mem.asm"

%endif ; LIB_UBT_UBT_ASM
