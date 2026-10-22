; Radiance RGBE decoder: flat and modern per-channel scanline RLE.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/image.inc"

extern pixbuf_create
extern arena_alloc
extern memcopy

section .text
global hdr_decode
hdr_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,48
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    cmp r13,10
    jb .bad
    cmp dword [r12],0x41523F23    ; "#?RA"
    jne .check_rgbe
    cmp dword [r12+4],0x4E414944 ; "DIAN"
    jne .bad
    jmp .header
.check_rgbe:
    cmp dword [r12],0x47523F23    ; "#?RG"
    jne .bad
.header:
    ; Locate the blank line ending metadata.
    xor r14d,r14d
.find_blank:
    lea rax,[r14+2]
    cmp rax,r13
    jae .bad
    cmp word [r12+r14],0x0A0A
    je .resolution
    inc r14
    jmp .find_blank
.resolution:
    add r14,2
    ; Standard orientation: -Y <height> +X <width>.
    lea rsi,[r12+r14]
    mov rdx,r13
    sub rdx,r14
    cmp rdx,8
    jb .bad
    cmp word [rsi],0x592D         ; "-Y"
    jne .bad
    add rsi,2
    sub rdx,2
    call .uint
    test rcx,rcx
    jz .bad
    mov [rsp+4],eax
    add rsi,rcx
    sub rdx,rcx
.seek_x:
    test rdx,rdx
    jz .bad
    cmp word [rsi],0x582B         ; "+X"
    je .have_x
    inc rsi
    dec rdx
    jmp .seek_x
.have_x:
    add rsi,2
    sub rdx,2
    call .uint
    test rcx,rcx
    jz .bad
    mov [rsp],eax
.skip_line:
    test rdx,rdx
    jz .bad
    cmp byte [rsi+rcx],10
    je .payload
    inc rcx
    jmp .skip_line
.payload:
    lea r12,[rsi+rcx+1]
    mov rax,r12
    sub rax,rbx                  ; not based on file; recompute below
    ; Allocate one planar scanline scratch buffer.
    mov eax,[rsp]
    shl eax,2
    mov rdi,rbx
    mov rsi,rax
    call arena_alloc
    test rax,rax
    jz .bad
    mov [rsp+8],rax
    mov rdi,rbx
    mov esi,[rsp]
    mov edx,[rsp+4]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov [rsp+16],rax
    xor r14d,r14d
.row:
    cmp r14d,[rsp+4]
    jae .done
    cmp r13,4
    jb .bad
    cmp byte [r12],2
    jne .flat_row
    cmp byte [r12+1],2
    jne .flat_row
    movzx eax,word [r12+2]
    xchg al,ah
    cmp eax,[rsp]
    jne .bad
    add r12,4
    sub r13,4
    xor r15d,r15d               ; channel
.channel:
    cmp r15d,4
    jae .convert
    xor r10d,r10d
.packet:
    cmp r10d,[rsp]
    jae .next_channel
    cmp r13,2
    jb .bad
    movzx eax,byte [r12]
    inc r12
    dec r13
    cmp eax,128
    jbe .literal
    sub eax,128
    movzx edx,byte [r12]
    inc r12
    dec r13
.run:
    test eax,eax
    jz .packet
    cmp r10d,[rsp]
    jae .bad
    mov rcx,[rsp+8]
    lea rcx,[rcx+r10*4]
    mov [rcx+r15],dl
    inc r10d
    dec eax
    jmp .run
.literal:
    test eax,eax
    jz .bad
    cmp rax,r13
    ja .bad
.lit_loop:
    test eax,eax
    jz .packet
    mov dl,[r12]
    inc r12
    dec r13
    mov rcx,[rsp+8]
    lea rcx,[rcx+r10*4]
    mov [rcx+r15],dl
    inc r10d
    dec eax
    jmp .lit_loop
.next_channel:
    inc r15d
    jmp .channel
.flat_row:
    mov eax,[rsp]
    shl rax,2
    cmp rax,r13
    ja .bad
    mov rdi,[rsp+8]
    mov rsi,r12
    mov rcx,rax
    call memcopy
    add r12,rax
    sub r13,rax
.convert:
    mov rax,[rsp+16]
    mov rdi,[rax+PixBuf_data]
    mov rax,[rax+PixBuf_stride]
    imul rax,r14
    add rdi,rax
    mov rsi,[rsp+8]
    xor r10d,r10d
.pixel:
    cmp r10d,[rsp]
    jae .next_row
    movzx ecx,byte [rsi+r10*4+3]
    movzx eax,byte [rsi+r10*4+2]
    call .rgbe_channel
    mov [rdi+r10*4],al
    movzx eax,byte [rsi+r10*4+1]
    call .rgbe_channel
    mov [rdi+r10*4+1],al
    movzx eax,byte [rsi+r10*4]
    call .rgbe_channel
    mov [rdi+r10*4+2],al
    mov byte [rdi+r10*4+3],255
    inc r10d
    jmp .pixel
.next_row:
    inc r14d
    jmp .row
.done:
    mov rax,[rsp+16]
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,48
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; Parse unsigned decimal at rsi, max rdx. OUT eax=value, rcx=consumed incl ws.
.uint:
    xor eax,eax
    xor ecx,ecx
.u_skip:
    cmp rcx,rdx
    jae .u_done
    cmp byte [rsi+rcx],' '
    jne .u_digits
    inc rcx
    jmp .u_skip
.u_digits:
    movzx r8d,byte [rsi+rcx]
    sub r8d,'0'
    cmp r8d,9
    ja .u_done
    imul eax,10
    add eax,r8d
    inc rcx
    jmp .u_digits
.u_done:
    ret

; Approximate RGBE channel to display byte with exposure clamp.
.rgbe_channel:
    test ecx,ecx
    jz .zero
    sub ecx,128
    cmp ecx,0
    je .clamp
    js .shift_right
    cmp ecx,8
    jae .max
    shl eax,cl
    jmp .clamp
.shift_right:
    neg ecx
    cmp ecx,8
    jae .zero
    shr eax,cl
.clamp:
    cmp eax,255
    jbe .channel_done
.max:
    mov eax,255
.channel_done:
    ret
.zero:
    xor eax,eax
    ret

section .data
global hdr_version
hdr_version: dq 0x010000
