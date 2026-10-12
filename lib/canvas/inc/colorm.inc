; ============================================================================
; Color Management Shared Definitions
; ============================================================================

%ifndef __COLORM_INC__
%define __COLORM_INC__

; Rendering intents
%define CM_INTENT_PERCEPTUAL            0
%define CM_INTENT_RELATIVE_COLORIMETRIC 1
%define CM_INTENT_SATURATION           2
%define CM_INTENT_ABSOLUTE_COLORIMETRIC 3

; Transform flags
%define CM_FLAG_HDR_PASSTHROUGH   (1 << 0)
%define CM_FLAG_LINEAR_BLEND      (1 << 1)
%define CM_FLAG_TONEMAP           (1 << 2)

; Pixel encodings
%define CM_ENC_SRGB               0
%define CM_ENC_LINEAR             1
%define CM_ENC_PQ                 2  ; ST.2084
%define CM_ENC_HLG                3

; Matrix3x3 fixed 16.16 (9 x i32)
%define MAT3_SIZE    36

; TRC curve types
%define TRC_TYPE_GAMMA    0
%define TRC_TYPE_TABLE    1
%define TRC_TYPE_PARAM    2
%define TRC_TYPE_SRGB     3
%define TRC_TYPE_LINEAR   4

%endif ; __COLORM_INC__
