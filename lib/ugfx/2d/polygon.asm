; Filled polygon rasterization using the even-odd rule and half-open edges.
%include "ugfx.inc"

section .text
; IN pixbuf*, points[{s32 x,s32 y}], count, BGRA color.
global polygon_draw
polygon_draw:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14d,ecx
    test rbx,rbx
    jz .bad
    test r12,r12
    jz .bad
    cmp r13,3
    jb .bad
    ; One signed 64-bit intersection per edge.
    mov rax,r13
    shl rax,3
    add rax,15
    and rax,-16
    sub rsp,rax
    mov r15,rax
    ; Clamp polygon Y bounds to the target.
    mov eax,[r12+4]
    mov r10d,eax
    mov r11d,eax
    mov rcx,1
.bounds:
    cmp rcx,r13
    jae .clip
    mov eax,[r12+rcx*8+4]
    cmp eax,r10d
    cmovl r10d,eax
    cmp eax,r11d
    cmovg r11d,eax
    inc rcx
    jmp .bounds
.clip:
    xor eax,eax
    test r10d,r10d
    cmovs r10d,eax
    mov eax,[rbx+PixBuf_height]
    cmp r11d,eax
    cmovg r11d,eax
.scanline:
    cmp r10d,r11d
    jge .ok
    xor r8d,r8d                 ; intersection count
    xor r9d,r9d                 ; vertex index
.edges:
    cmp r9,r13
    jae .sort
    mov rcx,r9
    inc rcx
    cmp rcx,r13
    jb .next_index
    xor ecx,ecx
.next_index:
    mov esi,[r12+r9*8+4]
    mov edi,[r12+rcx*8+4]
    ; Include y in [min,max), avoiding double-counted vertices.
    cmp esi,edi
    je .edge_next
    mov eax,esi
    mov edx,edi
    cmp eax,edx
    jle .ordered
    xchg eax,edx
.ordered:
    cmp r10d,eax
    jl .edge_next
    cmp r10d,edx
    jge .edge_next
    ; x = x0 + (y-y0)*(x1-x0)/(y1-y0), in signed 64-bit.
    movsxd rax,dword [r12+rcx*8]
    movsxd rdx,dword [r12+r9*8]
    sub rax,rdx
    movsxd rsi,r10d
    movsxd rdi,dword [r12+r9*8+4]
    sub rsi,rdi
    imul rax,rsi
    movsxd rsi,dword [r12+rcx*8+4]
    sub rsi,rdi
    cqo
    idiv rsi
    movsxd rdx,dword [r12+r9*8]
    add rax,rdx
    mov [rsp+r8*8],rax
    inc r8
.edge_next:
    inc r9
    jmp .edges
.sort:
    ; Stable insertion sort; typical UI polygons have very few crossings.
    mov rcx,1
.sort_outer:
    cmp rcx,r8
    jae .spans
    mov rax,[rsp+rcx*8]
    mov rdx,rcx
.sort_inner:
    test rdx,rdx
    jz .sort_place
    mov rsi,[rsp+rdx*8-8]
    cmp rsi,rax
    jle .sort_place
    mov [rsp+rdx*8],rsi
    dec rdx
    jmp .sort_inner
.sort_place:
    mov [rsp+rdx*8],rax
    inc rcx
    jmp .sort_outer
.spans:
    xor ecx,ecx
.span_loop:
    lea rax,[rcx+1]
    cmp rax,r8
    jae .next_y
    mov esi,[rsp+rcx*8]
    mov edx,[rsp+rcx*8+8]
    xor eax,eax
    test esi,esi
    cmovs esi,eax
    mov eax,[rbx+PixBuf_width]
    cmp edx,eax
    cmovg edx,eax
    cmp esi,edx
    jge .span_next
    mov rdi,[rbx+PixBuf_data]
    mov rax,[rbx+PixBuf_stride]
    imul rax,r10
    add rdi,rax
    lea rdi,[rdi+rsi*4]
    mov eax,r14d
    push rcx
    mov ecx,edx
    sub ecx,esi
    rep stosd
    pop rcx
.span_next:
    add rcx,2
    jmp .span_loop
.next_y:
    inc r10d
    jmp .scanline
.ok:
    xor eax,eax
    add rsp,r15
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

global triangle_draw
triangle_draw:
    PROLOGUE_SAVE rbx
    sub rsp,32
    mov rbx,rdi
    mov [rsp],esi
    mov [rsp+4],edx
    mov [rsp+8],ecx
    mov [rsp+12],r8d
    mov [rsp+16],r9d
    mov [rsp+20],r10d
    mov rdi,rbx
    mov rsi,rsp
    mov edx,3
    mov ecx,r11d
    call polygon_draw
    add rsp,32
    EPILOGUE_RESTORE rbx
    ret

global quad_draw
quad_draw:
    mov rcx,rdx
    mov edx,4
    jmp polygon_draw

section .data
global polygon_version
polygon_version: dq 0x010100
global triangle_version
triangle_version: dq 0x010100
global quad_version
quad_version: dq 0x010100
