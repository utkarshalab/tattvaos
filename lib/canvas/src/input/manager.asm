; ============================================================================
; Input Manager — Central Input Coordination, Device Enumeration
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/input.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; InputManager Struct
; ============================================================================
%define InputManager_SEATS       0
%define InputManager_SEAT_COUNT  8
%define InputManager_DEFAULT_SEAT 16
%define InputManager_DEVICE_HOTPLUG 24
%define InputManager_SIZE        32

; ============================================================================
; input_manager_create
;   Create input manager
; ============================================================================
global input_manager_create
input_manager_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi       ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + InputManager_SEATS], 0
    mov dword [rbx + InputManager_SEAT_COUNT], 0
    mov qword [rbx + InputManager_DEFAULT_SEAT], 0
    mov qword [rbx + InputManager_DEVICE_HOTPLUG], 0

    ; Create default seat
    mov rdi, rbx
    mov rsi, r12
    call seat_create_default

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; input_manager_destroy
;   Destroy input manager
; ============================================================================
global input_manager_destroy
input_manager_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Destroy all seats
    mov rax, [rbx + InputManager_SEATS]
.seat_loop:
    test rax, rax
    jz .done
    push rax
    call seat_destroy
    pop rax
    mov rax, [rax + Seat_NEXT]
    jmp .seat_loop

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; seat_create_default
;   Create default seat
; ============================================================================
global seat_create_default
seat_create_default:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate seat
    mov rdi, 72  ; Seat_SIZE
    call arena_alloc
    test rax, rax
    jz .oom

    mov rdi, rax
    mov rsi, rbx
    mov rdx, r12
    call seat_create

    ; Add to manager's seat list
    mov rbx, [rbx + InputManager_SEATS]
    mov [rax + Seat_NEXT], rbx
    mov [rbx + InputManager_SEATS], rax
    inc dword [rbx + InputManager_SEAT_COUNT]

    mov qword [rbx + InputManager_DEFAULT_SEAT], rax

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.oom:
    mov rax, -ENOMEM
    leave
    ret

; ============================================================================
; input_manager_get_seat
;   Get seat by name or default
; ============================================================================
global input_manager_get_seat
input_manager_get_seat:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi       ; name (optional)
    ASSERT_PTR rbx

    test r12, r12
    jz .return_default

    ; Search by name
    mov rax, [rdi + InputManager_SEATS]
.search_loop:
    test rax, rax
    jz .not_found
    mov r12, [rax + Seat_NAME]
    call str_cmp
    test rax, rax
    jz .found
    mov rax, [rax + Seat_NEXT]
    jmp .search

.not_found:
    xor rax, rax
    leave
    ret

.found:
    leave
    ret

.return_default:
    mov rax, [rdi + InputManager_DEFAULT_SEAT]
    leave
    ret

; ============================================================================
; input_manager_list_seats
;   List all seats
; ============================================================================
global input_manager_list_seats
input_manager_list_seats:
    PROLOGUE
    mov rax, [rdi + InputManager_SEATS]
    leave
    ret

; ============================================================================
; input_manager_device_hotplug
;   Handle device hotplug
; ============================================================================
global input_manager_device_hotplug
input_manager_device_hotplug:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi      ; action (add/remove)
    mov r13, rdx       ; device info
    mov r14, rcx       ; seat (optional)
    ASSERT_PTR rbx
    ASSERT_PTR r13

    test r12d, r12d
    jz .remove

    ; Add device
    call .add_device
    jmp .done

.remove:
    call .remove_device

.done:
    xor rax, rax
    leave
    ret

.add_device:
    ; Parse device info from r13
    ; Create appropriate device type
    ret

.remove_device:
    ret

section .data
global input_manager_version
input_manager_version: dq 0x010000