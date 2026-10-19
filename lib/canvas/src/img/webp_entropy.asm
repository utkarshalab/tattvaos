; Shared VP8L image-data decoder for main and subresolution images.
%include "inc/abi.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern arena_alloc
extern webp_bits_get
extern webp_huff_group_read
extern webp_huff_group_decode
extern webp_huff_groups_decode

section .text

; reader,arena,width,height,pixels,allow_meta -> 0 or -EINVAL.
global webp_decode_image
webp_decode_image:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,128
    mov rbx,rdi
    mov r12,rsi
    mov r14d,edx
    mov r15d,ecx
    mov r13,r8
    mov [rsp+124],r9d
    test rbx,rbx
    jz .bad
    test r12,r12
    jz .bad
    test r13,r13
    jz .bad
    test r14d,r14d
    jz .bad
    test r15d,r15d
    jz .bad
    mov rax,r14
    imul rax,r15
    jo .bad
    mov [rsp+WebPVP8LState.pixels],r13
    mov [rsp+WebPVP8LState.capacity],rax
    mov qword [rsp+WebPVP8LState.produced],0
    mov qword [rsp+WebPVP8LState.cache],0
    mov [rsp+WebPVP8LState.width],r14d
    mov dword [rsp+WebPVP8LState.cache_bits],0
    mov dword [rsp+84],1              ; group count
    mov qword [rsp+96],0              ; entropy image
    mov rdi,rbx
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .bad
    test eax,eax
    jz .cache_ready
    mov rdi,rbx
    mov esi,4
    call webp_bits_get
    test rax,rax
    js .bad
    inc eax
    cmp eax,11
    ja .bad
    mov [rsp+80],eax
    mov [rsp+WebPVP8LState.cache_bits],eax
    mov ecx,eax
    mov rsi,4
    shl rsi,cl
    mov rdi,r12
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+WebPVP8LState.cache],rax
    mov rdi,rax
    xor eax,eax
    mov ecx,[rsp+80]
    mov edx,1
    shl edx,cl
    mov ecx,edx
    rep stosd
.cache_ready:
    cmp dword [rsp+124],0
    je .groups_ready
    mov rdi,rbx
    mov esi,1
    call webp_bits_get
    test rax,rax
    js .bad
    test eax,eax
    jz .groups_ready
    mov rdi,rbx
    mov esi,3
    call webp_bits_get
    test rax,rax
    js .bad
    add eax,2
    mov [rsp+92],eax                  ; prefix bits
    mov ecx,eax
    mov edx,1
    shl edx,cl
    dec edx
    mov eax,r14d
    add eax,edx
    jc .bad
    shr eax,cl
    mov [rsp+88],eax                  ; entropy width
    mov eax,r15d
    add eax,edx
    jc .bad
    shr eax,cl
    mov [rsp+80],eax                  ; entropy height
    imul eax,[rsp+88]
    jo .bad
    mov [rsp+76],eax                  ; entropy pixel count
    mov rsi,rax
    shl rsi,2
    mov rdi,r12
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+96],rax
    mov rdi,rbx
    mov rsi,r12
    mov edx,[rsp+88]
    mov ecx,[rsp+80]
    mov r8,rax
    xor r9d,r9d                       ; entropy images have no meta layer
    call webp_decode_image
    test rax,rax
    js .bad
    mov rdi,[rsp+96]
    mov ecx,[rsp+76]
    xor edx,edx
.max_group:
    test ecx,ecx
    jz .max_group_done
    mov eax,[rdi]
    shr eax,8
    and eax,0xffff
    cmp eax,edx
    cmova edx,eax
    add rdi,4
    dec ecx
    jmp .max_group
.max_group_done:
    inc edx
    mov [rsp+84],edx
.groups_ready:
    mov eax,[rsp+84]
    imul rsi,rax,WEBP_HUFF_GROUP_SIZE
    jo .bad
    mov rdi,r12
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+104],rax                 ; groups
    mov rdi,r12
    mov rsi,WEBP_HUFF_MAX_SYMBOLS+19
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+112],rax
    mov rdi,r12
    mov rsi,WEBP_HUFF_TABLE_SIZE
    call arena_alloc
    test rax,rax
    jle .bad
    mov [rsp+120],rax
    mov dword [rsp+80],0
.read_group:
    mov eax,[rsp+80]
    cmp eax,[rsp+84]
    jae .decode_pixels
    imul rdx,rax,WEBP_HUFF_GROUP_SIZE
    add rdx,[rsp+104]
    mov rdi,rbx
    mov esi,[rsp+WebPVP8LState.cache_bits]
    mov rcx,[rsp+112]
    mov r8,[rsp+120]
    call webp_huff_group_read
    test rax,rax
    js .bad
    inc dword [rsp+80]
    jmp .read_group
.decode_pixels:
    cmp qword [rsp+96],0
    je .decode_single
    lea rdi,[rsp+40]
    mov rax,[rsp+104]
    mov [rdi+WebPMetaState.groups],rax
    mov rax,[rsp+96]
    mov [rdi+WebPMetaState.entropy],rax
    lea rax,[rsp]
    mov [rdi+WebPMetaState.vp8l],rax
    mov eax,[rsp+84]
    mov [rdi+WebPMetaState.group_count],eax
    mov eax,[rsp+88]
    mov [rdi+WebPMetaState.entropy_width],eax
    mov eax,[rsp+92]
    mov [rdi+WebPMetaState.prefix_bits],eax
    mov rsi,rdi
    mov rdi,rbx
    call webp_huff_groups_decode
    jmp .decoded
.decode_single:
    mov rdi,rbx
    mov rsi,[rsp+104]
    lea rdx,[rsp]
    call webp_huff_group_decode
.decoded:
    test rax,rax
    js .bad
    cmp rax,[rsp+WebPVP8LState.capacity]
    jne .bad
    xor eax,eax
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.bad:
    mov rax,-EINVAL
    add rsp,128
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

section .data
global webp_entropy_version
webp_entropy_version: dq 0x010000
