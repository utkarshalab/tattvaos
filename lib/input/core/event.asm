; =============================================================================
; Utkarsha OS — lib/input/core/event.asm
; =============================================================================
; The event ring and the ut_input_* functions canvas calls.
;
; Drivers post events from their interrupt handlers into one ring. A fiber
; (lib/input/kernel.asm) drains it with input_pump and hands each event to
; the registered callback, so the callback never runs inside an interrupt
; (lib/canvas/docs/KERNEL_NEEDS.md, step 3: "one call at a time from any
; fiber is enough").
;
; Producers take a spin lock and must run with interrupts disabled, as
; interrupt handlers do; otherwise an interrupt on the same CPU could spin on
; a lock its own CPU holds. There is one consumer, so it takes no lock.
; =============================================================================

%ifndef LIB_INPUT_CORE_EVENT_ASM
%define LIB_INPUT_CORE_EVENT_ASM

section .bss
alignb 64
input_ring:         resb INPUT_RING_LEN * input_event_size
alignb 64
input_ring_tail:    resd 1              ; next slot to fill (producers)
alignb 64
input_ring_head:    resd 1              ; next slot to deliver (consumer)
input_ring_lock:    resd 1
global input_dropped
input_dropped:      resd 1              ; events lost to a full ring
global input_discarded
input_discarded:    resd 1              ; events with no callback to take them
alignb 8
input_cb_fn:        resq 1
input_cb_cookie:    resq 1

section .text

; -----------------------------------------------------------------------------
; input_init — empty the ring and the device list, forget the callback
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_init
input_init:
    xor eax, eax
    mov [rel input_ring_tail], eax
    mov [rel input_ring_head], eax
    mov [rel input_ring_lock], eax
    mov [rel input_dropped], eax
    mov [rel input_discarded], eax
    mov [rel input_cb_fn], rax
    mov [rel input_cb_cookie], rax
    jmp input_dev_reset

; -----------------------------------------------------------------------------
; input_post — queue one event (drivers, interrupts disabled)
; Input:  EDI = type, ESI = code, EDX = value, ECX = device ID
; Output: EAX = 0, or -INPUT_ENOSPC when the ring is full
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_post
input_post:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov ebx, edi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx

    ; count it against its device
    mov edi, ecx
    call input_dev_find
    test rax, rax
    jz .stamp
    inc dword [rax + input_dev.events]
.stamp:
    call input_now                      ; before the lock: it may be slow
    mov r8, rax

    ; take the lock
.spin:
    mov eax, 1
    xchg eax, [rel input_ring_lock]
    test eax, eax
    jz .locked
.wait:
    pause
    cmp dword [rel input_ring_lock], 0
    jne .wait
    jmp .spin
.locked:
    mov ecx, [rel input_ring_tail]
    mov eax, ecx
    sub eax, [rel input_ring_head]
    cmp eax, INPUT_RING_LEN
    jae .full

    mov eax, ecx
    and eax, INPUT_RING_LEN - 1
    imul eax, eax, input_event_size
    lea rdx, [rel input_ring]
    add rdx, rax
    mov [rdx + input_event.type], ebx
    mov [rdx + input_event.code], r12d
    mov [rdx + input_event.value], r13d
    mov [rdx + input_event.device], r14d
    mov [rdx + input_event.time], r8
    inc ecx
    mov [rel input_ring_tail], ecx      ; publish after the slot is written
    mov dword [rel input_ring_lock], 0
    xor eax, eax
    jmp .out
.full:
    inc dword [rel input_dropped]
    mov dword [rel input_ring_lock], 0
    mov eax, -INPUT_ENOSPC
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; input_pump — deliver every queued event to the callback (one fiber only)
; Output: EAX = events taken off the ring
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global input_pump
input_pump:
    push rbx
    push r12
    sub rsp, 8
    xor r12d, r12d
.next:
    mov ebx, [rel input_ring_head]
    cmp ebx, [rel input_ring_tail]
    je .done
    mov eax, ebx
    and eax, INPUT_RING_LEN - 1
    imul eax, eax, input_event_size
    lea rdi, [rel input_ring]
    add rdi, rax
    mov rax, [rel input_cb_fn]          ; reloaded: a callback may unregister
    test rax, rax
    jz .discard
    mov rsi, [rel input_cb_cookie]
    call rax                            ; copies the record before returning
    jmp .taken
.discard:
    inc dword [rel input_discarded]
.taken:
    inc ebx
    mov [rel input_ring_head], ebx      ; frees the slot for producers
    inc r12d
    jmp .next
.done:
    mov eax, r12d
    add rsp, 8
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ut_input_register_callback — receive every input event
; Input:  RDI = function(RDI = input_event*, RSI = cookie), RSI = cookie
; Output: RAX = 0; -INPUT_EINVAL for no function; -INPUT_EBUSY when a
;         callback is already registered
; -----------------------------------------------------------------------------
global ut_input_register_callback
ut_input_register_callback:
    test rdi, rdi
    jz .invalid
    cmp qword [rel input_cb_fn], 0
    jne .busy
    mov [rel input_cb_cookie], rsi      ; the cookie first: the pump reads
    mov [rel input_cb_fn], rdi          ; the function, then the cookie
    xor eax, eax
    ret
.invalid:
    mov rax, -INPUT_EINVAL
    ret
.busy:
    mov rax, -INPUT_EBUSY
    ret

; -----------------------------------------------------------------------------
; ut_input_unregister_callback — stop receiving events
; Output: RAX = 0
; -----------------------------------------------------------------------------
global ut_input_unregister_callback
ut_input_unregister_callback:
    xor eax, eax
    mov [rel input_cb_fn], rax
    ret

; -----------------------------------------------------------------------------
; ut_input_device_info — what a device is
; Input:  EDI = device ID
; Output: RAX = input_dev_info* (read-only), or -INPUT_ENODEV
; -----------------------------------------------------------------------------
global ut_input_device_info
ut_input_device_info:
    call input_dev_find
    test rax, rax
    jz .none
    ret
.none:
    mov rax, -INPUT_ENODEV
    ret

; -----------------------------------------------------------------------------
; ut_input_grab — take a device for one client (kiosk, direct scan-out)
; Input:  EDI = device ID, ESI = 1 to grab, 0 to release
; Output: RAX = 0; -INPUT_EBUSY when already grabbed; -INPUT_ENODEV
; With one callback the grab only marks the device; routing a grabbed
; device to its holder arrives with more than one receiver (ROADMAP.md §6.1).
; -----------------------------------------------------------------------------
global ut_input_grab
ut_input_grab:
    call input_dev_find
    test rax, rax
    jz .none
    test esi, esi
    jz .release
    test dword [rax + input_dev.flags], INPUT_DEV_GRABBED
    jnz .busy
    or dword [rax + input_dev.flags], INPUT_DEV_GRABBED
    xor eax, eax
    ret
.release:
    and dword [rax + input_dev.flags], ~INPUT_DEV_GRABBED
    xor eax, eax
    ret
.busy:
    mov rax, -INPUT_EBUSY
    ret
.none:
    mov rax, -INPUT_ENODEV
    ret

%endif ; LIB_INPUT_CORE_EVENT_ASM
