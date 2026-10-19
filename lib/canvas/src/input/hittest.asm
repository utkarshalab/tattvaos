; ============================================================================
; Hit Test — Surface Hit Testing for Input Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/rect.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

section .text

; ---------------------------------------------------------------------------
; hittest_surface
;   Test if point hits surface
;   IN:  rdi = surface*, rsi = x, rdx = y
;   OUT: rax = 1 if hit, 0 if miss
; ---------------------------------------------------------------------------
global hittest_surface
hittest_surface:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov rax, [rbx + Surface.current + SurfaceState.input]
    test rax, rax
    jz .use_opaque

    ; Check input region
    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call region_contains_point
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.use_opaque:
    mov rax, [rbx + Surface.current + SurfaceState.opaque]
    test rax, rax
    jz .no_region

    mov rdi, rax
    mov esi, r12d
    mov edx, r13d
    call region_contains_point
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.no_region:
    test r12d, r12d
    js .miss
    test r13d, r13d
    js .miss
    cmp r12d, [rbx + Surface.current + SurfaceState.width]
    jae .miss
    cmp r13d, [rbx + Surface.current + SurfaceState.height]
    jae .miss
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.miss:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
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

    ; zorder_iterate is bottom-to-top; the linear list is maintained top-first.

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
