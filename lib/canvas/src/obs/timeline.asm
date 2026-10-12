; ============================================================================
; Frame Timeline — Per-Frame CPU/GPU Marker History (64 frames)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc FrameMark {
    .frame_seq:      resq 1
    .composite_start: resq 1
    .composite_end:  resq 1
    .flip_time:      resq 1
    .vblank_time:    resq 1
    .present_time:   resq 1
    .damage_bytes:   resq 1
    .flags:          resd 1
}
%define FrameMark_size    60

struc FrameTimeline {
    .server:         resq 1
    .marks:          resq 1
    .head:           resq 1
    .count:          resq 1
    .seq:            resq 1
}
%define FrameTimeline_size    40

%define FRAME_TIMELINE_DEPTH  64

; ---------------------------------------------------------------------------
; frame_timeline_init
; ---------------------------------------------------------------------------
global frame_timeline_init
frame_timeline_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, FrameTimeline_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + FrameTimeline.server], rdi
    mov rdi, [rbx + FrameTimeline.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, FRAME_TIMELINE_DEPTH
    imul rsi, FrameMark_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + FrameTimeline.marks], rax
    mov qword [rbx + FrameTimeline.head], 0
    mov qword [rbx + FrameTimeline.count], 0
    mov qword [rbx + FrameTimeline.seq], 0
    mov qword [rdi + Server.frame_timeline], rbx
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; frame_timeline_begin
;   Start a frame record, returns mark*
; ---------------------------------------------------------------------------
global frame_timeline_begin
frame_timeline_begin:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + Server.frame_timeline]
    test rax, rax
    jz .none
    mov rbx, rax
    mov rax, [rbx + FrameTimeline.head]
    mov rdi, [rbx + FrameTimeline.marks]
    imul rax, FrameMark_size
    add rdi, rax
    mov rax, rdi
    ; stamp seq + composite start
    mov rdi, [rbx + FrameTimeline.seq]
    inc qword [rbx + FrameTimeline.seq]
    mov [rax + FrameMark.frame_seq], rdi
    call tv_time_now_ns
    mov [rax + FrameMark.composite_start], rax
    mov qword [rax + FrameMark.composite_end], 0
    mov qword [rax + FrameMark.flip_time], 0
    mov qword [rax + FrameMark.vblank_time], 0
    mov qword [rax + FrameMark.present_time], 0
    mov qword [rax + FrameMark.damage_bytes], 0
    mov dword [rax + FrameMark.flags], 0
    ret
.none:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; frame_timeline_mark
;   IN: rdi = mark*, rsi = field_offset
; ---------------------------------------------------------------------------
global frame_timeline_mark
frame_timeline_mark:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    call tv_time_now_ns
    mov [rbx + rsi], rax
    ret

; ---------------------------------------------------------------------------
; frame_timeline_end
; ---------------------------------------------------------------------------
global frame_timeline_end
frame_timeline_end:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    call tv_time_now_ns
    mov [r12 + FrameMark.composite_end], rax
    mov rax, [rbx + Server.frame_timeline]
    mov rbx, rax
    mov rax, [rbx + FrameTimeline.head]
    inc rax
    cmp rax, FRAME_TIMELINE_DEPTH
    jb .no_wrap
    xor rax, rax
.no_wrap:
    mov [rbx + FrameTimeline.head], rax
    mov rax, [rbx + FrameTimeline.count]
    cmp rax, FRAME_TIMELINE_DEPTH
    jae .done
    inc qword [rbx + FrameTimeline.count]
.done:
    xor rax, rax
    ret

section .data
global frame_timeline_version
frame_timeline_version: dq 0x010000
