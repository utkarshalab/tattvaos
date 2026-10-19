; WebP RIFF container validation and VP8/VP8L/VP8X metadata parsing.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

%define FOURCC_RIFF 0x46464952
%define FOURCC_WEBP 0x50424557
%define FOURCC_VP8  0x20385056
%define FOURCC_VP8L 0x4c385056
%define FOURCC_VP8X 0x58385056

section .text

; reader,data,len -> 0. VP8L consumes bits least-significant bit first.
global webp_bits_init
webp_bits_init:
    test rdi,rdi
    jz .bits_init_bad
    test rsi,rsi
    jz .bits_init_bad
    mov [rdi+WebPBitReader.cursor],rsi
    add rsi,rdx
    jc .bits_init_bad
    mov [rdi+WebPBitReader.end],rsi
    mov qword [rdi+WebPBitReader.bits],0
    mov dword [rdi+WebPBitReader.count],0
    xor eax,eax
    ret
.bits_init_bad:
    mov rax,-EINVAL
    ret

; reader,count(0..24) -> unsigned value, or -EINVAL on exhaustion.
global webp_bits_get
webp_bits_get:
    cmp esi,24
    ja .bits_bad
    test esi,esi
    jz .bits_zero
    mov ecx,[rdi+WebPBitReader.count]
    mov r8,[rdi+WebPBitReader.bits]
    mov r9,[rdi+WebPBitReader.cursor]
    mov r10,[rdi+WebPBitReader.end]
.bits_fill:
    cmp ecx,esi
    jae .bits_ready
    cmp r9,r10
    jae .bits_bad
    movzx eax,byte [r9]
    shl rax,cl
    or r8,rax
    inc r9
    add ecx,8
    jmp .bits_fill
.bits_ready:
    mov eax,1
    mov edx,esi
    mov cl,dl
    shl eax,cl
    dec eax
    and eax,r8d
    mov ecx,esi
    shr r8,cl
    mov ecx,[rdi+WebPBitReader.count]
    ; Include bytes fetched by this call before subtracting consumed bits.
    mov rdx,r9
    sub rdx,[rdi+WebPBitReader.cursor]
    shl edx,3
    add ecx,edx
    sub ecx,esi
    mov [rdi+WebPBitReader.cursor],r9
    mov [rdi+WebPBitReader.bits],r8
    mov [rdi+WebPBitReader.count],ecx
    ret
.bits_zero:
    xor eax,eax
    ret
.bits_bad:
    mov rax,-EINVAL
    ret

; data,len -> 1 only for a structurally bounded RIFF/WEBP container.
global webp_probe
webp_probe:
    cmp rsi,12
    jb .no
    cmp dword [rdi],FOURCC_RIFF
    jne .no
    cmp dword [rdi+8],FOURCC_WEBP
    jne .no
    mov eax,[rdi+4]
    cmp eax,4
    jb .no
    add rax,8
    jc .no
    cmp rax,rsi
    ja .no
    mov eax,1
    ret
.no:
    xor eax,eax
    ret

; data,len,WebPInfo* -> 0 or -EINVAL. The first primary bitstream wins.
global webp_inspect
webp_inspect:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    test r13,r13
    jz .bad
    mov rdi,r13
    xor eax,eax
    mov ecx,WebPInfo_size/8
    rep stosq
    mov rdi,rbx
    mov rsi,r12
    call webp_probe
    test eax,eax
    jz .bad
    mov r14d,[rbx+4]
    add r14,8                         ; logical RIFF end
    mov r15d,12
.chunk:
    cmp r15,r14
    jae .done
    lea rax,[r15+8]
    cmp rax,r14
    ja .bad
    mov r10d,[rbx+r15]
    mov r11d,[rbx+r15+4]
    lea r8,[r15+8]
    mov rax,r8
    add rax,r11
    jc .bad
    cmp rax,r14
    ja .bad
    cmp r10d,FOURCC_VP8X
    je .vp8x
    cmp r10d,FOURCC_VP8L
    je .vp8l
    cmp r10d,FOURCC_VP8
    je .vp8
