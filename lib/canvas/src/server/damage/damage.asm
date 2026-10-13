; ============================================================================
; Damage — Damage Tracking for Output and Surfaces
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

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
    mov rsi, r12
    mov rdx, 8
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
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get surface current damage
    mov rax, [r12 + Surface.current + SurfaceState.damage]
    test rax, rax
    jz .no_damage

    ; Get surface transform and position
    mov r13, [r12 + Surface.current + SurfaceState.transform]
    mov r14, [r12 + Surface.current + SurfaceState.buf_x]
    mov r15, [r12 + Surface.current + SurfaceState.buf_y]

    ; Transform damage to output coordinates
    ; TODO: Apply transform, scale, position

    ; Add to output damage
    mov rdi, [rbx + Server.damage_region]
    mov rsi, rax
    call region_union
    TEST_ASSERT_OK rax

.no_damage:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; damage_add_rect
;   Add rect to output damage
; ---------------------------------------------------------------------------
global damage_add_rect
damage_add_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.damage_region]
    call region_add_rect
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
