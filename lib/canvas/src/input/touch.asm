; Touch Input Handling - bounded multi-touch slots and surface delivery
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/input.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern surface_touch_down
extern surface_touch_up
extern surface_touch_motion
extern surface_touch_cancel
extern surface_unset_touch_focus

%define TOUCH_SLOTS Touch.slots
%define TOUCH_NUM_SLOTS Touch.num_slots
%define TOUCH_MAX Touch.max_slots
%define TOUCH_ACTIVE Touch.active_slots
%define TOUCH_SURFACE Touch.surface
%define SLOT_ID TouchSlot.tracking_id
%define SLOT_X TouchSlot.x
%define SLOT_Y TouchSlot.y
%define SLOT_ACTIVE TouchSlot.active

section .text

global touch_create
touch_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov qword [rbx + InputDevice_TYPE], INPUT_TYPE_TOUCH
    mov [rbx + InputDevice_NAME], r13
    mov [rbx + InputDevice_SEAT], r12
    mov [rbx + InputDevice_CAPS], r14d
    mov qword [rbx + InputDevice_NEXT], 0
    mov qword [rbx + TOUCH_SLOTS], 0
    mov dword [rbx + TOUCH_NUM_SLOTS], TOUCH_MAX_SLOTS
    mov dword [rbx + TOUCH_MAX], TOUCH_MAX_SLOTS
    mov dword [rbx + TOUCH_ACTIVE], 0
    mov qword [rbx + TOUCH_SURFACE], 0
    mov rdi, [r12 + Seat.arena]
    mov rsi, TOUCH_MAX_SLOTS * TouchSlot_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + TOUCH_SLOTS], rax
    xor ecx, ecx
.init:
    mov dword [rax + SLOT_ID], -1
    mov byte [rax + SLOT_ACTIVE], 0
    add rax, TouchSlot_SIZE
    inc ecx
    cmp ecx, TOUCH_MAX_SLOTS
    jb .init
    mov rax, [r12 + Seat.devices]
    mov [rbx + InputDevice_NEXT], rax
    mov [r12 + Seat.devices], rbx
    test r14d, DEVICE_CAP_TOUCH
    jz .ok
    mov [r12 + Seat.touch], rbx
.ok:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

global touch_destroy
touch_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    call touch_unlink_from_seat
    mov rdi, [rbx + TOUCH_SURFACE]
    test rdi, rdi
    jz .done
    call surface_unset_touch_focus
.done:
    mov qword [rbx + TOUCH_SURFACE], 0
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

touch_unlink_from_seat:
    mov r12, [rbx + InputDevice_SEAT]
    test r12, r12
    jz .done
    lea rdx, [r12 + Seat.devices]
.scan:
    mov rax, [rdx]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    lea rdx, [rax + InputDevice_NEXT]
    jmp .scan
.unlink:
    mov rax, [rbx + InputDevice_NEXT]
    mov [rdx], rax
    cmp [r12 + Seat.touch], rbx
    jne .done
    mov qword [r12 + Seat.touch], 0
.done:
    ret

global touch_down
touch_down:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    cmp r12d, TOUCH_MAX_SLOTS
    jae .no_slot
    call touch_slot_ptr
    cmp byte [rax + SLOT_ACTIVE], 0
    jne .no_slot
    mov [rax + SLOT_ID], r15d
    mov [rax + SLOT_X], r13d
    mov [rax + SLOT_Y], r14d
    mov byte [rax + SLOT_ACTIVE], 1
    inc dword [rbx + TOUCH_ACTIVE]
    mov rdi, [rbx + TOUCH_SURFACE]
    test rdi, rdi
    jz .done
    mov esi, r15d
    mov edx, r13d
    mov ecx, r14d
    call surface_touch_down
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.no_slot:
    mov rax, -ENOSPC
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global touch_up
touch_up:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    call touch_find_id
    test rax, rax
    jz .done
    mov byte [rax + SLOT_ACTIVE], 0
    mov dword [rax + SLOT_ID], -1
    cmp dword [rbx + TOUCH_ACTIVE], 0
    je .notify
    dec dword [rbx + TOUCH_ACTIVE]
.notify:
    mov rdi, [rbx + TOUCH_SURFACE]
    test rdi, rdi
    jz .done
    mov esi, r12d
    call surface_touch_up
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

global touch_motion
touch_motion:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx
    call touch_find_id
    test rax, rax
    jz .not_found
    mov [rax + SLOT_X], r13d
    mov [rax + SLOT_Y], r14d
    mov rdi, [rbx + TOUCH_SURFACE]
    test rdi, rdi
    jz .done
    mov esi, r12d
    mov edx, r13d
    mov ecx, r14d
    call surface_touch_motion
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.not_found:
    mov rax, -ENOENT
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

global touch_cancel
touch_cancel:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    xor r12d, r12d
.loop:
    cmp r12d, TOUCH_MAX_SLOTS
    jae .finished
    call touch_slot_ptr
    cmp byte [rax + SLOT_ACTIVE], 0
    je .next
    mov byte [rax + SLOT_ACTIVE], 0
    mov dword [rax + SLOT_ID], -1
.next:
    inc r12d
    jmp .loop
.finished:
    mov dword [rbx + TOUCH_ACTIVE], 0
    mov rdi, [rbx + TOUCH_SURFACE]
    test rdi, rdi
    jz .done
    call surface_touch_cancel
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

global touch_set_surface
touch_set_surface:
    ASSERT_PTR rdi
    mov [rdi + TOUCH_SURFACE], rsi
    xor eax, eax
    ret

global touch_get_slot
touch_get_slot:
    cmp esi, TOUCH_MAX_SLOTS
    jae .invalid
    mov eax, esi
    imul rax, TouchSlot_SIZE
    add rax, [rdi + TOUCH_SLOTS]
    ret
.invalid:
    xor eax, eax
    ret

touch_slot_ptr:
    mov eax, r12d
    imul rax, TouchSlot_SIZE
    add rax, [rbx + TOUCH_SLOTS]
    ret

touch_find_id:
    mov rax, [rbx + TOUCH_SLOTS]
    xor ecx, ecx
.loop:
    cmp ecx, TOUCH_MAX_SLOTS
    jae .missing
    cmp byte [rax + SLOT_ACTIVE], 0
    je .next
    cmp dword [rax + SLOT_ID], r12d
    je .found
.next:
    add rax, TouchSlot_SIZE
    inc ecx
    jmp .loop
.missing:
    xor eax, eax
.found:
    ret

section .data
global touch_version
touch_version: dq 0x010000
