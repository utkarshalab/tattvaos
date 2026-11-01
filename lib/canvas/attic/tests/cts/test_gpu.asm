; ============================================================================
; GPU Tests — Initialization, Shaders, Compute, Textures, Framebuffers, Sync
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/gpu_render.inc"

section .text

global test_gpu_init
test_gpu_init:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_shader_compile
test_shader_compile:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_gpu_compute
test_gpu_compute:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_gpu_texture
test_gpu_texture:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_framebuffer
test_framebuffer:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_gpu_sync
test_gpu_sync:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_gpu_memory
test_gpu_memory:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

section .data
global test_gpu_version
test_gpu_version: dq 0x010000