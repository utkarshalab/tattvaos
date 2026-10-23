; ============================================================================
; Magnifier — Screen Magnification for Accessibility
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
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
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, Magnifier_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    mov byte [r13 + Magnifier.enabled], 0
    mov qword [r13 + Magnifier.scale], FIX_ONE * 2
    mov byte [r13 + Magnifier.follow_mouse], 1
    mov byte [r13 + Magnifier.follow_focus], 1
    mov byte [r13 + Magnifier.fullscreen], 0
    mov dword [r13 + Magnifier.x], 0
    mov dword [r13 + Magnifier.y], 0
    mov dword [r13 + Magnifier.width], 0
    mov dword [r13 + Magnifier.height], 0
    mov qword [r13 + Magnifier.source_output], 0
    mov qword [r13 + Magnifier.target_output], 0

    mov qword [rbx + Server.magnifier], r13
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
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
    ; Keep the sampled point inside the source output; rendering consumes the
    ; stored coordinates on the next compositor frame.
    mov r12, [rbx + Magnifier.source_output]
    test r12, r12
    jz .done
    mov eax, [rbx + Magnifier.x]
    cmp eax, [r12 + Output.x]
    jge .x_low_ok
    mov eax, [r12 + Output.x]
.x_low_ok:
    mov ecx, [r12 + Output.x]
    add ecx, [r12 + Output.width]
    dec ecx
    cmp eax, ecx
    cmovg eax, ecx
    mov [rbx + Magnifier.x], eax
    mov eax, [rbx + Magnifier.y]
    cmp eax, [r12 + Output.y]
    jge .y_low_ok
    mov eax, [r12 + Output.y]
.y_low_ok:
    mov ecx, [r12 + Output.y]
    add ecx, [r12 + Output.height]
    dec ecx
    cmp eax, ecx
    cmovg eax, ecx
    mov [rbx + Magnifier.y], eax

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
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    cmp byte [rbx + Magnifier.enabled], 0
    je .render_done
    mov r14, [r12 + PixBuf.data]
    mov r15, [r13 + PixBuf.data]
    test r14, r14
    jz .render_bad
    test r15, r15
    jz .render_bad
    xor r8d, r8d                  ; destination y
.row:
    cmp r8d, [r13 + PixBuf.height]
    jae .render_done
    mov eax, r8d
    shl rax, 16
    xor edx, edx
    div qword [rbx + Magnifier.scale]
    add eax, [rbx + Magnifier.y]
    cmp eax, [r12 + PixBuf.height]
    jae .render_done
    imul rax, [r12 + PixBuf.stride]
    lea r9, [r14 + rax]
    mov eax, r8d
    imul rax, [r13 + PixBuf.stride]
    lea r10, [r15 + rax]
    xor r11d, r11d
.col:
    cmp r11d, [r13 + PixBuf.width]
    jae .next_row
    mov eax, r11d
    shl rax, 16
    xor edx, edx
    div qword [rbx + Magnifier.scale]
    add eax, [rbx + Magnifier.x]
    cmp eax, [r12 + PixBuf.width]
    jae .next_row
    mov eax, [r9 + rax * 4]
    mov [r10 + r11 * 4], eax
    inc r11d
    jmp .col
.next_row:
    inc r8d
    jmp .row
.render_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.render_done:

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global magnifier_version
magnifier_version: dq 0x010000
