; MIME type parsing and wildcard negotiation.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern memcopy
extern str_cmp

struc MimeType
    .type:    resq 1
    .subtype: resq 1
    .params:  resq 1
    .next:    resq 1
endstruc

section .text
global mime_init
mime_init:
    xor eax, eax
    ret

; rdi=bytes, rsi=len, rdx=arena
global mime_parse
mime_parse:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    test r12, r12
    jz .invalid
    test r13, r13
    jz .invalid
    cmp r13, 128
    ja .invalid
    xor ecx, ecx
.slash:
    cmp rcx, r13
    jae .invalid
    cmp byte [r12 + rcx], '/'
    je .have_slash
    inc rcx
    jmp .slash
.have_slash:
    test rcx, rcx
    jz .invalid
    lea r15, [rcx + 1]
    cmp r15, r13
    jae .invalid
    mov rdi, r14
    mov rsi, MimeType_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + MimeType.params], 0
    mov qword [rbx + MimeType.next], 0
    mov rdi, r14
    mov rsi, r12
    mov rdx, rcx
    call .dup_range
    test rax, rax
    jz .oom
    mov [rbx + MimeType.type], rax
    mov rcx, r15
.semi:
    cmp rcx, r13
    jae .sub_end
    cmp byte [r12 + rcx], ';'
    je .sub_end
    inc rcx
    jmp .semi
.sub_end:
    mov rdx, rcx
    sub rdx, r15
    test rdx, rdx
    jz .invalid
    mov rdi, r14
    lea rsi, [r12 + r15]
    call .dup_range
    test rax, rax
    jz .oom
    mov [rbx + MimeType.subtype], rax
    cmp rcx, r13
    jae .done
    inc rcx
.param_ws:
    cmp rcx, r13
    jae .done
    mov al, [r12 + rcx]
    cmp al, ' '
    je .skip_param_ws
    cmp al, 9
    jne .param_copy
.skip_param_ws:
    inc rcx
    jmp .param_ws
.param_copy:
    mov rdx, r13
    sub rdx, rcx
    mov rdi, r14
    lea rsi, [r12 + rcx]
    call .dup_range
    test rax, rax
    jz .oom
    mov [rbx + MimeType.params], rax
.done:
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.dup_range:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    lea rsi, [r13 + 1]
    call arena_alloc
    test rax, rax
    jz .dup_out
    push rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, r13
    call memcopy
    pop rax
    mov byte [rax + r13], 0
.dup_out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global mime_match
mime_match:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    test rbx, rbx
    jz .no
    test r12, r12
    jz .no
    mov rdi, [rbx + MimeType.type]
    mov rsi, [r12 + MimeType.type]
    call .component_match
    test eax, eax
    jz .no
    mov rdi, [rbx + MimeType.subtype]
    mov rsi, [r12 + MimeType.subtype]
    call .component_match
    EPILOGUE_RESTORE rbx, r12
    ret
.no:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret
.component_match:
    cmp byte [rdi], '*'
    jne .check_right
    cmp byte [rdi + 1], 0
    je .yes
.check_right:
    cmp byte [rsi], '*'
    jne .compare
    cmp byte [rsi + 1], 0
    je .yes
.compare:
    call str_cmp
    test rax, rax
    setz al
    movzx eax, al
    ret
.yes:
    mov eax, 1
    ret

; rdi=mime, rsi=buffer, rdx=capacity
global mime_to_string
mime_to_string:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    test r13, r13
    jz .small
    mov rsi, [rbx + MimeType.type]
    call .append
    test eax, eax
    js .out
    mov al, '/'
    call .put
    test eax, eax
    js .out
    mov rsi, [rbx + MimeType.subtype]
    call .append
    test eax, eax
    js .out
    mov byte [r12 + r14], 0
    mov rax, r14
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.small:
    mov rax, -(ENOBUFS)
    jmp .out
.append:
    mov al, [rsi]
    test al, al
    jz .append_done
    call .put
    test eax, eax
    js .append_done
    inc rsi
    jmp .append
.append_done:
    ret
.put:
    lea rax, [r14 + 1]
    cmp rax, r13
    jae .put_fail
    mov [r12 + r14], al
    inc r14
    xor eax, eax
    ret
.put_fail:
    mov rax, -(ENOBUFS)
    ret

section .data
global mime_version
mime_version: dq 0x010000
