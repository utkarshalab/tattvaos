; Atomic surface state commits.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern fence_signal
extern handle_resolve
extern list_pop_front
extern list_push_back
extern presentation_queue
extern region_clear
extern region_copy

; Server-side surface layout (kept local until compositor/client surfaces are
; split into separately named public structures).
%define S_ID 0
%define S_CURRENT 48
%define S_PENDING 176
%define S_FRAME_SEQ 296
%define SS_BUFFER 0
%define SS_BUF_X 8
%define SS_BUF_Y 12
%define SS_DAMAGE 16
%define SS_OPAQUE 24
%define SS_INPUT 32
%define SS_TRANSFORM 40
%define SS_SCALE 44
%define SS_SUBSURFACES 52
%define SS_FRAME_CBS 60
%define SS_PENDING 68

%define BUFFER_RELEASE_FENCE 60
%define BUFFER_STATE 84
%define BUFFER_ALLOCATED 1

section .text

global commit_init
commit_init:
    xor eax, eax
    ret

; IN server*, surface*, flags. A one-surface transaction is intrinsically atomic.
global commit_surface
commit_surface:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .invalid
    test r12, r12
    jz .invalid
    cmp byte [r12 + S_PENDING + SS_PENDING], 1
    jne .done
    mov r14, [r12 + S_CURRENT + SS_BUFFER]
    mov rdi, r12
    call surface_apply_state
    test rax, rax
    js .out
    inc qword [r12 + S_FRAME_SEQ]
    mov rdi, rbx
    mov rsi, r12
    mov rdx, [r12 + S_FRAME_SEQ]
    call presentation_queue
    test rax, rax
    js .out
    mov rdi, r12
    call surface_fire_frame_callbacks
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    call surface_release_old_buffer
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
    lea r12, [rbx + S_CURRENT]
    lea r13, [rbx + S_PENDING]
    mov rax, [r13 + SS_BUFFER]
    mov [r12 + SS_BUFFER], rax
    mov eax, [r13 + SS_BUF_X]
    mov [r12 + SS_BUF_X], eax
    mov eax, [r13 + SS_BUF_Y]
    mov [r12 + SS_BUF_Y], eax
    mov eax, [r13 + SS_TRANSFORM]
    mov [r12 + SS_TRANSFORM], eax
    mov rax, [r13 + SS_SCALE]
    mov [r12 + SS_SCALE], rax

    mov rdi, [r12 + SS_DAMAGE]
    mov rsi, [r13 + SS_DAMAGE]
    call region_copy
    test rax, rax
    js .out
    mov rdi, [r13 + SS_DAMAGE]
    call region_clear
    mov rdi, [r12 + SS_OPAQUE]
    mov rsi, [r13 + SS_OPAQUE]
    call region_copy
    test rax, rax
    js .out
    mov rdi, [r12 + SS_INPUT]
    mov rsi, [r13 + SS_INPUT]
    call region_copy
    test rax, rax
    js .out

    ; Transfer pending one-shot callbacks to the current batch.
.move_callback:
    mov rdi, [r13 + SS_FRAME_CBS]
    call list_pop_front
    test rax, rax
    jz .callbacks_done
    mov rsi, rax
    mov rdi, [r12 + SS_FRAME_CBS]
    call list_push_back
    jmp .move_callback
.callbacks_done:
    mov byte [r13 + SS_PENDING], 0
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; Callback nodes are arena-owned: prev,next,fn,user_data.
surface_fire_frame_callbacks:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, [rbx + S_CURRENT + SS_FRAME_CBS]
.loop:
    mov rdi, r12
    call list_pop_front
    test rax, rax
    jz .done
    mov r13, rax
    mov r14, [r13 + 16]
    test r14, r14
    jz .loop
    mov rdi, rbx
    mov rsi, [r13 + 24]
    mov rdx, [rbx + S_FRAME_SEQ]
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
    cmp r13, [r12 + S_CURRENT + SS_BUFFER]
    je .done
    mov rdi, [rbx + Server.buffer_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .done
    mov byte [rax + BUFFER_STATE], BUFFER_ALLOCATED
    mov edx, [rax + BUFFER_RELEASE_FENCE]
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
    cmp byte [rax + S_PENDING + SS_PENDING], 1
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
    inc qword [r15 + S_FRAME_SEQ]
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
    mov rdx, [r15 + S_FRAME_SEQ]
    call presentation_queue
    test rax, rax
    js .out
    mov rdi, r15
    call surface_fire_frame_callbacks
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
