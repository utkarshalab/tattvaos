; Core VP8L prefix, LZ77 copy, and color-cache primitives.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern webp_bits_get
extern webp_huff_decode

section .text

; reader,prefix_code(0..23) -> decoded positive length/distance value.
global webp_prefix_value
webp_prefix_value:
    cmp esi,23
    ja .bad
    cmp esi,4
    jae .extended
    lea eax,[rsi+1]
    ret
.extended:
    mov edx,esi
    sub edx,2
    shr edx,1                         ; extra bits
    mov eax,esi
    and eax,1
    add eax,2
    mov ecx,edx
    shl eax,cl                        ; range base before +1
    push rax
    mov esi,edx
    call webp_bits_get
    pop rcx
    test rax,rax
    js .bad
    add rax,rcx
    inc rax
    ret
.bad:
    mov rax,-EINVAL
    ret

; pixels,produced,capacity,distance,count -> new produced count or -EINVAL.
global webp_copy_pixels
webp_copy_pixels:
    test rdi,rdi
    jz .copy_bad
    test r8,r8
    jz .copy_bad
    test rcx,rcx
    jz .copy_bad
    cmp rcx,rsi
    ja .copy_bad
    mov rax,rsi
    add rax,r8
    jc .copy_bad
    cmp rax,rdx
    ja .copy_bad
    mov r9,rsi
    sub r9,rcx
    xor r10d,r10d
.copy:
    cmp r10,r8
    jae .copy_done
    mov r11d,[rdi+r9*4]
    mov [rdi+rsi*4],r11d
    inc r9                            ; forward copy intentionally permits overlap
    inc rsi
    inc r10
    jmp .copy
.copy_done:
    ret
.copy_bad:
    mov rax,-EINVAL
    ret

; ARGB value, cache_bits(1..11) -> cache slot.
global webp_color_cache_index
webp_color_cache_index:
    cmp esi,1
    jb .cache_bad
    cmp esi,11
    ja .cache_bad
    imul eax,edi,0x1e35a7bd
    mov ecx,32
    sub ecx,esi
    shr eax,cl
    ret
.cache_bad:
    mov rax,-EINVAL
    ret

; image_width,distance_code -> scan-line distance or -EINVAL.
global webp_distance_value
webp_distance_value:
    test edi,edi
    jz .distance_bad
    test esi,esi
    jz .distance_bad
    cmp esi,120
    jbe .distance_plane
    lea eax,[rsi-120]
    ret
.distance_plane:
    dec esi
    lea rdx,[rel distance_map]
    movsx eax,byte [rdx+rsi*2]
    movsx ecx,byte [rdx+rsi*2+1]
    imul ecx,edi
    add eax,ecx
    cmp eax,1
    jge .distance_done
    mov eax,1
.distance_done:
    ret
.distance_bad:
    mov rax,-EINVAL
    ret

; reader,group,pixels,count,cache,cache_bits -> count or negative error.
; Literal/cache-only helper. The full decoder below handles LZ symbols.
global webp_huff_group_decode_literals
webp_huff_group_decode_literals:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    mov [rsp],r9d
    test r13,r13
    jz .decode_bad
    cmp dword [rsp],11
    ja .decode_bad
    xor ecx,ecx
    mov [rsp+4],ecx
.pixel:
    mov ecx,[rsp+4]
    cmp rcx,r14
    jae .decode_done
    lea rdi,[r12+WEBP_GROUP_GREEN]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .decode_bad
    cmp eax,256
    jb near .literal
    cmp eax,280
    jb near .decode_bad
    cmp dword [rsp],0
    je .decode_bad
    sub eax,280
    mov edx,eax
    mov ecx,[rsp]
    mov eax,1
    shl eax,cl
    cmp edx,eax
    jae .decode_bad
    mov eax,[r15+rdx*4]
    jmp near .store
.literal:
    mov [rsp+8],eax                  ; green
    lea rdi,[r12+WEBP_GROUP_RED]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .decode_bad
    mov edx,eax
    shl edx,16
    mov [rsp+12],edx
    lea rdi,[r12+WEBP_GROUP_BLUE]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .decode_bad
    or [rsp+12],eax
    lea rdi,[r12+WEBP_GROUP_ALPHA]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .decode_bad
    shl eax,24
    or eax,[rsp+12]
    mov edx,[rsp+8]
    shl edx,8
    or eax,edx
    cmp dword [rsp],0
    je .store
    push rax
    mov edi,eax
    mov esi,[rsp+8]                  ; cache_bits after push
    call webp_color_cache_index
    mov edx,eax
    pop rax
    mov [r15+rdx*4],eax
