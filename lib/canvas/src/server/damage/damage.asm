; ============================================================================
; Damage — Damage Tracking for Output and Surfaces
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern region_init
extern region_add_rect
extern region_clear
extern surface_transform_rect

section .text

; ---------------------------------------------------------------------------
; damage_init
;   Initialize damage tracking
; ---------------------------------------------------------------------------
global damage_init
damage_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create output damage region
    mov rdi, r12
    call region_init
    test rax, rax
    jnz .ok
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

.ok:
    mov qword [rbx + Server.damage_region], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; damage_add_surface
;   Add surface damage to output damage
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global damage_add_surface
damage_add_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get surface current damage
    mov r13, [r12 + Surface.current + SurfaceState.damage]
    test r13, r13
    jz .no_damage

    ; Get surface transform and position
    movsxd r14, dword [r12 + Surface.current + SurfaceState.buf_x]
    movsxd r15, dword [r12 + Surface.current + SurfaceState.buf_y]
    mov rcx, [r13 + Region.count]
    mov r13, [r13 + Region.rects]
.damage_loop:
    test rcx, rcx
    jz .success
    mov [rsp + 16], rcx
    mov rdi, r12
    mov rsi, r13
    mov rdx, rsp
    call surface_transform_rect
    test rax, rax
    js .error
    add dword [rsp], r14d
    add dword [rsp + 4], r15d
    mov rdi, [rbx + Server.damage_region]
    mov rsi, rsp
    call region_add_rect
    test rax, rax
    js .error
    add r13, 16
    mov rcx, [rsp + 16]
    dec rcx
    jmp .damage_loop
.success:
    xor eax, eax
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.error:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_damage:
    xor rax, rax
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; damage_add_rect
;   Add rect to output damage
; ---------------------------------------------------------------------------
global damage_add_rect
damage_add_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx

    mov dword [rsp], r12d
    mov dword [rsp + 4], r13d
    mov dword [rsp + 8], r14d
    mov dword [rsp + 12], r15d
    mov rdi, [rbx + Server.damage_region]
    mov rsi, rsp
    call region_add_rect
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; damage_clear
;   Clear output damage (after frame)
; ---------------------------------------------------------------------------
global damage_clear
damage_clear:
    PROLOGUE
    ASSERT_PTR rdi

    mov rdi, [rdi + Server.damage_region]
    call region_clear
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; damage_get
;   Get output damage region
; ---------------------------------------------------------------------------
global damage_get
damage_get:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.damage_region]
    leave
    ret

section .data
global damage_version
damage_version: dq 0x010000
