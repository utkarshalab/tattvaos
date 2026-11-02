; ============================================================================
; Framebuffer Linear Backend — Complete Implementation
; Simple linear framebuffer (VBE/UEFI GOP)
; ============================================================================
; The compositor draws into an output's framebuffer in ordinary memory, the
; same as headless. After a frame, fb_linear_flip copies each damaged rectangle
; to the real framebuffer, whose rows may be longer than the output's: reading
; display memory is slow, so it is only ever written. Pixels are 32-bit BGRX.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/fixed.inc"
%include "inc/image.inc"
%include "inc/color.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern headless_create_virtual_output
extern headless_deinit
extern memcopy

section .text

; ---------------------------------------------------------------------------
; fb_linear_init
;   Initialize linear framebuffer backend
;   IN:  rdi = backend* (arena and server already set), rsi = config*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global fb_linear_init
fb_linear_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r13, [rbx + Backend.arena]
    mov r14, [rbx + Backend.server]

    mov rax, -(EINVAL)
    cmp qword [r12 + Config.fb_base], 0
    je .out
    cmp dword [r12 + Config.fb_width], 0
    je .out
    cmp dword [r12 + Config.fb_height], 0
    je .out
    mov ecx, [r12 + Config.fb_width]
    shl ecx, 2
    cmp [r12 + Config.fb_stride], ecx
    jb .out                             ; rows too short for 32-bit pixels

    ; Zero backend state
    mov rdi, rbx
    mov rcx, Backend_size
    xor eax, eax
    rep stosb

    mov [rbx + Backend.arena], r13
    mov [rbx + Backend.server], r14
    mov [rbx + Backend.config], r12
    mov rax, [r12 + Config.fb_base]
    mov [rbx + Backend.fb_base], rax
    mov rax, [r12 + Config.fb_size]
    mov [rbx + Backend.fb_size], rax
    lea rax, [rel fb_linear_flip]
    mov [rbx + Backend.flip], rax

    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; fb_linear_create_output
;   The one output, the size of the framebuffer
;   IN:  rdi = backend*
;   OUT: rax = output*, 0 on error
; ---------------------------------------------------------------------------
global fb_linear_create_output
fb_linear_create_output:
    ASSERT_PTR rdi
    mov rax, [rdi + Backend.config]
    mov esi, [rax + Config.fb_width]
    mov edx, [rax + Config.fb_height]
    mov ecx, DRM_FORMAT_BGRA8888
    jmp headless_create_virtual_output

; ---------------------------------------------------------------------------
; fb_linear_deinit
; ---------------------------------------------------------------------------
global fb_linear_deinit
fb_linear_deinit:
    jmp headless_deinit

; ---------------------------------------------------------------------------
; fb_linear_modeset
;   The framebuffer has the one mode the firmware set
;   IN:  rdi = backend*, rsi = output*, rdx = mode*
;   OUT: rax = 0 OK, -EINVAL
; ---------------------------------------------------------------------------
global fb_linear_modeset
fb_linear_modeset:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    ASSERT_PTR rdx
    mov eax, [rdx + Mode.width]
    cmp eax, [rsi + Output.width]
    jne .bad_mode
    mov eax, [rdx + Mode.height]
    cmp eax, [rsi + Output.height]
    jne .bad_mode
    mov [rsi + Output.current_mode], rdx
    xor eax, eax
    ret
.bad_mode:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; fb_linear_flip
;   Copy the frame's damage to the framebuffer
;   IN:  rdi = backend*, rsi = output*, rdx = damage region*, rcx = fence (unused)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global fb_linear_flip
fb_linear_flip:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 24                         ; next rect index, width in bytes
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    mov qword [rsp], 0
.rect:
    mov rax, [rsp]
    cmp rax, [r13 + Region.count]
    jae .done
    inc qword [rsp]
    shl rax, 4
    add rax, [r13 + Region.rects]

    ; Clip to the output
    movsxd rcx, dword [rax]             ; left
    movsxd rdx, dword [rax + 4]         ; top
    movsxd r8, dword [rax + 8]
    add r8, rcx                         ; right
    movsxd r9, dword [rax + 12]
    add r9, rdx                         ; bottom
    xor eax, eax
    test rcx, rcx
    cmovs rcx, rax
    test rdx, rdx
    cmovs rdx, rax
    mov eax, [r12 + Output.width]
    cmp r8, rax
    cmovg r8, rax
    mov eax, [r12 + Output.height]
    cmp r9, rax
    cmovg r9, rax
    sub r8, rcx
    jle .rect
    sub r9, rdx
    jle .rect

    shl r8, 2
    mov [rsp + 8], r8                   ; bytes in a row
    mov r15, r9                         ; rows

    mov rax, [rbx + Backend.config]
    mov r14d, [rax + Config.fb_stride]
    imul r14, rdx
    lea r14, [r14 + rcx * 4]
    add r14, [rbx + Backend.fb_base]    ; destination
    imul rdx, [r12 + Output.stride]
    lea rax, [rdx + rcx * 4]
    add rax, [r12 + Output.framebuffer]
    mov [rsp + 16], rax                 ; source
.row:
    mov rdi, r14
    mov rsi, [rsp + 16]
    mov rdx, [rsp + 8]
    call memcopy
    mov rax, [rbx + Backend.config]
    mov eax, [rax + Config.fb_stride]
    add r14, rax
    mov rax, [r12 + Output.stride]
    add [rsp + 16], rax
    dec r15
    jnz .row
    jmp .rect
.done:
    xor eax, eax
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; fb_linear_vblank_wait
;   The firmware's framebuffer has no vblank to wait for
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global fb_linear_vblank_wait
fb_linear_vblank_wait:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; fb_linear_hotplug
; ---------------------------------------------------------------------------
global fb_linear_hotplug
fb_linear_hotplug:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; fb_linear_cursor
;   Software cursor: track position
;   IN:  rdi = backend*, rcx = x, r8 = y
; ---------------------------------------------------------------------------
global fb_linear_cursor
fb_linear_cursor:
    ASSERT_PTR rdi
    mov [rdi + Backend.cursor_x], ecx
    mov [rdi + Backend.cursor_y], r8d
    xor eax, eax
    ret

section .data
global fb_linear_backend_version
fb_linear_backend_version: dq 0x010100
