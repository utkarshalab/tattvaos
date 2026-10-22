; Windows ICO/CUR decoder: embedded PNG and uncompressed 32-bit DIB entries.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

extern pixbuf_create
extern png_decode
extern memcopy

section .text
global ico_decode
ico_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,22
    jb .bad
    cmp word [r12],0
    jne .bad
    movzx eax,word [r12+2]
    cmp eax,1
    je .type_ok
    cmp eax,2
    jne .bad
.type_ok:
    movzx eax,word [r12+4]
    test eax,eax
    jz .bad
    mov r14d,[r12+14]             ; resource size
    mov r15d,[r12+18]             ; resource offset
    mov eax,r15d
    add rax,r14
    cmp rax,r13
    ja .bad
    lea rsi,[r12+r15]
    cmp r14,8
    jb .bad
    cmp dword [rsi],0x474E5089
    jne .dib
    mov rdi,rbx
    mov rdx,r14
    call png_decode
    jmp .return
.dib:
    cmp r14,40
    jb .bad
    cmp dword [rsi],40
    jb .bad
    mov eax,[rsi+4]
    mov [rsp],eax                 ; width
    mov eax,[rsi+8]
    cdq
    xor eax,edx
    sub eax,edx
    shr eax,1                     ; ICO DIB height includes AND mask
    mov [rsp+4],eax
    cmp word [rsi+12],1
    jne .bad
    cmp word [rsi+14],32
    jne .bad
    mov eax,[rsp]
    imul rax,[rsp+4]
    shl rax,2
    add rax,40
    cmp rax,r14
    ja .bad
    push rsi
    mov rdi,rbx
    mov esi,[rsp+8]               ; width beneath pushed source
    mov edx,[rsp+12]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    pop rsi
    test rax,rax
    jz .bad
    mov rbx,rax
    lea r8,[rsi+40]
    mov r9,[rbx+PixBuf_data]
    xor r10d,r10d
.row:
    cmp r10d,[rsp+4]
    jae .done
    mov eax,[rsp+4]
    dec eax
    sub eax,r10d
    imul eax,[rsp]
    shl eax,2
    lea rsi,[r8+rax]
    mov rax,[rbx+PixBuf_stride]
    imul rax,r10
    lea rdi,[r9+rax]
    mov ecx,[rsp]
    shl rcx,2
    call memcopy
    inc r10d
    jmp .row
.done:
    mov rax,rbx
.return:
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    jmp .return

section .data
global ico_version
ico_version: dq 0x010000
