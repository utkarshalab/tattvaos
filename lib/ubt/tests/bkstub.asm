; =============================================================================
; lib/ubt/tests/bkstub.asm — lib/ubt/kernel.asm with the USB kernel glue,
; for tests
; =============================================================================
; lib/usb's kernel stub (console, pages, PCI and mapping through hooks) with
; the USB stack and its glue, then Bluetooth and its glue.
; =============================================================================

%include "lib/usb/tests/ukstub.asm"
%include "lib/ubt/ubt.asm"
%include "lib/ubt/kernel.asm"
