; =============================================================================
; lib/cal/tai.asm
; International Atomic Time (TAI) & Leap Second offsets mapping.
;
; Maps standard Unix Epoch seconds to monotonic TAI seconds by applying
; historical leap second adjustments.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CAL_TAI_ASM
%define IO_CAL_TAI_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/cal/cal.inc"

section .text

global cal_epoch_to_tai

; =============================================================================
; cal_epoch_to_tai — Translate Unix Epoch seconds to TAI (Atomic) seconds
; In : RDI = 64-bit Unix Epoch seconds
; Out: RAX = 64-bit TAI seconds
; =============================================================================
IO_FUNC cal_epoch_to_tai
    mov     rax, rdi                ; RAX = standard Unix seconds

    ; Check historical leap second boundary dates (stored as Unix timestamps)
    cmp     rdi, 1483228800         ; Jan 1, 2017 00:00:00 UTC
    jae     .add_37
    cmp     rdi, 1435670400         ; Jul 1, 2015 00:00:00 UTC
    jae     .add_36
    cmp     rdi, 1341062400         ; Jul 1, 2012 00:00:00 UTC
    jae     .add_35
    cmp     rdi, 1230768000         ; Jan 1, 2009 00:00:00 UTC
    jae     .add_34
    cmp     rdi, 1136073600         ; Jan 1, 2006 00:00:00 UTC
    jae     .add_33
    cmp     rdi, 915148800          ; Jan 1, 1999 00:00:00 UTC
    jae     .add_32
    
    ; Legacy fallback for dates prior to 1999
    add     rax, 30                 ; Baseline offset for older dates
    ret

.add_37:
    add     rax, 37
    ret
.add_36:
    add     rax, 36
    ret
.add_35:
    add     rax, 35
    ret
.add_34:
    add     rax, 34
    ret
.add_33:
    add     rax, 33
    ret
.add_32:
    add     rax, 32
    ret
IO_ENDFUNC cal_epoch_to_tai

%endif ; IO_CAL_TAI_ASM
