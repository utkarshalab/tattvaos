; ============================================================================
; Magnifier — Screen Magnification for Accessibility
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/fixed.inc"
%include "inc/server_offsets.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define MAGNIFIER_MIN_SCALE    0x10000      ; 1.0
%define MAGNIFIER_MAX_SCALE    0x100000     ; 16.0

section .text

struc Magnifier
    .enabled:           resb 1
    .scale:             resq 1
    .follow_mouse:      resb 1
    .follow_focus:      resb 1
    .fullscreen:        resb 1
    .x:                 resd 1
    .y:                 resd 1
    .width:             resd 1
    .height:            resd 1
    .source_output:     resq 1
    .target_output:     resq 1
endstruc


; ---------------------------------------------------------------------------
; magnifier_init
; ---------------------------------------------------------------------------
global magnifier_init
magnifier_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, Magnifier_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov byte [rbx + Magnifier.enabled], 0
    mov qword [rbx + Magnifier.scale], FIX_ONE * 2
    mov byte [rbx + Magnifier.follow_mouse], 1
    mov byte [rbx + Magnifier.follow_focus], 1
    mov byte [rbx + Magnifier.fullscreen], 0
    mov dword [rbx + Magnifier.x], 0
    mov dword [rbx + Magnifier.y], 0
    mov dword [rbx + Magnifier.width], 0
    mov dword [rbx + Magnifier.height], 0
    mov qword [rbx + Magnifier.source_output], 0
    mov qword [rbx + Magnifier.target_output], 0

    mov qword [rdi + Server.magnifier], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; magnifier_enable
; ---------------------------------------------------------------------------
global magnifier_enable
magnifier_enable:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov byte [rbx + Magnifier.enabled], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; magnifier_disable
; ---------------------------------------------------------------------------
global magnifier_disable
magnifier_disable:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov byte [rbx + Magnifier.enabled], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; magnifier_set_scale
; ---------------------------------------------------------------------------
global magnifier_set_scale
magnifier_set_scale:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp rsi, MAGNIFIER_MIN_SCALE
    jb .too_small
    cmp rsi, MAGNIFIER_MAX_SCALE
    ja .too_large

    mov qword [rbx + Magnifier.scale], rsi
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.too_small:
    mov rax, -(ERANGE)
    EPILOGUE_RESTORE rbx
    ret
.too_large:
    mov rax, -(ERANGE)
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; magnifier_set_mode
; ---------------------------------------------------------------------------
global magnifier_set_mode
magnifier_set_mode:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp rsi, 0
    je .set_fullscreen
    cmp rsi, 1
    je .set_windowed
    cmp rsi, 2
    je .set_follow_mouse
    cmp rsi, 3
    je .set_follow_focus
    jmp .invalid

.set_fullscreen:
    mov byte [rbx + Magnifier.fullscreen], 1
    EPILOGUE_RESTORE rbx
    ret
.set_windowed:
    mov byte [rbx + Magnifier.fullscreen], 0
    EPILOGUE_RESTORE rbx
    ret
.set_follow_mouse:
    mov byte [rbx + Magnifier.follow_mouse], dl
    EPILOGUE_RESTORE rbx
    ret
.set_follow_focus:
    mov byte [rbx + Magnifier.follow_focus], dl
    EPILOGUE_RESTORE rbx
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; magnifier_update
;   Update magnifier position
; ---------------------------------------------------------------------------
global magnifier_update
magnifier_update:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp byte [rbx + Magnifier.enabled], 0
    je .done

    ; Get mouse position if following
    cmp byte [rbx + Magnifier.follow_mouse], 0
    je .check_focus

    mov r12, [rbx + Server.default_seat]
    test r12, r12
    je .check_focus

    mov r12, [r12 + Seat.pointer]
    mov eax, [r12 + Pointer.x]
    mov [rbx + Magnifier.x], eax
    mov eax, [r12 + Pointer.y]
    mov [rbx + Magnifier.y], eax
    jmp .update_window

.check_focus:
    cmp byte [rbx + Magnifier.follow_focus], 0
    je .update_window

    mov r12, [rbx + Server.focus]
    test r12, r12
    je .update_window

    mov rax, [r12 + Focus.surface]
    test rax, rax
    je .update_window

    mov r13, [rax + Surface.current + SurfaceState.buf_x]
    mov [rbx + Magnifier.x], r13d
    mov r13, [rax + Surface.current + SurfaceState.buf_y]
    mov [rbx + Magnifier.y], r13d

.update_window:
    ; Update magnifier window position/size
    ; TODO: Call backend to update magnifier window

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; magnifier_render
;   Render magnified view
; ---------------------------------------------------------------------------
global magnifier_render
magnifier_render:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    ; TODO: Render magnified region
    ; 1. Get source region from output
    ; 2. Scale by magnifier.scale
    ; 3. Render to magnifier window

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global magnifier_version
magnifier_version: dq 0x010000
