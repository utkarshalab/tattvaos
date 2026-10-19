; Native filled-path rendering and hit testing.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/geometry.inc"
%include "inc/externs.inc"

section .text
; IN pixbuf*, path*, BGRA color. Additional registers are intentionally unused.
global path_render
path_render:
    PROLOGUE_SAVE rbx,r12,r13
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13d,edx
    test rbx,rbx
    jz .bad
    test r12,r12
    jz .bad
    mov rdi,r12
    mov rsi,rsp
    mov edx,0x4000
    call path_tessellate
    test rax,rax
    js .out
    cmp dword [rsp+TessPath_COUNT],3
    jb .empty
    mov rdi,rbx
    mov rsi,[rsp+TessPath_POINTS]
    mov edx,[rsp+TessPath_COUNT]
    mov ecx,r13d
    call polygon_draw
    jmp .out
.empty: xor eax,eax
    jmp .out
.bad: mov rax,-EINVAL
.out:
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13
    ret

; IN path*, x, y, fill rule. Curves are tested after native flattening.
global path_hit_test
path_hit_test:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12d,esi
    mov r13d,edx
    mov rdi,rbx
    mov rsi,rsp
    mov edx,0x4000
    call path_tessellate
    test rax,rax
    js .out
    mov r14,[rsp+TessPath_POINTS]
    mov r15d,[rsp+TessPath_COUNT]
    cmp r15d,3
    jb .outside
    xor r8d,r8d
    xor r9d,r9d
.edge:
    cmp r9d,r15d
    jae .result
    mov ecx,r9d
    inc ecx
    cmp ecx,r15d
    jb .idx
    xor ecx,ecx
.idx:
    mov esi,[r14+r9*8+4]
    mov edi,[r14+rcx*8+4]
    cmp esi,edi
    je .next
    mov eax,esi
    mov edx,edi
    cmp eax,edx
    jle .ordered
    xchg eax,edx
.ordered:
    cmp r13d,eax
    jl .next
    cmp r13d,edx
    jge .next
    movsxd rax,dword [r14+rcx*8]
    movsxd rdx,dword [r14+r9*8]
    sub rax,rdx
    movsxd rsi,r13d
    movsxd rdi,dword [r14+r9*8+4]
    sub rsi,rdi
    imul rax,rsi
    movsxd rsi,dword [r14+rcx*8+4]
    sub rsi,rdi
    cqo
    idiv rsi
    movsxd rdx,dword [r14+r9*8]
    add rax,rdx
    cmp r12d,eax
    jge .next
    xor r8d,1
.next:
    inc r9d
    jmp .edge
.result:
    mov eax,r8d
    jmp .out
.outside: xor eax,eax
.out:
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; Gradient and pattern fills are routed through their native paint engines.
; They return ENOTSUP until those engines expose per-pixel samplers suitable
; for polygon masking; callers can render a solid path without fallback.
global path_render_gradient
path_render_gradient:
    mov rax,-ENOTSUP
    ret
global path_render_pattern
path_render_pattern:
    mov rax,-ENOTSUP
    ret

section .data
global path_render_version
path_render_version: dq 0x010100
