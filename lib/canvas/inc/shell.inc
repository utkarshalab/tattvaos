; ============================================================================
; Shell Definitions — Toplevels, Decorations, Workspaces, Layers, Policies
; ============================================================================

%ifndef __SHELL_INC__
%define __SHELL_INC__

%include "inc/fixed.inc"
%include "inc/geometry.inc"

; ============================================================================
; Toplevel States
; ============================================================================
%define TOPLEVEL_STATE_DEFAULT     0
%define TOPLEVEL_STATE_MAXIMIZED   (1 << 0)
%define TOPLEVEL_STATE_FULLSCREEN  (1 << 1)
%define TOPLEVEL_STATE_TILED       (1 << 2)
%define TOPLEVEL_STATE_FLOATING    (1 << 3)
%define TOPLEVEL_STATE_MINIMIZED   (1 << 4)
%define TOPLEVEL_STATE_MODAL       (1 << 5)

; Toplevel capabilities
%define TOPLEVEL_CAP_NONE          0
%define TOPLEVEL_CAP_MINIMIZE      (1 << 0)
%define TOPLEVEL_CAP_MAXIMIZE      (1 << 1)
%define TOPLEVEL_CAP_FULLSCREEN    (1 << 2)
%define TOPLEVEL_CAP_CLOSE         (1 << 3)

; ============================================================================
; Toplevel
; ============================================================================
%define TOPLEVEL_SURFACE       0
%define TOPLEVEL_SHELL         8
%define TOPLEVEL_TITLE         16
%define TOPLEVEL_APP_ID        24
%define TOPLEVEL_STATE         32
%define TOPLEVEL_PENDING_STATE 36
%define TOPLEVEL_CONFIGURE_SERIAL 40
%define TOPLEVEL_CAPABILITIES  44
%define TOPLEVEL_PENDING_WIDTH 48
%define TOPLEVEL_PENDING_HEIGHT 52
%define TOPLEVEL_SAVED_WIDTH   56
%define TOPLEVEL_SAVED_HEIGHT  60
%define TOPLEVEL_DECORATION    64
%define TOPLEVEL_X             72
%define TOPLEVEL_Y             80
%define TOPLEVEL_WIDTH         88
%define TOPLEVEL_HEIGHT        96
%define TOPLEVEL_NEXT_WS       104
%define TOPLEVEL_PREV_WS       112
%define TOPLEVEL_LAYOUT_NODE   120
%define TOPLEVEL_OUTPUT        128
%define TOPLEVEL_WORKSPACE     136
%define TOPLEVEL_SIZE          144

; ============================================================================
; Decoration
; ============================================================================
%define DECORATION_TOPLEVEL      0
%define DECORATION_MODE          8
%define DECORATION_THEME         16
%define DECORATION_BUTTONS       24
%define DECORATION_BUTTON_COUNT  32
%define DECORATION_TITLEBAR_H    36
%define DECORATION_BORDER_W      40
%define DECORATION_FRAME_CB      48
%define DECORATION_RENDER_DATA   56
%define DECORATION_SIZE          64

%define DECORATION_MODE_SERVER   0
%define DECORATION_MODE_CLIENT   1
%define DECORATION_MODE_NONE     2

; Button types
%define BTN_CLOSE      0
%define BTN_MAXIMIZE   1
%define BTN_MINIMIZE   2
%define BTN_MENU       3

; Button states
%define BTN_NORMAL     0
%define BTN_HOVER      1
%define BTN_PRESSED    2
%define BTN_DISABLED   3

; ============================================================================
; Decoration Button
; ============================================================================
%define DECOR_BTN_RECT      0
%define DECOR_BTN_TYPE      16
%define DECOR_BTN_STATE     20
%define DECOR_BTN_CALLBACK  24
%define DECOR_BTN_USER_DATA 32
%define DECOR_BTN_SIZE      40

; ============================================================================
; Decoration Draw State
; ============================================================================
%define DECOR_DRAW_FB        0
%define DECOR_DRAW_STRIDE    8
%define DECOR_DRAW_WIDTH     16
%define DECOR_DRAW_HEIGHT    20
%define DECOR_DRAW_TITLE_BG  24
%define DECOR_DRAW_BORDER    28
%define DECOR_DRAW_BTN_BG    32
%define DECOR_DRAW_BTN_FG    36
%define DECOR_DRAW_INACTIVE  40
%define DECOR_DRAW_SIZE      48

; ============================================================================
; Theme
; ============================================================================
%define THEME_NAME          0
%define THEME_COLORS        8
%define THEME_FONT          16
%define THEME_FONT_SIZE     24
%define THEME_BORDER_W      28
%define THEME_BORDER_R      32
%define THEME_TITLEBAR_H    36
%define THEME_BTN_SIZE      40
%define THEME_PADDING       44
%define THEME_SIZE          56

