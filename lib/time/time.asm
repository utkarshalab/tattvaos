; =============================================================================
; lib/time/time.asm
; Time Library main wrapper.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_TIME_ASM
%define IO_TIME_ASM

%include "lib/time/time.inc"

; Include sub-modules
%include "lib/time/tsc.asm"
%include "lib/time/rtc.asm"
%include "lib/time/mono.asm"
%include "lib/time/delay.asm"

%endif ; IO_TIME_ASM
