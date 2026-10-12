; ============================================================================
; CTS Surface — Surface Lifecycle, Attach, Damage, Commit
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"
%include "inc/canvas_client.inc"

section .text

global test_cts_surface_suite
test_cts_surface_suite:
    TEST_SUITE_BEGIN test_cts_surface_suite

    TEST_CASE test_cts_surface_create_destroy
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rbx, rax
        mov rdi, rbx
        call canvas_surface_create
        TEST_ASSERT_PTR rax
        mov rdi, rbx
        mov rsi, rax
        call canvas_surface_destroy
        TEST_ASSERT_OK rax
        mov rdi, rbx
        call canvas_disconnect
    TEST_END

    TEST_CASE test_cts_buffer_attach_commit
        mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE
        call canvas_connect
        TEST_ASSERT_PTR rax
        mov rbx, rax
        mov rdi, rbx
        call canvas_surface_create
        TEST_ASSERT_PTR rax
        mov r12d, eax
        mov rdi, rbx
        mov esi, 64
        mov rdx, 64
        mov rcx, 0x41524742
        call canvas_buffer_create
        TEST_ASSERT_PTR rax
        mov rdi, rbx
        mov esi, r12d
        mov edx, eax
        xor ecx, ecx
        xor r8d, r8d
        call canvas_surface_attach
        TEST_ASSERT_OK rax
        mov rdi, rbx
        mov esi, r12d
        xor edx, edx
        call canvas_surface_commit
        TEST_ASSERT_OK rax
        mov rdi, rbx
        call canvas_disconnect
    TEST_END

    TEST_SUITE_END
