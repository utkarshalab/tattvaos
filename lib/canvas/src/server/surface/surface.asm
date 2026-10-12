; ============================================================================
; Surface — Core Surface with Double-Buffered State
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; surface_init
;   Initialize surface subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global surface_init
surface_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.surface_table], 0
    mov qword [rbx + Server.arena], r12
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_create
;   Create surface
;   IN:  rdi = server*, rsi = client*, rdx = role (optional)
;   OUT: rax = surface_handle, negative error
; ---------------------------------------------------------------------------
global surface_create
surface_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate surface
    ; Surface includes double-buffered state (current + pending)
    mov rdi, [rbx + Server.arena]
    mov rsi, 256   ; Surface struct with state
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax        ; surface*

    ; Initialize surface
    mov qword [r14 + Surface.id], 0
    mov dword [r14 + Surface.role], 0
    mov qword [r14 + Surface.role_data], 0
    mov dword [r14 + Surface.output], 0
    mov qword [r14 + Surface.z_order], 0
    mov qword [r14 + Surface.client], r12

    ; Initialize current state
    mov qword [r14 + Surface.current + SurfaceState.buffer], 0
    mov dword [r14 + Surface.current + SurfaceState.buf_x], 0
    mov dword [r14 + Surface.current + SurfaceState.buf_y], 0
    mov qword [r14 + Surface.current + SurfaceState.damage], 0
    mov qword [r14 + Surface.current + SurfaceState.opaque], 0
    mov qword [r14 + Surface.current + SurfaceState.input], 0
    mov dword [r14 + Surface.current + SurfaceState.transform], 0
    mov qword [r14 + Surface.current + SurfaceState.scale], FIX_ONE
    mov qword [r14 + Surface.current + SurfaceState.subsurfaces], 0
    mov qword [r14 + Surface.current + SurfaceState.frame_cbs], 0
    mov byte [r14 + Surface.current + SurfaceState.pending], 0

    ; Initialize pending state (same)
    mov qword [r14 + Surface.pending + SurfaceState.buffer], 0
    mov dword [r14 + Surface.pending + SurfaceState.buf_x], 0
    mov dword [r14 + Surface.pending + SurfaceState.buf_y], 0
    mov qword [r14 + Surface.pending + SurfaceState.damage], 0
    mov qword [r14 + Surface.pending + SurfaceState.opaque], 0
    mov qword [r14 + Surface.pending + SurfaceState.input], 0
    mov dword [r14 + Surface.pending + SurfaceState.transform], 0
    mov qword [r14 + Surface.pending + SurfaceState.scale], FIX_ONE
    mov qword [r14 + Surface.pending + SurfaceState.subsurfaces], 0
    mov qword [r14 + Surface.pending + SurfaceState.frame_cbs], 0
    mov byte [r14 + Surface.pending + SurfaceState.pending], 0

    ; Create damage region
    mov rdi, [rbx + Server.arena]
    mov rsi, [rbx + Server.arena]
    mov rdx, 8
    call region_init
    test rax, rax
    jnz .damage_ok
    jmp .oom

.damage_ok:
    mov qword [r14 + Surface.current + SurfaceState.damage], rax
    mov qword [r14 + Surface.pending + SurfaceState.damage], rax

    ; Create opaque region
    mov rdi, [rbx + Server.arena]
    mov rsi, [rbx + Server.arena]
    mov rdx, 8
    call region_init
    test rax, rax
    jnz .opaque_ok
    jmp .oom

.opaque_ok:
    mov qword [r14 + Surface.current + SurfaceState.opaque], rax
    mov qword [r14 + Surface.pending + SurfaceState.opaque], rax

    ; Create input region
    mov rdi, [rbx + Server.arena]
    mov rsi, [rbx + Server.arena]
    mov rdx, 8
    call region_init
    test rax, rax
    jnz .input_ok
    jmp .oom

.input_ok:
    mov qword [r14 + Surface.current + SurfaceState.input], rax
    mov qword [r14 + Surface.pending + SurfaceState.input], rax

    ; Create subsurface list
    mov rdi, [rbx + Server.arena]
    mov rsi, [rbx + Server.arena]
    call list_init
    test rax, rax
    jnz .sub_ok
    jmp .oom

.sub_ok:
    mov qword [r14 + Surface.current + SurfaceState.subsurfaces], rax
    mov qword [r14 + Surface.pending + SurfaceState.subsurfaces], rax

    ; Create frame callback list
    mov rdi, [rbx + Server.arena]
    mov rsi, [rbx + Server.arena]
    call list_init
    test rax, rax
    jnz .fc_ok
    jmp .oom

