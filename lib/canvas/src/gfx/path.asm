; Native TattvaOS vector path command container.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/geometry.inc"
%include "inc/externs.inc"

section .text
; IN path*, arena*. Storage is bounded deliberately to prevent hostile paths
; from causing unbounded display-server allocations.
global path_create
path_create:
    PROLOGUE_SAVE rbx,r12,r13
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .bad
    test r12,r12
    jz .bad
    mov rdi,r12
    mov rsi,PATH_MAX_VERBS
    call arena_alloc
    test rax,rax
    jz .oom
    mov [rbx+Path_VERBS],rax
    mov rdi,r12
    mov rsi,PATH_MAX_POINTS*8
    call arena_alloc
    test rax,rax
    jz .oom
    mov [rbx+Path_POINTS],rax
    mov qword [rbx+Path_COUNT],0
    mov qword [rbx+Path_POINT_COUNT],0
    mov dword [rbx+Path_CAP],PATH_MAX_VERBS
    mov [rbx+Path_ARENA],r12
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13
    ret
.bad: mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13
    ret
.oom: mov rax,-ENOMEM
    EPILOGUE_RESTORE rbx,r12,r13
    ret

; IN path*, verb, source points*, point count.
path_append:
    PROLOGUE_SAVE rbx,r12,r13,r14
    mov rbx,rdi
    mov r12d,esi
    mov r13,rdx
    mov r14,rcx
    mov rax,[rbx+Path_COUNT]
    cmp eax,[rbx+Path_CAP]
    jae .full
    mov rdi,[rbx+Path_POINT_COUNT]
    lea rcx,[rdi+r14]
    cmp rcx,PATH_MAX_POINTS
    ja .full
    mov rdx,[rbx+Path_VERBS]
    mov [rdx+rax],r12b
    inc qword [rbx+Path_COUNT]
    test r14,r14
    jz .ok
    shl rdi,3
    add rdi,[rbx+Path_POINTS]
    mov rsi,r13
    mov rdx,r14
    shl rdx,3
    call memcopy
    add [rbx+Path_POINT_COUNT],r14
.ok: xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret
.full: mov rax,-ENOSPC
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret

global path_move_to
path_move_to:
    sub rsp,16
    mov [rsp],esi
    mov [rsp+4],edx
    mov esi,PATH_VERB_MOVE
    mov rdx,rsp
    mov ecx,1
    call path_append
    add rsp,16
    ret

global path_line_to
path_line_to:
    sub rsp,16
    mov [rsp],esi
    mov [rsp+4],edx
    mov esi,PATH_VERB_LINE
    mov rdx,rsp
    mov ecx,1
    call path_append
    add rsp,16
    ret

global path_quad_to
path_quad_to:
    sub rsp,16
    mov [rsp],esi
    mov [rsp+4],edx
    mov [rsp+8],ecx
    mov [rsp+12],r8d
    mov esi,PATH_VERB_QUAD
    mov rdx,rsp
    mov ecx,2
    call path_append
    add rsp,16
    ret

global path_cubic_to
path_cubic_to:
    sub rsp,32
    mov [rsp],esi
    mov [rsp+4],edx
    mov [rsp+8],ecx
    mov [rsp+12],r8d
    mov [rsp+16],r9d
    mov [rsp+20],r10d
    mov esi,PATH_VERB_CUBIC
    mov rdx,rsp
    mov ecx,3
    call path_append
    add rsp,32
    ret

; Native arc command: rx,ry,rotation,flags,end-x,end-y (three point slots).
global path_arc_to
path_arc_to:
    sub rsp,32
    mov [rsp],esi
    mov [rsp+4],edx
    mov [rsp+8],ecx
    mov [rsp+12],r8d
    mov [rsp+16],r9d
    mov [rsp+20],r10d
    mov esi,PATH_VERB_ARC
    mov rdx,rsp
    mov ecx,3
    call path_append
    add rsp,32
    ret

global path_close
path_close:
    mov esi,PATH_VERB_CLOSE
    xor edx,edx
    xor ecx,ecx
    jmp path_append

global path_reset
path_reset:
    test rdi,rdi
    jz .bad
    mov qword [rdi+Path_COUNT],0
    mov qword [rdi+Path_POINT_COUNT],0
    xor eax,eax
    ret
.bad: mov rax,-EINVAL
    ret

section .data
global path_version
path_version: dq 0x010100
