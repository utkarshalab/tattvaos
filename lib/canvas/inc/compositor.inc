; ============================================================================
; Compositor Core Definitions — Composition, Damage, Output, Surface State
; ============================================================================

%ifndef __COMPOSITOR_INC__
%define __COMPOSITOR_INC__

%include "inc/fixed.inc"
%include "inc/geometry.inc"

; ============================================================================
; Damage Region
; ============================================================================
%define DAMAGE_RECTS      0
%define DAMAGE_COUNT      8
%define DAMAGE_CAPACITY   16
%define DAMAGE_ARENA      24
%define DAMAGE_SIZE       32

%define DamageRect_X      0
%define DamageRect_Y      4
%define DamageRect_W      8
%define DamageRect_H      12
%define DamageRect_SIZE   16

; ============================================================================
; Output
; ============================================================================
%define OUTPUT_ID              0
%define OUTPUT_NAME            8
%define OUTPUT_BACKEND         16
%define OUTPUT_FRAMEBUFFER     24
%define OUTPUT_SCALE           32
%define OUTPUT_ROTATION        40
%define OUTPUT_ICC_PROFILE     48
%define OUTPUT_VRR_ENABLED     56
%define OUTPUT_VRR_FLAGS       64
%define OUTPUT_VRR_CAPS        72
%define OUTPUT_VRR_MIN_REFRESH 80
%define OUTPUT_VRR_MAX_REFRESH 88
%define OUTPUT_MODES           96
%define OUTPUT_POSITION        104
%define OUTPUT_DAMAGE          112
%define OUTPUT_X               88
%define OUTPUT_Y               96
%define OUTPUT_WIDTH           104
%define OUTPUT_HEIGHT          112
%define OUTPUT_CONNECTED       120
%define OUTPUT_CONTROLLER      128
%define OUTPUT_CRTC_INDEX      136
%define OUTPUT_EDID            144
%define OUTPUT_HPD_IRQ         152
%define OUTPUT_HPD_REGISTER    160
%define OUTPUT_I2C_BUS         168
%define OUTPUT_CURRENT_SURFACE 176
%define OUTPUT_CURRENT_MODE    184
%define OUTPUT_SURFACES        192
%define OUTPUT_TOPLEVELS       200
%define OUTPUT_HOTPLUG_CALLBACK 208
%define OUTPUT_NEXT            216
%define OUTPUT_STRIDE          224
%define OUTPUT_FRAME_CLOCK     232
%define OUTPUT_DPMS_STATE      240
%define OUTPUT_DPMS_TIMEOUT    241
%define OUTPUT_GAMMA_LUT       248
%define OUTPUT_CONTROLLER_PTR  256
%define OUTPUT_SIZE            264

; Output DPMS states
%define DPMS_ON         0
%define DPMS_STANDBY    1
%define DPMS_SUSPEND    2
%define DPMS_OFF        3

; Output rotation
%define ROTATE_0        0
%define ROTATE_90       1
%define ROTATE_180      2
%define ROTATE_270      3

; ============================================================================
; Surface State
; ============================================================================
%define SURFACE_BUFFER       0
%define SURFACE_DAMAGE       8
%define SURFACE_PENDING      16
%define SURFACE_BUF_X        24
%define SURFACE_BUF_Y        32
%define SURFACE_INPUT        36
%define SURFACE_OPAQUE       44
%define SURFACE_WIDTH        48
%define SURFACE_HEIGHT       56
%define SURFACE_TRANSFORM    64
%define SURFACE_SCALE        72
%define SURFACE_FRAME_CBS    80
%define SURFACE_SUBSURFACES  88
%define SURFACE_STRIDE       96
%define SURFACE_SIZE         104

%define SURFACE_STATE_BUFFER 0
%define SURFACE_STATE_DAMAGE 8
%define SURFACE_STATE_PENDING 16

; Transform enum
%define TRANSFORM_NORMAL       0
%define TRANSFORM_90           1
%define TRANSFORM_180          2
%define TRANSFORM_270          3
%define TRANSFORM_FLIPPED      4
%define TRANSFORM_FLIPPED_90   5
%define TRANSFORM_FLIPPED_180  6
%define TRANSFORM_FLIPPED_270  7

; ============================================================================
; Frame Clock
; ============================================================================
%define FRAME_CLOCK_CALLBACKS    0
%define FRAME_CLOCK_NEXT_VBLANK  8
%define FRAME_CLOCK_REFRESH_NS   16
%define FRAME_CLOCK_SIZE         24

%define FrameClock_NEXT_VBLANK 8
%define FrameClock_REFRESH_NS  16
%define FrameClock_CALLBACKS   0

; ============================================================================
; Compositor
; ============================================================================
%define COMPOSITOR_OUTPUTS       0
%define COMPOSITOR_DAMAGE        8
%define COMPOSITOR_FRAME_CLOCK   16
%define COMPOSITOR_RENDER_LIST   24
%define COMPOSITOR_BG_COLOR      32
%define COMPOSITOR_CURSOR        40
%define COMPOSITOR_CURSOR_X      48
%define COMPOSITOR_CURSOR_Y      56
%define COMPOSITOR_SIZE          64

; ============================================================================
; Render List Entry
; ============================================================================
%define RENDER_ENTRY_SURFACE   0
%define RENDER_ENTRY_X         8
%define RENDER_ENTRY_Y         16
%define RENDER_ENTRY_Z         24
%define RENDER_ENTRY_ALPHA     28
%define RENDER_ENTRY_TRANSFORM 32
%define RENDER_ENTRY_CLIP      40
%define RENDER_ENTRY_NEXT      48
%define RENDER_ENTRY_SIZE      56

; ============================================================================
; Frame Callback
; ============================================================================
%define FRAME_CB_SURFACE    0
%define FRAME_CB_SEQ        8
%define FRAME_CB_TIMESTAMP  16
%define FRAME_CB_NEXT       24
%define FRAME_CB_SIZE       32

%endif ; __COMPOSITOR_INC__