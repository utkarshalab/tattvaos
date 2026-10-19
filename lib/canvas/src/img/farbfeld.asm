; farbfeld decoder: big-endian 16-bit RGBA, lossless and unambiguous.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

section .text
global farbfeld_decode
farbfeld_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,16
    jb .bad
    cmp dword [r12],0x62617266     ; "farb"
    jne .bad
    cmp dword [r12+4],0x646C6566   ; "feld"
    jne .bad
    mov r14d,[r12+8]
    bswap r14d
    mov r15d,[r12+12]
    bswap r15d
    test r14d,r14d
    jz .bad
    test r15d,r15d
    jz .bad
    mov rax,r14
    imul rax,r15
    shl rax,3
    add rax,16
    cmp rax,r13
    ja .bad
    push r14
    push r15
    mov rdi,rbx
    mov rsi,r14
    mov rdx,r15
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    pop r15
    pop r14
    test rax,rax
    jz .bad
    mov rbx,rax
    mov rdi,[rbx+PixBuf_data]
    add r12,16
    imul r14,r15
.pixel:
    test r14,r14
    jz .done
    mov al,[r12+4]                 ; B high byte
    mov [rdi],al
    mov al,[r12+2]                 ; G high byte
    mov [rdi+1],al
    mov al,[r12]                   ; R high byte
    mov [rdi+2],al
    mov al,[r12+6]                 ; A high byte
    mov [rdi+3],al
    add r12,8
    add rdi,4
    dec r14
    jmp .pixel
.done:
    mov rax,rbx
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global farbfeld_version
farbfeld_version: dq 0x010000