%define THEME_COLOR_BG         0
%define THEME_COLOR_FG         4
%define THEME_COLOR_ACCENT     8
%define THEME_COLOR_BORDER     12
%define THEME_COLOR_TITLE_BG   16
%define THEME_COLOR_TITLE_FG   20
%define THEME_COLOR_BTN_BG     24
%define THEME_COLOR_BTN_FG     28
%define THEME_COLOR_BTN_HOVER_BG 32
%define THEME_COLOR_BTN_HOVER_FG 36
%define THEME_COLOR_BTN_PRESS_BG 40
%define THEME_COLOR_BTN_PRESS_FG 44
%define THEME_COLORS_SIZE      48

; ============================================================================
; Layer
; ============================================================================
%define LAYER_SURFACE         0
%define LAYER_SHELL           8
%define LAYER_OUTPUT          16
%define LAYER_LAYER           24
%define LAYER_NAMESPACE       32
%define LAYER_ANCHOR          40
%define LAYER_EXCLUSIVE_ZONE  48
%define LAYER_KEYBOARD_INT    52
%define LAYER_WIDTH           56
%define LAYER_HEIGHT          60
%define LAYER_MARGIN_TOP      64
%define LAYER_MARGIN_RIGHT    68
%define LAYER_MARGIN_BOTTOM   72
%define LAYER_MARGIN_LEFT     76
%define LAYER_NEXT            80
%define LAYER_SIZE            88

; Layer types
%define LAYER_BACKGROUND   0
%define LAYER_BOTTOM       1
%define LAYER_TOP          2
%define LAYER_OVERLAY      3

; Anchor flags
%define ANCHOR_TOP    (1 << 0)
%define ANCHOR_BOTTOM (1 << 1)
%define ANCHOR_LEFT   (1 << 2)
%define ANCHOR_RIGHT  (1 << 3)

; Keyboard interactivity
%define KEYBOARD_NONE     0
%define KEYBOARD_EXCLUSIVE 1
%define KEYBOARD_ON_DEMAND 2

; ============================================================================
; Popup
; ============================================================================
%define POPUP_SURFACE     0
%define POPUP_SHELL       8
%define POPUP_PARENT      16
%define POPUP_POSITION    24
%define POPUP_X           28
%define POPUP_Y           32
%define POPUP_WIDTH       36
%define POPUP_HEIGHT      40
%define POPUP_CONSTRAIN   44
%define POPUP_NEXT        48
%define POPUP_SIZE        56

; ============================================================================
; Workspace
; ============================================================================
%define WORKSPACE_OUTPUT      0
%define WORKSPACE_LAYOUT      8
%define WORKSPACE_TOPLEVELS   16
%define WORKSPACE_IDX         24
%define WORKSPACE_NAME        32
%define WORKSPACE_SIZE        40

; ============================================================================
; Layout Node (for tiling)
; ============================================================================
%define LAYOUT_NODE_TYPE     0
%define LAYOUT_NODE_LEFT     8
%define LAYOUT_NODE_RIGHT    16
%define LAYOUT_NODE_PARENT   24
%define LAYOUT_NODE_RECT     32
%define LAYOUT_NODE_CLIENT   40
%define LAYOUT_NODE_RATIO    48
%define LAYOUT_NODE_MASTER   56
%define LAYOUT_NODE_TOPLEVEL 64
%define LAYOUT_NODE_X        72
%define LAYOUT_NODE_Y        80
%define LAYOUT_NODE_WIDTH    88
%define LAYOUT_NODE_HEIGHT   96
%define LAYOUT_NODE_GAP      104
%define LAYOUT_NODE_SIZE     112

%define NODE_TYPE_HORIZONTAL 0
%define NODE_TYPE_VERTICAL   1
%define NODE_TYPE_LEAF       2

; ============================================================================
; Layout Engine
; ============================================================================
%define LAYOUT_ROOT         0
%define LAYOUT_NODE_COUNT   8
%define LAYOUT_GAP_SIZE     16
%define LAYOUT_MASTER_RATIO 24
%define LAYOUT_SMART_GAPS   32
%define LAYOUT_SMART_BORDERS 40
%define LAYOUT_SERVER       48
%define LAYOUT_SIZE         56

; ============================================================================
; Policy Interface
; ============================================================================
%define POLICY_SERVER       0
%define POLICY_LAYOUT       8
%define POLICY_CONFIGURE    16
%define POLICY_FOCUS_CHANGE 24
%define POLICY_NEW_WINDOW   32
%define POLICY_CLOSE_WINDOW 40
%define POLICY_WS_CHANGED   48
%define POLICY_TILE_WINDOW  48
%define POLICY_WIN_CONFIG   56
%define POLICY_SIZE         64

; ============================================================================
; Configure
; ============================================================================
%define CONFIGURE_SERIAL    0
%define CONFIGURE_SURFACE   8
%define CONFIGURE_WIDTH     16
%define CONFIGURE_HEIGHT    20
%define CONFIGURE_STATES    24
%define CONFIGURE_CALLBACK  28
%define CONFIGURE_USER_DATA 36
%define CONFIGURE_ACK_CB    44
%define CONFIGURE_NEXT      52
%define CONFIGURE_SIZE      56

%endif ; __SHELL_INC__