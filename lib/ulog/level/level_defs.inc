; =============================================================================
; Tattva OS — lib/ulog/level/level_defs.inc
; =============================================================================
; Level constants and severity ordering. Numerically increasing = more severe,
; matching syslog/RFC 5424 ordering so sinks/net_format.asm's PRI mapping is a
; direct arithmetic translation, not a lookup table.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_LEVEL_LEVEL_DEFS_INC
%define LIB_ULOG_LEVEL_LEVEL_DEFS_INC

%define LVL_TRACE       0
%define LVL_DEBUG       1
%define LVL_INFO        2
%define LVL_WARN        3
%define LVL_ERROR       4
%define LVL_FATAL       5
%define LVL_OFF         6       ; not a real record level; used as a filter threshold only

%define LVL_COUNT       7
%define LVL_DEFAULT     LVL_INFO

%endif ; LIB_ULOG_LEVEL_LEVEL_DEFS_INC
