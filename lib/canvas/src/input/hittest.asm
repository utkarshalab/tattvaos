; ============================================================================
; Hit Test — Surface Hit Testing for Input Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/rect.inc"

section .text

; ---------------------------------------------------------------------------
; hittest_surface
;   Test if point hits surface
;   IN:  rdi = surface*, rsi = x, rdx = y
;   OUT: rax = 1 if hit, 0 if miss
; ---------------------------------------------------------------------------
global hittest_surface
hittest_surface:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    ; Get surface geometry
    mov eax, [rbx + Surface.current + SurfaceState.buf_x]
    mov edx, [rbx + Surface.current + SurfaceState.buf_y]
    ; TODO: Get buffer width/height

    ; For now, use input region
    mov rax, [rdi + Surface.current + SurfaceState.input]
    test rax, rax
    jz .use_opaque

    ; Check input region
    mov rdi, rax
    mov rsi, r12d
    mov rdx, r13d
    call region_contains_point
    ret

.use_opaque:
    mov rax, [rdi + Surface.current + SurfaceState.opaque]
    test rax, rax
    jz .no_region

    mov rdi, rax
    mov rsi, r12d
    mov rdx, r13d
    call region_contains_point
    ret

.no_region:
    ; Fall back to buffer geometry
    ; TODO: Implement buffer geometry check
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; hittest_surface_tree
;   Find topmost surface at point
;   IN:  rdi = server*, rsi = x, rdx = y
;   OUT: rax = surface*, 0 if none
; ---------------------------------------------------------------------------
global hittest_surface_tree
hittest_surface_tree:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    ; Iterate surfaces in reverse z-order (top to bottom)
    mov r14, [rbx + Server.surfaces]
    test r14, r14
    jz .none

    ; Get z-order tree
    mov r14, [rbx + Server.z_order_tree]
    test r14, r14
    jz .linear_search

    ; TODO: Use z-order tree for efficient hit testing

.linear_search:
    ; Linear search through surfaces
    mov rax, [rbx + Server.surfaces]
.surface_loop:
    test rax, rax
    jz .none

    ; Test hit
    push rax
    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call hittest_surface
    pop rax
    test rax, rax
    jnz .hit

    mov rax, [rax + Surface.z_order_next]
    jmp .surface_loop

.hit:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global hittest_version
hittest_version: dq 0x010000