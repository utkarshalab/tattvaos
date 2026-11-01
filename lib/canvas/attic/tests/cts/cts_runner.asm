; ============================================================================
; CTS Runner — Conformance Test Suite Runner
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

section .text

; ============================================================================
; cts_run_all
;   Run all CTS tests
; ============================================================================
global cts_run_all
cts_run_all:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi       ; test_context
    ASSERT_PTR rbx

    ; Initialize test context
    call .init_context

    ; Run test suites
    call cts_suite_protocol
    call cts_suite_render
    call cts_suite_input
    call cts_suite_shell
    call cts_suite_compositor
    call cts_suite_gpu
    call cts_suite_protocol
    call cts_suite_security
    call cts_suite_performance
    call cts_suite_stress
    call cts_suite_regression

    ; Print summary
    call .print_summary

    ; Return pass/fail
    mov eax, [rbx + TestContext_FAIL_COUNT]
    test eax, eax
    jz .all_passed

    mov rax, 1
    EPILOGUE_RESTORE rbx
    ret

.all_passed:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.init_context:
    ; Initialize test context
    mov qword [rbx + TestContext_TOTAL], 0
    mov qword [rbx + TestContext_PASSED], 0
    mov qword [rbx + TestContext_FAILED], 0
    mov qword [rbx + TestContext_SKIPPED], 0
    ret

.print_summary:
    ; Print test summary
    ; TODO: Implement
    ret

