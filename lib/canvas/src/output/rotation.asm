; ============================================================================
; Output Rotation — 90/180/270 Degree Rotation Support
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern backend_modeset

%define ROTATION_NORMAL    0

section .text

%define ROTATION_90        1
%define ROTATION_180       2
%define ROTATION_270       3

; ---------------------------------------------------------------------------
; rotation_init
; ---------------------------------------------------------------------------
global rotation_init
rotation_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; rotation_apply
;   Apply rotation to output
;   IN:  rdi = server*, rsi = output*, rdx = rotation
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global rotation_apply
rotation_apply:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp rdx, 3
    ja .invalid

    mov ecx, [r12 + Output.rotation]
    mov dword [r12 + Output.rotation], edx

    ; Swap width/height for 90/270
    xor ecx, edx
    test ecx, 1
    jz .no_swap

    mov eax, [r12 + Output.width]
    mov edx, [r12 + Output.height]
    mov [r12 + Output.width], edx
    mov [r12 + Output.height], eax

    mov eax, [r12 + Output.width]
    shl rax, 2
    mov [r12 + Output.stride], rax

.no_swap:
    ; Reconfigure backend for rotation
    mov rax, [r12 + Output.current_mode]
    test rax, rax
    jz .configured
    mov rdi, [rbx + Server.backend]
    mov rsi, r12
    mov rdx, rax
    call backend_modeset
    test rax, rax
    jnz .backend_failed
.configured:

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.backend_failed:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rotation_transform_coord
;   Transform coordinate through rotation
;   IN:  rdi = output*, rsi = x, rdx = y, rcx = out_x*, r8 = out_y*
; ---------------------------------------------------------------------------
global rotation_transform_coord
rotation_transform_coord:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r14
    ASSERT_PTR r8

    mov eax, [rbx + Output.rotation]
    cmp eax, ROTATION_90
    je .rot90
    cmp eax, ROTATION_180
    je .rot180
    cmp eax, ROTATION_270
    je .rot270

    ; Normal
    mov [r14], r12d
    mov [r8], r13d
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.rot90:
    ; (x, y) -> (h - y, x)
    mov eax, [rbx + Output.height]
    sub eax, r13d
    mov [r14], eax
    mov [r8], r12d
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.rot180:
    ; (x, y) -> (w - x, h - y)
    mov eax, [rbx + Output.width]
    sub eax, r12d
    mov [r14], eax
    mov eax, [rbx + Output.height]
    sub eax, r13d
    mov [r8], eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.rot270:
    ; (x, y) -> (y, w - x)
    mov [r14], r13d
    mov eax, [rbx + Output.width]
    sub eax, r12d
    mov [r8], eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; rotation_transform_rect
;   Transform rectangle through rotation
;   IN:  rdi = output*, rsi = src_rect*, rdx = dst_rect*
; ---------------------------------------------------------------------------
global rotation_transform_rect
rotation_transform_rect:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov eax, [rbx + Output.rotation]
    cmp eax, ROTATION_90
    je .rot90
    cmp eax, ROTATION_180
    je .rot180
    cmp eax, ROTATION_270
    je .rot270

    ; Normal - copy rect
    mov rax, [r12]
    mov [r13], rax
    mov rax, [r12 + 8]
    mov [r13 + 8], rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.rot90:
    ; (x1,y1,x2,y2) -> (h-y2, x1, h-y1, x2)
    mov eax, [rbx + Output.height]
    sub eax, [r12 + 4]
    mov [r13 + 0], eax

    mov eax, [r12 + 0]
    mov [r13 + 4], eax

    mov eax, [rbx + Output.height]
    sub eax, [r12 + 0]
    mov [r13 + 8], eax

    mov eax, [r12 + 4]
    mov [r13 + 12], eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.rot180:
    ; (x1,y1,x2,y2) -> (w-x2, h-y2, w-x1, h-y1)
    mov eax, [rbx + Output.width]
    sub eax, [r12 + 8]
    mov [r13 + 0], eax

    mov eax, [rbx + Output.height]
    sub eax, [r12 + 12]
    mov [r13 + 4], eax

    mov eax, [rbx + Output.width]
    sub eax, [r12 + 0]
    mov [r13 + 8], eax

    mov eax, [rbx + Output.height]
    sub eax, [r12 + 4]
    mov [r13 + 12], eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.rot270:
    ; (x1,y1,x2,y2) -> (y1, w-x2, y2, w-x1)
    mov eax, [r12 + 4]
    mov [r13 + 0], eax

    mov eax, [rbx + Output.width]
    sub eax, [r12 + 8]
    mov [r13 + 4], eax

    mov eax, [r12 + 12]
    mov [r13 + 8], eax

    mov eax, [rbx + Output.width]
    sub eax, [r12 + 0]
    mov [r13 + 12], eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global rotation_version
rotation_version: dq 0x010000
