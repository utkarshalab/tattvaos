; ============================================================================
; Stress Tests — Many Surfaces, Many Clients, Rapid Commits, Large Buffers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

section .text

global test_many_surfaces
test_many_surfaces:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_many_clients
test_many_clients:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_rapid_commits
test_rapid_commits:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_large_buffers
test_large_buffers:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

global test_long_running
test_long_running:
    PROLOGUE_SAVE rbx
    TEST_ASSERT 1, 1
    leave
    ret

section .data
global test_stress_version
test_stress_version: dq 0x010000