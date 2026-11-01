; ============================================================================
; Quota Structures — Shared Quota / Governance Definitions
; ============================================================================

%ifndef __QUOTA_INC__
%define __QUOTA_INC__

; Error codes (also in errors.inc, repeated for module independence)
%ifndef EQUOTA_MEM
%define EQUOTA_MEM      1800
%define EQUOTA_SURF     1801
%define EQUOTA_RATE     1802
%endif

; Client quota offsets (mirrors Quota struct in quota.asm)

; Default limits
%define QUOTA_DEFAULT_MEM       (64 * 1024 * 1024)
%define QUOTA_DEFAULT_SURFS     256
%define QUOTA_DEFAULT_BUFS      64
%define QUOTA_DEFAULT_OBJS      65536

%endif ; __QUOTA_INC__
