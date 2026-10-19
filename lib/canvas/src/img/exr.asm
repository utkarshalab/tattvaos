; OpenEXR scanline decoder: uncompressed UINT/HALF/FLOAT RGB(A) channels.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

section .text
global exr_decode
exr_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,128
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,32
    jb .bad
    cmp dword [r12],0x01312F76
    jne .bad
    lea r14,[r12+8]
    lea r15,[r12+r13]
    mov dword [rsp+16],-1         ; compression not yet seen
    mov dword [rsp+20],0          ; channel count
.attribute:
    cmp r14,r15
    jae .bad
    cmp byte [r14],0
    je .header_done
    mov r8,r14                    ; attribute name
.skip_name:
    cmp r14,r15
    jae .bad
    cmp byte [r14],0
    je .name_done
    inc r14
    jmp .skip_name
.name_done:
    inc r14
    mov r9,r14                    ; type name
.skip_type:
    cmp r14,r15
    jae .bad
    cmp byte [r14],0
    je .type_done
    inc r14
    jmp .skip_type
.type_done:
    inc r14
    lea rax,[r14+4]
    cmp rax,r15
    ja .bad
    mov r10d,[r14]
    add r14,4
    lea rax,[r14+r10]
    cmp rax,r15
    ja .bad
    cmp dword [r8],0x6E616863     ; "chan"
    jne .check_window
    cmp dword [r8+4],0x00736C65   ; "els\0"
    jne .check_window
    mov rdi,r14
    mov rcx,r10
    call .parse_channels
    test eax,eax
    jnz .bad
    jmp .attr_next
.check_window:
    cmp dword [r8],0x61746164     ; "dataWindow"
    jne .check_compression
    cmp dword [r8+4],0x646E6957
    jne .check_compression
    cmp r10d,16
    jne .bad
    mov eax,[r14]
    mov [rsp],eax                 ; xmin
    mov eax,[r14+4]
    mov [rsp+4],eax               ; ymin
    mov eax,[r14+8]
    sub eax,[rsp]
    inc eax
    mov [rsp+8],eax               ; width
    mov eax,[r14+12]
    sub eax,[rsp+4]
    inc eax
    mov [rsp+12],eax              ; height
    jmp .attr_next
.check_compression:
    cmp dword [r8],0x706D6F63     ; "comp"
    jne .attr_next
    cmp r10d,1
    jne .bad
    movzx eax,byte [r14]
    mov [rsp+16],eax
.attr_next:
    add r14,r10
    jmp .attribute
.header_done:
    inc r14
    cmp dword [rsp+16],0          ; NO_COMPRESSION
    jne .bad
    cmp dword [rsp+20],0
    je .bad
    cmp dword [rsp+8],0
    jle .bad
    cmp dword [rsp+12],0
    jle .bad
    mov eax,[rsp+12]
    shl rax,3
    add rax,r14
    cmp rax,r15
    ja .bad
    mov [rsp+24],r14              ; chunk offset table
    mov rdi,rbx
    mov esi,[rsp+8]
    mov edx,[rsp+12]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov [rsp+32],rax
    ; Initialize alpha and RGB deterministically.
    mov rdi,[rax+PixBuf_data]
    mov esi,0xFF000000
    mov edx,[rsp+8]
    mov ecx,[rsp+12]
    mov r8,[rax+PixBuf_stride]
    call fill_solid
    xor r11d,r11d
.chunk:
    cmp r11d,[rsp+12]
    jae .done
    mov rax,[rsp+24]
    mov rax,[rax+r11*8]
    lea rcx,[rax+8]
    cmp rcx,r13
    ja .bad
    lea rsi,[r12+rax]
    mov ecx,[rsi]                 ; file y
    sub ecx,[rsp+4]
    js .bad
    cmp ecx,[rsp+12]
    jae .bad
    mov edx,[rsi+4]
    lea rax,[rax+rdx+8]
    cmp rax,r13
    ja .bad
    add rsi,8
    mov [rsp+40],ecx              ; output row
    xor r10d,r10d                 ; channel index
.channel:
    cmp r10d,[rsp+20]
    jae .next_chunk
    lea r8,[rsp+48+r10*8]
    movzx eax,byte [r8]           ; output byte offset: B=0,G=1,R=2,A=3,255=skip
    mov [rsp+44],eax
    movzx r9d,byte [r8+1]         ; pixel type: UINT=0, HALF=1, FLOAT=2
    xor ecx,ecx
.sample:
    cmp ecx,[rsp+8]
    jae .next_channel
    cmp r9d,1
    je .half
    mov eax,[rsi]
    add rsi,4
    cmp r9d,2
    je .float
    shr eax,24                    ; UINT normalized from high byte
    jmp .write
.half:
    movzx eax,word [rsi]
    add rsi,2
    call .half_u8
    jmp .write
.float:
    movd xmm0,eax
    maxss xmm0,[rel fzero]
    minss xmm0,[rel fone]
    mulss xmm0,[rel f255]
    cvtss2si eax,xmm0
.write:
    cmp dword [rsp+44],255
    je .sample_next
    mov rdx,[rsp+32]
    mov rdi,[rdx+PixBuf_data]
    mov rdx,[rdx+PixBuf_stride]
    imul rdx,[rsp+40]
    add rdi,rdx
    mov edx,[rsp+44]
    mov [rdi+rcx*4+rdx],al
.sample_next:
    inc ecx
    jmp .sample
.next_channel:
    inc r10d
    jmp .channel
.next_chunk:
    inc r11d
    jmp .chunk
.done:
    mov rax,[rsp+32]
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; chlist at rdi, size rcx. Store {destination,type} pairs at rsp+48.
.parse_channels:
    push rbx
    mov rbx,rsp
    add rbx,16                    ; caller's local area after return/push
    xor r8d,r8d
.ch:
    test rcx,rcx
    jz .ch_ok
    cmp byte [rdi],0
    je .ch_ok
    mov al,[rdi]
    mov r9d,255
    cmp al,'B'
    jne .not_b
    xor r9d,r9d
.not_b:
    cmp al,'G'
    jne .not_g
    mov r9d,1
.not_g:
    cmp al,'R'
    jne .not_r
    mov r9d,2
.not_r:
    cmp al,'A'
    jne .name_end
    mov r9d,3
.name_end:
    inc rdi
    dec rcx
    jz .ch_bad
    cmp byte [rdi],0
    jne .name_end
    inc rdi
    dec rcx
    cmp rcx,16
    jb .ch_bad
    cmp r8d,4
    jae .ch_bad
    mov eax,[rdi]
    cmp eax,2
    ja .ch_bad
    mov [rbx+48+r8*8],r9b
    mov [rbx+49+r8*8],al
    inc r8d
    add rdi,16
    sub rcx,16
    jmp .ch
.ch_ok:
    mov [rbx+20],r8d
    xor eax,eax
    pop rbx
    ret
.ch_bad:
    mov eax,-1
    pop rbx
    ret

.half_u8:
    test ax,0x8000
    jnz .half_zero
    mov edx,eax
    shr edx,10
    and edx,31
    jz .half_zero
    cmp edx,15
    jae .half_max
    and eax,1023
    add eax,1024
    imul eax,255
    mov ecx,25
    sub ecx,edx
    shr eax,cl
    ret
.half_max:
    mov eax,255
    ret
.half_zero:
    xor eax,eax
    ret

section .rodata
align 4
fzero: dd 0.0
fone:  dd 1.0
f255:  dd 255.0
section .data
global exr_version
exr_version: dq 0x010000
