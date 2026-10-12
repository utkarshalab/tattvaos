; ============================================================================
; Commit — Atomic Surface State Commit
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; commit_init
;   Initialize commit subsystem
; ---------------------------------------------------------------------------
global commit_init
commit_init:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; commit_surface
;   Commit surface pending state to current
;   IN:  rdi = server*, rsi = surface*, rdx = flags
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global commit_surface
commit_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Check if there's pending state
    mov rax, [r12 + Surface.pending]
    cmp byte [rax + SurfaceState.pending], 1
    jne .nothing_pending

    ; Check transaction flag
    test r13, 1  ; TRANSACTION
    jz .apply_now

    ; Transaction: queue for atomic commit
    ; TODO: Add to transaction list
    jmp .done

.apply_now:
    ; Apply pending state to current
    call surface_apply_state

    ; Handle frame callbacks
    call surface_fire_frame_callbacks

    ; Handle buffer release
    call surface_release_old_buffer

.nothing_pending:
.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; surface_apply_state (internal)
;   Copy pending -> current
; ---------------------------------------------------------------------------
surface_apply_state:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, [rbx + Surface.current]
    mov r13, [rbx + Surface.pending]

    ; Copy buffer attachment
    mov rax, [r13 + SurfaceState.buffer]
    mov [r12 + SurfaceState.buffer], rax
    mov eax, [r13 + SurfaceState.buf_x]
    mov [r12 + SurfaceState.buf_x], eax
    mov eax, [r13 + SurfaceState.buf_y]
    mov [r12 + SurfaceState.buf_y], eax

    ; Copy damage
    mov rax, [r13 + SurfaceState.damage]
    mov [r12 + SurfaceState.damage], rax

    ; Copy opaque region
    mov rax, [r13 + SurfaceState.opaque]
    mov [r12 + SurfaceState.opaque], rax

    ; Copy input region
    mov rax, [r13 + SurfaceState.input]
    mov [r12 + SurfaceState.input], rax

    ; Copy transform
    mov eax, [r13 + SurfaceState.transform]
    mov [r12 + SurfaceState.transform], eax

    ; Copy scale
    mov rax, [r13 + SurfaceState.scale]
    mov [r12 + SurfaceState.scale], rax

    ; Clear pending flag
    mov byte [r13 + SurfaceState.pending], 0

    ret

; ---------------------------------------------------------------------------
; surface_fire_frame_callbacks (internal)
;   Fire frame callbacks for committed frame
; ---------------------------------------------------------------------------
surface_fire_frame_callbacks:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, [rbx + Surface.current + SurfaceState.frame_cbs]

    ; Iterate callbacks
    mov r13, [r12 + List.head]
    test r13, r13
    jz .done

.loop:
    ; Get callback data
    ; struct FrameCallback { surface, callback_fn, user_data, seq }
    mov rdi, [r13 + 8]   ; callback_fn
    mov rsi, rbx         ; surface
    mov rdx, [r13 + 16]  ; user_data
    mov rcx, [rbx + Surface.frame_seq]  ; sequence
    call rdi

    ; Remove fired callback
    mov rax, r13
    mov r13, [r13 + ListNode.next]
    ; TODO: free callback object
    mov rdi, [rbx + Surface.current + SurfaceState.frame_cbs]
    mov rsi, rax
    call list_remove

    test r13, r13
    jnz .loop

.done:
    ret

; ---------------------------------------------------------------------------
; surface_release_old_buffer (internal)
;   Release previously attached buffer
; ---------------------------------------------------------------------------
surface_release_old_buffer:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ; TODO: Signal release fence on old buffer
    ret

; ---------------------------------------------------------------------------
; commit_transaction
;   Commit multiple surfaces atomically
;   IN:  rdi = server*, rsi = surface_array, rdx = count
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global commit_transaction
commit_transaction:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Validate all surfaces have pending state
    test r13, r13
    jz .done

    mov r14, r12
.check_loop:
    mov rsi, [r14]
    mov rax, [rsi + Surface.pending]
    cmp byte [rax + SurfaceState.pending], 1
    jne .fail
    add r14, 8
    dec r13
    jnz .check_loop

    ; All have pending - apply all
    mov r13, rdx
    mov r14, rsi
.apply_loop:
    mov rsi, [r14]
    call surface_apply_state
    add r14, 8
    dec r13
    jnz .apply_loop

    ; Fire frame callbacks for all
    mov r13, rdx
    mov r14, rsi
.callback_loop:
    mov rsi, [r14]
    call surface_fire_frame_callbacks
    add r14, 8
    dec r13
    jnz .callback_loop

    ; Release old buffers
    mov r13, rdx
    mov r14, rsi
.release_loop:
    mov rsi, [r14]
    call surface_release_old_buffer
    add r14, 8
    dec r13
    jnz .release_loop

.done:
    xor rax, rax
    ret

.fail:
    RETURN_ERROR ESURF_COMMIT

section .data

global commit_version
commit_version: dq 0x010000