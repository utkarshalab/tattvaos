; =============================================================================
; Tattva OS — lib/ucmp/arch/common/types.inc
; =============================================================================
; Data Type Aliases & Common Structure Sizes.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UCMP_TYPES_INC
%define UCMP_TYPES_INC

%define u8  byte
%define u16 word
%define u32 dword
%define u64 qword

%define UCMP_CACHE_LINE_SIZE    64
%define UCMP_PAGE_SIZE_4K       4096

%endif ; UCMP_TYPES_INC