.next:
    lea rax,[r15+r11+8]
    lea r15,[rax+1]
    and r15,-2
    cmp r15,r14
    ja .bad
    jmp .chunk

.vp8x:
    cmp r11d,10
    jne .bad
    cmp dword [r13+WebPInfo.width],0
    jne .bad
    movzx edx,byte [rbx+r8]
    test edx,0xc1                    ; reserved feature bits
    jnz .bad
    cmp byte [rbx+r8+1],0
    jne .bad
    cmp byte [rbx+r8+2],0
    jne .bad
    cmp byte [rbx+r8+3],0
    jne .bad
    mov [r13+WebPInfo.flags],edx
    movzx ecx,byte [rbx+r8+4]
    movzx edx,byte [rbx+r8+5]
    shl edx,8
    or ecx,edx
    movzx edx,byte [rbx+r8+6]
    shl edx,16
    or ecx,edx
    inc ecx
    mov [r13+WebPInfo.width],ecx
    movzx ecx,byte [rbx+r8+7]
    movzx edx,byte [rbx+r8+8]
    shl edx,8
    or ecx,edx
    movzx edx,byte [rbx+r8+9]
    shl edx,16
    or ecx,edx
    inc ecx
    mov [r13+WebPInfo.height],ecx
    jmp .next

.vp8l:
    cmp dword [r13+WebPInfo.codec],WEBP_CODEC_NONE
    jne .bad
    cmp r11d,5
    jb .bad
    cmp byte [rbx+r8],0x2f
    jne .bad
    mov edx,[rbx+r8+1]
    mov ecx,edx
    shr ecx,29
    jnz .bad
    mov eax,edx
    and eax,0x3fff
    inc eax
    mov r9d,edx
    shr r9d,14
    and r9d,0x3fff
    inc r9d
    bt edx,28
    jnc .vp8l_no_alpha
    or dword [r13+WebPInfo.flags],WEBP_FLAG_ALPHA
.vp8l_no_alpha:
    call .set_primary
    jmp .next

.vp8:
    cmp dword [r13+WebPInfo.codec],WEBP_CODEC_NONE
    jne .bad
    cmp r11d,10
    jb .bad
    test byte [rbx+r8],1             ; only a key frame has dimensions
    jnz .bad
    cmp byte [rbx+r8+3],0x9d
    jne .bad
    cmp byte [rbx+r8+4],0x01
    jne .bad
    cmp byte [rbx+r8+5],0x2a
    jne .bad
    movzx eax,word [rbx+r8+6]
    and eax,0x3fff
    movzx r9d,word [rbx+r8+8]
    and r9d,0x3fff
    test eax,eax
    jz .bad
    test r9d,r9d
    jz .bad
    mov ecx,WEBP_CODEC_VP8
    call .set_primary_common
    jmp .next

; eax=width, r9d=height, r8=payload, r11=size.
.set_primary:
    mov ecx,WEBP_CODEC_VP8L
.set_primary_common:
    cmp dword [r13+WebPInfo.width],0
    je .store_dimensions
    cmp eax,[r13+WebPInfo.width]
    ja .bad
    cmp r9d,[r13+WebPInfo.height]
    ja .bad
    jmp .store_primary
.store_dimensions:
    mov [r13+WebPInfo.width],eax
    mov [r13+WebPInfo.height],r9d
.store_primary:
    mov [r13+WebPInfo.codec],ecx
    lea rdx,[rbx+r8]
    mov [r13+WebPInfo.payload],rdx
    mov [r13+WebPInfo.payload_len],r11
    ret

.done:
    cmp dword [r13+WebPInfo.width],0
    je .bad
    cmp dword [r13+WebPInfo.height],0
    je .bad
    cmp dword [r13+WebPInfo.codec],WEBP_CODEC_NONE
    je .bad
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global webp_version
webp_version: dq 0x010000
