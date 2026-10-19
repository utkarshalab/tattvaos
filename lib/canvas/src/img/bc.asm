; BC1/BC2/BC3 (DXT1/DXT3/DXT5) block decompressor.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

section .text
; IN arena,data,len,width,height,format(1..3). OUT PixBuf*.
global bc_decode
bc_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,128
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov [rsp],ecx                 ; width
    mov [rsp+4],r8d              ; height
    mov [rsp+8],r9d              ; format
    cmp r9d,1
    jb .bad
    cmp r9d,3
    ja .bad
    mov eax,[rsp]
    add eax,3
    shr eax,2
    mov [rsp+12],eax             ; block columns
    mov eax,[rsp+4]
    add eax,3
    shr eax,2
    mov [rsp+16],eax             ; block rows
    mov ecx,8
    cmp dword [rsp+8],1
    je .block_size
    mov ecx,16
.block_size:
    mov eax,[rsp+12]
    imul eax,[rsp+16]
    imul eax,ecx
    cmp rax,r13
    ja .bad
    mov rdi,rbx
    mov esi,[rsp]
    mov edx,[rsp+4]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov [rsp+24],rax
    mov dword [rsp+20],0          ; block y
.block_row:
    mov eax,[rsp+20]
    cmp eax,[rsp+16]
    jae .done
    mov dword [rsp+28],0          ; block x
.block_col:
    mov eax,[rsp+28]
    cmp eax,[rsp+12]
    jae .next_block_row
    mov r14,r12                   ; block pointer
    cmp dword [rsp+8],1
    je .color_block
    add r14,8
.color_block:
    movzx eax,word [r14]
    call .rgb565
    mov [rsp+32],eax
    movzx eax,word [r14+2]
    call .rgb565
    mov [rsp+36],eax
    mov eax,[rsp+32]
    mov edx,[rsp+36]
    mov ecx,[rsp+8]
    cmp ecx,1
    jne .four_color
    movzx ecx,word [r14]
    cmp cx,[r14+2]
    jbe .three_color
.four_color:
    call .mix_four
    jmp .indices
.three_color:
    mov ecx,eax
    and ecx,0x00FEFEFE
    mov edi,edx
    and edi,0x00FEFEFE
    add ecx,edi
    shr ecx,1
    or ecx,0xFF000000
    mov [rsp+40],ecx
    mov dword [rsp+44],0
.indices:
    mov r15d,[r14+4]
    xor r10d,r10d                ; pixel 0..15
.pixel:
    cmp r10d,16
    jae .advance_block
    mov ecx,r10d
    shl ecx,1
    mov eax,r15d
    shr eax,cl
    and eax,3
    mov eax,[rsp+32+rax*4]
    cmp dword [rsp+8],2
    je .alpha_bc2
    cmp dword [rsp+8],3
    je .alpha_bc3
    jmp .write
.alpha_bc2:
    mov ecx,r10d
    shl ecx,2
    mov rdx,[r12]
    shr rdx,cl
    and edx,15
    imul edx,17
    and eax,0x00FFFFFF
    shl edx,24
    or eax,edx
    jmp .write
.alpha_bc3:
    movzx edx,byte [r12]
    movzx edi,byte [r12+1]
    mov rcx,[r12]
    shr rcx,16
    mov r8d,r10d
    imul r8d,3
    mov cl,r8b
    mov r8,[r12]
    shr r8,16
    shr r8,cl
    and r8d,7
    cmp r8d,0
    je .alpha_have
    cmp r8d,1
    je .alpha_one
    cmp edx,edi
    jbe .alpha_six
    mov ecx,8
    sub ecx,r8d
    imul ecx,edx
    mov r9d,r8d
    dec r9d
    imul r9d,edi
    add ecx,r9d
    mov edx,ecx
    mov ecx,7
    mov eax,edx
    xor edx,edx
    div ecx
    mov edx,eax
    jmp .alpha_have
.alpha_six:
    cmp r8d,6
    je .alpha_zero
    cmp r8d,7
    je .alpha_max
    mov ecx,6
    sub ecx,r8d
    imul ecx,edx
    mov r9d,r8d
    dec r9d
    imul r9d,edi
    add ecx,r9d
    mov eax,ecx
    xor edx,edx
    mov ecx,5
    div ecx
    mov edx,eax
    jmp .alpha_have
.alpha_one:
    mov edx,edi
    jmp .alpha_have
.alpha_zero:
    xor edx,edx
    jmp .alpha_have
.alpha_max:
    mov edx,255
.alpha_have:
    mov eax,[rsp+32]
    mov ecx,r10d
    shl ecx,1
    mov r9d,r15d
    shr r9d,cl
    and r9d,3
    mov eax,[rsp+32+r9*4]
    and eax,0x00FFFFFF
    shl edx,24
    or eax,edx
.write:
    mov edx,r10d
    and edx,3                    ; local x
    mov ecx,r10d
    shr ecx,2                    ; local y
    mov edi,[rsp+28]
    shl edi,2
    add edi,edx
    cmp edi,[rsp]
    jae .pixel_next
    mov edx,[rsp+20]
    shl edx,2
    add edx,ecx
    cmp edx,[rsp+4]
    jae .pixel_next
    mov r8,[rsp+24]
    mov r9,[r8+PixBuf_data]
    mov rcx,[r8+PixBuf_stride]
    imul rcx,rdx
    add r9,rcx
    mov [r9+rdi*4],eax
.pixel_next:
    inc r10d
    jmp .pixel
.advance_block:
    mov eax,8
    cmp dword [rsp+8],1
    je .advance_size
    mov eax,16
.advance_size:
    add r12,rax
    inc dword [rsp+28]
    jmp .block_col
.next_block_row:
    inc dword [rsp+20]
    jmp .block_row
.done:
    mov rax,[rsp+24]
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

.rgb565:
    mov edx,eax
    and edx,31
    shl edx,3
    mov ecx,eax
    shr ecx,5
    and ecx,63
    shl ecx,10
    or edx,ecx
    shr eax,11
    shl eax,19
    or eax,edx
    or eax,0xFF000000
    ret
.mix_four:
    ; Per-channel interpolation using packed-byte-safe masked arithmetic.
    mov r10d,eax
    mov r11d,edx
    xor r8d,r8d
    xor r9d,r9d
    xor ecx,ecx
.mix_byte:
    mov eax,r10d
    shr eax,cl
    and eax,255
    mov edi,r11d
    shr edi,cl
    and edi,255
    lea edx,[rax+rax]
    add edx,edi
    push rcx
    mov eax,edx
    xor edx,edx
    mov ecx,3
    div ecx
    pop rcx
    shl eax,cl
    or r8d,eax
    mov eax,r10d
    shr eax,cl
    and eax,255
    mov edi,r11d
    shr edi,cl
    and edi,255
    lea edx,[rdi+rdi]
    add edx,eax
    push rcx
    mov eax,edx
    xor edx,edx
    mov ecx,3
    div ecx
    pop rcx
    shl eax,cl
    or r9d,eax
    add ecx,8
    cmp ecx,24
    jbe .mix_byte
    or r8d,0xFF000000
    or r9d,0xFF000000
    mov [rsp+48],r8d
    mov [rsp+52],r9d
    ret

section .data
global bc_version
bc_version: dq 0x010000
