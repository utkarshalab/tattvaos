; ============================================================================
; Popup Management — Transient Surfaces, Menus, Tooltips
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"
%include "inc/backend.inc"

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

    mov qword [rbx + Popup.surface], r13
    mov qword [rbx + Popup.shell], r12
    mov qword [rbx + Popup.parent], r14
    mov dword [rbx + Popup.position], 0  ; default: top-left
    mov dword [rbx + Popup.x], 0
    mov dword [rbx + Popup.y], 0
    mov dword [rbx + Popup.width], 0
    mov dword [rbx + Popup.height], 0
    mov dword [rbx + Popup.constrain], 1  ; constrain to output

    ; Link into shell's popup list
    mov rax, [r12 + Shell.popups]
    mov [rbx + Popup.next], rax
    mov [r12 + Shell.popups], rbx

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
    mov r12, [rbx + Popup.shell]
    call .unlink_from_shell

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.unlink_from_shell:
    mov rax, [r12 + Shell.popups]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + Popup.next]
    mov [r12 + Shell.popups], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + Popup.next]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + Popup.next]
    mov [r12 + Popup.next], rax

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

    mov dword [rbx + Popup.position], esi
    mov dword [rbx + Popup.x], edx
    mov dword [rbx + Popup.y], ecx

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

    mov dword [rbx + Popup.width], esi
    mov dword [rbx + Popup.height], edx

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

    mov dword [rbx + Popup.constrain], esi
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
    mov rax, [rbx + Popup.parent]
    mov r14d, [rax + Toplevel.x]
    mov r15d, [rax + Toplevel.y]

    ; Get parent size
    mov r14d, [rax + Toplevel.width]
    mov r15d, [rax + Toplevel.height]

    ; Compute position based on position enum
    mov eax, [rbx + Popup.position]

    ; Simplified: just use x,y offsets
    mov eax, [rbx + Popup.x]
    mov edx, [rbx + Popup.y]
    add eax, r14d
    add edx, r15d

    ; Constrain to output if needed
    cmp dword [rbx + Popup.constrain], 0
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
    mov r13d, [r12 + Output.x]
    mov r14d, [r12 + Output.y]
    mov r15d, [r12 + Output.width]
    mov r14d, [r12 + Output.height]

    ; Get popup size
    mov eax, [rbx + Popup.width]
    mov edx, [rbx + Popup.height]

    ; Constrain X
    mov eax, [rbx + Popup.x]
    cmp eax, r13d
    jge .check_x_max
    mov eax, r13d
    jmp .set_x
.check_x_max:
    add eax, [rbx + Popup.width]
    cmp eax, r15d
    jle .set_x
    sub eax, [rbx + Popup.width]
    sub eax, r15d
.set_x:
    mov [rbx + Popup.x], eax

    ; Constrain Y
    mov eax, [rbx + Popup.y]
    cmp eax, r14d
    jge .check_y_max
    mov eax, r14d
    jmp .set_y
.check_y_max:
    add eax, [rbx + Popup.height]
    cmp eax, r14d
    jle .set_y
    sub eax, [rbx + Popup.height]
    sub eax, r14d
.set_y:
    mov [rbx + Popup.y], eax

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global popup_version
popup_version: dq 0x010000