; ============================================================================
; cts_suite_protocol
;   Protocol conformance tests
; ============================================================================
global cts_suite_protocol
cts_suite_protocol:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Test message encoding/decoding
    TEST_CASE protocol_encode_decode
    call test_protocol_encode_decode

    ; Test message validation
    TEST_CASE protocol_validation
    call test_protocol_validation

    ; Test opcode mapping
    TEST_CASE opcode_mapping
    call test_opcode_mapping

    ; Test error handling
    TEST_CASE protocol_errors
    call test_protocol_errors

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_render
;   Rendering conformance tests
; ============================================================================
global cts_suite_render
cts_suite_render:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Test line drawing
    TEST_CASE render_line
    call test_render_line

    ; Test rectangle fill
    TEST_CASE render_rect_fill
    call test_render_rect_fill

    ; Test circle drawing
    TEST_CASE render_circle
    call test_render_circle

    ; Test ellipse
    TEST_CASE render_ellipse
    call test_render_ellipse

    ; Test arc
    TEST_CASE render_arc
    call test_render_arc

    ; Test rounded rect
    TEST_CASE render_rounded_rect
    call test_render_rounded_rect

    ; Test triangle
    TEST_CASE render_triangle
    call test_render_triangle

    ; Test polygon
    TEST_CASE render_polygon
    call test_render_polygon

    ; Test path rendering
    TEST_CASE render_path
    call test_render_path

    ; Test gradients
    TEST_CASE render_gradient_linear
    call test_gradient_linear
    TEST_CASE render_gradient_radial
    call test_gradient_radial
    TEST_CASE render_gradient_conical
    call test_gradient_conical

    ; Test strokes
    TEST_CASE render_stroke
    call test_render_stroke

    ; Test compositing
    TEST_CASE render_composite
    call test_render_composite

    ; Test transforms
    TEST_CASE render_transform
    call test_render_transform

    ; Test clipping
    TEST_CASE render_clip
    call test_render_clip

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_input
;   Input system conformance tests
; ============================================================================
global cts_suite_input
cts_suite_input:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Pointer tests
    TEST_CASE input_pointer_create
    call test_pointer_create
    TEST_CASE input_pointer_motion
    call test_pointer_motion
    TEST_CASE input_pointer_button
    call test_pointer_button
    TEST_CASE input_pointer_axis
    call test_pointer_axis
    TEST_CASE input_pointer_focus
    call test_pointer_focus
    TEST_CASE input_pointer_grab
    call test_pointer_grab
    TEST_CASE input_pointer_constraint
    call test_pointer_constraint

    ; Keyboard tests
    TEST_CASE input_keyboard_create
    call test_keyboard_create
    TEST_CASE input_keyboard_key
    call test_keyboard_key
    TEST_CASE input_keyboard_modifiers
    call test_keyboard_modifiers
    TEST_CASE input_keyboard_repeat
    call test_keyboard_repeat
    TEST_CASE input_keyboard_keymap
    call test_keyboard_keymap

    ; Touch tests
    TEST_CASE input_touch_create
    call test_touch_create
    TEST_CASE input_touch_down
    call test_touch_down
    TEST_CASE input_touch_up
    call test_touch_up
    TEST_CASE input_touch_motion
    call test_touch_motion
    TEST_CASE input_touch_cancel
    call test_touch_cancel

    ; Tablet tests
    TEST_CASE input_tablet_create
    call test_tablet_create
    TEST_CASE input_tablet_axis
    call test_tablet_axis
    TEST_CASE input_tablet_proximity
    call test_tablet_proximity
    TEST_CASE input_tablet_tip
    call test_tablet_tip
    TEST_CASE input_tablet_button
    call test_tablet_button

    ; Seat tests
    TEST_CASE input_seat_create
    call test_seat_create
    TEST_CASE input_seat_focus
    call test_seat_focus
    TEST_CASE input_seat_selection
    call test_seat_selection
    TEST_CASE input_seat_drag
    call test_seat_drag

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_shell
;   Shell/Window management conformance tests
; ============================================================================
global cts_suite_shell
cts_suite_shell:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Toplevel tests
    TEST_CASE shell_toplevel_create
    call test_toplevel_create
    TEST_CASE shell_toplevel_state
    call test_toplevel_state
    TEST_CASE shell_toplevel_configure
    call test_toplevel_configure
    TEST_CASE shell_toplevel_position
    call test_toplevel_position

    ; Decoration tests
    TEST_CASE shell_decoration_create
    call test_decoration_create
    TEST_CASE shell_decoration_render
    call test_decoration_render
    TEST_CASE shell_decoration_button
    call test_decoration_button

    ; Workspace tests
    TEST_CASE shell_workspace_create
    call test_workspace_create
    TEST_CASE shell_workspace_switch
    call test_workspace_switch
    TEST_CASE shell_workspace_toplevel
    call test_workspace_toplevel

    ; Layer tests
    TEST_CASE shell_layer_create
    call test_layer_create
    TEST_CASE shell_layer_anchor
    call test_layer_anchor
    TEST_CASE shell_layer_exclusive
    call test_layer_exclusive
    TEST_CASE shell_layer_keyboard
    call test_layer_keyboard

    ; Popup tests
    TEST_CASE shell_popup_create
    call test_popup_create
    TEST_CASE shell_popup_position
    call test_popup_position
    TEST_CASE shell_popup_constrain
    call test_popup_constrain

    ; Layout tests
    TEST_CASE shell_layout_create
    call test_layout_create
    TEST_CASE shell_layout_apply
    call test_layout_apply
    TEST_CASE shell_layout_tiling
    call test_layout_tiling

    ; Policy tests
    TEST_CASE shell_policy_floating
    call test_policy_floating
    TEST_CASE shell_policy_tiling
    call test_policy_tiling
    TEST_CASE shell_policy_kiosk
    call test_policy_kiosk

    ; Policy external
    TEST_CASE shell_policy_external
    call test_policy_external

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_compositor
;   Compositor conformance tests
; ============================================================================
global cts_suite_compositor
cts_suite_compositor:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Damage tracking
    TEST_CASE compositor_damage
    call test_compositor_damage

    ; Output management
    TEST_CASE compositor_output
    call test_compositor_output

    ; Surface state
    TEST_CASE compositor_surface_state
    call test_surface_state

    ; Frame clock
    TEST_CASE compositor_frame_clock
    call test_frame_clock

    ; Compositor core
    TEST_CASE compositor_composite
    call test_compositor_composite

    ; Cursor
    TEST_CASE compositor_cursor
    call test_compositor_cursor

    ; Frame callbacks
    TEST_CASE compositor_frame_callbacks
    call test_frame_callbacks

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_gpu
;   GPU acceleration conformance tests
; ============================================================================
global cts_suite_gpu
cts_suite_gpu:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; GPU initialization
    TEST_CASE gpu_init
    call test_gpu_init

    ; Shader compilation
    TEST_CASE gpu_shader_compile
    call test_shader_compile

    ; Compute shaders
    TEST_CASE gpu_compute
    call test_gpu_compute

    ; Texture management
    TEST_CASE gpu_texture
    call test_gpu_texture

    ; Framebuffer
    TEST_CASE gpu_framebuffer
    call test_framebuffer

    ; Synchronization
    TEST_CASE gpu_sync
    call test_gpu_sync

    ; Memory management
    TEST_CASE gpu_memory
    call test_gpu_memory

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_protocol
;   Protocol conformance tests
; ============================================================================
global cts_suite_protocol
cts_suite_protocol:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Message encoding/decoding
    TEST_CASE protocol_encode
    call test_protocol_encode
    TEST_CASE protocol_decode
    call test_protocol_decode
    TEST_CASE protocol_validation
    call test_protocol_validation

    ; Object lifecycle
    TEST_CASE protocol_object_lifecycle
    call test_object_lifecycle

    ; Event ordering
    TEST_CASE protocol_event_order
    call test_event_order

    ; Error handling
    TEST_CASE protocol_error_handling
    call test_protocol_errors

    ; Version negotiation
    TEST_CASE protocol_version
    call test_protocol_version

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_security
;   Security conformance tests
; ============================================================================
global cts_suite_security
cts_suite_security:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Capability enforcement
    TEST_CASE security_caps
    call test_security_caps

    ; Isolation
    TEST_CASE security_isolation
    call test_isolation

    ; Memory protection
    TEST_CASE security_memory
    call test_memory_protection

    ; Input validation
    TEST_CASE security_input
    call test_input_validation

    ; Privilege escalation
    TEST_CASE security_privilege
    call test_privilege_escalation

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_performance
;   Performance benchmarks
; ============================================================================
global cts_suite_performance
cts_suite_performance:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Rendering throughput
    TEST_CASE perf_render_throughput
    call test_render_throughput

    ; Latency
    TEST_CASE perf_latency
    call test_latency

    ; Memory usage
    TEST_CASE perf_memory
    call test_memory_usage

    ; CPU usage
    TEST_CASE perf_cpu
    call test_cpu_usage

    ; Frame rate stability
    TEST_CASE perf_framerate
    call test_framerate_stability

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_stress
;   Stress tests
; ============================================================================
global cts_suite_stress
cts_suite_stress:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Many surfaces
    TEST_CASE stress_many_surfaces
    call test_many_surfaces

    ; Many clients
    TEST_CASE stress_many_clients
    call test_many_clients

    ; Rapid commits
    TEST_CASE stress_rapid_commits
    call test_rapid_commits

    ; Large buffers
    TEST_CASE stress_large_buffers
    call test_large_buffers

    ; Long running
    TEST_CASE stress_long_running
    call test_long_running

    xor rax, rax
    leave
    ret

; ============================================================================
; cts_suite_regression
;   Regression tests
; ============================================================================
global cts_suite_regression
cts_suite_regression:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Known bug fixes
    TEST_CASE regression_1
    call test_regression_1
    TEST_CASE regression_2
    call test_regression_2
    TEST_CASE regression_3
    call test_regression_3

    xor rax, rax
    leave
    ret

section .data
global cts_version
cts_version: dq 0x010000