; =============================================================================
; Utkarsha OS — lib/usb/usb.asm — the USB stack as one translation unit
; =============================================================================
; Included by the kernel (kernel/entry.asm) and assembled on its own for the
; host tests (tests/run_tests.sh). ROADMAP.md has the plan.
; =============================================================================

%ifndef LIB_USB_USB_ASM
%define LIB_USB_USB_ASM

%include "lib/input/input.asm"       ; HID reports become input events there
%include "lib/usb/usb.inc"
%include "lib/usb/core/hooks.asm"
%include "lib/usb/core/desc.asm"

; host controllers
%include "lib/usb/hcd/xhci/xhci.inc"
%include "lib/usb/hcd/xhci/ring.asm"
%include "lib/usb/hcd/xhci/init.asm"
%include "lib/usb/hcd/xhci/cmd.asm"
%include "lib/usb/hcd/xhci/port.asm"
%include "lib/usb/hcd/xhci/xfer.asm"

; the core over them
%include "lib/usb/core/enum.asm"

; class drivers
%include "lib/usb/class/hub/hub.asm"
%include "lib/usb/class/hid/hid.asm"

%endif ; LIB_USB_USB_ASM
