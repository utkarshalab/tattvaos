; =============================================================================
; Tattva OS — lib/ucmp/arch/common/error.inc
; =============================================================================
; Comprehensive Compression Subsystem Error Code Definitions.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef UCMP_ERROR_INC
%define UCMP_ERROR_INC

%define UCMP_SUCCESS                    0
%define UCMP_ERR_DECOMP_CORRUPT        -100
%define UCMP_ERR_HEADER_INVALID        -101
%define UCMP_ERR_DEST_OVERFLOW         -102
%define UCMP_ERR_DICTIONARY_MISSING    -103
%define UCMP_ERR_HUFFMAN_INVALID       -104
%define UCMP_ERR_FSE_STATE_INVALID     -105
%define UCMP_ERR_OUT_OF_BOUNDS         -106

%endif ; UCMP_ERROR_INC
