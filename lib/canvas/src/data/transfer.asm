; Bounded native-memory streaming transfers.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern memset
extern memcopy

%define TRANSFER_STATUS_PENDING    1
%define TRANSFER_STATUS_ACTIVE     2
%define TRANSFER_STATUS_COMPLETE   3
%define TRANSFER_STATUS_ERROR      4
%define TRANSFER_STATUS_CANCELLED  5
%define TRANSFER_CHUNK_DEFAULT     65536

section .text
global transfer_init
transfer_init:
    mov qword [rdi + Server.transfers], 0
    mov qword [rdi + Server.transfer_count], 0
    xor eax, eax
    ret

global transfer_create
transfer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9
    mov rdi, [rbx + Server.arena]
    mov rsi, Transfer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rsp + 8], rax
    mov rdi, rax
    xor esi, esi
    mov rdx, Transfer_size
    call memset
    mov rax, [rsp + 8]
    mov [rax + Transfer.source_client], r12
    mov [rax + Transfer.target_client], r13
    mov [rax + Transfer.mime_type], r14
    mov [rax + Transfer.mime_type_len], r15
    mov rdx, [rsp]
    mov [rax + Transfer.total_size], rdx
    mov qword [rax + Transfer.chunk_size], TRANSFER_CHUNK_DEFAULT
    mov dword [rax + Transfer.status], TRANSFER_STATUS_PENDING
    mov rdx, [rbx + Server.transfers]
    mov [rax + Transfer.next], rdx
    mov [rbx + Server.transfers], rax
    inc qword [rbx + Server.transfer_count]
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; transfer, source memory, target memory
global transfer_start
transfer_start:
    cmp dword [rdi + Transfer.status], TRANSFER_STATUS_PENDING
    jne .bad
    test rsi, rsi
    jz .bad
    mov [rdi + Transfer.source_fd], rsi
    mov [rdi + Transfer.target_fd], rdx
    mov dword [rdi + Transfer.status], TRANSFER_STATUS_ACTIVE
    xor eax, eax
    ret
.bad:
    mov rax, -(EINVAL)
    ret

; transfer, destination, capacity -> bytes copied
global transfer_read_chunk
transfer_read_chunk:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_ACTIVE
    jne .inactive
    mov r14, [rbx + Transfer.total_size]
    sub r14, [rbx + Transfer.transferred]
    cmp r14, r13
    cmova r14, r13
    cmp r14, [rbx + Transfer.chunk_size]
    cmova r14, [rbx + Transfer.chunk_size]
    test r14, r14
    jz .complete
    mov rsi, [rbx + Transfer.source_fd]
    add rsi, [rbx + Transfer.transferred]
    mov rdi, r12
    mov rdx, r14
    call memcopy
    add [rbx + Transfer.transferred], r14
    mov rax, r14
    mov rax, [rbx + Transfer.transferred]
    cmp rax, [rbx + Transfer.total_size]
    jb .out
.complete:
    mov dword [rbx + Transfer.status], TRANSFER_STATUS_COMPLETE
    call transfer_notify
    mov rax, r14
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.inactive:
    mov rax, -(EINVAL)
    jmp .out

; transfer, source, length -> bytes copied
global transfer_write_chunk
transfer_write_chunk:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_ACTIVE
    jne .write_bad
    mov rax, [rbx + Transfer.total_size]
    sub rax, [rbx + Transfer.transferred]
    cmp r13, rax
    cmova r13, rax
    mov rdi, [rbx + Transfer.target_fd]
    test rdi, rdi
    jz .write_bad
    add rdi, [rbx + Transfer.transferred]
    mov rsi, r12
    mov rdx, r13
    call memcopy
    add [rbx + Transfer.transferred], r13
    mov rax, [rbx + Transfer.transferred]
    cmp rax, [rbx + Transfer.total_size]
    jb .write_more
    mov dword [rbx + Transfer.status], TRANSFER_STATUS_COMPLETE
    call transfer_notify
.write_more:
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.write_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

transfer_notify:
    mov rax, [rbx + Transfer.callback]
    test rax, rax
    jz .notify_done
    mov rdi, [rbx + Transfer.user_data]
    mov esi, [rbx + Transfer.status]
    call rax
.notify_done:
    ret

global transfer_cancel
transfer_cancel:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_COMPLETE
    je .cancel_done
    mov dword [rbx + Transfer.status], TRANSFER_STATUS_CANCELLED
    mov qword [rbx + Transfer.source_fd], 0
    mov qword [rbx + Transfer.target_fd], 0
    call transfer_notify
.cancel_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx
    ret

global transfer_get_progress
transfer_get_progress:
    mov rax, [rdi + Transfer.transferred]
    mov [rsi], rax
    mov rax, [rdi + Transfer.total_size]
    mov [rdx], rax
    mov eax, [rdi + Transfer.status]
    ret

section .data
global transfer_version
transfer_version: dq 0x010000
