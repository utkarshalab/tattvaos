; ============================================================================
; Damage Ring — Buffer-Age Tracking for Partial Updates
; Tracks which buffer regions were modified N frames ago
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define DAMAGE_RING_SIZE    64  ; Number of frames to track
%define DamageRing_buffers  0
%define DamageRing.buffers 0
%define DamageRing_regions  8
%define DamageRing.regions 8
%define DamageRing_head     16
%define DamageRing.head 16
%define DamageRing_count    24
%define DamageRing.count 24
%define DamageRing_size     32

section .text



; ---------------------------------------------------------------------------
; damage_ring_init
;   Initialize damage ring
;   IN:  rdi = damage_ring*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global damage_ring_init
damage_ring_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate buffer array (DAMAGE_RING_SIZE * pointer)
    mov rdi, r12
    mov rsi, DAMAGE_RING_SIZE
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + DamageRing_buffers], rax

    ; Allocate region array
    mov rdi, r12
    mov rsi, DAMAGE_RING_SIZE
    shl rsi, 3
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + DamageRing_regions], rax

    mov qword [rbx + DamageRing_head], 0
    mov qword [rbx + DamageRing_count], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; damage_ring_push
;   Push current frame damage (called after commit)
;   IN:  rdi = damage_ring*, rsi = buffer*, rdx = damage_region*
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global damage_ring_push
damage_ring_push:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov rax, [rbx + DamageRing.head]
    mov rdi, [rbx + DamageRing.buffers]
    mov [rdi + rax * 8], r12

    mov rdi, [rbx + DamageRing.regions]
    mov [rdi + rax * 8], r13

    ; Advance head
    inc rax
    cmp rax, DAMAGE_RING_SIZE
    jb .no_wrap
    xor rax, rax
.no_wrap:
    mov [rbx + DamageRing.head], rax

    ; Update count
    mov rax, [rbx + DamageRing.count]
    cmp rax, DAMAGE_RING_SIZE
    jb .inc_count
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.inc_count:
    inc rax
    mov [rbx + DamageRing.count], rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; damage_ring_get_age
;   Get damage for buffer age N (0 = current, 1 = previous, etc.)
;   IN:  rdi = damage_ring*, rsi = age (0 = current)
;   OUT: rax = damage_region*, 0 if not available
; ---------------------------------------------------------------------------
global damage_ring_get_age
damage_ring_get_age:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + DamageRing.count]
    cmp r12, rax
    jae .not_found

    ; Index = (head - 1 - age) % size
    mov rax, [rbx + DamageRing.head]
    sub rax, 1
    sub rax, r12
    cmp rax, 0
    jae .no_wrap
    add rax, DAMAGE_RING_SIZE
.no_wrap:

    mov rbx, [rbx + DamageRing.regions]
    mov rax, [rbx + rax * 8]
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; damage_ring_get_buffer
;   Get buffer for age
; ---------------------------------------------------------------------------
global damage_ring_get_buffer
damage_ring_get_buffer:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + DamageRing.count]
    cmp r12, rax
    jae .not_found

    mov rax, [rbx + DamageRing.head]
    sub rax, 1
    sub rax, r12
    cmp rax, 0
    jae .no_wrap
    add rax, DAMAGE_RING_SIZE
.no_wrap:

    mov rbx, [rbx + DamageRing.buffers]
    mov rax, [rbx + rax * 8]
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; damage_ring_clear
;   Clear damage ring
; ---------------------------------------------------------------------------
global damage_ring_clear
damage_ring_clear:
    PROLOGUE
    ASSERT_PTR rdi
    mov qword [rdi + DamageRing.head], 0
    mov qword [rdi + DamageRing.count], 0
    xor rax, rax
    leave
    ret

section .data
global damage_ring_version
damage_ring_version: dq 0x010000
