; Native texture containers: DDS, KTX 1, and KTX 2 uncompressed 32-bit paths.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

extern pixbuf_create
extern bc_decode

section .text

; Common copier. IN arena, pixels, len, width, height, source_is_rgba.
texture_copy_32:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    mov r10,r9
    mov rax,r14
    imul rax,r15
    shl rax,2
    cmp rax,r13
    ja .bad
    push r10
    mov rdi,rbx
    mov rsi,r14
    mov rdx,r15
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    pop r10
    test rax,rax
    jz .bad
    mov rbx,rax
    mov rdi,[rbx+PixBuf_data]
    imul r14,r15
.pixel:
    test r14,r14
    jz .done
    mov eax,[r12]
    test r10,r10
    jz .store
    mov edx,eax
    and eax,0xFF00FF00
    mov ecx,edx
    and ecx,0x000000FF
    shl ecx,16
    or eax,ecx
    and edx,0x00FF0000
    shr edx,16
    or eax,edx
.store:
    mov [rdi],eax
    add r12,4
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

global dds_decode
dds_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,128
    jb .bad
    cmp dword [r12],0x20534444
    jne .bad
    cmp dword [r12+4],124
    jne .bad
    cmp dword [r12+76],32
    jne .bad
    test dword [r12+80],0x4       ; DDPF_FOURCC
    jz .dds_rgb
    mov eax,[r12+84]
    mov r9d,1
    cmp eax,0x31545844            ; DXT1
    je .dds_bc
    mov r9d,2
    cmp eax,0x33545844            ; DXT3
    je .dds_bc
    mov r9d,3
    cmp eax,0x35545844            ; DXT5
    jne .bad
.dds_bc:
    mov rdi,rbx
    lea rsi,[r12+128]
    lea rdx,[r13-128]
    mov ecx,[r12+16]
    mov r8d,[r12+12]
    call bc_decode
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.dds_rgb:
    test dword [r12+80],0x40      ; DDPF_RGB
    jz .bad
    cmp dword [r12+88],32
    jne .bad
    xor r9d,r9d                   ; BGRA masks are Canvas-native
    cmp dword [r12+92],0x00FF0000
    je .copy
    cmp dword [r12+92],0x000000FF
    jne .bad
    mov r9d,1                     ; RGBA byte order
.copy:
    mov ecx,[r12+16]
    mov r8d,[r12+12]
    lea rsi,[r12+128]
    lea rdx,[r13-128]
    mov rdi,rbx
    call texture_copy_32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

global ktx_decode
ktx_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,68
    jb .bad
    cmp dword [r12],0x58544BAB
    jne .bad
    cmp dword [r12+4],0xBB313120
    jne .bad
    cmp dword [r12+8],0x0A1A0A0D
    jne .bad
    cmp dword [r12+12],0x04030201
    jne .bad
    mov eax,[r12+28]
    mov r9d,1
    cmp eax,0x83F1                ; DXT1 RGBA
    je .ktx_bc
    mov r9d,2
    cmp eax,0x83F2                ; DXT3
    je .ktx_bc
    mov r9d,3
    cmp eax,0x83F3                ; DXT5
    je .ktx_bc
    cmp dword [r12+16],0x1401     ; GL_UNSIGNED_BYTE
    jne .bad
    mov eax,[r12+24]
    xor r9d,r9d
    cmp eax,0x80E1                ; GL_BGRA
    je .layout
    cmp eax,0x1908                ; GL_RGBA
    jne .bad
    mov r9d,1
.layout:
    mov eax,[r12+60]
    add eax,64
    add eax,3
    and eax,-4
    add eax,4                     ; skip imageSize
    cmp rax,r13
    jae .bad
    lea rsi,[r12+rax]
    mov rdx,r13
    sub rdx,rax
    mov ecx,[r12+36]
    mov r8d,[r12+40]
    mov rdi,rbx
    call texture_copy_32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.ktx_bc:
    mov eax,[r12+60]
    add eax,64
    add eax,3
    and eax,-4
    mov edx,[r12+rax]
    add eax,4
    cmp rax,r13
    jae .bad
    lea rsi,[r12+rax]
    mov ecx,[r12+36]
    mov r8d,[r12+40]
    mov rdi,rbx
    call bc_decode
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

global ktx2_decode
ktx2_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,104
    jb .bad
    cmp dword [r12],0x58544BAB
    jne .bad
    cmp dword [r12+4],0xBB323020
    jne .bad
    cmp dword [r12+8],0x0A1A0A0D
    jne .bad
    cmp dword [r12+44],0          ; no supercompression
    jne .bad
    mov eax,[r12+12]
    xor r9d,r9d
    cmp eax,44                    ; VK_FORMAT_B8G8R8A8_UNORM
    je .level
    cmp eax,37                    ; VK_FORMAT_R8G8B8A8_UNORM
    je .rgba2
    mov r9d,1
    cmp eax,131                   ; BC1 RGB UNORM
    je .ktx2_bc
    cmp eax,133                   ; BC1 RGBA UNORM
    je .ktx2_bc
    mov r9d,2
    cmp eax,135                   ; BC2 UNORM
    je .ktx2_bc
    mov r9d,3
    cmp eax,137                   ; BC3 UNORM
    jne .bad
.ktx2_bc:
    mov rax,[r12+80]
    mov rdx,[r12+88]
    mov rcx,rax
    add rcx,rdx
    cmp rcx,r13
    ja .bad
    lea rsi,[r12+rax]
    mov ecx,[r12+20]
    mov r8d,[r12+24]
    mov rdi,rbx
    call bc_decode
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.rgba2:
    mov r9d,1
.level:
    mov rax,[r12+80]              ; first level byteOffset
    mov rdx,[r12+88]              ; byteLength
    mov rcx,rax
    add rcx,rdx
    cmp rcx,r13
    ja .bad
    lea rsi,[r12+rax]
    mov ecx,[r12+20]
    mov r8d,[r12+24]
    mov rdi,rbx
    call texture_copy_32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global texture_version
texture_version: dq 0x010000
