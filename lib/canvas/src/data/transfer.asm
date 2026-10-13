; ============================================================================
; Transfer — Streaming Data Transfers (Large Data, Chunked)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/channel.inc"

; struct offsets (hoisted above use)
%define Transfer_size    112
%define TRANSFER_STATUS_NONE       0
%define TRANSFER_STATUS_PENDING    1
%define TRANSFER_STATUS_ACTIVE     2
%define TRANSFER_STATUS_COMPLETE   3
%define TRANSFER_STATUS_ERROR      4
%define TRANSFER_STATUS_CANCELLED  5
%define TRANSFER_CHUNK_DEFAULT    (64 * 1024)  ; 64KB

section .text

struc Transfer
    .source_client:     resq 1
    .target_client:     resq 1
    .mime_type:         resq 1
    .mime_type_len:     resq 1
    .total_size:        resq 1
    .transferred:       resq 1
    .chunk_size:        resq 1
    .buffer:            resq 1
    .buffer_size:       resq 1
    .status:            resd 1
    .source_fd:         resq 1
    .target_fd:         resq 1
    .callback:          resq 1
    .user_data:         resq 1
endstruc



; ---------------------------------------------------------------------------
; transfer_init
; ---------------------------------------------------------------------------
global transfer_init
transfer_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.transfers], 0
    mov qword [rbx + Server.transfer_count], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; transfer_create
;   Create streaming transfer
;   IN:  rdi = server*, rsi = source_client*, rdx = target_client*, rcx = mime_type, r8 = mime_len, r9 = total_size
;   OUT: rax = transfer*, negative error
; ---------------------------------------------------------------------------
global transfer_create
transfer_create:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Allocate transfer
    mov rdi, [rbx + Server.arena]
    mov rsi, Transfer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov qword [rbx + Transfer.source_client], r12
    mov qword [rbx + Transfer.target_client], r13
    mov qword [rbx + Transfer.mime_type], r14
    mov qword [rbx + Transfer.mime_type_len], r15
    mov qword [rbx + Transfer.total_size], r9
    mov qword [rbx + Transfer.transferred], 0
    mov qword [rbx + Transfer.chunk_size], TRANSFER_CHUNK_DEFAULT
    mov qword [rbx + Transfer.buffer], 0
    mov qword [rbx + Transfer.buffer_size], 0
    mov dword [rbx + Transfer.status], TRANSFER_STATUS_PENDING
    mov qword [rbx + Transfer.source_fd], 0
    mov qword [rbx + Transfer.target_fd], 0
    mov qword [rbx + Transfer.callback], 0
    mov qword [rbx + Transfer.user_data], 0

    ; Allocate buffer
    mov rdi, [rdi + Server.arena]
    mov rsi, TRANSFER_CHUNK_DEFAULT
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Transfer.buffer], rax
    mov qword [rbx + Transfer.buffer_size], TRANSFER_CHUNK_DEFAULT

    ; Add to transfer list
    mov rax, [rdi + Server.transfers]
    mov [rbx + Transfer.next], rax
    mov [rdi + Server.transfers], rbx
    inc qword [rdi + Server.transfer_count]

    mov dword [rbx + Transfer.status], TRANSFER_STATUS_ACTIVE
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; transfer_start
;   Start transfer
; ---------------------------------------------------------------------------
global transfer_start
transfer_start:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_ACTIVE
    jne .invalid_state

    ; Open source/target FDs
    ; TODO: Implement based on mime type (shared memory, pipe, etc.)

    mov dword [rbx + Transfer.status], TRANSFER_STATUS_ACTIVE
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.invalid_state:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; transfer_read_chunk
;   Read next chunk from source
; ---------------------------------------------------------------------------
global transfer_read_chunk
transfer_read_chunk:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_ACTIVE
    jne .not_active

    ; Read chunk
    ; TODO: Read from source FD into buffer

    ; Update transferred
    add qword [rbx + Transfer.transferred], rax

    ; Check completion
    cmp qword [rbx + Transfer.transferred], [rbx + Transfer.total_size]
    jae .complete

    mov rax, 1  ; more data
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.complete:
    mov dword [rbx + Transfer.status], TRANSFER_STATUS_COMPLETE
    ; TODO: Call completion callback

.not_active:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; transfer_write_chunk
;   Write chunk to target
; ---------------------------------------------------------------------------
global transfer_write_chunk
transfer_write_chunk:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_ACTIVE
    jne .not_active

    ; Write chunk
    ; TODO: Write from buffer to target FD

    ; Update transferred
    add qword [rbx + Transfer.transferred], rax

    ; Check completion
    cmp qword [rbx + Transfer.transferred], [rbx + Transfer.total_size]
    jae .complete

    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

.complete:
    mov dword [rbx + Transfer.status], TRANSFER_STATUS_COMPLETE
    ; TODO: Call completion callback

.not_active:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; transfer_cancel
; ---------------------------------------------------------------------------
global transfer_cancel
transfer_cancel:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_COMPLETE
    je .done
    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_ERROR
    je .done
    cmp dword [rbx + Transfer.status], TRANSFER_STATUS_CANCELLED
    je .done

    mov dword [rbx + Transfer.status], TRANSFER_STATUS_CANCELLED

    ; Close FDs
    ; TODO

    ; Call cancellation callback
    mov rax, [rbx + Transfer.callback]
    test rax, rax
    jz .done
    mov rdi, [rbx + Transfer.user_data]
    call rax

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; transfer_get_progress
; ---------------------------------------------------------------------------
global transfer_get_progress
transfer_get_progress:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    ASSERT_PTR rdx

    mov rax, [rdi + Transfer.transferred]
    mov [rsi], rax
    mov rax, [rdi + Transfer.total_size]
    mov [rdx], rax
    mov eax, [rdi + Transfer.status]
    leave
    ret

section .data
global transfer_version
transfer_version: dq 0x010000
