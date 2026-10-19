; ============================================================================
; Popup Management — Transient Surfaces, Menus, Tooltips
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; popup_create
;   Create popup surface
; ============================================================================
global popup_create
popup_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi  ; shell
    mov r13, rdx  ; surface
    mov r14, rcx  ; parent
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    ASSERT_PTR r14

    mov qword [rbx + POPUP_SURFACE], r13
    mov qword [rbx + POPUP_SHELL], r12
    mov qword [rbx + POPUP_PARENT], r14
    mov dword [rbx + POPUP_POSITION], 0  ; default: top-left
    mov dword [rbx + POPUP_X], 0
    mov dword [rbx + POPUP_Y], 0
    mov dword [rbx + POPUP_WIDTH], 0
    mov dword [rbx + POPUP_HEIGHT], 0
    mov dword [rbx + POPUP_CONSTRAIN], 1  ; constrain to output

    ; Link into shell's popup list
    mov rax, [r12 + SHELL_POPUPS]
    mov [rbx + POPUP_NEXT], rax
    mov [r12 + SHELL_POPUPS], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; popup_destroy
;   Destroy popup
; ============================================================================
global popup_destroy
popup_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Unlink from shell
    mov r12, [rbx + POPUP_SHELL]
    call .unlink_from_shell

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.unlink_from_shell:
    mov rax, [r12 + SHELL_POPUPS]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + POPUP_NEXT]
    mov [r12 + SHELL_POPUPS], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + POPUP_NEXT]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + POPUP_NEXT]
    mov [r12 + POPUP_NEXT], rax

.done:
    ret

; ============================================================================
; popup_set_position
;   Set popup position relative to parent
; ============================================================================
global popup_set_position
popup_set_position:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + POPUP_POSITION], esi
    mov dword [rbx + POPUP_X], edx
    mov dword [rbx + POPUP_Y], ecx

    xor rax, rax
    leave
    ret

; ============================================================================
; popup_set_size
;   Set popup size
; ============================================================================
global popup_set_size
popup_set_size:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + POPUP_WIDTH], esi
    mov dword [rbx + POPUP_HEIGHT], edx

    xor rax, rax
    leave
    ret

; ============================================================================
; popup_set_constrain
;   Set constrain flag
; ============================================================================
global popup_set_constrain
popup_set_constrain:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + POPUP_CONSTRAIN], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; popup_get_position
;   Get computed popup position
; ============================================================================
global popup_get_position
popup_get_position:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi  ; output x
    mov r13, rdx  ; output y
    ASSERT_PTR rbx

    ; Get parent toplevel position
    mov rax, [rbx + POPUP_PARENT]
    mov r14d, [rax + TOPLEVEL_X]
    mov r15d, [rax + TOPLEVEL_Y]

    ; Get parent size
    mov r14d, [rax + TOPLEVEL_WIDTH]
    mov r15d, [rax + TOPLEVEL_HEIGHT]

    ; Compute position based on position enum
    mov eax, [rbx + POPUP_POSITION]

    ; Simplified: just use x,y offsets
    mov eax, [rbx + POPUP_X]
    mov edx, [rbx + POPUP_Y]
    add eax, r14d
    add edx, r15d

    ; Constrain to output if needed
    cmp dword [rbx + POPUP_CONSTRAIN], 0
    je .no_constrain

    ; Constrain to output bounds
    ; ...

.no_constrain:
    leave
    ret

; ============================================================================
; popup_constrain_to_output
;   Constrain popup to output bounds
; ============================================================================
global popup_constrain_to_output
popup_constrain_to_output:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; output
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get output bounds
    mov r13d, [r12 + OUTPUT_X]
    mov r14d, [r12 + OUTPUT_Y]
    mov r15d, [r12 + OUTPUT_WIDTH]
    mov r14d, [r12 + OUTPUT_HEIGHT]

    ; Get popup size
    mov eax, [rbx + POPUP_WIDTH]
    mov edx, [rbx + POPUP_HEIGHT]

    ; Constrain X
    mov eax, [rbx + POPUP_X]
    cmp eax, r13d
    jge .check_x_max
    mov eax, r13d
    jmp .set_x
.check_x_max:
    add eax, [rbx + POPUP_WIDTH]
    cmp eax, r15d
    jle .set_x
    sub eax, [rbx + POPUP_WIDTH]
    sub eax, r15d
.set_x:
    mov [rbx + POPUP_X], eax

    ; Constrain Y
    mov eax, [rbx + POPUP_Y]
    cmp eax, r14d
    jge .check_y_max
    mov eax, r14d
    jmp .set_y
.check_y_max:
    add eax, [rbx + POPUP_HEIGHT]
    cmp eax, r14d
    jle .set_y
    sub eax, [rbx + POPUP_HEIGHT]
    sub eax, r14d
.set_y:
    mov [rbx + POPUP_Y], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global popup_version
popup_version: dq 0x010000