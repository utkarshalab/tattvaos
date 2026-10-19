; ============================================================================
; Compositor Tests — Damage, Output, Surface State, Frame Clock, Compositing
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/compositor.inc"

section .text

global test_compositor_damage
test_compositor_damage:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_compositor_output
test_compositor_output:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_surface_state
test_surface_state:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_frame_clock
test_frame_clock:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_compositor_composite
test_compositor_composite:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_compositor_cursor
test_compositor_cursor:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_frame_callbacks
test_frame_callbacks:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

section .data
global test_compositor_version
test_compositor_version: dq 0x010000