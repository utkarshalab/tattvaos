; Truevision TGA decoder: grayscale/true-color, raw or RLE, 24/32-bit.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text
global tga_decode
tga_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,18
    jb .bad
    cmp byte [r12+1],0
    jne .bad                      ; color maps intentionally rejected
    movzx r14d,byte [r12+2]
    cmp r14d,2
    je .type_ok
    cmp r14d,3
    je .type_ok
    cmp r14d,10
    je .type_ok
    cmp r14d,11
    jne .bad
.type_ok:
    movzx r10d,word [r12+12]
    movzx r11d,word [r12+14]
    test r10d,r10d
    jz .bad
    test r11d,r11d
    jz .bad
    movzx r15d,byte [r12+16]
    cmp r14d,3
    je .gray_depth
    cmp r14d,11
    je .gray_depth
    cmp r15d,24
    je .depth_ok
    cmp r15d,32
    jne .bad
    jmp .depth_ok
.gray_depth:
    cmp r15d,8
    jne .bad
.depth_ok:
    movzx eax,byte [r12]
    add eax,18
    cmp rax,r13
    ja .bad
    add r12,rax
    sub r13,rax
    push r10
    push r11
    mov rdi,rbx
    mov rsi,r10
    mov rdx,r11
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    pop r11
    pop r10
    test rax,rax
    jz .bad
    mov rbx,rax
    mov rdi,[rbx+PixBuf_data]
    mov r8,r10
    imul r8,r11                    ; pixels remaining
    xor r9d,r9d                    ; packet remaining
    xor ecx,ecx                    ; packet is RLE
.pixel:
    test r8,r8
    jz .done
    test r9,r9
    jnz .packet_active
    cmp r14d,10
    je .packet_header
    cmp r14d,11
    jne .raw_packet
.packet_header:
    test r13,r13
    jz .bad
    movzx eax,byte [r12]
    inc r12
    dec r13
    mov ecx,eax
    and ecx,0x80
    and eax,0x7F
    inc eax
    mov r9,rax
    jmp .load_if_needed
.raw_packet:
    mov r9,1
    xor ecx,ecx
.load_if_needed:
    test ecx,ecx
    jz .read_sample
    cmp r9,rax                     ; first pixel of RLE packet
    jne .packet_active
.read_sample:
    mov eax,r15d
    shr eax,3
    cmp r13,rax
    jb .bad
    cmp r15d,8
    jne .color
    mov al,[r12]
    movzx r10d,al
    imul r10d,0x00010101
    or r10d,0xFF000000
    jmp .sample_ready
.color:
    mov eax,[r12]
    cmp r15d,24
    jne .sample_ready
    or eax,0xFF000000
.sample_ready:
    mov r10d,eax
    mov eax,r15d
    shr eax,3
    add r12,rax
    sub r13,rax
.packet_active:
    mov eax,r10d
    mov [rdi],eax
    add rdi,4
    dec r8
    dec r9
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
global tga_version
tga_version: dq 0x010000
