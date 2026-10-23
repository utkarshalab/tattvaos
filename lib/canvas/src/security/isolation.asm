; ============================================================================
; Isolation — Software Isolation Enforcement
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/handle.inc"
%include "inc/channel.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

%define AUDIT_ACTION_PRIVILEGED 4
%define AUDIT_RESULT_DENIED     2

; ---------------------------------------------------------------------------
; isolation_init
; ---------------------------------------------------------------------------
global isolation_init
isolation_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.isolation], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; isolation_check_handle
;   Validate handle ownership
;   IN:  rdi = server*, rsi = client*, rdx = handle
;   OUT: rax = object_ptr if valid, 0 if invalid
; ---------------------------------------------------------------------------
global isolation_check_handle
isolation_check_handle:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Resolve handle in client's table
    mov rax, [r12 + Client.obj_table]
    test rax, rax
    jz .invalid

    mov rdi, rax
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .invalid

    ; Resolution through the per-client table is the ownership boundary.
    ; Shared objects are imported as distinct handles into that same table.

    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; isolation_check_buffer_access
;   Check if client can access buffer
; ---------------------------------------------------------------------------
global isolation_check_buffer_access
isolation_check_buffer_access:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Resolve buffer handle
    mov rdi, [r12 + Client.obj_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .invalid

    ; Check buffer ownership
    mov r13, [rax + Buffer.client_id]
    cmp r13, [r12 + Client.id]
    je .owned

    ; A non-owner entry in this client's object table is an imported share.
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.owned:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; isolation_check_surface_access
;   Check if client can access surface
; ---------------------------------------------------------------------------
global isolation_check_surface_access
isolation_check_surface_access:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Resolve surface handle
    mov rdi, [r12 + Client.obj_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .invalid

    ; Check surface ownership
    mov r13, [rax + Surface.client]
    cmp r13, r12
    je .owned

    EPILOGUE_RESTORE rbx, r12, r13
    ret

.owned:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; isolation_enforce_ownership
;   Ensure client owns object before operation
; ---------------------------------------------------------------------------
global isolation_enforce_ownership
isolation_enforce_ownership:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Resolve handle
    mov rdi, [r12 + Client.obj_table]
    mov rsi, r13
    call handle_resolve
    test rax, rax
    jz .invalid

    ; Check owner
    mov r13, [rax + Object.client_id]
    cmp r13, [r12 + Client.id]
    je .ok

    ; Not owner
    mov rax, -(EPERM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.ok:
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; isolation_fault
;   Handle isolation violation (client fault)
; ---------------------------------------------------------------------------
global isolation_fault
isolation_fault:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Log fault
    call isolation_log_fault

    ; Disconnect client
    mov rdi, rbx
    mov rsi, r12
    call client_disconnect

    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; isolation_log_fault
; ---------------------------------------------------------------------------
isolation_log_fault:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov rdi, rbx
    mov rsi, AUDIT_ACTION_PRIVILEGED
    mov rdx, [r12 + Client.id]
    xor rcx, rcx
    mov r8, AUDIT_RESULT_DENIED
    xor r9, r9
    xor r10, r10
    call audit_log
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global isolation_version
isolation_version: dq 0x010000
