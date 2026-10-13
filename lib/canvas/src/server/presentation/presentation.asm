; ============================================================================
; Presentation — Frame Presentation Feedback
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define PresentInfo_kind       0
%define PresentInfo.kind 0
%define PresentInfo_seq        4
%define PresentInfo.seq 4
%define PresentInfo_time       8
%define PresentInfo.time 8
%define PresentInfo_refresh_ns 16
%define PresentInfo.refresh_ns 16
%define PresentInfo_flags      24
%define PresentInfo.flags 24
%define PresentInfo_size       32
%define PRESENT_KIND_VSYNC    0
%define PRESENT_KIND_IMMEDIATE 1
%define PRESENT_KIND_ASYNC    2
%define PRESENT_FLAG_HW_COMPLETION  1
%define PRESENT_FLAG_ZERO_COPY      2
%define PRESENT_FLAG_ASYNC          4

section .text

; ---------------------------------------------------------------------------
; presentation_init
; ---------------------------------------------------------------------------
global presentation_init
presentation_init:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; presentation_queue
;   Queue presentation feedback for committed surface
;   IN:  rdi = server*, rsi = surface*, rdx = seq
; ---------------------------------------------------------------------------
global presentation_queue
presentation_queue:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Create feedback object
    ; struct PresentInfo { kind, seq, time, refresh_ns, flags }
    mov rdi, [rbx + Server.arena]
    mov rsi, 40
    call arena_alloc
    test rax, rax
    jz .oom

    mov dword [rax + PresentInfo.kind], 0  ; vsync
    mov qword [rax + PresentInfo.seq], r13
    mov qword [rax + PresentInfo.time], 0  ; filled at vblank
    mov rdi, [rbx + Server.outputs]
    mov rdx, [rdx + Output.frame_clock]
    mov rdx, [rdx + FrameClock.refresh_ns]
    mov qword [rax + PresentInfo.refresh_ns], rdx
    mov dword [rax + PresentInfo.flags], 0

    ; Queue for vblank
    ; TODO

    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; presentation_complete
;   Complete presentation at vblank
;   IN:  rdi = server*, rsi = surface*, rdx = vblank_time_ns
; ---------------------------------------------------------------------------
global presentation_complete
presentation_complete:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Fill in presentation time
    ; TODO: Find queued feedback and fill time

    ; Send feedback to client
    ; TODO: Encode cw_present.presentation_feedback event

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; presentation_get_feedback
;   Get last presentation feedback
; ---------------------------------------------------------------------------
global presentation_get_feedback
presentation_get_feedback:
    PROLOGUE
    ; TODO
    xor rax, rax
    leave
    ret

section .data




global presentation_version
presentation_version: dq 0x010000
