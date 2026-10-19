; VP8 lossy frame validation and boolean arithmetic decoder.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; reader,data,len -> 0/-EINVAL.
global webp_bool_init
webp_bool_init:
    test rdi,rdi
    jz .init_bad
    test rsi,rsi
    jz .init_bad
    cmp rdx,2
    jb .init_bad
    lea rcx,[rsi+2]
    mov [rdi+WebPBoolReader.cursor],rcx
    add rsi,rdx
    jc .init_bad
    mov [rdi+WebPBoolReader.end],rsi
    mov dword [rdi+WebPBoolReader.range],255
    movzx eax,byte [rcx-2]
    shl eax,8
    movzx edx,byte [rcx-1]
    or eax,edx
    mov [rdi+WebPBoolReader.value],eax
    mov dword [rdi+WebPBoolReader.count],0
    mov dword [rdi+WebPBoolReader.error],0
    xor eax,eax
    ret
.init_bad:
    mov rax,-EINVAL
    ret

; reader,probability-of-zero(1..255) -> bit or -EINVAL.
global webp_bool_get
webp_bool_get:
    test rdi,rdi
    jz .get_bad
    cmp esi,1
    jb .get_bad
    cmp esi,255
    ja .get_bad
    cmp dword [rdi+WebPBoolReader.error],0
    jne .get_bad
    mov r8d,[rdi+WebPBoolReader.range]
    lea eax,[r8-1]
    imul eax,esi
    shr eax,8
    inc eax                            ; split
    mov edx,eax
    shl edx,8                          ; scaled split
    mov ecx,[rdi+WebPBoolReader.value]
    xor r9d,r9d
    cmp ecx,edx
    jb .selected
    mov r9d,1
    sub ecx,edx
    sub r8d,eax
    jmp .normalize
.selected:
    mov r8d,eax
.normalize:
    cmp r8d,128
    jae .store
    shl r8d,1
    shl ecx,1
    inc dword [rdi+WebPBoolReader.count]
    cmp dword [rdi+WebPBoolReader.count],8
    jb .normalize
    mov rax,[rdi+WebPBoolReader.cursor]
    cmp rax,[rdi+WebPBoolReader.end]
    jae .get_exhausted
    movzx edx,byte [rax]
    or ecx,edx
    inc rax
    mov [rdi+WebPBoolReader.cursor],rax
    mov dword [rdi+WebPBoolReader.count],0
    jmp .normalize
.store:
    mov [rdi+WebPBoolReader.range],r8d
    mov [rdi+WebPBoolReader.value],ecx
    mov eax,r9d
    ret
.get_exhausted:
    mov dword [rdi+WebPBoolReader.error],1
.get_bad:
    mov rax,-EINVAL
    ret

; reader,bit_count(0..32) -> unsigned literal or -EINVAL.
global webp_bool_literal
webp_bool_literal:
    PROLOGUE_SAVE rbx,r12,r13
    mov rbx,rdi
    mov r12d,esi
    cmp r12d,32
    ja .literal_bad
    xor r13d,r13d
.literal_next:
    test r12d,r12d
    jz .literal_done
    mov rdi,rbx
    mov esi,128
    call webp_bool_get
    test rax,rax
    js .literal_bad
    shl r13d,1
    or r13d,eax
    dec r12d
    jmp .literal_next
.literal_done:
    mov eax,r13d
    EPILOGUE_RESTORE rbx,r12,r13
.literal_bad:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13

; VP8 payload,len,WebPVP8Info* -> 0/-EINVAL. WebP carries key frames only.
global webp_vp8_inspect
webp_vp8_inspect:
    test rdi,rdi
    jz .inspect_bad
    test rdx,rdx
    jz .inspect_bad
    cmp rsi,10
    jb .inspect_bad
    mov eax,[rdi]
    and eax,0x00ffffff
    test eax,1                         ; interframe is invalid in WebP
    jnz .inspect_bad
    mov ecx,eax
    shr ecx,1
    and ecx,7
    cmp ecx,3
    ja .inspect_bad
    mov r8d,eax
    shr r8d,4
    and r8d,1
    mov r9d,eax
    shr r9d,5                          ; first partition size
    cmp byte [rdi+3],0x9d
    jne .inspect_bad
    cmp byte [rdi+4],0x01
    jne .inspect_bad
    cmp byte [rdi+5],0x2a
    jne .inspect_bad
    movzx eax,word [rdi+6]
    and eax,0x3fff
    jz .inspect_bad
    movzx r10d,word [rdi+8]
    and r10d,0x3fff
    jz .inspect_bad
    mov r11,rsi
    sub r11,10
    cmp r9,r11
    ja .inspect_bad
    mov [rdx+WebPVP8Info.width],eax
    mov [rdx+WebPVP8Info.height],r10d
    mov [rdx+WebPVP8Info.version],ecx
    mov [rdx+WebPVP8Info.show_frame],r8d
    lea rax,[rdi+10]
    mov [rdx+WebPVP8Info.first],rax
    mov [rdx+WebPVP8Info.first_len],r9
    add rax,r9
    mov [rdx+WebPVP8Info.tokens],rax
    sub r11,r9
    mov [rdx+WebPVP8Info.tokens_len],r11
    xor eax,eax
    ret
.inspect_bad:
    mov rax,-EINVAL
    ret

section .data
global webp_vp8_version
webp_vp8_version: dq 0x010000
