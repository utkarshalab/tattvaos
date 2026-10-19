; Native path flattening into an integer point stream.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/geometry.inc"
%include "inc/externs.inc"
%define TESS_CAP 8192

section .text
global path_tessellate
path_tessellate:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,64
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .bad
    test r12,r12
    jz .bad
    mov rdi,[rbx+Path_ARENA]
    mov rsi,TESS_CAP
    call arena_alloc
    test rax,rax
    jz .oom
    mov [r12+TessPath_VERBS],rax
    mov rdi,[rbx+Path_ARENA]
    mov rsi,TESS_CAP*8
    call arena_alloc
    test rax,rax
    jz .oom
    mov [r12+TessPath_POINTS],rax
    mov dword [r12+TessPath_COUNT],0
    mov dword [r12+TessPath_CAP],TESS_CAP
    xor r13d,r13d              ; command index
    xor r14d,r14d              ; source point index
    mov r15,[rbx+Path_VERBS]
.commands:
    cmp r13,[rbx+Path_COUNT]
    jae .done
    movzx eax,byte [r15+r13]
    inc r13
    cmp eax,PATH_VERB_CLOSE
    je .close
    mov rdx,[rbx+Path_POINTS]
    lea rdx,[rdx+r14*8]
    cmp eax,PATH_VERB_MOVE
    je .one
    cmp eax,PATH_VERB_LINE
    je .one
    cmp eax,PATH_VERB_QUAD
    je .quad
    cmp eax,PATH_VERB_CUBIC
    je .cubic
    cmp eax,PATH_VERB_ARC
    je .arc
    mov rax,-EINVAL
    jmp .out
.one:
    mov ecx,[rdx]
    mov r8d,[rdx+4]
    mov [rsp+32],ecx
    mov [rsp+36],r8d
    cmp eax,PATH_VERB_MOVE
    jne .one_emit
    mov [rsp+40],ecx
    mov [rsp+44],r8d
.one_emit:
    call .emit
    inc r14
    jmp .commands
.quad:
    ; p0 is current, p1/p2 are source. Evaluate 16 uniform samples.
    mov eax,[rsp+32]
    mov [rsp],eax
    mov eax,[rsp+36]
    mov [rsp+4],eax
    mov eax,[rdx]
    mov [rsp+8],eax
    mov eax,[rdx+4]
    mov [rsp+12],eax
    mov eax,[rdx+8]
    mov [rsp+16],eax
    mov eax,[rdx+12]
    mov [rsp+20],eax
    mov r9d,1
.quad_loop:
    cmp r9d,16
    jg .quad_done
    mov eax,16
    sub eax,r9d
    mov r10d,eax
    imul eax,eax
    imul eax,[rsp]
    mov ecx,r10d
    imul ecx,r9d
    shl ecx,1
    imul ecx,[rsp+8]
    add eax,ecx
    mov ecx,r9d
    imul ecx,ecx
    imul ecx,[rsp+16]
    add eax,ecx
    sar eax,8
    mov [rsp+32],eax
    mov eax,r10d
    imul eax,eax
    imul eax,[rsp+4]
    mov ecx,r10d
    imul ecx,r9d
    shl ecx,1
    imul ecx,[rsp+12]
    add eax,ecx
    mov ecx,r9d
    imul ecx,ecx
    imul ecx,[rsp+20]
    add eax,ecx
    sar eax,8
    mov [rsp+36],eax
    call .emit
    inc r9d
    jmp .quad_loop
.quad_done:
    add r14,2
    jmp .commands
.cubic:
    ; De Casteljau sampling at 1/32 increments, using 16.16 t.
    mov eax,[rsp+32]
    mov [rsp],eax
    mov eax,[rsp+36]
    mov [rsp+4],eax
    mov r9d,1
