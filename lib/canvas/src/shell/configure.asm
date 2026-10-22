; ============================================================================
; Configure — Surface Configuration Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/shell.inc"

extern arena_alloc

section .text

; ============================================================================
; configure_create
;   Create configure object
; ============================================================================
global configure_create
configure_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate configure
    mov rdi, 56  ; CONFIGURE_SIZE
    call arena_alloc
    test rax, rax
    jz .oom

    ; Initialize
    mov dword [rax + CONFIGURE_SERIAL], 0
    mov qword [rax + CONFIGURE_SURFACE], rbx
    mov dword [rax + CONFIGURE_WIDTH], 0
    mov dword [rax + CONFIGURE_HEIGHT], 0
    mov dword [rax + CONFIGURE_STATES], 0
    mov qword [rax + CONFIGURE_CALLBACK], 0
    mov qword [rax + CONFIGURE_USER_DATA], 0
    mov qword [rax + CONFIGURE_ACK_CB], 0
    mov qword [rax + CONFIGURE_NEXT], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.oom:
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; configure_destroy
;   Destroy configure
; ============================================================================
global configure_destroy
configure_destroy:
    PROLOGUE
    ; Arena handles cleanup
    xor rax, rax
    leave
    ret

; ============================================================================
; configure_ack
;   Acknowledge configure
; ============================================================================
global configure_ack
configure_ack:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Call ack callback if set
    mov rax, [rbx + CONFIGURE_ACK_CB]
    test rax, rax
    jz .done
    call rax

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; configure_set_size
;   Set configure size
; ============================================================================
global configure_set_size
configure_set_size:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + CONFIGURE_WIDTH], esi
    mov dword [rbx + CONFIGURE_HEIGHT], edx
    xor rax, rax
    leave
    ret

; ============================================================================
; configure_set_states
;   Set configure states
; ============================================================================
global configure_set_states
configure_set_states:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + CONFIGURE_STATES], esi
    xor rax, rax
    leave
    ret

; ============================================================================
; configure_set_serial
;   Set configure serial
; ============================================================================
global configure_set_serial
configure_set_serial:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + CONFIGURE_SERIAL], esi
    xor rax, rax
    leave
    ret

section .data
global configure_version
configure_version: dq 0x010000
