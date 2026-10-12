; ============================================================================
; Frame Clock — Per-Output Frame Scheduling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; frame_clock_init
;   Initialize frame clock for output
;   IN:  rdi = frame_clock*, rsi = output*, rdx = refresh_ns
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global frame_clock_init
frame_clock_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + FrameClock.output], r12
    mov qword [rbx + FrameClock.refresh_ns], rdx
    mov qword [rbx + FrameClock.next_vblank], 0
    mov qword [rbx + FrameClock.phase], 0
    mov qword [rbx + FrameClock.callbacks], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; frame_clock_start
;   Start frame clock (called on first commit)
; ---------------------------------------------------------------------------
global frame_clock_start
frame_clock_start:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Get current time
    call tv_time_now_ns
    mov r12, rax

    ; Align to next vblank
    mov rax, r12
    add rax, [rbx + FrameClock.refresh_ns]
    xor rdx, rdx
    div qword [rbx + FrameClock.refresh_ns]
    mul qword [rbx + FrameClock.refresh_ns]
    mov [rbx + FrameClock.next_vblank], rax

    ; Schedule first vblank interrupt
    mov rdi, [rbx + FrameClock.output]
    call output_schedule_vblank

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; frame_clock_schedule
;   Schedule frame callback for next vblank
;   IN:  rdi = frame_clock*, rsi = callback_fn, rdx = user_data
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global frame_clock_schedule
frame_clock_schedule:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Add callback to list
    ; TODO: Create callback object and add to list
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; frame_clock_vblank
;   Handle vblank interrupt
;   IN:  rdi = frame_clock*, rsi = vblank_time_ns
; ---------------------------------------------------------------------------
global frame_clock_vblank
frame_clock_vblank:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Update next vblank
    mov rax, [rbx + FrameClock.next_vblank]
    add rax, [rbx + FrameClock.refresh_ns]
    mov [rbx + FrameClock.next_vblank], rax

    ; Fire callbacks
    mov r13, [rbx + FrameClock.callbacks]
    test r13, r13
    jz .done

.callback_loop:
    ; Fire callback
    ; TODO: Call callback with vblank time
    mov r13, [r13 + ListNode.next]
    test r13, r13
    jnz .callback_loop

.done:
    ; Schedule next vblank
    mov rdi, [rbx + FrameClock.output]
    call output_schedule_vblank

    ret

; ---------------------------------------------------------------------------
; frame_clock_get_phase
;   Get frame phase (time until next vblank)
; ---------------------------------------------------------------------------
global frame_clock_get_phase
frame_clock_get_phase:
    PROLOGUE
    ASSERT_PTR rdi

    call tv_time_now_ns
    mov rdx, [rdi + FrameClock.next_vblank]
    sub rdx, rax
    mov rax, rdx
    ret

; ---------------------------------------------------------------------------
; frame_clock_get_refresh
;   Get refresh interval
; ---------------------------------------------------------------------------
global frame_clock_get_refresh
frame_clock_get_refresh:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + FrameClock.refresh_ns]
    ret

section .data

%define FrameClock_output      0
%define FrameClock_refresh_ns  8
%define FrameClock_next_vblank 16
%define FrameClock_phase       24
%define FrameClock_callbacks   32
%define FrameClock_size        40

global frame_clock_version
frame_clock_version: dq 0x010000