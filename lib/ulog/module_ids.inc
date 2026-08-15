; =============================================================================
; Tattva OS — lib/ulog/module_ids.inc
; =============================================================================
; Canonical module/app-ID registry (DLT-style). Every subsystem that emits a
; log record identifies itself by one of these 16-bit IDs, never a free-text
; string — keeps log_record_t fixed-size and keeps level_module_map.asm's
; per-module override table a flat array instead of a string lookup.
;
; RULES
;   1. IDs are grouped by layer (0x00NN kernel, 0x01NN lib, 0x02NN crypto,
;      0x03NN storage, 0x04NN security, 0x05NN unet, 0xFFNN ulog itself).
;   2. Never renumber an existing ID once another module's calls reference
;      it — append new IDs at the next free slot in the group instead.
;   3. MOD_COUNT bounds every per-module table (level_module_map,
;      ratelimit_hash's signature space). Keep it a power of two.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_MODULE_IDS_INC
%define LIB_ULOG_MODULE_IDS_INC

; ---- kernel/ (0x00xx) -------------------------------------------------------
%define MOD_KERNEL_ENTRY        0x0001
%define MOD_KERNEL_ARCH         0x0002
%define MOD_KERNEL_SCHED        0x0003
%define MOD_KERNEL_DRIVERS      0x0004
%define MOD_KERNEL_MM           0x0005
%define MOD_KERNEL_SECURITY     0x0006
%define MOD_KERNEL_POWER        0x0007

; ---- lib/ (0x01xx) -----------------------------------------------------------
%define MOD_LIB_MEM             0x0010
%define MOD_LIB_IO              0x0011
%define MOD_LIB_STR             0x0012
%define MOD_LIB_TIME            0x0013
%define MOD_LIB_CAL             0x0014
%define MOD_LIB_URAND           0x0015
%define MOD_LIB_UMATH           0x0016
%define MOD_LIB_UCMP            0x0017
%define MOD_LIB_UFILE           0x0018
%define MOD_LIB_HW              0x0019

; ---- crypto/ (0x02xx) --------------------------------------------------------
%define MOD_CRYPTO_UHASH        0x0020
%define MOD_CRYPTO_UCRYPT       0x0021
%define MOD_CRYPTO_USIGN        0x0022
%define MOD_CRYPTO_USSL         0x0023
%define MOD_CRYPTO_UX509        0x0024

; ---- storage/ (0x03xx) --------------------------------------------------------
%define MOD_STORAGE_UXFS        0x0030
%define MOD_STORAGE_UWAL        0x0031
%define MOD_STORAGE_UBXP        0x0032
%define MOD_STORAGE_UDB         0x0033

; ---- security/ (0x04xx) --------------------------------------------------------
%define MOD_SECURITY_USRAUTH    0x0040

; ---- unet/ (0x05xx) --------------------------------------------------------------
%define MOD_UNET_CORE           0x0050
%define MOD_UNET_ROUTING        0x0051
%define MOD_UNET_SECURITY       0x0052
%define MOD_UNET_SERVICES       0x0053

; ---- ulog itself (0xFFxx) — self_stats_report.asm tags its own records ------
%define MOD_ULOG_INTERNAL       0xFF00

; Bounds every fixed-size per-module table. Keep a power of two comfortably
; above the highest ID above; groups get sparse headroom on purpose.
%define MOD_COUNT               256

%endif ; LIB_ULOG_MODULE_IDS_INC
