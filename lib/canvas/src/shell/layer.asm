; ============================================================================
; Layer Shell — Popups, Menus, Tooltips, OSD, Backgrounds
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"

extern surface_set_size

section .text

; ============================================================================
; layer_create
;   Create layer surface
; ============================================================================
global layer_create
layer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi  ; shell
    mov r13, rdx  ; surface
    mov r14d, ecx ; layer
    mov r15, r8   ; namespace
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + LAYER_SURFACE], r13
    mov qword [rbx + LAYER_SHELL], r12
    mov dword [rbx + LAYER_LAYER], r14d
    mov qword [rbx + LAYER_NAMESPACE], r15

    ; Defaults
    mov dword [rbx + LAYER_ANCHOR], 0
    mov dword [rbx + LAYER_EXCLUSIVE_ZONE], 0
    mov dword [rbx + LAYER_KEYBOARD_INT], KEYBOARD_NONE
    mov dword [rbx + LAYER_WIDTH], 0
    mov dword [rbx + LAYER_HEIGHT], 0
    mov dword [rbx + LAYER_MARGIN_TOP], 0
    mov dword [rbx + LAYER_MARGIN_RIGHT], 0
    mov dword [rbx + LAYER_MARGIN_BOTTOM], 0
    mov dword [rbx + LAYER_MARGIN_LEFT], 0

    ; Validate layer
    cmp r14d, LAYER_OVERLAY
    jg .invalid

    ; Get output for this layer
    mov r15, [r12 + SHELL_OUTPUTS]
.find_output:
    test r15, r15
    jz .no_output
    mov r14, [r15 + OUTPUT_CURRENT_SURFACE]
    test r14, r14
    jz .next_output
    mov [rbx + LAYER_OUTPUT], r15
    jmp .output_found
.next_output:
    mov r15, [r15 + OUTPUT_NEXT]
    jmp .find_output

.no_output:
    ; Use first output
    mov r15, [r12 + SHELL_OUTPUTS]
    mov [rbx + LAYER_OUTPUT], r15

.output_found:
    ; Link into shell's layer list
    mov rax, [r12 + SHELL_LAYERS]
    mov [rbx + LAYER_NEXT], rax
    mov [r12 + SHELL_LAYERS], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.invalid:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; layer_destroy
;   Destroy layer surface
; ============================================================================
global layer_destroy
layer_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Unlink from shell
    mov r12, [rbx + LAYER_SHELL]
    call .unlink_from_shell

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.unlink_from_shell:
    mov rax, [r12 + SHELL_LAYERS]
    test rax, rax
    jz .done

    cmp rax, rbx
    jne .find_prev
    mov rax, [rbx + LAYER_NEXT]
    mov [r12 + SHELL_LAYERS], rax
    jmp .done

.find_prev:
    mov r12, rax
.prev_loop:
    mov rax, [r12 + LAYER_NEXT]
    test rax, rax
    jz .done
    cmp rax, rbx
    je .unlink
    mov r12, rax
    jmp .prev_loop

.unlink:
    mov rax, [rbx + LAYER_NEXT]
    mov [r12 + LAYER_NEXT], rax

.done:
    ret

; ============================================================================
; layer_set_anchor
;   Set anchor edges
; ============================================================================
global layer_set_anchor
layer_set_anchor:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Validate anchor flags
    test esi, ~0xF
    jnz .invalid

    mov dword [rbx + LAYER_ANCHOR], esi
    xor rax, rax
    leave
    ret

.invalid:
    mov rax, -EINVAL
    leave
    ret

; ============================================================================
; layer_set_exclusive_zone
;   Set exclusive zone (for panels/docks)
; ============================================================================
global layer_set_exclusive_zone
layer_set_exclusive_zone:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + LAYER_EXCLUSIVE_ZONE], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; layer_set_keyboard_interactivity
;   Set keyboard interactivity
; ============================================================================
global layer_set_keyboard_interactivity
layer_set_keyboard_interactivity:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp esi, KEYBOARD_NONE
    je .valid
    cmp esi, KEYBOARD_EXCLUSIVE
    je .valid
    cmp esi, KEYBOARD_ON_DEMAND
    je .valid
    mov rax, -EINVAL
    leave
    ret

.valid:
    mov dword [rbx + LAYER_KEYBOARD_INT], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; layer_set_size
;   Set layer surface size
; ============================================================================
global layer_set_size
layer_set_size:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + LAYER_WIDTH], esi
    mov dword [rbx + LAYER_HEIGHT], edx

    ; Update surface
    mov rax, [rbx + LAYER_SURFACE]
    test rax, rax
    jz .done
    mov rdi, rax
    call surface_set_size

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; layer_set_margin
;   Set margins
; ============================================================================
global layer_set_margin
layer_set_margin:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + LAYER_MARGIN_TOP], esi
    mov dword [rbx + LAYER_MARGIN_RIGHT], edx
    mov dword [rbx + LAYER_MARGIN_BOTTOM], ecx
    mov dword [rbx + LAYER_MARGIN_LEFT], r8d

    xor rax, rax
    leave
    ret

; ============================================================================
; layer_get_output
;   Get assigned output
; ============================================================================
global layer_get_output
layer_get_output:
    PROLOGUE
    mov rax, [rdi + LAYER_OUTPUT]
    leave
    ret

section .data
global layer_version
layer_version: dq 0x010000
