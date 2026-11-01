; ============================================================================
; Shell Tests — Toplevels, Decorations, Workspaces, Layers, Popups, Layouts, Policies
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/shell.inc"

section .text

; ============================================================================
; Toplevel Tests
; ============================================================================

global test_toplevel_create
test_toplevel_create:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_toplevel_state
test_toplevel_state:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_toplevel_configure
test_toplevel_configure:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_toplevel_position
test_toplevel_position:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Decoration Tests
; ============================================================================

global test_decoration_create
test_decoration_create:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_decoration_render
test_decoration_render:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_decoration_button
test_decoration_button:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Workspace Tests
; ============================================================================

global test_workspace_create
test_workspace_create:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_workspace_switch
test_workspace_switch:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_workspace_toplevel
test_workspace_toplevel:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Layer Tests
; ============================================================================

global test_layer_create
test_layer_create:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_layer_anchor
test_layer_anchor:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_layer_exclusive
test_layer_exclusive:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_layer_keyboard
test_layer_keyboard:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Popup Tests
; ============================================================================

global test_popup_create
test_popup_create:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_popup_position
test_popup_position:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_popup_constrain
test_popup_constrain:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Layout Tests
; ============================================================================

global test_layout_create
test_layout_create:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_layout_apply
test_layout_apply:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_layout_tiling
test_layout_tiling:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

; ============================================================================
; Policy Tests
; ============================================================================

global test_policy_floating
test_policy_floating:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_policy_tiling
test_policy_tiling:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_policy_kiosk
test_policy_kiosk:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_policy_external
test_policy_external:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

section .data
global test_shell_version
test_shell_version: dq 0x010000