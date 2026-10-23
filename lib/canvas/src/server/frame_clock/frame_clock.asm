; ============================================================================
; Frame Clock — Per-Output Frame Scheduling
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"

extern output_schedule_vblank
extern ut_timer_cancel

; struct offsets (hoisted above use)
%define FrameClock_output      0
%define FrameClock.output 0
%define FrameClock_refresh_ns  8
%define FrameClock.refresh_ns 8
%define FrameClock_next_vblank 16
%define FrameClock.next_vblank 16
%define FrameClock_phase       24
%define FrameClock.phase 24
%define FrameClock_callbacks   32
%define FrameClock.callbacks 32
%define FrameClock_size        40

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
    EPILOGUE_RESTORE rbx, r12
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
    call ut_time_now_ns
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
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; frame_clock_schedule
;   Schedule frame callback for next vblank
;   IN:  rdi = frame_clock*, rsi = callback_fn, rdx = user_data
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global frame_clock_schedule
frame_clock_schedule:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    test r12, r12
    jz .invalid
    mov rdi, 32
    xor esi, esi
    mov eax, SYS_MEM_ALLOC
    syscall
    test rax, rax
    jz .oom
    test rax, rax
    js .out
    mov qword [rax], 0
    mov rcx, [rbx + FrameClock.callbacks]
    mov [rax + 8], rcx
    mov [rax + 16], r12
    mov [rax + 24], r13
    mov [rbx + FrameClock.callbacks], rax
    xor rax, rax
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.invalid:
    mov rax, -(EINVAL)
    jmp .out
.oom:
    mov rax, -(ENOMEM)
    jmp .out
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

    ; Detach the one-shot callback batch before invoking user code. New callbacks
    ; scheduled from a callback are therefore deferred to the next vblank.
    mov r13, [rbx + FrameClock.callbacks]
    mov qword [rbx + FrameClock.callbacks], 0
    test r13, r13
    jz .done

.callback_loop:
    mov rax, [r13 + 8]
    mov [rbx + FrameClock.phase], rax
    mov rdi, r12
    mov rsi, [r13 + 24]
    call qword [r13 + 16]
    mov rax, [rbx + FrameClock.phase]
    mov rdi, r13
    mov r13, rax
    mov eax, SYS_MEM_FREE
    syscall
    test r13, r13
    jnz .callback_loop

.done:
    ; Schedule next vblank
    mov rdi, [rbx + FrameClock.output]
    call output_schedule_vblank

    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; frame_clock_get_phase
;   Get frame phase (time until next vblank)
; ---------------------------------------------------------------------------
global frame_clock_get_phase
frame_clock_get_phase:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rdi

    call ut_time_now_ns
    mov rdx, [rbx + FrameClock.next_vblank]
    sub rdx, rax
    jns .phase_ok
    xor edx, edx
.phase_ok:
    mov rax, rdx
    EPILOGUE_RESTORE rbx
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
    leave
    ret

; Cancel the armed one-shot timer and release queued callback nodes.
global frame_clock_deinit
frame_clock_deinit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rdi, [rbx + FrameClock.phase]
    test rdi, rdi
    jz .free_callbacks
    call ut_timer_cancel
    mov qword [rbx + FrameClock.phase], 0
.free_callbacks:
    mov r12, [rbx + FrameClock.callbacks]
    mov qword [rbx + FrameClock.callbacks], 0
.free_loop:
    test r12, r12
    jz .deinit_done
    mov rbx, [r12 + 8]
    mov rdi, r12
    mov eax, SYS_MEM_FREE
    syscall
    mov r12, rbx
    jmp .free_loop
.deinit_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data


global frame_clock_version
frame_clock_version: dq 0x010000
