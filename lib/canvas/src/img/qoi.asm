; Quite OK Image decoder (QOI specification v1.0).
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text
global qoi_decode
qoi_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,22
    jb .bad
    cmp dword [r12],0x66696F71
    jne .bad
    mov eax,[r12+4]
    bswap eax
    mov r10d,eax
    mov eax,[r12+8]
    bswap eax
    mov r11d,eax
    test r10d,r10d
    jz .bad
    test r11d,r11d
    jz .bad
    cmp byte [r12+12],3
    je .header_ok
    cmp byte [r12+12],4
    jne .bad
.header_ok:
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
    mov r14,[rbx+PixBuf_data]
    mov r15,r10
    imul r15,r11
    add r12,14
    sub r13,14
    sub rsp,272
    mov rdi,rsp
    xor eax,eax
    mov ecx,32
    rep stosq                       ; 64-entry RGBA index
    mov dword [rsp+256],0xFF000000 ; r,g,b,a byte order in memory
    xor r11d,r11d                  ; run remaining
.pixel:
    test r15,r15
    jz .done
    test r11d,r11d
    jnz .emit_run
    test r13,r13
    jz .decode_bad
    movzx eax,byte [r12]
    inc r12
    dec r13
    cmp al,0xFE
    je .rgb
    cmp al,0xFF
    je .rgba
    mov edx,eax
    and edx,0xC0
    jz .index
    cmp edx,0x40
    je .diff
    cmp edx,0x80
    je .luma
    and eax,0x3F
    mov r11d,eax
    jmp .update_index
.index:
    and eax,0x3F
    mov eax,[rsp+rax*4]
    mov [rsp+256],eax
    jmp .emit
.diff:
    mov edx,eax
    shr edx,4
    and edx,3
    sub edx,2
    add [rsp+256],dl
    mov edx,eax
    shr edx,2
    and edx,3
    sub edx,2
    add [rsp+257],dl
    and eax,3
    sub eax,2
    add [rsp+258],al
    jmp .update_index
.luma:
    cmp r13,1
    jb .decode_bad
    and eax,0x3F
    sub eax,32                    ; dg
    movzx edx,byte [r12]
    inc r12
    dec r13
    mov ecx,edx
    shr ecx,4
    and ecx,15
    sub ecx,8
    add ecx,eax
    add [rsp+256],cl
    add [rsp+257],al
    and edx,15
    sub edx,8
    add edx,eax
    add [rsp+258],dl
    jmp .update_index
.rgb:
    cmp r13,3
    jb .decode_bad
    mov ax,[r12]
    mov [rsp+256],ax
    mov al,[r12+2]
    mov [rsp+258],al
    add r12,3
    sub r13,3
    jmp .update_index
.rgba:
    cmp r13,4
    jb .decode_bad
    mov eax,[r12]
    mov [rsp+256],eax
    add r12,4
    sub r13,4
.update_index:
    movzx eax,byte [rsp+256]
    lea eax,[rax+rax*2]
    movzx edx,byte [rsp+257]
    lea edx,[rdx+rdx*4]
    add eax,edx
    movzx edx,byte [rsp+258]
    imul edx,7
    add eax,edx
    movzx edx,byte [rsp+259]
    imul edx,11
    add eax,edx
    and eax,63
    mov edx,[rsp+256]
    mov [rsp+rax*4],edx
    jmp .emit
.emit_run:
    dec r11d
.emit:
    mov al,[rsp+258]
    mov [r14],al
    mov al,[rsp+257]
    mov [r14+1],al
    mov al,[rsp+256]
    mov [r14+2],al
    mov al,[rsp+259]
    mov [r14+3],al
    add r14,4
    dec r15
    jmp .pixel
.done:
    add rsp,272
    mov rax,rbx
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.decode_bad:
    add rsp,272
.bad:
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global qoi_version
qoi_version: dq 0x010000
