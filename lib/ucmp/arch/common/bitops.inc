; =============================================================================
; Tattva OS — lib/ucmp/arch/common/bitops.inc
; =============================================================================
; Fast Bit Manipulation Macros (Shifts, Rotates, Bit Swaps).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UCMP_BITOPS_INC
%define UCMP_BITOPS_INC

; -----------------------------------------------------------------------------
; Endian BSWAP Macros
; -----------------------------------------------------------------------------
%macro UCMP_BSWAP32 1
    bswap %1
%endmacro

%macro UCMP_BSWAP64 1
    bswap %1
%endmacro

; -----------------------------------------------------------------------------
; Fast Bit Count Macros (POPCNT / LZCNT)
; -----------------------------------------------------------------------------
%macro UCMP_COUNT_BITS_SET 2
    popcnt %1, %2
%endmacro

%macro UCMP_COUNT_LEADING_ZEROS 2
    lzcnt %1, %2
%endmacro

%endif ; UCMP_BITOPS_INC
