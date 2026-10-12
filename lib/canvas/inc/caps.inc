; ============================================================================
; Capability Bits — Interface Capability Definitions
; ============================================================================

%ifndef __CAPS_INC__
%define __CAPS_INC__

; Core (always granted)
%define CAP_DISPLAY     (1 << 0)
%define CAP_BUFFER      (1 << 1)
%define CAP_SURFACE     (1 << 2)
%define CAP_PRESENT     (1 << 3)

; Output/Input
%define CAP_OUTPUT      (1 << 4)
%define CAP_SEAT        (1 << 5)
%define CAP_POINTER     (1 << 6)
%define CAP_KEYBOARD    (1 << 7)
%define CAP_TOUCH       (1 << 8)
%define CAP_TABLET      (1 << 9)

; Shell/Data
%define CAP_SHELL       (1 << 10)
%define CAP_LAYER       (1 << 11)
%define CAP_DECORATION  (1 << 12)
%define CAP_DATA        (1 << 13)

; Text/A11y
%define CAP_TEXT        (1 << 14)
%define CAP_A11Y        (1 << 15)

; Privileged (require trust profile + explicit grant)
%define CAP_CAPTURE     (1 << 32)
%define CAP_INJECT      (1 << 33)
%define CAP_POLICY      (1 << 34)
%define CAP_DEBUG       (1 << 35)
%define CAP_SESSION     (1 << 36)
%define CAP_REMOTE      (1 << 37)

; Trust Profiles
%define TRUST_TRUSTED    0
%define TRUST_STANDARD   1
%define TRUST_SANDBOXED  2
%define TRUST_REMOTE     3
%define TRUST_KIOSK      4

; Profile Capability Masks
%define PROFILE_TRUSTED_CAPS    0xFFFFFFFFFFFFFFFF
%define PROFILE_STANDARD_CAPS   (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_OUTPUT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_SHELL|CAP_LAYER|CAP_DECORATION|CAP_DATA|CAP_TEXT|CAP_A11Y)
%define PROFILE_SANDBOXED_CAPS  (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_SHELL)
%define PROFILE_REMOTE_CAPS     (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_SHELL|CAP_LAYER|CAP_REMOTE)
%define PROFILE_KIOSK_CAPS      (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_SHELL)

%endif