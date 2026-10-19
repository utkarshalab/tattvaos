; ============================================================================
; Dispatch — Opcode Dispatch Tables
; ============================================================================

%include "inc/abi.inc"
%include "inc/externs.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; struct offsets (hoisted above use)
%define Dispatch_table    0
%define Dispatch.table 0
%define Dispatch_count    8
%define Dispatch.count 8
%define Dispatch_capacity 16
%define Dispatch.capacity 16
%define Dispatch_arena    24
%define Dispatch.arena 24
%define Dispatch_size     32

section .text

; ---------------------------------------------------------------------------
; dispatch_init
;   Initialize dispatch table
;   IN:  rdi = dispatch*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global dispatch_init
dispatch_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Dispatch.table], 0
    mov qword [rbx + Dispatch.count], 0
    mov qword [rbx + Dispatch.capacity], 0
    mov qword [rbx + Dispatch.arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; dispatch_register
;   Register handler for opcode
;   IN:  rdi = dispatch*, rsi = interface_id, rdx = opcode, rcx = handler_fn
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global dispatch_register
dispatch_register:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r14

    ; Build key: (interface_id << 16) | opcode
    mov rax, r12
    shl rax, 16
    or rax, r13
    mov r12, rax

    mov rdi, [rbx + Dispatch.table]
    test rdi, rdi
    jnz .has_table

    ; Allocate table
    mov rdi, [rbx + Dispatch.arena]
    mov rsi, 4096
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rbx + Dispatch.table], rax
    mov qword [rbx + Dispatch.capacity], 256
    mov qword [rbx + Dispatch.count], 0
    mov rdi, rax
    xor rsi, rsi
    mov rdx, 4096
    call memset

.has_table:
    mov rdi, [rbx + Dispatch.table]
    mov rax, r12
    imul rax, 0x9E3779B1
    shr rax, 16
    and rax, 255
    mov r15, 256
.probe:
    mov rcx, rax
    shl rcx, 4
    mov rdx, [rdi + rcx]
    test rdx, rdx
    jz .insert
    dec rdx
    cmp rdx, r12
    je .update
    inc rax
    and rax, 255
    dec r15
    jnz .probe
    jmp .grow
.update:
    mov [rdi + rcx + 8], r14
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.insert:
    mov rdx, r12
    inc rdx
    mov [rdi + rcx], rdx
    mov [rdi + rcx + 8], r14
    inc qword [rbx + Dispatch.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.grow:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; dispatch_call
;   Call handler for opcode
;   IN:  rdi = dispatch*, rsi = interface_id, rdx = opcode, rcx = client*, r8 = msg_hdr*, r9 = payload, r10 = handles
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global dispatch_call
dispatch_call:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov [rsp], r9
    mov [rsp + 8], r10
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx

    ; Build key
    mov rax, r12
    shl rax, 16
    or rax, r13
    mov r12, rax

    mov rdi, [rbx + Dispatch.table]
    test rdi, rdi
    jz .not_found
    imul rax, 0x9E3779B1
    shr rax, 16
    and rax, 255
    mov r13, 256
.search_loop:
    mov rcx, rax
    shl rcx, 4
    mov rdx, [rdi + rcx]
    test rdx, rdx
    jz .not_found
    dec rdx
    cmp rdx, r12
    je .found
    inc rax
    and rax, 255
    dec r13
    jnz .search_loop
    jmp .not_found

.found:
    mov rax, [rdi + rcx + 8]
    ; Call handler(client, msg_hdr, payload, handles)
    mov rdi, r14
    mov rsi, r15
    mov rdx, [rsp]
    mov rcx, [rsp + 8]
    call rax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_found:
    mov rax, -(ECWP_OPCODE)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data


global dispatch_version
dispatch_version: dq 0x010000
