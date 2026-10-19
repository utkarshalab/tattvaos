; Netpbm P4/P5/P6 decoder (binary bitmap/grayscale/RGB).
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; IN rdi=arena, rsi=data, rdx=len. OUT rax=PixBuf* or 0.
global pnm_decode
pnm_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,8
    jb .bad
    cmp byte [r12],'P'
    jne .bad
    movzx r15d,byte [r12+1]
    cmp r15d,'5'
    je .header
    cmp r15d,'4'
    je .header
    cmp r15d,'6'
    jne .bad
.header:
    lea r14,[r12+2]
    sub r13,2
    call .next_uint
    test rdx,rdx
    jz .bad
    mov r10,rax                 ; width
    call .next_uint
    test rdx,rdx
    jz .bad
    mov r11,rax                 ; height
    cmp r15d,'4'
    je .separator
    call .next_uint
    cmp rax,255
    jne .bad
.separator:
    test r13,r13
    jz .bad
    cmp byte [r14],13
    jne .one_sep
    inc r14
    dec r13
.one_sep:
    cmp byte [r14],10
    je .consume_sep
    cmp byte [r14],' '
    jne .bad
.consume_sep:
    inc r14
    dec r13
    mov rax,r10
    imul rax,r11
    mov rcx,rax
    cmp r15d,'4'
    jne .not_bitmap_size
    mov rcx,r10
    add rcx,7
    shr rcx,3
    imul rcx,r11
    jmp .size_ready
.not_bitmap_size:
    cmp r15d,'6'
    jne .size_ready
    lea rcx,[rax+rax*2]
.size_ready:
    cmp r13,rcx
    jb .bad
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
    imul r10,r11
.pixels:
    test r10,r10
    jz .done
    cmp r15d,'5'
    je .gray
    cmp r15d,'4'
    je .bitmap
    jmp .rgb
.gray:
    mov al,[r14]
    mov [rdi],al
    mov [rdi+1],al
    mov [rdi+2],al
    inc r14
    jmp .alpha
.bitmap:
    mov rax,[rbx+PixBuf_width]
    imul rax,[rbx+PixBuf_height]
    sub rax,r10                    ; linear output index
    xor edx,edx
    div qword [rbx+PixBuf_width]   ; rax=row, rdx=column
    mov rcx,[rbx+PixBuf_width]
    add rcx,7
    shr rcx,3
    imul rax,rcx
    mov rcx,rdx
    shr rcx,3
    add rax,rcx
    mov cl,dl
    and ecx,7
    mov al,[r14+rax]
    mov ecx,7
    and edx,7
    sub ecx,edx
    shr al,cl
    and eax,1
    dec eax                       ; PBM 1=black, 0=white
    mov [rdi],al
    mov [rdi+1],al
    mov [rdi+2],al
    jmp .alpha
.rgb:
    mov al,[r14+2]
    mov [rdi],al
    mov al,[r14+1]
    mov [rdi+1],al
    mov al,[r14]
    mov [rdi+2],al
    add r14,3
.alpha:
    mov byte [rdi+3],255
    add rdi,4
    dec r10
    jmp .pixels
.done:
    mov rax,rbx
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; cursor r14, remaining r13; returns value rax and digit count rdx.
.next_uint:
.skip:
    test r13,r13
    jz .uint_bad
    cmp byte [r14],'#'
    jne .space
.comment:
    inc r14
    dec r13
    jz .uint_bad
    cmp byte [r14],10
    jne .comment
.space:
    cmp byte [r14],' '
    je .skip_one
    cmp byte [r14],9
    je .skip_one
    cmp byte [r14],10
    je .skip_one
    cmp byte [r14],13
    jne .digits
.skip_one:
    inc r14
    dec r13
    jmp .skip
.digits:
    xor eax,eax
    xor edx,edx
.digit:
    test r13,r13
    jz .uint_done
    movzx ecx,byte [r14]
    sub ecx,'0'
    cmp ecx,9
    ja .uint_done
    imul rax,10
    add rax,rcx
    inc r14
    dec r13
    inc rdx
    jmp .digit
.uint_done:
    ret
.uint_bad:
    xor eax,eax
    xor edx,edx
    ret

section .data
global pnm_version
pnm_version: dq 0x010000
