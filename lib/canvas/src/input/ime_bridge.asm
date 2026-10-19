; ============================================================================
; IME Bridge — Input Method Editor Bridge for Complex Input
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; IMEBridge Struct
; ============================================================================
%define IMEBridge_SEAT          0
%define IMEBridge_ACTIVE_IME    8
%define IMEBridge_AVAILABLE_IMES 16
%define IMEBridge_IME_COUNT     24
%define IMEBridge_FOCUSED_TEXT_INPUT 28
%define IMEBridge_SIZE         32

; ============================================================================
; IMEInfo Struct
; ============================================================================
%define IMEInfo_NAME           0
%define IMEInfo_ENGINE         8
%define IMEInfo_CAPABILITIES   16
%define IMEInfo_LANGUAGE       24
%define IMEInfo_SIZE           32

; IME capabilities
%define IME_CAP_PREEDIT        (1 << 0)
%define IME_CAP_COMPLETION     (1 << 1)
%define IME_CAP_PREDICTION     (1 << 2)
%define IME_CAP_SURROUNDING    (1 << 3)
%define IME_CAP_PREDICTION     (1 << 4)

; ============================================================================
; ime_bridge_create
;   Create IME bridge
; ============================================================================
global ime_bridge_create
ime_bridge_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi       ; seat
    mov r13, rdx       ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + IMEBridge_SEAT], r12
    mov qword [rbx + IMEBridge_ACTIVE_IME], 0
    mov qword [rbx + IMEBridge_AVAILABLE_IMES], 0
    mov dword [rbx + IMEBridge_IME_COUNT], 0
    mov qword [rbx + IMEBridge_FOCUSED_TEXT_INPUT], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ============================================================================
; ime_bridge_destroy
;   Destroy IME bridge
; ============================================================================
global ime_bridge_destroy
ime_bridge_destroy:
    PROLOGUE
    xor rax, rax
    leave
    ret

; ============================================================================
; ime_bridge_register
;   Register IME engine
; ============================================================================
global ime_bridge_register
ime_bridge_register:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi       ; name
    mov r13, rdx       ; engine path
    mov r14d, ecx      ; capabilities
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Allocate IME info
    mov rdi, 32  ; IMEInfo_SIZE
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rax + IMEInfo_NAME], r12
    mov qword [rax + IMEInfo_ENGINE], r13
    mov dword [rax + IMEInfo_CAPABILITIES], r14d
    mov qword [rax + IMEInfo_LANGUAGE], 0

    ; Add to available list
    mov r12, [rbx + IMEBridge_AVAILABLE_IMES]
    mov [rax + IMEInfo_NEXT], r12
    mov [rbx + IMEBridge_AVAILABLE_IMES], rax
    inc dword [rbx + IMEBridge_IME_COUNT]

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.oom:
    mov rax, -ENOMEM
    leave
    ret

; ============================================================================
; ime_bridge_activate
;   Activate IME for text input
; ============================================================================
global ime_bridge_activate
ime_bridge_activate:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi       ; text_input
    mov r13, rdx       ; ime_name
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Find IME engine
    mov rax, [rbx + IMEBridge_AVAILABLE_IMES]
.find_loop:
    test rax, rax
    jz .not_found

    mov r12, [rax + IMEInfo_NAME]
    mov r13, rsi
    call str_cmp
    test rax, rax
    jz .found

    mov rax, [rax + IMEInfo_NEXT]
    jmp .find_loop

.not_found:
    mov rax, -ENOENT
    EPILOGUE_RESTORE rbx, r12
    ret

.found:
    ; Activate IME
    mov [rbx + IMEBridge_ACTIVE_IME], rax
    mov qword [rbx + IMEBridge_FOCUSED_TEXT_INPUT], r12

    ; Notify text input
    mov rdi, r12
    call text_input_set_state

    xor rax, rax
    EPILOGUE_RESTORE rbx, r13
    ret

; ============================================================================
; ime_bridge_deactivate
;   Deactivate IME
; ============================================================================
global ime_bridge_deactivate
ime_bridge_deactivate:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Get active text input
    mov r12, [rbx + IMEBridge_FOCUSED_TEXT_INPUT]
    test r12, r12
    jz .done

    ; Reset text input state
    call text_input_reset

    mov qword [rbx + IMEBridge_ACTIVE_IME], 0
    mov qword [rbx + IMEBridge_FOCUSED_TEXT_INPUT], 0

    xor rax, rax
    leave
    ret

; ============================================================================
; ime_bridge_commit
;   Commit text from IME
; ============================================================================
global ime_bridge_commit
ime_bridge_commit:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi       ; text
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get focused text input
    mov r12, [rbx + IMEBridge_FOCUSED_TEXT_INPUT]
    test r12, r12
    jz .done

    ; Commit text
    mov rdi, r12
    mov rsi, rbx  ; text
    call text_input_commit

    xor rax, rax
    leave
    ret

; ============================================================================
; ime_bridge_preedit
;   Set preedit string
; ============================================================================
global ime_bridge_preedit
ime_bridge_preedit:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi       ; text
    mov r13d, edx      ; cursor
    mov r14d, ecx      ; preedit_start
    mov r15d, r8d      ; preedit_end
    ASSERT_PTR rbx

    ; Get focused text input
    mov r12, [rbx + IMEBridge_FOCUSED_TEXT_INPUT]
    test r12, r12
    jz .done

    ; Set preedit
    mov rdi, rbx
    mov rsi, rax  ; text
    mov rdx, r13d
    mov rcx, r14d
    mov r8d, r15d
    call text_input_set_preedit

    xor rax, rax
    leave
    ret

; ============================================================================
; ime_bridge_delete_surrounding
;   Delete surrounding text
; ============================================================================
global ime_bridge_delete_surrounding
ime_bridge_delete_surrounding:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi       ; offset
    mov r13d, edx       ; length
    ASSERT_PTR rbx

    ; Get focused text input
    mov r12, [rbx + IMEBridge_FOCUSED_TEXT_INPUT]
    test r12, r12
    jz .done

    call text_input_delete_surrounding

    xor rax, rax
    leave
    ret

section .data
global ime_bridge_version
ime_bridge_version: dq 0x010000