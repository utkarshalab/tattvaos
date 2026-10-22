; ============================================================================
; Backend Dispatcher — Selects and Calls Backend Functions
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern headless_init
extern headless_deinit
extern headless_modeset
extern headless_flip
extern headless_vblank_wait
extern headless_hotplug
extern headless_cursor
extern fb_linear_init
extern fb_linear_deinit
extern fb_linear_modeset
extern fb_linear_flip
extern fb_linear_vblank_wait
extern fb_linear_hotplug
extern fb_linear_cursor
extern native_init
extern native_deinit
extern native_modeset
extern native_flip
extern native_vblank_wait
extern native_hotplug
extern native_cursor
extern native_crtc_disable
extern remote_backend_init
extern remote_backend_deinit
extern remote_backend_modeset
extern remote_backend_flip
extern remote_backend_vblank_wait
extern remote_backend_hotplug
extern remote_backend_cursor

; struct offsets (hoisted above use)
%define BACKEND_HEADLESS    1
%define BACKEND_FB_LINEAR   2
%define BACKEND_NATIVE      3
%define BACKEND_REMOTE      4

section .text

; VRR policy hooks. Timing is driven by the compositor/frame clock; native
; backends additionally advertise BACKEND_CAP_VRR when hardware supports it.
global backend_vrr_enable
backend_vrr_enable:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    test qword [rdi + Backend.caps], BACKEND_CAP_VRR
    jz .vrr_unsupported
    xor eax, eax
    ret
.vrr_unsupported:
    mov rax, -(ENOTSUP)
    ret

global backend_vrr_disable
backend_vrr_disable:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    xor eax, eax
    ret

global backend_vrr_set_range
backend_vrr_set_range:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    test qword [rdi + Backend.caps], BACKEND_CAP_VRR
    jz .vrr_range_unsupported
    test rdx, rdx
    jz .vrr_range_invalid
    test rcx, rcx
    jz .vrr_range_invalid
    xor eax, eax
    ret
.vrr_range_unsupported:
    mov rax, -(ENOTSUP)
    ret
.vrr_range_invalid:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; backend_dpms
;   Apply display power state. Memory-only backends have no physical power
;   domain, so their state transition is an immediate success.
;   IN: rdi=backend*, rsi=output*, rdx=DPMS state (0=on, 1..3=low/off)
; ---------------------------------------------------------------------------
global backend_dpms
backend_dpms:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r13, 3
    ja .dpms_invalid
    cmp qword [rbx + Backend.state], BACKEND_NATIVE
    jne .dpms_success
    test r13, r13
    jnz .dpms_native_off
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r12 + Output.current_mode]
    test rdx, rdx
    jz .dpms_invalid
    call native_modeset
    EPILOGUE_RESTORE rbx, r12, r13
.dpms_native_off:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call native_crtc_disable
    EPILOGUE_RESTORE rbx, r12, r13
.dpms_success:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
.dpms_invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13

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
