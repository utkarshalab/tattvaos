%ifndef GUARD_LIB_TIME_TIMER_WHEEL_ASM
%define GUARD_LIB_TIME_TIMER_WHEEL_ASM
; =============================================================================
; Tattva OS — lib/time/timer_wheel.asm
; =============================================================================
; Hierarchical Hashed Timer Wheel Engine (O(1) Insert/Delete/Expire).
;
; 4-Level Hierarchical Wheel (Linux-style):
;   Level 0 (TVR):  256 slots × 1 tick     =   256 ticks  (~256ms @ 1kHz)
;   Level 1 (TVN):   64 slots × 256 ticks  = 16,384 ticks (~16s)
;   Level 2 (TVN):   64 slots × 16,384     =  1M ticks    (~17min)
;   Level 3 (TVN):   64 slots × 1M         =  67M ticks   (~18hrs)
;
; Total range: ~18 hours at 1kHz tick rate
; O(1) insert, O(1) delete (with list_head), O(1) cascade per tick
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/time/time.inc"

%define TVR_SIZE            256
%define TVN_SIZE            64
%define TVR_MASK            (TVR_SIZE - 1)
%define TVN_MASK            (TVN_SIZE - 1)

; Timer wheel levels
%define WHEEL_L0            0   ; 1 tick resolution
%define WHEEL_L1            1   ; 256 ticks
%define WHEEL_L2            2   ; 16384 ticks
%define WHEEL_L3            3   ; 1048576 ticks

struc timer_entry_t
    .expires:   resq 1      ; Absolute expiration tick (64-bit)
    .fn:        resq 1      ; Callback function pointer
    .arg:       resq 1      ; Callback argument
    .next:      resq 1      ; Next in bucket list
    .prev:      resq 1      ; Prev in bucket list (for O(1) delete)
    .active:    resb 1      ; 1 = armed, 0 = free
    .level:     resb 1      ; Wheel level (0-3)
    .pad:       resw 1
    .reserved:  resd 1
endstruc

struc timer_wheel_t
    ; Level 0: 256 buckets (1 tick)
    .tv1:           resq TVR_SIZE
    ; Level 1: 64 buckets (256 ticks)
    .tv2:           resq TVN_SIZE
    ; Level 2: 64 buckets (16384 ticks)
    .tv3:           resq TVN_SIZE
    ; Level 3: 64 buckets (1048576 ticks)
    .tv4:           resq TVN_SIZE
    .current_tick:  resq 1
    .pending_cnt:   resd 1      ; Active timer count
endstruc

section .bss
alignb 64
global timer_wheel
timer_wheel:      resb timer_wheel_t_size

section .text

global timer_wheel_init
global timer_wheel_add
global timer_wheel_del
global timer_wheel_tick
global timer_wheel_get_tick

; -----------------------------------------------------------------------------
; timer_wheel_init — Initialize 4-level hierarchical timer wheel
; Input: RDI = pointer to timer_wheel_t (or 0 for global)
; -----------------------------------------------------------------------------
align 64
timer_wheel_init:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    test rdi, rdi
    jz .use_global
    mov rbx, rdi
    jmp .init_wheel

.use_global:
    mov rbx, timer_wheel

.init_wheel:
    ; Zero all buckets
    xor eax, eax
    mov rcx, (TVR_SIZE + TVN_SIZE * 3)
    lea rdi, [rbx + timer_wheel_t.tv1]
    rep stosq

    mov qword [rbx + timer_wheel_t.current_tick], 0
    mov dword [rbx + timer_wheel_t.pending_cnt], 0

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; timer_wheel_get_tick — Get current timer wheel tick
; Output: RAX = current tick
; -----------------------------------------------------------------------------
align 16
timer_wheel_get_tick:
    mov rax, [rel timer_wheel + timer_wheel_t.current_tick]
    ret

; -----------------------------------------------------------------------------
; _timer_cascade — Cascade timers from higher wheel level to lower
; Input: RDI = timer_wheel_t*, RSI = level (1-3), RDX = index
; -----------------------------------------------------------------------------
align 32
_timer_cascade:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; timer_wheel_t*
    mov r12, rsi            ; level
    mov r13, rdx            ; index

    ; Get bucket head for this level/index
    cmp r12, 1
    je .cascade_tv2
    cmp r12, 2
    je .cascade_tv3
    cmp r12, 3
    je .cascade_tv4

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.cascade_tv2:
    lea r14, [rbx + timer_wheel_t.tv2 + r13 * 8]
    jmp .do_cascade

.cascade_tv3:
    lea r14, [rbx + timer_wheel_t.tv3 + r13 * 8]
    jmp .do_cascade

.cascade_tv4:
    lea r14, [rbx + timer_wheel_t.tv4 + r13 * 8]
    jmp .do_cascade

.do_cascade:
    mov r15, [r14]          ; Head of bucket list
    test r15, r15
    jz .done_cascade

    mov qword [r14], 0      ; Clear bucket

