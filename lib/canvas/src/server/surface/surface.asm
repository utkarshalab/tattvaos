; ============================================================================
; Surface — Core Surface with Double-Buffered State
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/caps.inc"

extern arena_alloc
extern handle_table_create
extern handle_create
extern handle_destroy
extern handle_resolve
extern list_init
extern list_push_back
extern region_init
extern region_destroy
extern region_clear
extern region_copy
extern region_add_rect
extern compositor_remove_surface
extern presentation_forget
extern stacking_destroyed
extern window_destroy
extern window_parent_gone

%define SURFACE_HANDLES        4096

%define SURFACE_ROLE_NONE      0
%define SURFACE_ROLE_TOPLEVEL  1
%define SURFACE_ROLE_POPUP     2
%define SURFACE_ROLE_LAYER     3
%define SURFACE_ROLE_SUBSURFACE 4

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

    mov [rbx + Server.arena], r12
    mov rdi, r12
    mov esi, SURFACE_HANDLES
    call handle_table_create
    mov [rbx + Server.surface_table], rax
    test rax, rax
    mov rax, -(ENOMEM)
    mov ecx, 0
    cmovnz rax, rcx
    EPILOGUE_RESTORE rbx, r12
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
    mov r15, [r12 + Client.arena]       ; a surface lives with its client

    ; Allocate surface
    ; Surface includes double-buffered state (current + pending)
    mov rdi, r15
    mov rsi, Surface_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax        ; surface*

    ; Initialize surface
    mov rdi, rax
    xor eax, eax
    mov ecx, Surface_size
    rep stosb
    mov [r14 + Surface.role], r13
    mov [r14 + Surface.client], r12

    ; Initialize current state
    mov qword [r14 + Surface.current + SurfaceState.scale], FIX_ONE

    ; Initialize pending state (same)
    mov qword [r14 + Surface.pending + SurfaceState.scale], FIX_ONE

    ; Create damage region
    mov rdi, r15
    call region_init
    test rax, rax
    jnz .damage_ok
    jmp .oom

.damage_ok:
    mov qword [r14 + Surface.current + SurfaceState.damage], rax
    mov rdi, r15
    call region_init
    test rax, rax
    jz .oom
    mov qword [r14 + Surface.pending + SurfaceState.damage], rax

    ; Create opaque region
    mov rdi, r15
    call region_init
    test rax, rax
    jnz .opaque_ok
    jmp .oom

.opaque_ok:
    mov qword [r14 + Surface.current + SurfaceState.opaque], rax
    mov rdi, r15
    call region_init
    test rax, rax
    jz .oom
    mov qword [r14 + Surface.pending + SurfaceState.opaque], rax

    ; Create input region
    mov rdi, r15
    call region_init
    test rax, rax
    jnz .input_ok
    jmp .oom

.input_ok:
    mov qword [r14 + Surface.current + SurfaceState.input], rax
    mov rdi, r15
    call region_init
    test rax, rax
    jz .oom
    mov qword [r14 + Surface.pending + SurfaceState.input], rax

    ; Create subsurface list
    mov rdi, r15
    mov rsi, 24
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    call list_init
    mov qword [r14 + Surface.current + SurfaceState.subsurfaces], r13
    mov rdi, r15
    mov rsi, 24
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    call list_init
    mov qword [r14 + Surface.pending + SurfaceState.subsurfaces], r13

    ; Create frame callback list
    mov rdi, r15
    mov rsi, 24
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    call list_init
    mov qword [r14 + Surface.current + SurfaceState.frame_cbs], r13
    mov rdi, r15
    mov rsi, 24
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    call list_init
    mov qword [r14 + Surface.pending + SurfaceState.frame_cbs], r13

    ; Create handle
    mov rdi, [rbx + Server.surface_table]
    mov rsi, r14
    call handle_create
    test rax, rax
    jz .oom
    mov [r14 + Surface.id], rax
    mov rcx, [r12 + Client.surfaces]
    mov [r14 + Surface.client_next], rcx
    mov [r12 + Client.surfaces], r14
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; surface_destroy
;   Destroy surface; its memory stays with the client until it leaves
;   IN:  rdi = server*, rsi = surface_handle
;   OUT: rax = 0 OK, -ENOENT
; ---------------------------------------------------------------------------
global surface_destroy
surface_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.surface_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov r13, rax

    ; Its popups done, no role, out of input focus, off its output, and any
    ; outstanding feedback
    mov rdi, rbx
    mov rsi, r13
    call window_parent_gone
    mov rdi, rbx
    mov rsi, r13
    call window_destroy                 ; -EINVAL if it had none: fine
    mov rdi, rbx
    mov rsi, r13
    call stacking_destroyed
    mov rdi, rbx
    mov rsi, r13
    call compositor_remove_surface
    mov rdi, r13
    call presentation_forget

    ; Off the client's list
    mov rcx, [r13 + Surface.client]
    lea rcx, [rcx + Client.surfaces]
.find:
    mov rax, [rcx]
    test rax, rax
    jz .unlinked
    cmp rax, r13
    je .unlink
    lea rcx, [rax + Surface.client_next]
    jmp .find
.unlink:
    mov rax, [r13 + Surface.client_next]
    mov [rcx], rax
.unlinked:

    ; Destroy regions
    mov rdi, [r13 + Surface.current + SurfaceState.damage]
    call region_destroy
    mov rdi, [r13 + Surface.current + SurfaceState.opaque]
    call region_destroy
    mov rdi, [r13 + Surface.current + SurfaceState.input]
    call region_destroy

    ; Destroy handle
    mov rdi, [rbx + Server.surface_table]
    mov rsi, r12
    call handle_destroy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; surface_destroy_client
