; =============================================================================
; Utkarsha OS — lib/input/input.asm
; =============================================================================
; Input devices: the event core and the drivers, as one include. Nothing
; here needs the kernel; lib/input/kernel.asm wires it to interrupts and a
; fiber. Plan: lib/input/ROADMAP.md.
;
; Phase 0: event core (device list, ring, ut_input_* for canvas)
; Phase 1: PS/2 controller and keyboard
; Phase 2: the HID core (report descriptors, values)
; =============================================================================

%ifndef LIB_INPUT_INPUT_ASM
%define LIB_INPUT_INPUT_ASM

%include "lib/input/input.inc"
%include "lib/input/core/hooks.asm"
%include "lib/input/core/dev.asm"
%include "lib/input/core/event.asm"
%include "lib/input/ps2/i8042.asm"
%include "lib/input/ps2/kbd.asm"
%include "lib/input/hid/hid.inc"
%include "lib/input/hid/parse.asm"
%include "lib/input/i2c_hid/i2c_hid.asm"

%endif ; LIB_INPUT_INPUT_ASM