.fc_ok:
    mov qword [r14 + Surface.current + SurfaceState.frame_cbs], rax
    mov qword [r14 + Surface.pending + SurfaceState.frame_cbs], rax

    ; Create handle
    mov rdi, [rbx + Server.surface_table]
    mov rsi, r14
    call handle_create
    test rax, rax
    jz .oom
    mov [r14 + Surface.id], eax

    mov rax, [r14 + Surface.id]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; surface_destroy
;   Destroy surface
; ---------------------------------------------------------------------------
global surface_destroy
surface_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.surface_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov rbx, rax

    ; Destroy regions
    mov rdi, [rbx + Surface.current + SurfaceState.damage]
    call region_destroy
    mov rdi, [rbx + Surface.current + SurfaceState.opaque]
    call region_destroy
    mov rdi, [rbx + Surface.current + SurfaceState.input]
    call region_destroy

    ; Destroy handle
    mov rdi, [rdi + Server.surface_table]
    mov rsi, r12
    call handle_destroy

    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; surface_attach
;   Attach buffer to surface
;   IN:  rdi = server*, rsi = surface*, rdx = buffer_handle, rcx = x, r8 = y
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global surface_attach
surface_attach:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .bad_buffer

    ; Set on pending state
    mov rax, [r12 + Surface.pending]
    mov qword [rax + SurfaceState.buffer], r13
    mov dword [rax + SurfaceState.buf_x], r14d
    mov dword [rax + SurfaceState.buf_y], r8d
    mov byte [rax + SurfaceState.pending], 1

    xor rax, rax
    ret

.bad_buffer:
    RETURN_ERROR EBUF_FORMAT

; ---------------------------------------------------------------------------
; surface_damage
;   Add damage rect to surface
;   IN:  rdi = server*, rsi = surface*, rdx = x, rcx = y, r8 = w, r9 = h
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global surface_damage
surface_damage:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [r12 + Surface.pending]
    mov rdi, [rax + SurfaceState.damage]
    mov rsi, r13d
    mov rdx, r14d
    mov rcx, r15d
    mov r8, r9d
    call region_add_rect
    test rax, rax
    jnz .fail

    mov byte [rax + SurfaceState.pending], 1
    xor rax, rax
    ret

.fail:
    RETURN_ERROR ESURF_DAMAGE

; ---------------------------------------------------------------------------
; surface_set_opaque_region
;   Set opaque region
; ---------------------------------------------------------------------------
global surface_set_opaque_region
surface_set_opaque_region:
    PROLOGUE
    ; TODO
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_set_input_region
;   Set input region
; ---------------------------------------------------------------------------
global surface_set_input_region
surface_set_input_region:
    PROLOGUE
    ; TODO
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_set_transform
;   Set transform
;   IN:  rdi = server*, rsi = surface*, rdx = transform
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global surface_set_transform
surface_set_transform:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov rax, [rsi + Surface.pending]
    mov dword [rax + SurfaceState.transform], edx
    mov byte [rax + SurfaceState.pending], 1
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_set_scale
;   Set scale (fixed-point 16.16)
; ---------------------------------------------------------------------------
global surface_set_scale
surface_set_scale:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi

    mov rax, [rsi + Surface.pending]
    mov qword [rax + SurfaceState.scale], rdx
    mov byte [rax + SurfaceState.pending], 1
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_frame_callback
;   Request frame callback
; ---------------------------------------------------------------------------
global surface_frame_callback
surface_frame_callback:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create callback object
    ; TODO

    xor rax, rax
    ret

section .data

%define Surface_id            0
%define Surface_role          8
%define Surface_role_data     16
%define Surface_output        24
%define Surface_z_order       32
%define Surface_client        40
%define Surface_current       48
%define Surface_pending       176
%define Surface_size          304

%define SurfaceState_buffer      0
%define SurfaceState_buf_x       8
%define SurfaceState_buf_y       12
%define SurfaceState_damage      16
%define SurfaceState_opaque      24
%define SurfaceState_input       32
%define SurfaceState_transform   40
%define SurfaceState_scale       44
%define SurfaceState_subsurfaces 52
%define SurfaceState_frame_cbs   60
%define SurfaceState_pending     68
%define SurfaceState_size        72

%define SURFACE_ROLE_NONE      0
%define SURFACE_ROLE_TOPLEVEL  1
%define SURFACE_ROLE_POPUP     2
%define SURFACE_ROLE_LAYER     3
%define SURFACE_ROLE_SUBSURFACE 4

global surface_version
surface_version: dq 0x010000