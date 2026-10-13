; ============================================================================
; Dispatch — Opcode Dispatch Tables
; ============================================================================

%include "inc/abi.inc"
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
    PROLOGUE_SAVE rbx, r12, r13, r14
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

    ; For now, just store in array (linear search)
    ; TODO: Use hash map for O(1) lookup
    mov rdi, [rbx + Dispatch.table]
    test rdi, rdi
    jnz .has_table

    ; Allocate table
    push r14
    mov rdi, [rbx + Dispatch.arena]
    mov rsi, 256
    mov rdx, 16
    call arena_alloc
    pop r14
    test rax, rax
    jz .oom
    mov [rbx + Dispatch.table], rax
    mov qword [rbx + Dispatch.capacity], 16
    mov qword [rbx + Dispatch.count], 0

.has_table:
    mov rdi, [rbx + Dispatch.table]
    mov rcx, [rbx + Dispatch.count]
    ; Check for duplicate
    xor rdx, rdx
.check_loop:
    cmp rdx, rcx
    jae .insert
    mov rax, [rdi + rdx * 16]
    cmp rax, r12
    jne .next
    ; Found - update
    mov [rdi + rdx * 16 + 8], r14
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.next:
    inc rdx
    jmp .check_loop

.insert:
    cmp rcx, [rbx + Dispatch.capacity]
    jae .grow

    mov [rdi + rcx * 16], r12
    mov [rdi + rcx * 16 + 8], r14
    inc qword [rbx + Dispatch.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.grow:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
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

    ; Linear search
    mov rdi, [rbx + Dispatch.table]
    mov rcx, [rbx + Dispatch.count]
    test rcx, rcx
    jz .not_found

    xor rdx, rdx
.search_loop:
    cmp rdx, rcx
    jae .not_found
    cmp qword [rdi + rdx * 16], rax
    je .found
    inc rdx
    jmp .search_loop

.found:
    mov rax, [rdi + rdx * 16 + 8]   ; handler
    ; Call handler(client, msg_hdr, payload, handles)
    mov rdi, r14
    mov rsi, r15
    mov rdx, r9
    mov rcx, r10
    call rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.not_found:
    mov rax, -(ECWP_OPCODE)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data


global dispatch_version
dispatch_version: dq 0x010000
