; ============================================================================
; Backend Dispatcher — Selects and Calls Backend Functions
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define BACKEND_HEADLESS    1
%define BACKEND_FB_LINEAR   2
%define BACKEND_NATIVE      3
%define BACKEND_REMOTE      4

section .text

; ---------------------------------------------------------------------------
; backend_init
;   Initialize selected backend
;   IN:  rdi = backend*, rsi = config*, rdx = backend_type
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global backend_init
backend_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Store backend type
    mov [rbx + Backend.state], r13

    ; Select backend
    cmp r13, BACKEND_HEADLESS
    je .headless
    cmp r13, BACKEND_FB_LINEAR
    je .fb_linear
    cmp r13, BACKEND_NATIVE
    je .native
    cmp r13, BACKEND_REMOTE
    je .remote

    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.headless:
    call headless_init
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.fb_linear:
    call fb_linear_init
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.native:
    call native_init
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.remote:
    call remote_backend_init
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; backend_deinit
; ---------------------------------------------------------------------------
global backend_deinit
backend_deinit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Backend.state]
    cmp rax, BACKEND_HEADLESS
    je .call_headless
    cmp rax, BACKEND_FB_LINEAR
    je .call_fb_linear
    cmp rax, BACKEND_NATIVE
    je .call_native
    cmp rax, BACKEND_REMOTE
    je .call_remote

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.call_headless:
    call headless_deinit
    EPILOGUE_RESTORE rbx
    ret

.call_fb_linear:
    call fb_linear_deinit
    EPILOGUE_RESTORE rbx
    ret

.call_native:
    call native_deinit
    EPILOGUE_RESTORE rbx
    ret

.call_remote:
    call remote_backend_deinit
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; backend_modeset
; ---------------------------------------------------------------------------
global backend_modeset
backend_modeset:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rax, [rbx + Backend.state]
    cmp rax, BACKEND_HEADLESS
    je .call_headless
    cmp rax, BACKEND_FB_LINEAR
    je .call_fb_linear
    cmp rax, BACKEND_NATIVE
    je .call_native
    cmp rax, BACKEND_REMOTE
    je .call_remote

    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_headless:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call headless_modeset
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_fb_linear:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call fb_linear_modeset
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_native:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call native_modeset
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_remote:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call remote_backend_modeset
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; backend_flip
; ---------------------------------------------------------------------------
global backend_flip
backend_flip:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rax, [rbx + Backend.state]
    cmp rax, BACKEND_HEADLESS
    je .call_headless
    cmp rax, BACKEND_FB_LINEAR
    je .call_fb_linear
    cmp rax, BACKEND_NATIVE
    je .call_native
    cmp rax, BACKEND_REMOTE
    je .call_remote

    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_headless:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call headless_flip
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_fb_linear:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call fb_linear_flip
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_native:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call native_flip
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_remote:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call remote_backend_flip
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; backend_vblank_wait
; ---------------------------------------------------------------------------
global backend_vblank_wait
backend_vblank_wait:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Backend.state]
    cmp rax, BACKEND_HEADLESS
    je .call_headless
    cmp rax, BACKEND_FB_LINEAR
    je .call_fb_linear
    cmp rax, BACKEND_NATIVE
    je .call_native
    cmp rax, BACKEND_REMOTE
    je .call_remote

    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_headless:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call headless_vblank_wait
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_fb_linear:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call fb_linear_vblank_wait
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_native:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call native_vblank_wait
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.call_remote:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    call remote_backend_vblank_wait
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; backend_hotplug
; ---------------------------------------------------------------------------
global backend_hotplug
backend_hotplug:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Backend.state]
    cmp rax, BACKEND_HEADLESS
    je .call_headless
    cmp rax, BACKEND_FB_LINEAR
    je .call_fb_linear
    cmp rax, BACKEND_NATIVE
    je .call_native
    cmp rax, BACKEND_REMOTE
    je .call_remote

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.call_headless:
    call headless_hotplug
    EPILOGUE_RESTORE rbx
    ret

.call_fb_linear:
    call fb_linear_hotplug
    EPILOGUE_RESTORE rbx
    ret

.call_native:
    call native_hotplug
    EPILOGUE_RESTORE rbx
    ret

.call_remote:
    call remote_backend_hotplug
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; backend_cursor
; ---------------------------------------------------------------------------
global backend_cursor
backend_cursor:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Backend.state]
    cmp rax, BACKEND_HEADLESS
    je .call_headless
    cmp rax, BACKEND_FB_LINEAR
    je .call_fb_linear
    cmp rax, BACKEND_NATIVE
    je .call_native
    cmp rax, BACKEND_REMOTE
    je .call_remote

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_headless:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call headless_cursor
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_fb_linear:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call fb_linear_cursor
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_native:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call native_cursor
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.call_remote:
    mov rdi, [rbx + Backend.state]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call remote_backend_cursor
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data


global backend_version
backend_version: dq 0x010000
