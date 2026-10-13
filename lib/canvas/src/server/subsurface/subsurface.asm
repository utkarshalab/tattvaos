; ============================================================================
; Subsurface — Subsurface Positioning and Sync
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

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
    PROLOGUE
    xor rax, rax
    leave
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
    TEST_ASSERT_OK rax

    ; Set parent pointer on child
    mov qword [r12 + Surface.role_data], r13
    mov dword [r12 + Surface.role], SURFACE_ROLE_SUBSURFACE

    ; Default: synchronized with parent
    mov byte [r12 + SubsurfaceData.sync], 1

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; subsurface_set_position
;   Set subsurface position relative to parent
;   IN:  rdi = server*, rsi = surface*, rdx = x, rcx = y
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global subsurface_set_position
subsurface_set_position:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov rax, [rsi + Surface.pending]
    mov dword [rax + SurfaceState.buf_x], edx
    mov dword [rax + SurfaceState.buf_y], ecx
    mov byte [rax + SurfaceState.pending], 1
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; subsurface_set_sync
;   Set sync mode (synchronized with parent commit)
; ---------------------------------------------------------------------------
global subsurface_set_sync
subsurface_set_sync:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov byte [rsi + SubsurfaceData.sync], 1
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; subsurface_set_desync
;   Set desync mode (independent commit)
; ---------------------------------------------------------------------------
global subsurface_set_desync
subsurface_set_desync:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov byte [rsi + SubsurfaceData.sync], 0
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; subsurface_destroy
;   Remove subsurface relationship
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
    TEST_ASSERT_OK rax

    mov qword [r12 + Surface.role_data], 0
    mov dword [r12 + Surface.role], 0

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data


global subsurface_version
subsurface_version: dq 0x010000
