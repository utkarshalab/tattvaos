; Arithmetic inverse transforms for WebP lossless ARGB pixels.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; pixels,count -> 0 or -EINVAL.
global webp_inverse_subtract_green
webp_inverse_subtract_green:
    test rdi,rdi
    jz .green_bad
    xor rcx,rcx
.green_pixel:
    cmp rcx,rsi
    jae .green_done
    mov eax,[rdi+rcx*4]
    mov edx,eax
    shr edx,8
    and edx,0xff                       ; green
    mov r8d,eax
    shr r8d,16
    add r8d,edx
    and r8d,0xff                       ; restored red
    mov r9d,eax
    add r9d,edx
    and r9d,0xff                       ; restored blue
    and eax,0xff00ff00                 ; preserve alpha and green
    shl r8d,16
    or eax,r8d
    or eax,r9d
    mov [rdi+rcx*4],eax
    inc rcx
    jmp .green_pixel
.green_done:
    xor eax,eax
    ret
.green_bad:
    mov rax,-EINVAL
    ret

; palette,count -> 0/-EINVAL. Palette entries are byte-wise deltas.
global webp_palette_expand
webp_palette_expand:
    test rdi,rdi
    jz .palette_bad
    test rsi,rsi
    jz .palette_bad
    cmp rsi,256
    ja .palette_bad
    mov rcx,1
.palette_next:
    cmp rcx,rsi
    jae .palette_done
    mov eax,[rdi+rcx*4]
    mov edx,[rdi+rcx*4-4]
    add eax,edx
    mov r8d,[rdi+rcx*4]
    xor r8d,edx
    xor r8d,eax
    and r8d,0x01010100
    sub eax,r8d
    mov [rdi+rcx*4],eax
    inc rcx
    jmp .palette_next
.palette_done:
    xor eax,eax
    ret
.palette_bad:
    mov rax,-EINVAL
    ret
; pixels,width,height,transform_pixels,size_bits,transform_count -> 0/-EINVAL.
global webp_inverse_color
webp_inverse_color:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    test rbx,rbx
    jz .color_bad
    test r14,r14
    jz .color_bad
    test r12,r12
    jz .color_bad
    test r13,r13
    jz .color_bad
    cmp r15d,2
    jb .color_bad
    cmp r15d,9
    ja .color_bad
    mov rax,r12
    mov ecx,r15d
    mov rdx,1
    shl rdx,cl
    dec rdx
    add rax,rdx
    jc .color_bad
    shr rax,cl
    mov [rsp],eax                      ; transform width
    mov rax,r13
    add rax,rdx
    jc .color_bad
    shr rax,cl
    mov edx,[rsp]
    imul rax,rdx
    jo .color_bad
    cmp rax,r9
    ja .color_bad
    mov dword [rsp+4],0                ; y
.color_row:
    mov eax,[rsp+4]
    cmp rax,r13
    jae .color_done
    mov dword [rsp+8],0                ; x
.color_pixel:
    mov eax,[rsp+8]
    cmp rax,r12
    jae .color_next_row
    mov edx,[rsp+4]
    mov ecx,r15d
    shr edx,cl
    imul edx,[rsp]
    mov eax,[rsp+8]
    shr eax,cl
    add edx,eax
    mov eax,[r14+rdx*4]
    mov [rsp+12],eax                   ; transform element
    mov eax,[rsp+4]
    imul rax,r12
    add eax,[rsp+8]
    mov [rsp+16],eax                   ; pixel index
    mov eax,[rbx+rax*4]
    mov [rsp+20],eax                   ; source pixel
    mov edx,eax
    shr edx,8
    movsx edx,dl                       ; signed green
    mov eax,[rsp+12]
    movsx ecx,al                       ; green_to_red
    imul ecx,edx
    sar ecx,5
    mov eax,[rsp+20]
    shr eax,16
    add eax,ecx
    and eax,0xff
    mov [rsp+24],eax                   ; restored red
    mov eax,[rsp+12]
    shr eax,8
    movsx ecx,al                       ; green_to_blue
    imul ecx,edx
    sar ecx,5
    mov eax,[rsp+12]
    shr eax,16
    movsx eax,al                       ; red_to_blue
    mov edx,[rsp+24]
    movsx edx,dl
    imul eax,edx
    sar eax,5
    add ecx,eax
    mov eax,[rsp+20]
    and eax,0xff
    add eax,ecx
    and eax,0xff                       ; restored blue
    mov edx,[rsp+20]
    and edx,0xff00ff00                 ; alpha and green
    mov ecx,[rsp+24]
    shl ecx,16
    or edx,ecx
    or edx,eax
    mov eax,[rsp+16]
    mov [rbx+rax*4],edx
    inc dword [rsp+8]
    jmp .color_pixel
