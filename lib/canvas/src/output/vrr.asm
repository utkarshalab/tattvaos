; ============================================================================
; VRR — Variable Refresh Rate (FreeSync/G-Sync/HDMI VRR)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define VRR_FLAG_FREESYNC   (1 << 0)
%define VRR_FLAG_GSYNC      (1 << 1)
%define VRR_FLAG_HDMI_VRR   (1 << 2)
%define Output_vrr_enabled    80
%define Output.vrr_enabled 80
%define Output_vrr_flags      84
%define Output.vrr_flags 84
%define Output_vrr_caps       88
%define Output.vrr_caps 88
%define Output_vrr_min_refresh 96
%define Output.vrr_min_refresh 96
%define Output_vrr_max_refresh 104
%define Output.vrr_max_refresh 104

section .text


; ---------------------------------------------------------------------------
; vrr_init
; ---------------------------------------------------------------------------
global vrr_init
vrr_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; vrr_enable
;   Enable VRR on output
;   IN:  rdi = server*, rsi = output*, rdx = vrr_flags
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global vrr_enable
vrr_enable:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check if output supports VRR
    mov rax, [r12 + Output.vrr_caps]
    test rax, rdx
    jz .unsupported

    ; Call backend VRR enable
    mov rdi, [rbx + Server.backend]
    mov rsi, r12
    call backend_vrr_enable
    test rax, rax
    jnz .fail

    mov byte [r12 + Output.vrr_enabled], 1
    mov [r12 + Output.vrr_flags], edx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.unsupported:
    mov rax, -(ENOTSUP)
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vrr_disable
;   Disable VRR on output
; ---------------------------------------------------------------------------
global vrr_disable
vrr_disable:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Call backend VRR disable
    mov rdi, [rbx + Server.backend]
    mov rsi, r12
    call backend_vrr_disable

    mov byte [r12 + Output.vrr_enabled], 0
    mov dword [r12 + Output.vrr_flags], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vrr_get_range
;   Get VRR refresh rate range
;   IN:  rdi = output*, rsi = min_refresh_ns*, rdx = max_refresh_ns*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global vrr_get_range
vrr_get_range:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + Output.vrr_min_refresh]
    mov [r12], rax

    mov rax, [rbx + Output.vrr_max_refresh]
    mov [rdx], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vrr_set_range
;   Set VRR refresh rate range
; ---------------------------------------------------------------------------
global vrr_set_range
vrr_set_range:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + Output.vrr_min_refresh], rdx
    mov [rbx + Output.vrr_max_refresh], rcx

    ; Call backend to update range
    mov rdi, [r12 + Output.backend]
    mov rsi, r12
    call backend_vrr_set_range

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; vrr_is_active
;   Check if VRR is currently active
; ---------------------------------------------------------------------------
global vrr_is_active
vrr_is_active:
    PROLOGUE
    ASSERT_PTR rdi
    movzx rax, byte [rdi + Output.vrr_enabled]
    leave
    ret

section .data


global vrr_version
vrr_version: dq 0x010000