.store:
    mov ecx,[rsp+4]
    mov [r13+rcx*4],eax
    inc dword [rsp+4]
    jmp .pixel
.decode_done:
    mov eax,[rsp+4]
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.decode_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; reader,group,WebPVP8LState* -> total produced pixels or negative error.
global webp_huff_group_decode
webp_huff_group_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    test r13,r13
    jz .full_bad
    mov r14,[r13+WebPVP8LState.pixels]
    test r14,r14
    jz .full_bad
    mov r15,[r13+WebPVP8LState.capacity]
    test r15,r15
    jz .full_bad
    cmp dword [r13+WebPVP8LState.width],0
    je .full_bad
    cmp dword [r13+WebPVP8LState.cache_bits],11
    ja .full_bad
    cmp dword [r13+WebPVP8LState.cache_bits],0
    je .full_cache_valid
    cmp qword [r13+WebPVP8LState.cache],0
    je .full_bad
.full_cache_valid:
    cmp qword [r13+WebPVP8LState.produced],r15
    ja .full_bad
.full_loop:
    mov rcx,[r13+WebPVP8LState.produced]
    cmp rcx,r15
    jae .full_done
    lea rdi,[r12+WEBP_GROUP_GREEN]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .full_bad
    cmp eax,256
    jb near .full_literal
    cmp eax,280
    jb near .full_copy
    mov ecx,[r13+WebPVP8LState.cache_bits]
    test ecx,ecx
    jz .full_bad
    sub eax,280
    mov edx,1
    shl edx,cl
    cmp eax,edx
    jae .full_bad
    mov rdx,[r13+WebPVP8LState.cache]
    test rdx,rdx
    jz .full_bad
    mov eax,[rdx+rax*4]
    jmp near .full_store
.full_literal:
    mov [rsp],eax
    lea rdi,[r12+WEBP_GROUP_RED]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .full_bad
    shl eax,16
    mov [rsp+4],eax
    lea rdi,[r12+WEBP_GROUP_BLUE]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .full_bad
    or [rsp+4],eax
    lea rdi,[r12+WEBP_GROUP_ALPHA]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .full_bad
    shl eax,24
    or eax,[rsp+4]
    mov edx,[rsp]
    shl edx,8
    or eax,edx
.full_store:
    mov rcx,[r13+WebPVP8LState.produced]
    mov [r14+rcx*4],eax
    inc rcx
    mov [r13+WebPVP8LState.produced],rcx
    mov [rsp+24],eax
    call .full_cache_pixel
    jmp .full_loop

.full_copy:
    sub eax,256
    mov rdi,rbx
    mov esi,eax
    call webp_prefix_value
    test rax,rax
    js .full_bad
    mov [rsp+8],rax                 ; copy length
    lea rdi,[r12+WEBP_GROUP_DISTANCE]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .full_bad
    mov rdi,rbx
    mov esi,eax
    call webp_prefix_value
    test rax,rax
    js .full_bad
    mov edi,[r13+WebPVP8LState.width]
    mov esi,eax
    call webp_distance_value
    test rax,rax
    js .full_bad
    mov rcx,[r13+WebPVP8LState.produced]
    mov [rsp+16],rcx                ; first copied pixel
    mov rdi,r14
    mov rsi,rcx
    mov rdx,r15
    mov rcx,rax
    mov r8,[rsp+8]
    call webp_copy_pixels
    test rax,rax
    js .full_bad
    mov [r13+WebPVP8LState.produced],rax
.full_cache_copies:
    mov rcx,[rsp+16]
    cmp rcx,[r13+WebPVP8LState.produced]
    jae .full_loop
    mov eax,[r14+rcx*4]
    mov [rsp+24],eax
    call .full_cache_pixel
    inc qword [rsp+16]
    jmp .full_cache_copies

