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
%define CAP_INPUT       (1 << 10)

; Shell/Data
%define CAP_SHELL       (1 << 11)
%define CAP_LAYER       (1 << 12)
%define CAP_DECORATION  (1 << 12)
%define CAP_DATA        (1 << 13)
%define CAP_CLIPBOARD   (1 << 14)

; Text/A11y
%define CAP_TEXT        (1 << 14)
%define CAP_A11Y        (1 << 15)

; Privileged (require trust profile + explicit grant)
%define CAP_CAPTURE     (1 << 16)
%define CAP_INJECT      (1 << 17)
%define CAP_POLICY      (1 << 18)
%define CAP_DEBUG       (1 << 19)
%define CAP_SESSION     (1 << 20)
%define CAP_REMOTE      (1 << 21)

; Surface roles
%define SURFACE_ROLE_TOPLEVEL   0
%define SURFACE_ROLE_SUBSURFACE 1
%define SURFACE_ROLE_LAYER      2
%define SURFACE_ROLE_POPUP      3

; Trust profiles
%define TRUST_TRUSTED    0
%define TRUST_STANDARD   1
%define TRUST_SANDBOXED  2
%define TRUST_REMOTE     3
%define TRUST_KIOSK      4

; Profile capability masks
%define PROFILE_TRUSTED_CAPS    0xFFFFFFFFFFFFFFFF
%define PROFILE_STANDARD_CAPS   (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_OUTPUT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_INPUT|CAP_SHELL|CAP_LAYER|CAP_DECORATION|CAP_DATA|CAP_CLIPBOARD|CAP_TEXT|CAP_A11Y)
%define PROFILE_SANDBOXED_CAPS  (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_SHELL)
%define PROFILE_REMOTE_CAPS     (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_SHELL|CAP_LAYER|CAP_REMOTE)
%define PROFILE_KIOSK_CAPS      (CAP_DISPLAY|CAP_BUFFER|CAP_SURFACE|CAP_PRESENT|CAP_SEAT|CAP_POINTER|CAP_KEYBOARD|CAP_TOUCH|CAP_TABLET|CAP_SHELL)

; Profile flags
%define PROFILE_FLAG_NO_PROMPTS     (1 << 0)
%define PROFILE_FLAG_UNLIMITED_MEM  (1 << 1)
%define PROFILE_FLAG_NO_AUDIT       (1 << 2)

; Fixed-point math
%define FIX_ONE (1 << 16)

%endif ; __CAPS_INC__