; ============================================================================
; Touch Input Handling — Multi-touch, Slots, Gestures
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/input.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; touch_create
;   Create touch device
; ============================================================================
global touch_create
touch_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi       ; seat
    mov r13, rdx       ; name
    mov r14d, ecx      ; capabilities
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + InputDevice_TYPE], INPUT_TYPE_TOUCH
    mov qword [rbx + InputDevice_NAME], r13
    mov qword [rbx + InputDevice_SEAT], r12
    mov dword [rbx + InputDevice_CAPS], r14d
    mov qword [rbx + InputDevice_NEXT], 0

    ; Initialize touch state
    mov qword [rbx + Touch_SLOTS], 0
    mov dword [rbx + Touch_NUM_SLOTS], 0
    mov dword [rbx + Touch_MAX_SLOTS], TOUCH_MAX_SLOTS
    mov dword [rbx + Touch_ACTIVE_SLOTS], 0
    mov qword [rbx + Touch_SURFACE], 0

    ; Allocate slots array
    mov rdi, TOUCH_MAX_SLOTS * 32  ; TouchSlot_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Touch_SLOTS], rax

    ; Initialize slots
    mov rcx, TOUCH_MAX_SLOTS
    xor rdx, rdx
.init_loop:
    mov qword [rax + rdx + TouchSlot_TRACKING_ID], 0xFFFFFFFF
    add rdx, 32
    dec rcx
    jnz .init_loop

    ; Add to seat's device list
    mov rax, [r12 + SEAT_DEVICES]
    mov [rbx + InputDevice_NEXT], rax
    mov [r12 + SEAT_DEVICES], rbx

    ; If touch capability, set as seat touch
    mov r14d, [r12 + SEAT_CAPABILITIES]
    test r14d, DEVICE_CAP_TOUCH
    jz .done
    mov [r12 + SEAT_TOUCH], rbx

.done:
    xor rax, rax
    leave
    ret

.oom:
    mov rax, -ENOMEM
    leave
    ret

; ============================================================================
; touch_destroy
;   Destroy touch device
; ============================================================================
global touch_destroy
touch_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Remove from seat's device list
    mov r12, [rbx + InputDevice_SEAT]
    call .unlink_from_seat

    ; Release grab on surface
    mov rax, [rbx + Touch_SURFACE]
    test rax, rax
    jz .done
    call surface_unset_touch_focus

.done:
    xor rax, rax
    leave
    ret

.unlink_from_seat:
    mov r12, [rbx + InputDevice_SEAT]
    mov rax, [r12 + SEAT_DEVICES]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + InputDevice_NEXT]
    mov [r12 + SEAT_DEVICES], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + InputDevice_NEXT]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + InputDevice_NEXT]
    mov [r12 + InputDevice_NEXT], rax

.done:
    ret

; ============================================================================
; touch_down
;   Touch down event
; ============================================================================
global touch_down
touch_down:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi       ; slot
    mov r13d, edx       ; x
    mov r14d, ecx       ; y
    mov r15d, r8d       ; tracking_id
    ASSERT_PTR rbx

    ; Find free slot
    call .find_free_slot
    test rax, rax
    jz .no_slot

    mov r12d, eax       ; slot index

    ; Update slot
    mov r13, [rbx + Touch_SLOTS]
    imul r12, 32  ; TouchSlot_SIZE
    add r13, r12

    mov dword [r13 + TouchSlot_TRACKING_ID], r15d
    mov dword [r13 + TouchSlot_X], r13d  ; x
    mov dword [r13 + TouchSlot_Y], r14d  ; y
    mov byte [r13 + TouchSlot_ACTIVE], 1

    ; Update active slots
    inc dword [rbx + Touch_ACTIVE_SLOTS]

    ; Get surface focus
    mov rax, [rbx + Touch_SURFACE]
    test rax, rax
    jz .done

    ; Send down event
    mov rdi, rax
    mov esi, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_TRACKING_ID]
    mov edx, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_X]
    mov ecx, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_Y]
    call surface_touch_down

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_slot:
    mov rax, -ENOSPC
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; touch_up
;   Touch up event
; ============================================================================
global touch_up
touch_up:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi       ; tracking_id
    mov r13d, edx       ; x
    mov r14d, ecx       ; y
    ASSERT_PTR rbx

    ; Find slot with tracking_id
    call .find_slot_by_id
    test rax, rax
    jz .done

    mov r12, rax        ; slot index

    ; Update slot
    imul r12, 32
    add r12, [rbx + Touch_SLOTS]

    mov dword [r12 + TouchSlot_TRACKING_ID], 0xFFFFFFFF
    mov byte [r12 + TouchSlot_ACTIVE], 0

    ; Update active slots
    dec dword [rbx + Touch_ACTIVE_SLOTS]

    ; Send up event
    mov rax, [rbx + Touch_SURFACE]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_TRACKING_ID]
    mov edx, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_X]
    mov ecx, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_Y]
    call surface_touch_up

    xor rax, rax
    leave
    ret

