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
%define Quota_max_mem       0
%define Quota_used_mem      8
%define Quota_max_surfs     16
%define Quota_used_surfs    20
%define Quota_max_bufs      24
%define Quota_used_bufs     28
%define Quota_max_objs      32
%define Quota_used_objs     36
%define Quota_client        40
%define Quota_size          56

; Default limits
%define QUOTA_DEFAULT_MEM       (64 * 1024 * 1024)
%define QUOTA_DEFAULT_SURFS     256
%define QUOTA_DEFAULT_BUFS      64
%define QUOTA_DEFAULT_OBJS      65536

%endif ; __QUOTA_INC__
