; ============================================================================
; Subsurface — Subsurface Positioning and Sync
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"
%include "inc/caps.inc"

; struct offsets (hoisted above use)
%define SubsurfaceData_sync   0
%define SubsurfaceData.sync 0
%define SubsurfaceData_size   1

section .text

; ---------------------------------------------------------------------------
; subsurface_init
;   Initialize subsurface subsystem
; ---------------------------------------------------------------------------
global subsurface_init
subsurface_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.subsurface], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; subsurface_create
;   Create subsurface relationship
;   IN:  rdi = server*, rsi = child_surface*, rdx = parent_surface*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global subsurface_create
subsurface_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Add child to parent's subsurface list
    mov rax, [r13 + Surface.current + SurfaceState.subsurfaces]
    mov rdi, rax
    mov rsi, r12
    call list_push_back
    test rax, rax
    js .error

    ; Set parent pointer on child
    mov qword [r12 + Surface.role_data], r13
    mov dword [r12 + Surface.role], SURFACE_ROLE_SUBSURFACE

    ; Default: synchronized with parent
    mov byte [r12 + SubsurfaceData.sync], 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.error:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; subsurface_set_position
;   Set subsurface position relative to parent
; ---------------------------------------------------------------------------
global subsurface_set_position
subsurface_set_position:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get parent surface
    mov rax, [r12 + Surface.role_data]
    test rax, rax
    jz .error

    ; Store position in child's pending state
    mov [r12 + Surface.pending + SurfaceState.buf_x], r13d
    mov [r12 + Surface.pending + SurfaceState.buf_y], r14d

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.error:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; subsurface_set_sync
;   Set subsurface sync mode
; ---------------------------------------------------------------------------
global subsurface_set_sync
subsurface_set_sync:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov byte [r12 + SubsurfaceData.sync], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; subsurface_set_desync
;   Set subsurface desync mode
; ---------------------------------------------------------------------------
global subsurface_set_desync
subsurface_set_desync:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov byte [r12 + SubsurfaceData.sync], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; subsurface_destroy
;   Destroy subsurface relationship
; ---------------------------------------------------------------------------
global subsurface_destroy
subsurface_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Remove from parent's list
    mov rax, [r12 + Surface.role_data]
    test rax, rax
    jz .done

    mov rdi, [rax + Surface.current + SurfaceState.subsurfaces]
    mov rsi, r12
    call list_remove
    test rax, rax
    js .error

    mov qword [r12 + Surface.role_data], 0
    mov dword [r12 + Surface.role], 0

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.error:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global subsurface_version
subsurface_version: dq 0x010000