; Adobe PSD composite-image decoder: 8-bit Gray/RGB(A), raw and PackBits RLE.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

section .text
global psd_decode
psd_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,80
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,30
    jb .bad
    cmp dword [r12],0x53504238    ; "8BPS"
    jne .bad
    cmp word [r12+4],0x0100       ; version 1, big endian
    jne .bad
    movzx eax,word [r12+12]
    xchg al,ah
    mov [rsp+8],eax               ; channels
    cmp eax,1
    jb .bad
    cmp eax,4
    ja .bad
    mov eax,[r12+14]
    bswap eax
    mov [rsp+4],eax               ; height
    mov eax,[r12+18]
    bswap eax
    mov [rsp],eax                 ; width
    cmp word [r12+22],0x0800      ; depth 8
    jne .bad
    movzx eax,word [r12+24]
    xchg al,ah
    mov [rsp+12],eax              ; color mode
    cmp eax,1                     ; grayscale
    je .mode_ok
    cmp eax,3                     ; RGB
    jne .bad
.mode_ok:
    test dword [rsp],-1
    jz .bad
    test dword [rsp+4],-1
    jz .bad
    lea r14,[r12+26]
    ; Skip color mode data, image resources, layer/mask sections.
    mov ecx,3
.skip_section:
    mov rax,r14
    sub rax,r12
    add rax,4
    cmp rax,r13
    ja .bad
    mov eax,[r14]
    bswap eax
    add r14,4
    add r14,rax
    mov rax,r14
    sub rax,r12
    cmp rax,r13
    ja .bad
    dec ecx
    jnz .skip_section
    mov rax,r14
    sub rax,r12
    add rax,2
    cmp rax,r13
    ja .bad
    movzx eax,word [r14]
    xchg al,ah
    mov [rsp+16],eax              ; compression
    add r14,2
    cmp eax,1
    ja .bad
    mov rax,[rsp]
    imul rax,[rsp+4]
    mov [rsp+24],rax              ; pixels/channel
    imul rax,[rsp+8]
    mov rdi,rbx
    mov rsi,rax
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+32],rax              ; planar bytes
    cmp dword [rsp+16],0
    jne .rle
    mov rdx,[rsp+24]
    imul rdx,[rsp+8]
    mov rax,r14
    sub rax,r12
    add rax,rdx
    cmp rax,r13
    ja .bad
    mov rdi,[rsp+32]
    mov rsi,r14
    mov rcx,rdx
    call memcopy
    jmp .compose
.rle:
    mov eax,[rsp+4]
    imul eax,[rsp+8]
    mov [rsp+40],eax              ; row count
    mov r15,r14                   ; row byte-count table
    lea r14,[r14+rax*2]
    mov rax,r14
    sub rax,r12
    cmp rax,r13
    ja .bad
    xor r10d,r10d
    mov rdi,[rsp+32]
.rle_row:
    cmp r10d,[rsp+40]
    jae .compose
    movzx eax,word [r15+r10*2]
    xchg al,ah
    mov [rsp+48],eax
    xor r11d,r11d
.packet:
    cmp r11d,[rsp]
    jae .row_done
    cmp dword [rsp+48],0
    jle .bad
    movsx eax,byte [r14]
    inc r14
    dec dword [rsp+48]
    cmp eax,-128
    je .packet
    test eax,eax
    js .repeat
    inc eax
    cmp eax,[rsp+48]
    ja .bad
.literal:
    test eax,eax
    jz .packet
    cmp r11d,[rsp]
    jae .bad
    mov dl,[r14]
    mov [rdi+r11],dl
    inc r14
    dec dword [rsp+48]
    inc r11d
    dec eax
    jmp .literal
.repeat:
    neg eax
    inc eax
    cmp dword [rsp+48],1
    jb .bad
    mov dl,[r14]
    inc r14
    dec dword [rsp+48]
.repeat_loop:
    test eax,eax
    jz .packet
    cmp r11d,[rsp]
    jae .bad
    mov [rdi+r11],dl
    inc r11d
    dec eax
    jmp .repeat_loop
.row_done:
    add rdi,[rsp]
    inc r10d
    jmp .rle_row
.compose:
    mov rdi,rbx
    mov esi,[rsp]
    mov edx,[rsp+4]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov rbx,rax
    mov rdi,[rbx+PixBuf_data]
    mov rsi,[rsp+32]
    xor r10,r10
.pixel:
    cmp r10,[rsp+24]
    jae .done
    cmp dword [rsp+12],1
    jne .rgb
    mov al,[rsi+r10]
    mov [rdi],al
    mov [rdi+1],al
    mov [rdi+2],al
    mov byte [rdi+3],255
    jmp .pixel_next
.rgb:
    mov rdx,[rsp+24]
    mov al,[rsi+r10]
    mov [rdi+2],al
    mov al,[rsi+rdx+r10]
    mov [rdi+1],al
    lea rcx,[rdx+rdx]
    mov al,[rsi+rcx+r10]
    mov [rdi],al
    mov byte [rdi+3],255
    cmp dword [rsp+8],4
    jb .pixel_next
    add rcx,rdx
    mov al,[rsi+rcx+r10]
    mov [rdi+3],al
.pixel_next:
    add rdi,4
    inc r10
    jmp .pixel
.done:
    mov rax,rbx
    add rsp,80
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,80
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global psd_version
psd_version: dq 0x010000