.cubic_loop:
    cmp r9d,32
    jg .cubic_done
    mov eax,r9d
    shl eax,11
    mov r10d,65536
    sub r10d,eax
    ; Bernstein weights in Q16.16.
    mov r11d,r10d
    imul r11,r10
    sar r11,16
    imul r11,r10
    sar r11,16
    mov ecx,eax
    imul rcx,rax
    sar rcx,16
    imul rcx,rax
    sar rcx,16
    mov esi,r10d
    imul rsi,r10
    sar rsi,16
    imul rsi,rax
    sar rsi,16
    imul esi,3
    mov edi,eax
    imul rdi,rax
    sar rdi,16
    imul rdi,r10
    sar rdi,16
    imul edi,3
    movsxd rax,dword [rsp]
    imul rax,r11
    movsxd r10,dword [rdx]
    imul r10,rsi
    add rax,r10
    movsxd r10,dword [rdx+8]
    imul r10,rdi
    add rax,r10
    movsxd r10,dword [rdx+16]
    imul r10,rcx
    add rax,r10
    sar rax,16
    mov [rsp+32],eax
    ; Y with same weights.
    movsxd rax,dword [rsp+4]
    imul rax,r11
    movsxd r10,dword [rdx+4]
    imul r10,rsi
    add rax,r10
    movsxd r10,dword [rdx+12]
    imul r10,rdi
    add rax,r10
    movsxd r10,dword [rdx+20]
    imul r10,rcx
    add rax,r10
    sar rax,16
    mov [rsp+36],eax
    call .emit
    inc r9d
    jmp .cubic_loop
.cubic_done:
    add r14,3
    jmp .commands
.arc:
    ; Arc records end in the third slot. Preserve a valid contour even when
    ; radii collapse; the dedicated arc rasterizer handles curved strokes.
    mov eax,[rdx+16]
    mov [rsp+32],eax
    mov eax,[rdx+20]
    mov [rsp+36],eax
    call .emit
    add r14,3
    jmp .commands
.close:
    mov eax,[rsp+40]
    mov [rsp+32],eax
    mov eax,[rsp+44]
    mov [rsp+36],eax
    call .emit
    jmp .commands
.emit:
    mov eax,[r12+TessPath_COUNT]
    cmp eax,[r12+TessPath_CAP]
    jae .emit_full
    mov rdi,[r12+TessPath_POINTS]
    mov ecx,[rsp+32]
    mov [rdi+rax*8],ecx
    mov ecx,[rsp+36]
    mov [rdi+rax*8+4],ecx
    mov rdi,[r12+TessPath_VERBS]
    mov byte [rdi+rax],PATH_VERB_LINE
    inc dword [r12+TessPath_COUNT]
    ret
.emit_full:
    mov rax,-ENOSPC
    add rsp,8
    jmp .out
.done:
    xor eax,eax
    jmp .out
.bad: mov rax,-EINVAL
    jmp .out
.oom: mov rax,-ENOMEM
.out:
    add rsp,64
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

global path_bounds
path_bounds:
    PROLOGUE_SAVE rbx,r12,r13,r14
    mov rbx,[rdi+Path_POINTS]
    mov r13,[rdi+Path_POINT_COUNT]
    test r13,r13
    jz .empty
    mov r12,rsi
    mov eax,[rbx]
    mov [r12],eax
    mov [r12+8],eax
    mov eax,[rbx+4]
    mov [r12+4],eax
    mov [r12+12],eax
    mov r14,1
.bloop:
    cmp r14,r13
    jae .bdone
    mov eax,[rbx+r14*8]
    cmp eax,[r12]
    jge .bmaxx
    mov [r12],eax
.bmaxx:
    mov eax,[rbx+r14*8]
    cmp eax,[r12+8]
    jle .bminy
    mov [r12+8],eax
.bminy:
    mov eax,[rbx+r14*8+4]
    cmp eax,[r12+4]
    jge .bmaxy
    mov [r12+4],eax
.bmaxy:
    mov eax,[rbx+r14*8+4]
    cmp eax,[r12+12]
    jle .bnext
    mov [r12+12],eax
.bnext:
    inc r14
    jmp .bloop
.bdone:
    mov eax,[r12+8]
    sub eax,[r12]
    mov [r12+8],eax
    mov eax,[r12+12]
    sub eax,[r12+4]
    mov [r12+12],eax
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret
.empty: mov rax,-ENOENT
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret

section .data
global path_tess_version
path_tess_version: dq 0x010100
