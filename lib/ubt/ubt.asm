; =============================================================================
; Utkarsha OS — lib/ubt/ubt.asm — Bluetooth as one translation unit
; =============================================================================
; Needs lib/usb (and so lib/input) first. ROADMAP.md has the plan; this is
; Phase 1's USB transport and HCI core, ACL links, L2CAP, discovery and
; advertising, and the Security Manager (with usign's P-256).
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
%include "lib/ubt/gap/gap.asm"
%include "lib/ubt/sm/crypto.asm"
%include "lib/ubt/sm/keys.asm"
%include "lib/ubt/sm/le.asm"
%include "lib/ubt/sm/br.asm"
%include "lib/ubt/sm/sec.asm"
%include "lib/ubt/gap/privacy.asm"
%include "lib/ubt/gatt/db.asm"
%include "lib/ubt/gatt/services.asm"
%include "lib/ubt/att/server.asm"
%include "lib/ubt/att/client.asm"
%include "lib/ubt/sdp/sdp.asm"
%include "lib/ubt/rfcomm/rfcomm.asm"
%include "lib/ubt/tr/usb.asm"
%include "lib/ubt/tr/mem.asm"

%endif ; LIB_UBT_UBT_ASM