.cascade_loop:
    mov r13, [r15 + timer_entry_t.next]
    dec dword [rbx + timer_wheel_t.pending_cnt]
    mov rdi, r15
    mov rsi, rbx
    call _timer_reinsert    ; Recalculate level/bucket for current tick

    mov r15, r13
    test r15, r15
    jnz .cascade_loop

.done_cascade:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; _timer_reinsert — Recalculate wheel level and bucket for timer
; Input: RDI = timer_entry_t*, RSI = timer_wheel_t*
; -----------------------------------------------------------------------------
align 32
_timer_reinsert:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi            ; timer_entry_t*
    mov r12, rsi            ; timer_wheel_t*

    mov rax, [rbx + timer_entry_t.expires]
    mov rcx, [r12 + timer_wheel_t.current_tick]
    sub rax, rcx            ; Relative ticks from now
    jle .expired_now

    ; Determine wheel level based on relative timeout
    cmp rax, TVR_SIZE
    jb .level0
    cmp rax, TVR_SIZE * TVN_SIZE
    jb .level1
    cmp rax, TVR_SIZE * TVN_SIZE * TVN_SIZE
    jb .level2
    jmp .level3

.level0:
    mov byte [rbx + timer_entry_t.level], WHEEL_L0
    mov rdx, [rbx + timer_entry_t.expires]
    and rdx, TVR_MASK
    lea rdi, [r12 + timer_wheel_t.tv1 + rdx * 8]
    jmp .insert_bucket

.level1:
    mov byte [rbx + timer_entry_t.level], WHEEL_L1
    mov rdx, [rbx + timer_entry_t.expires]
    shr rdx, 8              ; / 256
    and rdx, TVN_MASK
    lea rdi, [r12 + timer_wheel_t.tv2 + rdx * 8]
    jmp .insert_bucket

.level2:
    mov byte [rbx + timer_entry_t.level], WHEEL_L2
    mov rdx, [rbx + timer_entry_t.expires]
    shr rdx, 14             ; / 16384
    and rdx, TVN_MASK
    lea rdi, [r12 + timer_wheel_t.tv3 + rdx * 8]
    jmp .insert_bucket

.level3:
    mov byte [rbx + timer_entry_t.level], WHEEL_L3
    mov rdx, [rbx + timer_entry_t.expires]
    shr rdx, 20             ; / 1048576
    and rdx, TVN_MASK
    lea rdi, [r12 + timer_wheel_t.tv4 + rdx * 8]
    jmp .insert_bucket

.expired_now:
    ; Timer already expired - will be processed on next tick
    mov byte [rbx + timer_entry_t.level], WHEEL_L0
    lea rdi, [r12 + timer_wheel_t.tv1]

.insert_bucket:
    ; Insert at head of bucket list (lockless, single-producer)
    mov rax, [rdi]
    mov [rbx + timer_entry_t.next], rax
    test rax, rax
    jz .no_prev
    mov [rax + timer_entry_t.prev], rbx
.no_prev:
    mov qword [rbx + timer_entry_t.prev], 0
    mov qword [rdi], rbx

    inc dword [r12 + timer_wheel_t.pending_cnt]
    mov byte [rbx + timer_entry_t.active], 1

    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; timer_wheel_add — Add timer with relative delay in ticks
; Input: RDI = timer_entry_t*, RSI = delay_ticks (relative)
;        RDX = callback function, RCX = callback argument
; Output: RAX = 0 on success, -1 on error
; -----------------------------------------------------------------------------
align 64
timer_wheel_add:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi            ; timer_entry_t*
    mov r12, rsi            ; delay_ticks
    mov r13, rdx            ; callback fn
    mov r14, rcx            ; callback arg

    test rbx, rbx
    jz .error
    test r12, r12
    jz .error

    ; Check if already active
    cmp byte [rbx + timer_entry_t.active], 1
    je .error

    ; Set callback
    mov [rbx + timer_entry_t.fn], r13
    mov [rbx + timer_entry_t.arg], r14

    ; Calculate absolute expiration
    mov rax, [rel timer_wheel + timer_wheel_t.current_tick]
    add rax, r12
    mov [rbx + timer_entry_t.expires], rax

    ; Insert into wheel (use global wheel)
    mov rdi, rbx
    mov rsi, timer_wheel
    call _timer_reinsert

    xor eax, eax
    jmp .done

.error:
    mov eax, -1

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; timer_wheel_del — Remove timer from wheel (O(1) with prev pointer)
; Input: RDI = timer_entry_t*
; Output: RAX = 0 on success, -1 if not active
; -----------------------------------------------------------------------------
align 64
timer_wheel_del:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi

    cmp byte [rbx + timer_entry_t.active], 1
    jne .not_active

    ; Unlink from bucket list
    mov r12, [rbx + timer_entry_t.prev]
    mov r13, [rbx + timer_entry_t.next]

    test r12, r12
    jz .unlink_head
    mov [r12 + timer_entry_t.next], r13
    test r13, r13
    jz .unlink_done
    mov [r13 + timer_entry_t.prev], r12
    jmp .unlink_done

