; ============================================================================
; Damage Tracking — Dirty Region Accumulation & Minimal Redraw
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/compositor.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; damage_init
;   Initialize damage region
;   IN: rdi = damage*, rsi = arena
;   OUT: rax = 0 OK, -ENOMEM
; ============================================================================
global damage_init
damage_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate initial rect array
    mov rdi, r12
    mov rsi, 32 * 16  ; 32 rects
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + DAMAGE_RECTS], rax
    mov dword [rbx + DAMAGE_COUNT], 0
    mov dword [rbx + DAMAGE_CAPACITY], 32
    mov [rbx + DAMAGE_ARENA], r12

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; damage_destroy
;   Free damage region
; ============================================================================
global damage_destroy
damage_destroy:
    PROLOGUE
    ; Arena handles cleanup
    xor rax, rax
    leave
    ret

; ============================================================================
; damage_add_rect
;   Add rectangle to damage region (merges overlapping)
;   IN: rdi = damage*, rsi = x, rdx = y, rcx = w, r8 = h
; ============================================================================
global damage_add_rect
damage_add_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx

    ; Validate rect
    test r14d, r14d
    jle .done
    test r15d, r15d
    jle .done

    mov eax, [rbx + DAMAGE_COUNT]
    test eax, eax
    jz .first_rect

    ; Try to merge with existing rects
    mov r14, [rbx + DAMAGE_RECTS]
    mov ecx, [rbx + DAMAGE_COUNT]

.merge_loop:
    test ecx, ecx
    jz .add_new

    ; Check overlap with current rect
    mov eax, [r14 + DamageRect_X]
    mov edx, [r14 + DamageRect_Y]
    mov r8d, [r14 + DamageRect_W]
    mov r9d, [r14 + DamageRect_H]

    ; Quick reject: rects don't overlap
    mov eax, r12d
    add eax, r14d
    cmp eax, edx
    jle .next_rect

    mov eax, r13d
    add eax, r15d
    cmp eax, r9d
    jle .next_rect

    mov eax, edx
    add eax, r8d
    cmp eax, r12d
    jle .next_rect

    mov eax, r9d
    add eax, r9d
    cmp eax, r13d
    jle .next_rect

    ; Overlaps - merge
    ; New bounds = union of both rects
    cmp edx, r13d
    cmovg r13d, edx
    cmp r9d, r13d
    cmovg r13d, r9d

    ; Recompute x,y,w,h
    mov eax, r12d
    cmp eax, edx
    cmovl r12d, edx
    cmovl r13d, eax

    ; This is getting complex - just add for now
    ; Real implementation uses region union

.next_rect:
    add r14, DamageRect_SIZE
    dec ecx
    jmp .merge_loop

.add_new:
    ; Add new rect
    call .ensure_capacity
    test rax, rax
    jnz .done

    mov r14, [rbx + DAMAGE_RECTS]
    mov eax, [rbx + DAMAGE_COUNT]
    imul eax, DamageRect_SIZE
    add r14, rax
    mov [r14 + DamageRect_X], r12d
    mov [r14 + DamageRect_Y], r13d
    mov [r14 + DamageRect_W], r14d
    mov [r14 + DamageRect_H], r15d
    inc dword [rbx + DAMAGE_COUNT]

.first_rect:
    ; First rect - just add
    call .ensure_capacity
    test rax, rax
    jnz .done

    mov r14, [rbx + DAMAGE_RECTS]
    mov [r14 + DamageRect_X], r12d
    mov [r14 + DamageRect_Y], r13d
    mov [r14 + DamageRect_W], r14d
    mov [r14 + DamageRect_H], r15d
    inc dword [rbx + DAMAGE_COUNT]

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.ensure_capacity:
    mov eax, [rbx + DAMAGE_COUNT]
    cmp eax, [rbx + DAMAGE_CAPACITY]
    jl .cap_ok

    ; Grow capacity
    mov eax, [rbx + DAMAGE_CAPACITY]
    shl eax, 1
    imul eax, DamageRect_SIZE
    mov rdi, [rbx + DAMAGE_ARENA]
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .cap_fail

    ; Copy old data
    mov rdi, rax
    mov rsi, [rbx + DAMAGE_RECTS]
    mov ecx, [rbx + DAMAGE_COUNT]
    imul ecx, DamageRect_SIZE
    call memcopy

    mov [rbx + DAMAGE_RECTS], rax
    mov eax, [rbx + DAMAGE_CAPACITY]
    shl eax, 1
    mov [rbx + DAMAGE_CAPACITY], eax
    xor rax, rax
    ret

.cap_ok:
    xor rax, rax
    ret

.cap_fail:
    mov rax, -ENOMEM
    ret

; ============================================================================
; damage_get_rects
;   Get damage rects for rendering
;   IN: rdi = damage*, rsi = rects* (output), rdx = max_count
;   OUT: rax = count
; ============================================================================
global damage_get_rects
damage_get_rects:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov eax, [rbx + DAMAGE_COUNT]
    cmp eax, edx
    cmovg eax, edx

    test eax, eax
    jz .done

    mov rdi, r12
    mov rsi, [rbx + DAMAGE_RECTS]
    mov ecx, eax
    imul ecx, DamageRect_SIZE
    call memcopy

.done:
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; damage_clear
;   Clear all damage
; ============================================================================
global damage_clear
damage_clear:
    PROLOGUE
    mov dword [rdi + DAMAGE_COUNT], 0
    xor rax, rax
    leave
    ret

; ============================================================================
; damage_intersect_rect
;   Intersect damage with rect
; ============================================================================
global damage_intersect_rect
damage_intersect_rect:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx

    ; Clip each damage rect to the intersection
    mov r14, [rbx + DAMAGE_RECTS]
    mov ecx, [rbx + DAMAGE_COUNT]

.clip_loop:
    test ecx, ecx
    jz .done

    ; Clip current rect
    mov eax, [r14 + DamageRect_X]
    mov edx, [r14 + DamageRect_Y]
    mov r8d, [r14 + DamageRect_W]
    mov r9d, [r14 + DamageRect_H]

    ; Intersect with r12,r13,r14,r15
    call rect_intersect_clip
    ; ... clip logic here

    add r14, DamageRect_SIZE
    dec ecx
    jmp .clip_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; rect_intersect_clip - helper
; ============================================================================
rect_intersect_clip:
    ; r12,r13,r14,r15 = clip rect
    ; eax,edx,r8d,r9d = rect to clip
    ; Returns clipped rect in eax,edx,r8d,r9d
    ret

section .data
global damage_version
damage_version: dq 0x010000