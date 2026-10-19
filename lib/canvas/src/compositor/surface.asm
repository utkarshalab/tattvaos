; ============================================================================
; Surface State — Buffer Management, Commit, Frame Callbacks
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/compositor.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; surface_state_init
;   Initialize surface state
; ============================================================================
global surface_state_init
surface_state_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov dword [rbx + SurfaceState.width], 0
    mov dword [rbx + SurfaceState.height], 0
    mov dword [rbx + SurfaceState.stride], 0
    mov dword [rbx + SurfaceState.transform], TRANSFORM_NORMAL
    mov dword [rbx + SurfaceState.scale], 1
    mov qword [rbx + SurfaceState.buffer], 0
    mov qword [rbx + SurfaceState.damage], 0
    mov qword [rbx + SurfaceState.frame_cbs], 0

    ; Init damage
    lea rdi, [rbx + SurfaceState.damage]
    call damage_init

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; surface_state_destroy
;   Cleanup surface state
; ============================================================================
global surface_state_destroy
surface_state_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    lea rdi, [rbx + SurfaceState.damage]
    call damage_destroy

    ; Frame callbacks handled by compositor

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; surface_attach_buffer
;   Attach buffer to surface (pending state)
; ============================================================================
global surface_attach_buffer
surface_attach_buffer:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; buffer*
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Store buffer in pending state
    mov [rbx + SurfaceState.pending + SurfaceState.buffer], r12

    ; Get buffer dimensions
    mov eax, [r12 + Buffer.width]
    mov [rbx + SurfaceState.pending + SurfaceState.width], eax
    mov eax, [r12 + Buffer.height]
    mov [rbx + SurfaceState.pending + SurfaceState.height], eax
    mov eax, [r12 + Buffer.stride]
    mov [rbx + SurfaceState.pending + SurfaceState.stride], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; surface_damage
;   Add damage to surface
; ============================================================================
global surface_damage
surface_damage:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    lea rdi, [rbx + SurfaceState.damage]
    call damage_add_rect

    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; surface_commit
;   Commit pending state to current
; ============================================================================
global surface_commit
surface_commit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; serial
    ASSERT_PTR rbx

    ; Swap pending -> current
    mov rax, [rbx + SurfaceState.pending + SurfaceState.buffer]
    mov [rbx + SurfaceState.buffer], rax

    mov eax, [rbx + SurfaceState.pending + SurfaceState.width]
    mov [rbx + SurfaceState.width], eax
    mov eax, [rbx + SurfaceState.pending + SurfaceState.height]
    mov [rbx + SurfaceState.height], eax
    mov eax, [rbx + SurfaceState.pending + SurfaceState.stride]
    mov [rbx + SurfaceState.stride], eax

    ; Swap damage
    mov rax, [rbx + SurfaceState.pending + SurfaceState.damage]
    mov [rbx + SurfaceState.damage], rax

    ; Store serial
    mov [rbx + SurfaceState.frame_cbs], r12

    ; Trigger frame callbacks
    call .fire_frame_callbacks

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.fire_frame_callbacks:
    ; Fire all pending frame callbacks
    mov rax, [rbx + SurfaceState.frame_cbs]
    test rax, rax
    jz .done

    ; Iterate callbacks and fire
    ; ... implementation

.done:
    ret

; ============================================================================
; surface_get_buffer
;   Get current buffer
; ============================================================================
global surface_get_buffer
surface_get_buffer:
    PROLOGUE
    mov rax, [rdi + SurfaceState.buffer]
    leave
    ret

; ============================================================================
; surface_get_size
;   Get surface size
; ============================================================================
global surface_get_size
surface_get_size:
    PROLOGUE
    mov eax, [rdi + SurfaceState.width]
    mov edx, [rdi + SurfaceState.height]
    leave
    ret

; ============================================================================
; surface_set_transform
;   Set surface transform
; ============================================================================
global surface_set_transform
surface_set_transform:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp esi, TRANSFORM_NORMAL
    je .valid
    cmp esi, TRANSFORM_90
    je .valid
    cmp esi, TRANSFORM_180
    je .valid
    cmp esi, TRANSFORM_270
    je .valid
    cmp esi, TRANSFORM_FLIPPED
    je .valid
    cmp esi, TRANSFORM_FLIPPED_90
    je .valid
    cmp esi, TRANSFORM_FLIPPED_180
    je .valid
    cmp esi, TRANSFORM_FLIPPED_270
    je .valid
    mov rax, -EINVAL
    leave
    ret

.valid:
    mov dword [rbx + SurfaceState.transform], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; surface_set_scale
;   Set surface scale factor
; ============================================================================
global surface_set_scale
surface_set_scale:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    test esi, esi
    jz .invalid
    cmp esi, 8
    jg .invalid

    mov dword [rbx + SurfaceState.scale], esi
    xor rax, rax
    leave
    ret

.invalid:
    mov rax, -EINVAL
    leave
    ret

; ============================================================================
; frame_callback_init
;   Initialize frame callback
; ============================================================================
global frame_callback_init
frame_callback_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi  ; surface
    mov r13d, edx ; seq
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov [rbx + FrameCallback.surface], r12
    mov dword [rbx + FrameCallback.seq], r13d
    mov qword [rbx + FrameCallback.timestamp], 0
    mov qword [rbx + FrameCallback.next], 0

    ; Add to surface callback list
    mov rax, [r12 + SurfaceState.frame_cbs]
    mov [rbx + FrameCallback.next], rax
    mov [r12 + SurfaceState.frame_cbs], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global surface_state_version
surface_state_version: dq 0x010000