; ============================================================================
; Seat Management — Multi-device Input Coordination, Focus, Selection
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/input.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; seat_create
;   Create seat
; ============================================================================
global seat_create
seat_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi       ; name
    mov r13, rdx       ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + Seat_NAME], r12
    mov qword [rbx + Seat_ARENA], r13

    ; Initialize capabilities
    mov dword [rbx + Seat_CAPABILITIES], DEVICE_CAP_POINTER | DEVICE_CAP_KEYBOARD | DEVICE_CAP_TOUCH

    ; Initialize device lists
    mov qword [rbx + Seat_DEVICES], 0
    mov qword [rbx + Seat_POINTER], 0
    mov qword [rbx + Seat_KEYBOARD], 0
    mov qword [rbx + Seat_TOUCH], 0
    mov qword [rbx + Seat_TABLET], 0

    ; Initialize focus
    mov qword [rbx + Seat_POINTER_FOCUS], 0
    mov qword [rbx + Seat_KEYBOARD_FOCUS], 0
    mov qword [rbx + Seat_SELECTION], 0

    ; Initialize grabs
    mov qword [rbx + Seat_GRABS], 0

    ; Initialize selection
    mov qword [rbx + Seat_SELECTION_SOURCE], 0
    mov qword [rbx + Seat_SELECTION_SERIAL], 0

    ; Initialize drag
    mov qword [rbx + Seat_DRAG_SOURCE], 0
    mov qword [rbx + Seat_DRAG_ICON], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; seat_destroy
;   Destroy seat
; ============================================================================
global seat_destroy
seat_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Destroy all devices
    mov rax, [rbx + Seat_DEVICES]
.device_loop:
    test rax, rax
    jz .devices_done

    push rax
    call [rax + InputDevice_DESTROY]
    pop rax
    mov rax, [rax + InputDevice_NEXT]
    jmp .device_loop

.devices_done:
    ; Release grabs
    mov rax, [rbx + Seat_GRABS]
.grab_loop:
    test rax, rax
    jz .grabs_done
    call grab_destroy
    mov rax, [rax + Grab_NEXT]
    jmp .grab_loop

.grabs_done:
    ; Release selection
    mov rax, [rbx + Seat_SELECTION_SOURCE]
    test rax, rax
    jz .selection_done
    call data_source_destroy

.selection_done:
    ; Release drag
    mov rax, [rbx + Seat_DRAG_SOURCE]
    test rax, rax
    jz .drag_done
    call data_source_destroy

.drag_done:
    xor rax, rax
    leave
    ret

; ============================================================================
; seat_add_device
;   Add device to seat
; ============================================================================
global seat_add_device
seat_add_device:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi       ; seat
    mov r12, rsi       ; device
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Add to device list
    mov rax, [rbx + Seat_DEVICES]
    mov [r12 + InputDevice_NEXT], rax
    mov [rbx + Seat_DEVICES], r12

    ; Set device's seat
    mov qword [r12 + InputDevice_SEAT], rbx

    ; Update capabilities
    mov eax, [r12 + InputDevice_CAPS]
    or dword [rbx + Seat_CAPABILITIES], eax

    ; Set as primary device if first of type
    mov eax, [r12 + InputDevice_CAPS]
    test eax, DEVICE_CAP_POINTER
    jz .check_keyboard
    cmp qword [rbx + Seat_POINTER], 0
    jne .check_keyboard
    mov qword [rbx + Seat_POINTER], rbx
.check_keyboard:
    test eax, DEVICE_CAP_KEYBOARD
    jz .check_touch
    cmp qword [rbx + Seat_KEYBOARD], 0
    jne .check_touch
    mov qword [rbx + Seat_KEYBOARD], rbx
.check_touch:
    test eax, DEVICE_CAP_TOUCH
    jz .check_tablet
    cmp qword [rbx + Seat_TOUCH], 0
    jne .check_tablet
    mov qword [rbx + Seat_TOUCH], rbx
.check_tablet:
    test eax, DEVICE_CAP_TABLET
    jz .done
    cmp qword [rbx + Seat_TABLET], 0
    jne .done
    mov qword [rbx + Seat_TABLET], rbx

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; seat_remove_device
;   Remove device from seat
; ============================================================================
global seat_remove_device
seat_remove_device:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Remove from device list
    mov rax, [rbx + Seat_DEVICES]
    test rax, rax
    jz .done

    cmp rax, r12
    jne .find_prev

    mov rax, [r12 + InputDevice_NEXT]
    mov [rbx + Seat_DEVICES], rax
    jmp .check_primary

