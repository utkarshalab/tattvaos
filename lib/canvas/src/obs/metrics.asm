; ============================================================================
; Metrics — Global Server Metrics (frames, latency, memory, errors)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define Metrics_SIZE    88

section .text

; Metrics struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n

; ---------------------------------------------------------------------------
; metrics_init
; ---------------------------------------------------------------------------
global metrics_init
metrics_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Metrics_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + Metrics.server], rdi
    mov qword [rbx + Metrics.frames], 0
    mov qword [rbx + Metrics.dropped], 0
    mov qword [rbx + Metrics.commits], 0
    mov qword [rbx + Metrics.presents], 0
    mov qword [rbx + Metrics.input_events], 0
    mov qword [rbx + Metrics.proto_errors], 0
    mov qword [rbx + Metrics.faults], 0
    call tv_time_now_ns
    mov [rbx + Metrics.last_fps_time], rax
    mov qword [rbx + Metrics.last_frames], 0
    mov qword [rbx + Metrics.fps], 0
    mov qword [rdi + Server.metrics], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; metrics_inc
;   IN: rdi = server*, rsi = field_offset
; ---------------------------------------------------------------------------
global metrics_inc
metrics_inc:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.metrics]
    test rax, rax
    jz .none
    inc qword [rax + rsi]
    xor rax, rax
    leave
    ret
.none:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; metrics_tick_fps
; ---------------------------------------------------------------------------
global metrics_tick_fps
metrics_tick_fps:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + Server.metrics]
    test rax, rax
    jz .none
    mov rbx, rax
    call tv_time_now_ns
    mov rcx, rax
    sub rcx, [rbx + Metrics.last_fps_time]
    cmp rcx, 1000000000
    jb .done
    mov rax, [rbx + Metrics.frames]
    sub rax, [rbx + Metrics.last_frames]
    ; fps = frames * 1e9 / elapsed
    mov rdx, 1000000000
    imul rax, rdx
    xor rdx, rdx
    div rcx
    mov [rbx + Metrics.fps], rax
    mov rax, [rbx + Metrics.frames]
    mov [rbx + Metrics.last_frames], rax
    call tv_time_now_ns
    mov [rbx + Metrics.last_fps_time], rax
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret
.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; metrics_snapshot
; ---------------------------------------------------------------------------
global metrics_snapshot
metrics_snapshot:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + Server.metrics]
    test rax, rax
    jz .none
    mov rdi, r12
    mov rsi, rax
    mov rcx, Metrics_size
    shr rcx, 3
    rep movsq
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.none:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global metrics_version
metrics_version: dq 0x010000
