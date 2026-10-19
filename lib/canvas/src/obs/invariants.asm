; ============================================================================
; Invariants — Scene-Graph Invariant Checks (debug builds, after commit)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

; struct offsets (hoisted above use)
%define INV_OK              0
%define INV_ZORDER_CYCLE    1
%define INV_DANGLING_PARENT 2
%define INV_BAD_GEOMETRY    3
%define INV_STALE_HANDLE    4

section .text


; ---------------------------------------------------------------------------
; invariants_check_all
;   IN: rdi = server* — OUT: rax = INV_* code
; ---------------------------------------------------------------------------
global invariants_check_all
invariants_check_all:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, rbx
    call invariants_check_surfaces
    test rax, rax
    jnz .fail
    mov rdi, rbx
    call invariants_check_zorder
    test rax, rax
    jnz .fail
    mov rdi, rbx
    call invariants_check_subsurfaces
    test rax, rax
    jnz .fail
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret
.fail:
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; invariants_check_surfaces — every surface has valid geometry + client
; ---------------------------------------------------------------------------
global invariants_check_surfaces
invariants_check_surfaces:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Server.surfaces]
    mov rcx, 1048576
.surface_loop:
    test r12, r12
    jz .surface_ok
    test rcx, rcx
    jz .surface_cycle
    cmp qword [r12 + Surface.client], 0
    je .surface_stale
    mov rax, [r12 + Surface.current]
    test rax, rax
    jz .surface_stale
    cmp dword [rax + SurfaceState.width], 0
    jl .surface_geometry
    cmp dword [rax + SurfaceState.height], 0
    jl .surface_geometry
    mov r12, [r12 + Surface.z_order_next]
    dec rcx
    jmp .surface_loop
.surface_cycle:
    mov rax, INV_ZORDER_CYCLE
    jmp .surface_out
.surface_stale:
    mov rax, INV_STALE_HANDLE
    jmp .surface_out
.surface_geometry:
    mov rax, INV_BAD_GEOMETRY
    jmp .surface_out
.surface_ok:
    xor rax, rax
.surface_out:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; invariants_check_zorder — z-order is a strict total order (no cycles)
; ---------------------------------------------------------------------------
global invariants_check_zorder
invariants_check_zorder:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Server.surfaces]
    mov r13, r12
.cycle_loop:
    test r13, r13
    jz .z_ok
    mov r13, [r13 + Surface.z_order_next]
    test r13, r13
    jz .z_ok
    mov r13, [r13 + Surface.z_order_next]
    mov r12, [r12 + Surface.z_order_next]
    cmp r12, r13
    je .z_cycle
    jmp .cycle_loop
.z_cycle:
    mov rax, INV_ZORDER_CYCLE
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.z_ok:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; invariants_check_subsurfaces — every subsurface parent resolves + no cycles
; ---------------------------------------------------------------------------
global invariants_check_subsurfaces
invariants_check_subsurfaces:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Server.surfaces]
.subsurface_next:
    test r12, r12
    jz .subsurface_ok
    cmp dword [r12 + Surface.role], 1
    jne .advance
    mov r13, r12
    mov ecx, 64
.parent_loop:
    mov r13, [r13 + Surface.role_data]
    test r13, r13
    jz .dangling
    cmp r13, r12
    je .parent_cycle
    cmp dword [r13 + Surface.role], 1
    jne .advance
    dec ecx
    jnz .parent_loop
.parent_cycle:
    mov rax, INV_ZORDER_CYCLE
    jmp .subsurface_out
.dangling:
    mov rax, INV_DANGLING_PARENT
    jmp .subsurface_out
.advance:
    mov r12, [r12 + Surface.z_order_next]
    jmp .subsurface_next
.subsurface_ok:
    xor rax, rax
.subsurface_out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; invariants_assert — trap with code in debug builds
; ---------------------------------------------------------------------------
global invariants_assert
invariants_assert:
    PROLOGUE
    test rdi, rdi
    jz .ok
    int3
.ok:
    xor rax, rax
    leave
    ret

section .data
global invariants_version
invariants_version: dq 0x010000