.find_prev:
    mov r13, rax
.prev_loop:
    mov rax, [r13 + InputDevice_NEXT]
    test rax, rax
    jz .done
    cmp rax, r12
    je .unlink
    mov r13, rax
    jmp .prev_loop

.unlink:
    mov rax, [r12 + InputDevice_NEXT]
    mov [r13 + InputDevice_NEXT], rax

.check_primary:
    ; If this was primary device of its type, find another
    mov eax, [r12 + InputDevice_CAPS]

    test eax, DEVICE_CAP_POINTER
    jz .check_keyboard
    cmp qword [rbx + Seat_POINTER], r12
    jne .check_keyboard
    call .find_pointer

.check_keyboard:
    test eax, DEVICE_CAP_KEYBOARD
    jz .check_touch
    cmp qword [rbx + Seat_KEYBOARD], r12
    jne .check_touch
    call .find_keyboard

.check_touch:
    test eax, DEVICE_CAP_TOUCH
    jz .check_tablet
    cmp qword [rbx + Seat_TOUCH], r12
    jne .check_tablet
    call .find_touch

.check_tablet:
    test eax, DEVICE_CAP_TABLET
    jz .done
    cmp qword [rbx + Seat_TABLET], r12
    jne .done
    call .find_tablet

.done:
    xor rax, rax
    leave
    ret

.find_pointer:
    mov rax, [rbx + Seat_DEVICES]
.find_pointer_loop:
    test rax, rax
    jz .done
    mov eax, [rax + InputDevice_CAPS]
    test eax, DEVICE_CAP_POINTER
    jz .next_pointer
    mov qword [rbx + Seat_POINTER], rax
    ret
.next_pointer:
    mov rax, [rax + InputDevice_NEXT]
    test rax, rax
    jnz .find_pointer_loop
    mov qword [rbx + Seat_POINTER], 0
    ret

.find_keyboard:
    mov rax, [rbx + Seat_DEVICES]
.find_keyboard_loop:
    test rax, rax
    jz .done
    mov eax, [rax + InputDevice_CAPS]
    test eax, DEVICE_CAP_KEYBOARD
    jz .next_keyboard
    mov qword [rbx + Seat_KEYBOARD], rax
    ret
.next_keyboard:
    mov rax, [rax + InputDevice_NEXT]
    test rax, rax
    jnz .find_keyboard_loop
    mov qword [rbx + Seat_KEYBOARD], 0
    ret

.find_touch:
    mov rax, [rbx + Seat_DEVICES]
.find_touch_loop:
    test rax, rax
    jz .done
    mov eax, [rax + InputDevice_CAPS]
    test eax, DEVICE_CAP_TOUCH
    jz .next_touch
    mov qword [rbx + Seat_TOUCH], rax
    ret
.next_touch:
    mov rax, [rax + InputDevice_NEXT]
    test rax, rax
    jnz .find_touch_loop
    mov qword [rbx + Seat_TOUCH], 0
    ret

.find_tablet:
    mov rax, [rbx + Seat_DEVICES]
.find_tablet_loop:
    test rax, rax
    jz .done
    mov eax, [rax + InputDevice_CAPS]
    test eax, DEVICE_CAP_TABLET
    jz .next_tablet
    mov qword [rbx + Seat_TABLET], rax
    ret
.next_tablet:
    mov rax, [rax + InputDevice_NEXT]
    test rax, rax
    jnz .find_tablet_loop
    mov qword [rbx + Seat_TABLET], 0
    ret

; ============================================================================
; seat_set_pointer_focus
;   Set pointer focus surface
; ============================================================================
global seat_set_pointer_focus
seat_set_pointer_focus:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi       ; surface
    ASSERT_PTR rbx

    ; Get current focus
    mov rax, [rbx + Seat_POINTER_FOCUS]
    cmp rax, r12
    je .same

    ; Leave old focus
    test rax, rax
    jz .set_new
    mov rdi, rax
    call surface_pointer_leave

.set_new:
    ; Set new focus
    mov [rbx + Seat_POINTER_FOCUS], r12
    test r12, r12
    jz .done

    mov rdi, r12
    call surface_pointer_enter

    ; Update cursor
    mov rax, [rbx + Seat_POINTER]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, [rax + Pointer_X]
    mov rdx, [rax + Pointer_Y]
    call surface_set_cursor

    xor rax, rax
    leave
    ret

.same:
    xor rax, rax
    leave
    ret