; ============================================================================
; touch_motion
;   Touch motion event
; ============================================================================
global touch_motion
touch_motion:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi       ; tracking_id
    mov r13d, edx       ; x
    mov r14d, ecx       ; y
    ASSERT_PTR rbx

    ; Find slot
    call .find_slot_by_id
    test rax, rax
    jz .done

    mov r12, rax        ; slot index

    ; Update position
    imul r12, 32
    add r12, [rbx + Touch_SLOTS]

    mov dword [r12 + TouchSlot_X], r13d
    mov dword [r12 + TouchSlot_Y], r14d

    ; Send motion event
    mov rax, [rbx + Touch_SURFACE]
    test rax, rax
    jz .done

    mov rdi, rax
    mov esi, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_TRACKING_ID]
    mov edx, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_X]
    mov ecx, [rbx + Touch_SLOTS + rax * 32 + TouchSlot_Y]
    call surface_touch_motion

    xor rax, rax
    leave
    ret

; ============================================================================
; touch_cancel
;   Cancel all touches
; ============================================================================
global touch_cancel
touch_cancel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    mov r12d, [rbx + Touch_ACTIVE_SLOTS]
    test r12d, r12d
    jz .done

    ; Cancel all active slots
    xor r13d, r13d
.cancel_loop:
    cmp r13d, TOUCH_MAX_SLOTS
    jge .done

    imul r12, r13d, 32
    add r12, [rbx + Touch_SLOTS]

    cmp byte [r12 + TouchSlot_ACTIVE], 0
    je .next_slot

    ; Send cancel event
    mov rax, [rbx + Touch_SURFACE]
    test rax, rax
    jz .next_slot

    mov rdi, rax
    mov esi, [rbx + Touch_SLOTS + r13d * 32 + TouchSlot_TRACKING_ID]
    call surface_touch_cancel

.next_slot:
    inc r13d
    jmp .cancel_loop

.done:
    ; Clear all slots
    mov rcx, TOUCH_MAX_SLOTS
    mov rdi, [rbx + Touch_SLOTS]
    xor rax, rax
    mov qword [rdi + TouchSlot_TRACKING_ID], 0xFFFFFFFF
    mov byte [rdi + TouchSlot_ACTIVE], 0
    ; ... clear all slots

    xor rax, rax
    leave
    ret

; ============================================================================
; .find_free_slot
;   Find first free slot
; ============================================================================
.find_free_slot:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi

    xor r12d, r12d
    mov r13, [rbx + Touch_SLOTS]

.loop:
    cmp r12d, TOUCH_MAX_SLOTS
    jge .not_found

    imul r13, r12d, 32
    add r13, [rbx + Touch_SLOTS]

    cmp byte [r13 + TouchSlot_ACTIVE], 0
    je .found

    inc r12d
    jmp .loop

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.found:
    mov eax, r12d
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; .find_slot_by_id
;   Find slot by tracking_id
; ============================================================================
.find_slot_by_id:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi       ; tracking_id

    xor r13d, r13d

.loop:
    cmp r13d, TOUCH_MAX_SLOTS
    jge .not_found

    imul r12, r13d, 32
    add r12, [rbx + Touch_SLOTS]

    cmp byte [r12 + TouchSlot_ACTIVE], 0
    je .next_slot

    cmp dword [r12 + TouchSlot_TRACKING_ID], r12d
    je .found

.next_slot:
    inc r13d
    jmp .loop

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.found:
    mov eax, r13d
    EPILOGUE_RESTORE rbx, r13
    ret

; ============================================================================
; touch_set_surface
;   Set touch focus surface
; ============================================================================
global touch_set_surface
touch_set_surface:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov qword [rbx + Touch_SURFACE], r12
    xor rax, rax
    leave
    ret

; ============================================================================
; touch_get_slot
;   Get slot info
; ============================================================================
global touch_get_slot
touch_get_slot:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx

    cmp r12d, TOUCH_MAX_SLOTS
    jge .invalid

    imul rax, r12d, 32
    add rax, [rbx + Touch_SLOTS]

    mov r12d, [rax + TouchSlot_TRACKING_ID]
    mov r13d, [rax + TouchSlot_X]
    mov r14d, [rax + TouchSlot_Y]
    mov r15b, [rax + TouchSlot_ACTIVE]

    mov eax, 1
    leave
    ret

.invalid:
    xor rax, rax
    leave
    ret

section .data
global touch_version
touch_version: dq 0x010000