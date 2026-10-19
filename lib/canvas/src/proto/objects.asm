; ============================================================================
; Protocol Objects — Server-side Object Table with Generation IDs
; ============================================================================

%include "inc/abi.inc"
%include "inc/externs.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/handle.inc"

; struct offsets (hoisted above use)
%define Obj_interface_id  0
%define Obj_version       2
%define Obj_refcount      4
%define Obj_data_ptr      12
%define Obj_size          20

section .text

; ---------------------------------------------------------------------------
; objects_init
;   Initialize object table
;   IN:  rdi = objects*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global objects_init
objects_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Object table is a handle table
    mov rdi, rbx
    mov rsi, r12
    mov rdx, 65536       ; 64K objects max per client
    call handle_table_init
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; objects_create
;   Create new protocol object
;   IN:  rdi = objects*, rsi = object_ptr, rdx = interface_id, rcx = version
;   OUT: rax = handle, 0 on failure
; ---------------------------------------------------------------------------
global objects_create
objects_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate object header
    ; struct Object { interface_id, version, refcount, data_ptr }
    push r12
    mov rdi, r12
    mov rsi, 32
    call arena_alloc
    pop r12
    test rax, rax
    jz .oom

    ; Fill object header
    mov [rax + 0], r13w        ; interface_id
    mov [rax + 2], r14w        ; version
    mov qword [rax + 4], 1     ; refcount
    mov [rax + 12], r12        ; data_ptr

    ; Create handle
    mov rdi, rbx
    mov rsi, rax
    call handle_create
    test rax, rax
    jz .oom

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; objects_resolve
;   Resolve handle to object data pointer
;   IN:  rdi = objects*, rsi = handle, rdx = expected_interface_id
;   OUT: rax = data_ptr, 0 if invalid/wrong interface
; ---------------------------------------------------------------------------
global objects_resolve
objects_resolve:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Resolve handle
    mov rdi, rbx
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .invalid

    ; Check interface ID
    cmp word [rax + 0], dx
    jne .invalid

    ; Return data pointer
    mov rax, [rax + 12]
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; objects_destroy
;   Destroy protocol object
;   IN:  rdi = objects*, rsi = handle
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global objects_destroy
objects_destroy:
    PROLOGUE
    ASSERT_PTR rdi

    mov rax, rsi
    call handle_destroy
    leave
    ret

; ---------------------------------------------------------------------------
; objects_ref
;   Increment object refcount
; ---------------------------------------------------------------------------
global objects_ref
objects_ref:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    call handle_resolve
    test rax, rax
    jz .invalid

    lock inc qword [rax + 4]
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.invalid:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; objects_unref
;   Decrement object refcount, destroy if zero
; ---------------------------------------------------------------------------
global objects_unref
objects_unref:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    call handle_resolve
    test rax, rax
    jz .invalid

    lock dec qword [rax + 4]
    jnz .done

    ; Refcount hit zero - destroy
    push rax
    mov rdi, rbx
    mov rsi, r12
    call handle_destroy
    pop rax
    ; Free object memory via arena (handled by arena_free_all on client disconnect)
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

.invalid:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; objects_lookup
;   Look up object by handle (no refcount change)
;   IN:  rdi = objects*, rsi = handle
;   OUT: rax = object_header_ptr, 0 if not found
; ---------------------------------------------------------------------------
global objects_lookup
objects_lookup:
    PROLOGUE
    ASSERT_PTR rdi
    call handle_resolve
    leave
    ret

section .data


global objects_version
objects_version: dq 0x010000