;   Destroy every surface of a client
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global surface_destroy_client
surface_destroy_client:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
.next:
    mov rax, [r12 + Client.surfaces]
    test rax, rax
    jz .done
    mov rdi, rbx
    mov rsi, [rax + Surface.id]
    call surface_destroy
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; surface_attach
;   Attach buffer to surface
;   IN:  rdi = server*, rsi = surface*, rdx = buffer_handle, rcx = x, r8 = y
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global surface_attach
surface_attach:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13                       ; 0: detach
    jz .set
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .bad_buffer

.set:
    ; Set on pending state
    lea rax, [r12 + Surface.pending]
    mov qword [rax + SurfaceState.buffer], r13
    mov dword [rax + SurfaceState.buf_x], r14d
    mov dword [rax + SurfaceState.buf_y], r15d
    mov dword [rax + SurfaceState.pending], 1

    xor rax, rax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.bad_buffer:
    mov rax, -(EBUF_FORMAT)
    jmp .out

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

    lea r13, [r12 + Surface.pending]
    sub rsp, 24                         ; the rect; 16-byte aligned
    mov dword [rsp], edx
    mov dword [rsp + 4], ecx
    mov dword [rsp + 8], r8d
    mov dword [rsp + 12], r9d
    mov rdi, [r13 + SurfaceState.damage]
    mov rsi, rsp
    call region_add_rect
    test rax, rax
    jnz .fail
    mov dword [r13 + SurfaceState.pending], 1
    xor rax, rax
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.fail:
    mov rax, -(ESURF_DAMAGE)
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; surface_set_opaque_region
;   The opaque region for the next commit: a copy of a region, or none
;   IN:  rdi = server*, rsi = surface*, rdx = Region* (0: none)
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global surface_set_opaque_region
surface_set_opaque_region:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    test rdx, rdx
    jz .clear
    mov rsi, rdx
    lea rax, [r12 + Surface.pending]
    mov rdi, [rax + SurfaceState.opaque]
    call region_copy
    test rax, rax
    js .out
    jmp .mark
.clear:
    lea rax, [r12 + Surface.pending]
    mov rdi, [rax + SurfaceState.opaque]
    call region_clear
.mark:
    mov dword [r12 + Surface.pending + SurfaceState.pending], 1
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; surface_set_input_region
;   The input region for the next commit: a copy of a region, or none (the
;   whole surface takes input)
;   IN:  rdi = server*, rsi = surface*, rdx = Region* (0: none)
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global surface_set_input_region
surface_set_input_region:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    test rdx, rdx
    jz .clear
    mov rsi, rdx
    mov rdi, [r12 + Surface.pending + SurfaceState.input]
    call region_copy
    test rax, rax
    js .out
    jmp .mark
.clear:
    mov rdi, [r12 + Surface.pending + SurfaceState.input]
    call region_clear
.mark:
    mov dword [r12 + Surface.pending + SurfaceState.pending], 1
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12
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

    lea rax, [rsi + Surface.pending]
    cmp edx, 5
    ja .invalid_transform
    mov dword [rax + SurfaceState.transform], edx
    mov dword [rax + SurfaceState.pending], 1
    xor rax, rax
    leave
    ret
.invalid_transform:
    mov rax, -(EINVAL)
    leave
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

    test rdx, rdx
    jle .invalid_scale
    lea rax, [rsi + Surface.pending]
    mov qword [rax + SurfaceState.scale], rdx
    mov dword [rax + SurfaceState.pending], 1
    xor rax, rax
    leave
    ret
.invalid_scale:
    mov rax, -(EINVAL)
    leave
    ret

; ---------------------------------------------------------------------------
; surface_frame_callback
;   Request frame callback
; ---------------------------------------------------------------------------
global surface_frame_callback
surface_frame_callback:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jz .invalid
    mov rax, [r12 + Surface.cb_free]    ; a spent node, or a new one
    test rax, rax
    jz .new_node
    mov rcx, [rax]
    mov [r12 + Surface.cb_free], rcx
    jmp .have_node
.new_node:
    mov rax, [r12 + Surface.client]
    mov rdi, [rax + Client.arena]
    mov rsi, 32
    call arena_alloc
    test rax, rax
    jz .oom
.have_node:
    mov qword [rax], 0
    mov qword [rax + 8], 0
    mov [rax + 16], r13
    mov [rax + 24], r14
    mov rsi, rax
    mov rdi, [r12 + Surface.pending + SurfaceState.frame_cbs]
    call list_push_back
    mov dword [r12 + Surface.pending + SurfaceState.pending], 1
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; surface_logical_size
;   A surface's size on the screen: its buffer's, times 120 over its buffer
;   scale (decision 0012)
;   IN:  rdi = Surface*, rsi = its Buffer*
;   OUT: eax = width, edx = height; rcx, r8 used
; ---------------------------------------------------------------------------
global surface_logical_size
surface_logical_size:
    mov ecx, [rdi + Surface.buffer_scale]
    test ecx, ecx
    jz .same
    cmp ecx, 120
    je .same
    mov eax, [rsi + Buffer.width]
    imul eax, eax, 120
    xor edx, edx
    div ecx
    mov r8d, eax
    mov eax, [rsi + Buffer.height]
    imul eax, eax, 120
    xor edx, edx
    div ecx
    mov edx, eax
    mov eax, r8d
    ret
.same:
    mov eax, [rsi + Buffer.width]
    mov edx, [rsi + Buffer.height]
    ret

section .data

global surface_version
surface_version: dq 0x010100
