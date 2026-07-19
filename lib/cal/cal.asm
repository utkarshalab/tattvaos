; =============================================================================
; lib/cal/cal.asm
; Calendar Library main wrapper.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_ASM
%define IO_CAL_ASM

%include "lib/cal/cal.inc"

; Include sub-modules
%include "lib/cal/gregorian.asm"
%include "lib/cal/unix.asm"
%include "lib/cal/iso8601.asm"
%include "lib/cal/jdn.asm"
%include "lib/cal/tai.asm"
%include "lib/cal/bs.asm"

%endif ; IO_CAL_ASM