; ============================================================================
; seat_set_keyboard_focus
;   Set keyboard focus surface
; ============================================================================
global seat_set_keyboard_focus
seat_set_keyboard_focus:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi       ; surface
    ASSERT_PTR rbx

    mov rax, [rbx + Seat_KEYBOARD_FOCUS]
    cmp rax, r12
    je .same

    ; Leave old focus
    test rax, rax
    jz .set_new
    mov rdi, rax
    call surface_keyboard_leave

.set_new:
    mov [rbx + Seat_KEYBOARD_FOCUS], r12
    test r12, r12
    jz .done

    mov rdi, r12
    call surface_keyboard_enter

    xor rax, rax
    leave
    ret

.same:
    xor rax, rax
    leave
    ret

; ============================================================================
; seat_get_pointer
;   Get pointer device
; ============================================================================
global seat_get_pointer
seat_get_pointer:
    PROLOGUE
    mov rax, [rdi + Seat_POINTER]
    leave
    ret

; ============================================================================
; seat_get_keyboard
;   Get keyboard device
; ============================================================================
global seat_get_keyboard
seat_get_keyboard:
    PROLOGUE
    mov rax, [rdi + Seat_KEYBOARD]
    leave
    ret

; ============================================================================
; seat_get_touch
;   Get touch device
; ============================================================================
global seat_get_touch
seat_get_touch:
    PROLOGUE
    mov rax, [rdi + Seat_TOUCH]
    leave
    ret

; ============================================================================
; seat_get_tablet
;   Get tablet device
; ============================================================================
global seat_get_tablet
seat_get_tablet:
    PROLOGUE
    mov rax, [rdi + Seat_TABLET]
    leave
    ret

; ============================================================================
; seat_set_selection
;   Set selection (clipboard/primary)
; ============================================================================
global seat_set_selection
seat_set_selection:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi       ; data_source
    mov r13d, edx      ; serial
    ASSERT_PTR rbx

    ; Release old selection
    mov rax, [rbx + Seat_SELECTION_SOURCE]
    test rax, rax
    jz .set_new
    call data_source_destroy

.set_new:
    mov [rbx + Seat_SELECTION_SOURCE], r12
    mov dword [rbx + Seat_SELECTION_SERIAL], r13d

    xor rax, rax
    leave
    ret

; ============================================================================
; seat_get_selection
;   Get current selection
; ============================================================================
global seat_get_selection
seat_get_selection:
    PROLOGUE
    mov rax, [rdi + Seat_SELECTION_SOURCE]
    mov rdx, [rdi + Seat_SELECTION_SERIAL]
    leave
    ret

; ============================================================================
; seat_start_drag
;   Start drag-and-drop
; ============================================================================
global seat_start_drag
seat_start_drag:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi       ; source
    mov r13, rdx       ; icon surface
    mov r14d, ecx      ; actions
    ASSERT_PTR rbx

    ; Release old drag
    mov rax, [rbx + Seat_DRAG_SOURCE]
    test rax, rax
    jz .set_new
    call data_source_destroy

.set_new:
    mov [rbx + Seat_DRAG_SOURCE], r12
    mov qword [rbx + Seat_DRAG_ICON], r13
    mov dword [rbx + Seat_DRAG_ACTIONS], r14d

    ; Set icon cursor
    test r13, r13
    jz .done
    mov rax, [rbx + Seat_POINTER]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, r13
    call surface_set_cursor

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; seat_end_drag
;   End drag-and-drop
; ============================================================================
global seat_end_drag
seat_end_drag:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + Seat_DRAG_SOURCE]
    test rax, rax
    jz .done
    call data_source_destroy

    mov qword [rbx + Seat_DRAG_SOURCE], 0
    mov qword [rbx + Seat_DRAG_ICON], 0
    mov dword [rbx + Seat_DRAG_ACTIONS], 0

    xor rax, rax
    leave
    ret

; ============================================================================
; seat_get_pointer_focus
;   Get current pointer focus
; ============================================================================
global seat_get_pointer_focus
seat_get_pointer_focus:
    PROLOGUE
    mov rax, [rdi + Seat_POINTER_FOCUS]
    leave
    ret

; ============================================================================
; seat_get_keyboard_focus
;   Get current keyboard focus
; ============================================================================
global seat_get_keyboard_focus
seat_get_keyboard_focus:
    PROLOGUE
    mov rax, [rdi + Seat_KEYBOARD_FOCUS]
    leave
    ret

section .data
global seat_version
seat_version: dq 0x010000