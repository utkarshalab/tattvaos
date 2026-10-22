; Server clipboard storage and MIME negotiation.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern memset
extern memcopy
extern memcmp

%define SELECTION_CLIPBOARD 0
%define SELECTION_PRIMARY   1

section .text
global clipboard_init
clipboard_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov [rbx + Server.arena], r12
    mov rdi, r12
    mov rsi, Clipboard_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    xor esi, esi
    mov rdx, Clipboard_size
    call memset
    mov dword [r13 + Clipboard.selection_type], SELECTION_CLIPBOARD
    mov [rbx + Server.clipboard], r13
    mov rdi, r12
    mov rsi, Clipboard_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    xor esi, esi
    mov rdx, Clipboard_size
    call memset
    mov dword [r13 + Clipboard.selection_type], SELECTION_PRIMARY
    mov [rbx + Server.primary_selection], r13
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; server, client, mime, mime_len, data, data_len
global clipboard_set
clipboard_set:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9
    test r13, r13
    jz .invalid
    test r15, r15
    jz .invalid
    test r14, r14
    jz .invalid
    cmp r14, 128
    ja .invalid
    cmp qword [rsp], CLIPBOARD_MAX_SIZE
    ja .large
    mov rdi, [rbx + Server.arena]
    mov rsi, [rsp]
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rsp + 8], rax
    mov rdi, rax
    mov rsi, r15
    mov rdx, [rsp]
    call memcopy
    mov rdi, [rbx + Server.arena]
    lea rsi, [r14 + 1]
    call arena_alloc
    test rax, rax
    jz .oom
    mov r15, rax
    mov rdi, r15
    mov rsi, r13
    mov rdx, r14
    call memcopy
    mov byte [r15 + r14], 0
    mov rax, [rbx + Server.clipboard]
    mov rdx, [rsp + 8]
    mov [rax + Clipboard.data], rdx
    mov rdx, [rsp]
    mov [rax + Clipboard.data_len], rdx
    mov [rax + Clipboard.mime_type], r15
    mov [rax + Clipboard.mime_type_len], r14
    mov [rax + Clipboard.source_client], r12
    lea rdx, [rax + Clipboard.mime_type]
    mov [rax + Clipboard.offered_mimes], rdx
    mov dword [rax + Clipboard.offered_count], 1
    inc qword [rax + Clipboard.serial]
    mov rdi, rbx
    mov rsi, rax
    call clipboard_send_event
    xor eax, eax
    jmp .out
.invalid:
    mov rax, -(EINVAL)
    jmp .out
.large:
    mov rax, -(ECLIP_SIZE)
    jmp .out
.oom:
    mov rax, -(ENOMEM)
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; server, requested_mime, requested_len -> rax=data, rdx=len
global clipboard_get
clipboard_get:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, [rbx + Server.clipboard]
    test rax, rax
    jz .empty
    cmp qword [rax + Clipboard.data_len], 0
    je .empty
    test r12, r12
    jz .return
    cmp r13, 3
    jne .exact
    cmp byte [r12], '*'
    jne .exact
    cmp byte [r12 + 1], '/'
    jne .exact
    cmp byte [r12 + 2], '*'
    je .return
.exact:
    cmp r13, [rax + Clipboard.mime_type_len]
    jne .mime
    mov rdi, r12
    mov rsi, [rax + Clipboard.mime_type]
    mov rdx, r13
    push rax
    call memcmp
    mov rcx, rax
    pop rax
    test rcx, rcx
    jnz .mime
.return:
    mov rdx, [rax + Clipboard.data_len]
    mov rax, [rax + Clipboard.data]
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.mime:
    mov rax, -(ECLIP_MIME)
    xor edx, edx
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.empty:
    xor eax, eax
    xor edx, edx
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; server -> rax=array of char*, rdx=count
global clipboard_get_mimes
clipboard_get_mimes:
    mov rax, [rdi + Server.clipboard]
    test rax, rax
    jz .none
    mov edx, [rax + Clipboard.offered_count]
    mov rax, [rax + Clipboard.offered_mimes]
    ret
.none:
    xor eax, eax
    xor edx, edx
    ret

; The serial is the notification generation consumed by native clients.
global clipboard_send_event
clipboard_send_event:
    mov rax, [rsi + Clipboard.serial]
    ret

section .data
global clipboard_version
clipboard_version: dq 0x010000