.color_next_row:
    inc dword [rsp+4]
    jmp .color_row
.color_done:
    xor eax,eax
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.color_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; WebPIndexState* -> 0 or -EINVAL.
global webp_inverse_color_index
webp_inverse_color_index:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    test rbx,rbx
    jz .index_bad
    mov r12,[rbx+WebPIndexState.packed]
    mov r13,[rbx+WebPIndexState.output]
    mov r14,[rbx+WebPIndexState.palette]
    test r12,r12
    jz .index_bad
    test r13,r13
    jz .index_bad
    test r14,r14
    jz .index_bad
    mov r15d,[rbx+WebPIndexState.width_bits]
    cmp r15d,3
    ja .index_bad
    cmp dword [rbx+WebPIndexState.width],0
    je .index_bad
    cmp dword [rbx+WebPIndexState.height],0
    je .index_bad
    cmp dword [rbx+WebPIndexState.palette_count],0
    je .index_bad
    cmp dword [rbx+WebPIndexState.palette_count],256
    ja .index_bad
    mov eax,1
    mov ecx,r15d
    shl eax,cl
    mov edx,[rbx+WebPIndexState.width]
    add edx,eax
    dec edx
    shr edx,cl
    cmp edx,[rbx+WebPIndexState.packed_width]
    ja .index_bad
    mov dword [rsp],0                  ; y
.index_row:
    mov eax,[rsp]
    cmp eax,[rbx+WebPIndexState.height]
    jae .index_done
    mov dword [rsp+4],0                ; x
.index_pixel:
    mov eax,[rsp+4]
    cmp eax,[rbx+WebPIndexState.width]
    jae .index_next_row
    mov edx,eax
    mov ecx,r15d
    shr edx,cl
    mov eax,[rsp]
    imul eax,[rbx+WebPIndexState.packed_width]
    add eax,edx
    mov eax,[r12+rax*4]
    shr eax,8
    and eax,0xff                       ; packed green indices
    mov r8d,eax
    mov ecx,r15d
    mov edx,8
    shr edx,cl
    mov [rsp+8],edx                    ; bits per index
    mov eax,1
    shl eax,cl
    dec eax                            ; packed-lane mask
    mov ecx,[rsp+4]
    and ecx,eax
    imul ecx,[rsp+8]
    mov eax,r8d
    shr eax,cl
    mov ecx,[rsp+8]
    mov edx,1
    shl edx,cl
    dec edx
    and eax,edx
    cmp eax,[rbx+WebPIndexState.palette_count]
    jae .index_transparent
    mov eax,[r14+rax*4]
    jmp .index_store
.index_transparent:
    xor eax,eax
.index_store:
    mov edx,[rsp]
    imul edx,[rbx+WebPIndexState.width]
    add edx,[rsp+4]
    mov [r13+rdx*4],eax
    inc dword [rsp+4]
    jmp .index_pixel
.index_next_row:
    inc dword [rsp]
    jmp .index_row
.index_done:
    xor eax,eax
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.index_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global webp_transform_version
webp_transform_version: dq 0x010000
