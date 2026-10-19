; ZSoft PCX decoder: 8-bit indexed and 24-bit planar RGB with PCX RLE.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

section .text
global pcx_decode
pcx_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,128
    jb .bad
    cmp byte [r12],10
    jne .bad
    cmp byte [r12+2],1
    jne .bad
    cmp byte [r12+3],8
    jne .bad
    movzx eax,word [r12+8]
    movzx ecx,word [r12+4]
    sub eax,ecx
    inc eax
    mov [rsp],eax
    movzx eax,word [r12+10]
    movzx ecx,word [r12+6]
    sub eax,ecx
    inc eax
    mov [rsp+4],eax
    movzx eax,byte [r12+65]
    cmp eax,1
    je .planes_ok
    cmp eax,3
    jne .bad
.planes_ok:
    mov [rsp+8],eax
    movzx eax,word [r12+66]
    mov [rsp+12],eax
    mov rax,[rsp+12]
    imul rax,[rsp+8]
    mov [rsp+16],rax
    mov rdi,rbx
    mov rsi,rax
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+24],rax
    mov rdi,rbx
    mov esi,[rsp]
    mov edx,[rsp+4]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov rbx,rax
    add r12,128
    sub r13,128
    xor r14d,r14d
.row:
    cmp r14d,[rsp+4]
    jae .done
    mov rdi,[rsp+24]
    mov rcx,[rsp+16]
.decode_row:
    test rcx,rcx
    jz .convert
    test r13,r13
    jz .bad
    movzx eax,byte [r12]
    inc r12
    dec r13
    mov edx,1
    cmp al,0xC0
    jb .literal
    mov edx,eax
    and edx,0x3F
    test r13,r13
    jz .bad
    movzx eax,byte [r12]
    inc r12
    dec r13
.literal:
    cmp rdx,rcx
    jbe .run_ok
    mov rdx,rcx
.run_ok:
    sub rcx,rdx
    rep stosb
    jmp .decode_row
.convert:
    mov rax,[rbx+PixBuf_stride]
    imul rax,r14
    add rax,[rbx+PixBuf_data]
    mov rdi,rax
    xor r15d,r15d
.pixel:
    cmp r15d,[rsp]
    jae .next_row
    cmp dword [rsp+8],3
    je .rgb
    ; Indexed PCX palette is the final 768 bytes, preceded by 0x0C.
    cmp r13,769
    jb .bad
    lea rdx,[r12+r13-768]
    mov rcx,[rsp+24]
    movzx eax,byte [rcx+r15]
    lea rax,[rax+rax*2]
    mov cl,[rdx+rax+2]
    mov [rdi],cl
    mov cl,[rdx+rax+1]
    mov [rdi+1],cl
    mov cl,[rdx+rax]
    mov [rdi+2],cl
    jmp .alpha
.rgb:
    mov rcx,[rsp+24]
    mov eax,[rsp+12]
    mov dl,[rcx+r15]
    mov [rdi+2],dl
    mov dl,[rcx+rax+r15]
    mov [rdi+1],dl
    add eax,[rsp+12]
    mov dl,[rcx+rax+r15]
    mov [rdi],dl
.alpha:
    mov byte [rdi+3],255
    add rdi,4
    inc r15d
    jmp .pixel
.next_row:
    inc r14d
    jmp .row
.done:
    mov rax,rbx
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global pcx_version
pcx_version: dq 0x010000
