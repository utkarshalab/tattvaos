; ============================================================================
; Record/Replay Unit Tests
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern record_is_active
extern record_start
extern record_stop
extern record_frame
extern replay_init
extern metrics_init
extern metrics_inc
extern metrics_tick_fps
extern stats_create
extern stats_inc
extern stats_commit
extern stats_present
extern trace_set_mask
extern trace_clear
extern protolog_set_enabled

section .text

global test_record_replay_suite
test_record_replay_suite:
    TEST_SUITE_BEGIN test_record_replay_suite

    TEST_CASE test_record_inactive_by_default
        ; record_is_active needs server*; pass minimal zeroed struct
        sub rsp, 64
        mov rdi, rsp
        mov rcx, 8
        xor rax, rax
.z1:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .z1
        mov rdi, rsp
        call record_is_active
        TEST_ASSERT_EQ rax, 0
        add rsp, 64
    TEST_END

    TEST_CASE test_stats_offsets
        ; stats_inc on stack-allocated stats block
        sub rsp, 112
        mov rdi, rsp
        mov rcx, 14
        xor rax, rax
.z2:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .z2
        mov rdi, rsp
        mov rsi, 8   ; frames offset
        call stats_inc
        TEST_ASSERT_OK rax
        cmp qword [rsp + 8], 1
        je .frames_ok
        call test_assert_fail
        jmp .frames_done
.frames_ok:
        call test_assert_pass
.frames_done:
        add rsp, 112
    TEST_END

    TEST_CASE test_metrics_offsets
        sub rsp, 96
        mov rdi, rsp
        mov rcx, 12
        xor rax, rax
.z3:
        mov qword [rdi + rax * 8], 0
        inc rax
        cmp rax, rcx
        jb .z3
        ; metrics_inc with missing metrics pointer returns 0 (no crash)
        mov rdi, rsp
        mov rsi, 8
        call metrics_inc
        TEST_ASSERT_OK rax
        add rsp, 96
    TEST_END

    TEST_SUITE_END