; Cache the pixel saved at caller rsp+24 (helper rsp+32 after return address).
.full_cache_pixel:
    cmp dword [r13+WebPVP8LState.cache_bits],0
    je .full_cache_done
    mov rdx,[r13+WebPVP8LState.cache]
    mov edi,[rsp+32]
    mov esi,[r13+WebPVP8LState.cache_bits]
    call webp_color_cache_index
    mov rdx,[r13+WebPVP8LState.cache]
    mov ecx,[rsp+32]
    mov [rdx+rax*4],ecx
.full_cache_done:
    ret
.full_done:
    mov rax,[r13+WebPVP8LState.produced]
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.full_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; reader,group,WebPVP8LState* -> new produced count after one token.
; A token is one literal/cache pixel or one complete LZ77 copy.
global webp_huff_group_decode_one
webp_huff_group_decode_one:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,32
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    test rbx,rbx
    jz .one_bad
    test r12,r12
    jz .one_bad
    test r13,r13
    jz .one_bad
    mov r14,[r13+WebPVP8LState.pixels]
    mov r15,[r13+WebPVP8LState.capacity]
    test r14,r14
    jz .one_bad
    cmp qword [r13+WebPVP8LState.produced],r15
    jae .one_bad
    cmp dword [r13+WebPVP8LState.width],0
    je .one_bad
    cmp dword [r13+WebPVP8LState.cache_bits],11
    ja .one_bad
    cmp dword [r13+WebPVP8LState.cache_bits],0
    je .one_decode
    cmp qword [r13+WebPVP8LState.cache],0
    je .one_bad
.one_decode:
    lea rdi,[r12+WEBP_GROUP_GREEN]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .one_bad
    cmp eax,256
    jb .one_literal
    cmp eax,280
    jb .one_copy
    mov ecx,[r13+WebPVP8LState.cache_bits]
    test ecx,ecx
    jz .one_bad
    sub eax,280
    mov edx,1
    shl edx,cl
    cmp eax,edx
    jae .one_bad
    mov rdx,[r13+WebPVP8LState.cache]
    mov eax,[rdx+rax*4]
    jmp .one_store
.one_literal:
    mov [rsp],eax
    lea rdi,[r12+WEBP_GROUP_RED]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .one_bad
    shl eax,16
    mov [rsp+4],eax
    lea rdi,[r12+WEBP_GROUP_BLUE]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .one_bad
    or [rsp+4],eax
    lea rdi,[r12+WEBP_GROUP_ALPHA]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .one_bad
    shl eax,24
    or eax,[rsp+4]
    mov edx,[rsp]
    shl edx,8
    or eax,edx
.one_store:
    mov rcx,[r13+WebPVP8LState.produced]
    mov [r14+rcx*4],eax
    inc rcx
    mov [r13+WebPVP8LState.produced],rcx
    mov [rsp+24],eax
    call .one_cache_pixel
    mov rax,[r13+WebPVP8LState.produced]
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.one_copy:
    sub eax,256
    mov rdi,rbx
    mov esi,eax
    call webp_prefix_value
    test rax,rax
    js .one_bad
    mov [rsp+8],rax
    lea rdi,[r12+WEBP_GROUP_DISTANCE]
    mov rsi,rbx
    call webp_huff_decode
    test rax,rax
    js .one_bad
    mov rdi,rbx
    mov esi,eax
    call webp_prefix_value
    test rax,rax
    js .one_bad
    mov edi,[r13+WebPVP8LState.width]
    mov esi,eax
    call webp_distance_value
    test rax,rax
    js .one_bad
    mov rcx,[r13+WebPVP8LState.produced]
    mov [rsp+16],rcx
    mov rdi,r14
    mov rsi,rcx
    mov rdx,r15
    mov rcx,rax
    mov r8,[rsp+8]
    call webp_copy_pixels
    test rax,rax
    js .one_bad
    mov [r13+WebPVP8LState.produced],rax
.one_cache_copies:
    mov rcx,[rsp+16]
    cmp rcx,[r13+WebPVP8LState.produced]
    jae .one_copy_done
    mov eax,[r14+rcx*4]
    mov [rsp+24],eax
    call .one_cache_pixel
    inc qword [rsp+16]
    jmp .one_cache_copies
