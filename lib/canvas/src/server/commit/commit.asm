; Atomic surface state commits.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern fence_ready
extern fence_signal
extern handle_resolve
extern list_pop_front
extern list_push_back
extern presentation_queue
extern region_clear
extern region_copy
extern region_union
extern stacking_mapped
extern stacking_unmapped
extern window_commit

%define BUFFER_ALLOCATED 1

section .text

global commit_init
commit_init:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; commit_retry
;   Each turn: every commit waiting for an acquire fence whose fence is now
;   signaled, or gone, is applied
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global commit_retry
commit_retry:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, [rbx + Server.client_list]
.client:
    test r12, r12
    jz .done
    mov r13, [r12 + Client.surfaces]
.surface:
    test r13, r13
    jz .next_client
    cmp qword [r13 + Surface.fence_wait], 0
    je .next_surface
    mov rdi, rbx
    mov rsi, r13
    xor edx, edx
    call commit_surface                 ; waits again if it must
.next_surface:
    mov r13, [r13 + Surface.client_next]
    jmp .surface
.next_client:
    mov r12, [r12 + Client.next_client]
    jmp .client
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; IN server*, surface*, flags. A one-surface transaction is intrinsically atomic.
; A buffer whose acquire fence is not signaled yet is not shown: the commit
; waits (Surface.fence_wait) and commit_retry applies it once the fence is
; signaled or gone.
global commit_surface
commit_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    cmp dword [r12 + Surface.pending + SurfaceState.pending], 1
    jne .done
    mov qword [r12 + Surface.fence_wait], 0
    mov rsi, [r12 + Surface.pending + SurfaceState.buffer]
    test rsi, rsi
    jz .ready
    mov rdi, [rbx + Server.buffer_table]
    call handle_resolve
    test rax, rax
    jz .ready
    mov esi, [rax + Buffer.acquire_fence]
    mov rdi, rbx
    call fence_ready
    test eax, eax
    jnz .ready
    mov qword [r12 + Surface.fence_wait], 1   ; its pixels are not done yet
    jmp .done
.ready:
    mov r14, [r12 + Surface.current + SurfaceState.buffer]
    mov rdi, r12
    call surface_apply_state
    test rax, rax
    js .out
    inc qword [r12 + Surface.frame_seq]
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r12 + Surface.frame_seq]
    call presentation_queue
    test rax, rax
    js .out
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call surface_release_old_buffer
    mov rdi, rbx                        ; a window goes where the server puts it
    mov rsi, r12
    call window_commit

    ; Its first buffer: it is mapped; no buffer any more: unmapped
    mov rax, [r12 + Surface.current + SurfaceState.buffer]
    mov rdi, rbx
    mov rsi, r12
    test r14, r14
    jnz .was_mapped
    test rax, rax
    jz .done
    call stacking_mapped
    jmp .done
.was_mapped:
    test rax, rax
    jnz .done
    call stacking_unmapped
.done:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax, -(EINVAL)
    jmp .out

; Copy pending values into current without aliasing owned region/list objects.
surface_apply_state:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    lea r12, [rbx + Surface.current]
    lea r13, [rbx + Surface.pending]
    mov rax, [r13 + SurfaceState.buffer]
    mov [r12 + SurfaceState.buffer], rax
    mov eax, [r13 + SurfaceState.buf_x]
    mov [r12 + SurfaceState.buf_x], eax
    mov eax, [r13 + SurfaceState.buf_y]
    mov [r12 + SurfaceState.buf_y], eax
    mov eax, [r13 + SurfaceState.transform]
    mov [r12 + SurfaceState.transform], eax
    mov rax, [r13 + SurfaceState.scale]
    mov [r12 + SurfaceState.scale], rax

    ; Damage adds up until the compositor takes it for a frame
    mov rdi, [r12 + SurfaceState.damage]
    mov rsi, [r13 + SurfaceState.damage]
    call region_union
    test rax, rax
    js .out
    mov rdi, [r13 + SurfaceState.damage]
    call region_clear
    mov rdi, [r12 + SurfaceState.opaque]
    mov rsi, [r13 + SurfaceState.opaque]
    call region_copy
    test rax, rax
    js .out
    mov rdi, [r12 + SurfaceState.input]
    mov rsi, [r13 + SurfaceState.input]
    call region_copy
    test rax, rax
    js .out

    ; Transfer pending one-shot callbacks to the current batch.
.move_callback:
    mov rdi, [r13 + SurfaceState.frame_cbs]
    call list_pop_front
    test rax, rax
    jz .callbacks_done
    mov rsi, rax
    mov rdi, [r12 + SurfaceState.frame_cbs]
    call list_push_back
    jmp .move_callback
.callbacks_done:
    mov dword [r13 + SurfaceState.pending], 0
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; The frame carrying this surface is done. Callback nodes are prev, next, fn,
; user_data; once fired they wait in Surface.cb_free for the next request.
; IN surface*.
global surface_fire_frame_callbacks
surface_fire_frame_callbacks:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, [rbx + Surface.current + SurfaceState.frame_cbs]
.loop:
    mov rdi, r12
    call list_pop_front
    test rax, rax
    jz .done
    mov r13, rax
    mov r14, [r13 + 16]
    mov rax, [rbx + Surface.cb_free]
    mov [r13], rax
    mov [rbx + Surface.cb_free], r13
    test r14, r14
    jz .loop
    mov rdi, rbx
    mov rsi, [r13 + 24]
    mov rdx, [rbx + Surface.frame_seq]
    call r14
    jmp .loop
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; Release a replaced buffer and signal its optional release fence.
; IN server*, surface*, old buffer handle.
surface_release_old_buffer:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test r13, r13
    jz .done
    cmp r13, [r12 + Surface.current + SurfaceState.buffer]
    je .done
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .done
    mov qword [rax + Buffer.state], BUFFER_ALLOCATED
    mov rdx, [rax + Buffer.release_fence]
    test edx, edx
    jz .done
    mov rdi, rbx
    mov esi, edx
    call fence_signal
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; Validate the entire set, apply all state, then publish side effects.
global commit_transaction
commit_transaction:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    test rbx, rbx
    jz .invalid
    test r13, r13
    jz .done
    test r12, r12
    jz .invalid
    xor r14d, r14d
.validate:
    cmp r14, r13
    jae .apply_begin
    mov rax, [r12 + r14 * 8]
    test rax, rax
    jz .fail
    cmp dword [rax + Surface.pending + SurfaceState.pending], 1
    jne .fail
    inc r14
    jmp .validate
.apply_begin:
    xor r14d, r14d
.apply:
    cmp r14, r13
    jae .publish_begin
    mov r15, [r12 + r14 * 8]
    mov rdi, r15
    call surface_apply_state
    test rax, rax
    js .out
    inc qword [r15 + Surface.frame_seq]
    inc r14
    jmp .apply
.publish_begin:
    xor r14d, r14d
.publish:
    cmp r14, r13
    jae .done
    mov r15, [r12 + r14 * 8]
    mov rdi, rbx
    mov rsi, r15
    mov rdx, [r15 + Surface.frame_seq]
    call presentation_queue
    test rax, rax
    js .out
    inc r14
    jmp .publish
.done:
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(ESURF_COMMIT)
    jmp .out
.invalid:
    mov rax, -(EINVAL)
    jmp .out

section .data
global commit_version
commit_version: dq 0x010100