.unlink_head:
    ; Find bucket head and update
    movzx r12, byte [rbx + timer_entry_t.level]
    mov rax, [rbx + timer_entry_t.expires]
    cmp r12, WHEEL_L0
    je .unlink_tv1
    cmp r12, WHEEL_L1
    je .unlink_tv2
    cmp r12, WHEEL_L2
    je .unlink_tv3
    jmp .unlink_tv4

.unlink_tv1:
    mov rdx, [rbx + timer_entry_t.expires]
    and rdx, TVR_MASK
    lea r12, [timer_wheel + timer_wheel_t.tv1 + rdx * 8]
    jmp .do_unlink_head

.unlink_tv2:
    mov rdx, [rbx + timer_entry_t.expires]
    shr rdx, 8
    and rdx, TVN_MASK
    lea r12, [timer_wheel + timer_wheel_t.tv2 + rdx * 8]
    jmp .do_unlink_head

.unlink_tv3:
    mov rdx, [rbx + timer_entry_t.expires]
    shr rdx, 14
    and rdx, TVN_MASK
    lea r12, [timer_wheel + timer_wheel_t.tv3 + rdx * 8]
    jmp .do_unlink_head

.unlink_tv4:
    mov rdx, [rbx + timer_entry_t.expires]
    shr rdx, 20
    and rdx, TVN_MASK
    lea r12, [timer_wheel + timer_wheel_t.tv4 + rdx * 8]
    jmp .do_unlink_head

.do_unlink_head:
    mov qword [r12], r13
    test r13, r13
    jz .unlink_done
    mov qword [r13 + timer_entry_t.prev], 0

.unlink_done:
    ; Clear timer entry
    mov qword [rbx + timer_entry_t.next], 0
    mov qword [rbx + timer_entry_t.prev], 0
    mov byte [rbx + timer_entry_t.active], 0
    mov byte [rbx + timer_entry_t.level], 0

    dec dword [rel timer_wheel + timer_wheel_t.pending_cnt]

    xor eax, eax
    jmp .done

.not_active:
    mov eax, -1

.done:
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; timer_wheel_tick — Advance wheel by 1 tick, process expired timers
; Input: RDI = timer_wheel_t* (0 = global)
; Output: RAX = number of timers expired
; -----------------------------------------------------------------------------
align 64
timer_wheel_tick:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    test rdi, rdi
    jz .use_global
    mov rbx, rdi
    jmp .do_tick

.use_global:
    mov rbx, timer_wheel

.do_tick:
    ; Advance current tick
    inc qword [rbx + timer_wheel_t.current_tick]
    mov r12, [rbx + timer_wheel_t.current_tick]

    ; Process Level 0 bucket
    mov r13, r12
    and r13, TVR_MASK
    lea r14, [rbx + timer_wheel_t.tv1 + r13 * 8]
    mov r15, [r14]
    mov qword [r14], 0

    mov r13, 0                  ; Expired count

.process_l0:
    test r15, r15
    jz .check_cascade

    mov rdi, r15
    mov r15, [r15 + timer_entry_t.next]

    ; Clear links
    mov qword [rdi + timer_entry_t.next], 0
    mov qword [rdi + timer_entry_t.prev], 0
    mov byte [rdi + timer_entry_t.active], 0
    dec dword [rbx + timer_wheel_t.pending_cnt]

    ; Call callback
    mov rax, [rdi + timer_entry_t.fn]
    test rax, rax
    jz .no_callback
    mov rdi, [rdi + timer_entry_t.arg]
    call rax

.no_callback:
    inc r13
    jmp .process_l0

.check_cascade:
    ; Check if we need to cascade higher levels
    test r12, TVR_MASK
    jnz .done_tick

    ; Cascade Level 1
    mov rdx, r12
    shr rdx, 8
    and rdx, TVN_MASK
    mov r15, rdx
    mov rdi, rbx
    mov rsi, WHEEL_L1
    call _timer_cascade
    test r15, r15
    jnz .done_tick

    ; Cascade Level 2
    mov rdx, r12
    shr rdx, 14
    and rdx, TVN_MASK
    mov r15, rdx
    mov rdi, rbx
    mov rsi, WHEEL_L2
    call _timer_cascade
    test r15, r15
    jnz .done_tick

    ; Cascade Level 3
    mov rdx, r12
    shr rdx, 20
    and rdx, TVN_MASK
    mov rdi, rbx
    mov rsi, WHEEL_L3
    call _timer_cascade

.done_tick:
    mov rax, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

%endif ; GUARD_LIB_TIME_TIMER_WHEEL_ASM