.one_copy_done:
    mov rax,[r13+WebPVP8LState.produced]
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.one_cache_pixel:
    cmp dword [r13+WebPVP8LState.cache_bits],0
    je .one_cache_done
    mov edi,[rsp+32]
    mov esi,[r13+WebPVP8LState.cache_bits]
    call webp_color_cache_index
    mov rdx,[r13+WebPVP8LState.cache]
    mov ecx,[rsp+32]
    mov [rdx+rax*4],ecx
.one_cache_done:
    ret
.one_bad:
    mov rax,-EINVAL
    add rsp,32
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

; reader,WebPMetaState* -> final produced count or -EINVAL.
global webp_huff_groups_decode
webp_huff_groups_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,16
    mov rbx,rdi
    mov r12,rsi
    test rbx,rbx
    jz .groups_bad
    test r12,r12
    jz .groups_bad
    mov r13,[r12+WebPMetaState.groups]
    mov r14,[r12+WebPMetaState.entropy]
    mov r15,[r12+WebPMetaState.vp8l]
    test r13,r13
    jz .groups_bad
    test r14,r14
    jz .groups_bad
    test r15,r15
    jz .groups_bad
    cmp dword [r12+WebPMetaState.group_count],0
    je .groups_bad
    cmp dword [r12+WebPMetaState.entropy_width],0
    je .groups_bad
    mov ecx,[r12+WebPMetaState.prefix_bits]
    cmp ecx,2
    jb .groups_bad
    cmp ecx,9
    ja .groups_bad
.groups_loop:
    mov rax,[r15+WebPVP8LState.produced]
    cmp rax,[r15+WebPVP8LState.capacity]
    jae .groups_done
    xor edx,edx
    mov ecx,[r15+WebPVP8LState.width]
    div rcx                            ; rax=y, rdx=x
    mov ecx,[r12+WebPMetaState.prefix_bits]
    shr rax,cl
    imul eax,[r12+WebPMetaState.entropy_width]
    shr rdx,cl
    add eax,edx
    mov eax,[r14+rax*4]
    shr eax,8
    and eax,0xffff
    cmp eax,[r12+WebPMetaState.group_count]
    jae .groups_bad
    imul rsi,rax,WEBP_HUFF_GROUP_SIZE
    add rsi,r13
    mov rdi,rbx
    mov rdx,r15
    call webp_huff_group_decode_one
    test rax,rax
    js .groups_bad
    jmp .groups_loop
.groups_done:
    mov rax,[r15+WebPVP8LState.produced]
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
.groups_bad:
    mov rax,-EINVAL
    add rsp,16
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15

section .data
global webp_vp8l_version
webp_vp8l_version: dq 0x010000

section .rodata
; Signed (xi,yi) pairs for VP8L distance codes 1..120.
distance_map:
    db 0,1, 1,0, 1,1, -1,1, 0,2, 2,0, 1,2, -1,2
    db 2,1, -2,1, 2,2, -2,2, 0,3, 3,0, 1,3, -1,3
    db 3,1, -3,1, 2,3, -2,3, 3,2, -3,2, 0,4, 4,0
    db 1,4, -1,4, 4,1, -4,1, 3,3, -3,3, 2,4, -2,4
    db 4,2, -4,2, 0,5, 3,4, -3,4, 4,3, -4,3, 5,0
    db 1,5, -1,5, 5,1, -5,1, 2,5, -2,5, 5,2, -5,2
    db 4,4, -4,4, 3,5, -3,5, 5,3, -5,3, 0,6, 6,0
    db 1,6, -1,6, 6,1, -6,1, 2,6, -2,6, 6,2, -6,2
    db 4,5, -4,5, 5,4, -5,4, 3,6, -3,6, 6,3, -6,3
    db 0,7, 7,0, 1,7, -1,7, 5,5, -5,5, 7,1, -7,1
    db 4,6, -4,6, 6,4, -6,4, 2,7, -2,7, 7,2, -7,2
    db 3,7, -3,7, 7,3, -7,3, 5,6, -5,6, 6,5, -6,5
    db 8,0, 4,7, -4,7, 7,4, -7,4, 8,1, 8,2, 6,6
    db -6,6, 8,3, 5,7, -5,7, 7,5, -7,5, 8,4, 6,7
    db -6,7, 7,6, -7,6, 8,5, 7,7, -7,7, 8,6, 8,7
