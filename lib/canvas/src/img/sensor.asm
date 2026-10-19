; Camera sensor pipeline: unpack, normalize, Bayer demosaic, white balance,
; camera matrix, and display-referred BGRA8 output.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/fixed.inc"

extern pixbuf_create
extern fix_sqrt

section .text

; IN rdi=arena, rsi=mosaic bytes, rdx=len, rcx=SensorImageDesc*.
global sensor_process
sensor_process:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    sub rsp,96
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    mov eax,[r14+SensorImageDesc.width]
    mov [rsp],eax
    mov eax,[r14+SensorImageDesc.height]
    mov [rsp+4],eax
    test dword [rsp],-1
    jz .bad
    test dword [rsp+4],-1
    jz .bad
    cmp dword [rsp],32768
    ja .bad
    cmp dword [rsp+4],32768
    ja .bad
    mov eax,[r14+SensorImageDesc.bit_depth]
    cmp eax,8
    jb .bad
    cmp eax,16
    ja .bad
    mov eax,[r14+SensorImageDesc.white_level]
    cmp eax,[r14+SensorImageDesc.black_level]
    jbe .bad
    mov rdi,rbx
    mov esi,[rsp]
    mov edx,[rsp+4]
    mov rcx,DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax,rax
    jz .bad
    mov [rsp+8],rax
    mov r15,[rax+PixBuf_data]
    xor eax,eax
    mov [rsp+16],eax              ; y
.row:
    mov eax,[rsp+16]
    cmp eax,[rsp+4]
    jae .done
    mov dword [rsp+20],0          ; x
.pixel:
    mov eax,[rsp+20]
    cmp eax,[rsp]
    jae .next_row
    ; Center and the eight immediate neighbors, normalized to 0..65535.
    mov rdi,r12
    mov rsi,r13
    mov rdx,r14
    mov ecx,[rsp+20]
    mov r8d,[rsp+16]
    call sensor_sample
    mov [rsp+24],eax              ; C
    mov ecx,[rsp+20]
    dec ecx
    mov r8d,[rsp+16]
    call .sample_again
    mov [rsp+28],eax              ; L
    mov ecx,[rsp+20]
    inc ecx
    mov r8d,[rsp+16]
    call .sample_again
    mov [rsp+32],eax              ; R
    mov ecx,[rsp+20]
    mov r8d,[rsp+16]
    dec r8d
    call .sample_again
    mov [rsp+36],eax              ; U
    mov ecx,[rsp+20]
    mov r8d,[rsp+16]
    inc r8d
    call .sample_again
    mov [rsp+40],eax              ; D
    mov ecx,[rsp+20]
    dec ecx
    mov r8d,[rsp+16]
    dec r8d
    call .sample_again
    mov [rsp+44],eax              ; UL
    mov ecx,[rsp+20]
    inc ecx
    mov r8d,[rsp+16]
    dec r8d
    call .sample_again
    mov [rsp+48],eax              ; UR
    mov ecx,[rsp+20]
    dec ecx
    mov r8d,[rsp+16]
    inc r8d
    call .sample_again
    mov [rsp+52],eax              ; DL
    mov ecx,[rsp+20]
    inc ecx
    mov r8d,[rsp+16]
    inc r8d
    call .sample_again
    mov [rsp+56],eax              ; DR
    ; Convert pattern+parity to color: 0=R, 1=G-on-R-row,
    ; 2=G-on-B-row, 3=B. Pattern is a two-bit XOR transform.
    mov eax,[rsp+16]
    add eax,[r14+SensorImageDesc.crop_y]
    and eax,1
    shl eax,1
    mov ecx,[rsp+20]
    add ecx,[r14+SensorImageDesc.crop_x]
    and ecx,1
    or eax,ecx
    mov ecx,[r14+SensorImageDesc.cfa]
    cmp ecx,SENSOR_CFA_BGGR
    jne .not_bggr
    xor eax,3
    jmp .site
.not_bggr:
    cmp ecx,SENSOR_CFA_GRBG
    jne .not_grbg
    xor eax,1
    jmp .site
.not_grbg:
    cmp ecx,SENSOR_CFA_GBRG
    jne .site
    xor eax,2
.site:
    cmp eax,0
    je .red_site
    cmp eax,3
    je .blue_site
    cmp eax,1
    je .green_red_row
    ; Green on a blue row: R vertical, B horizontal.
    mov eax,[rsp+36]
    add eax,[rsp+40]
    shr eax,1
    mov [rsp+60],eax
    mov eax,[rsp+24]
    mov [rsp+64],eax
    mov eax,[rsp+28]
    add eax,[rsp+32]
    shr eax,1
    mov [rsp+68],eax
    jmp .color
.green_red_row:
    mov eax,[rsp+28]
    add eax,[rsp+32]
    shr eax,1
    mov [rsp+60],eax
    mov eax,[rsp+24]
    mov [rsp+64],eax
    mov eax,[rsp+36]
    add eax,[rsp+40]
    shr eax,1
    mov [rsp+68],eax
    jmp .color
.red_site:
    mov eax,[rsp+24]
    mov [rsp+60],eax
    mov eax,[rsp+28]
    add eax,[rsp+32]
    add eax,[rsp+36]
    add eax,[rsp+40]
    shr eax,2
    mov [rsp+64],eax
    mov eax,[rsp+44]
    add eax,[rsp+48]
    add eax,[rsp+52]
    add eax,[rsp+56]
    shr eax,2
    mov [rsp+68],eax
    jmp .color
.blue_site:
    mov eax,[rsp+44]
    add eax,[rsp+48]
    add eax,[rsp+52]
    add eax,[rsp+56]
    shr eax,2
    mov [rsp+60],eax
    mov eax,[rsp+28]
    add eax,[rsp+32]
    add eax,[rsp+36]
    add eax,[rsp+40]
    shr eax,2
    mov [rsp+64],eax
    mov eax,[rsp+24]
    mov [rsp+68],eax
.color:
    ; White balance in 16.16.
    mov eax,[rsp+60]
    imul rax,[r14+SensorImageDesc.wb_r]
    sar rax,16
    mov [rsp+60],eax
    mov eax,[rsp+64]
    imul rax,[r14+SensorImageDesc.wb_g]
    sar rax,16
    mov [rsp+64],eax
    mov eax,[rsp+68]
    imul rax,[r14+SensorImageDesc.wb_b]
    sar rax,16
    mov [rsp+68],eax
    ; Signed 3x3 camera RGB -> display-linear RGB.
    lea rsi,[r14+SensorImageDesc.color_matrix]
    lea rdi,[rsp+72]
    xor r8d,r8d
.matrix_row:
    xor rax,rax
    movsxd rcx,dword [rsi+r8*4]
    movsxd rdx,dword [rsp+60]
    imul rcx,rdx
    add rax,rcx
    movsxd rcx,dword [rsi+r8*4+4]
    movsxd rdx,dword [rsp+64]
    imul rcx,rdx
    add rax,rcx
    movsxd rcx,dword [rsi+r8*4+8]
    movsxd rdx,dword [rsp+68]
    imul rcx,rdx
    add rax,rcx
    sar rax,16
    test rax,rax
    jns .matrix_hi
    xor eax,eax
.matrix_hi:
    cmp rax,65535
    jbe .matrix_store
    mov eax,65535
.matrix_store:
    mov [rdi],eax
    add rdi,4
    add r8d,3
    cmp r8d,9
    jb .matrix_row
    ; Linear 16-bit to display byte using a fast sqrt transfer curve.
    mov edi,[rsp+72]
    shl rdi,16
    call fix_sqrt
    shr rax,8
    mov [rsp+84],eax              ; R8
    mov edi,[rsp+76]
    shl rdi,16
    call fix_sqrt
    shr rax,8
    mov [rsp+88],eax              ; G8
    mov edi,[rsp+80]
    shl rdi,16
    call fix_sqrt
    shr rax,8
    mov [rsp+92],eax              ; B8
    mov rax,[rsp+8]
    mov rdi,[rax+PixBuf_data]
    mov eax,[rsp+16]
    mov rdx,[rsp+8]
    imul rax,[rdx+PixBuf_stride]
    add rdi,rax
    mov eax,[rsp+20]
    lea rdi,[rdi+rax*4]
    mov al,[rsp+92]
    mov [rdi],al
    mov al,[rsp+88]
    mov [rdi+1],al
    mov al,[rsp+84]
    mov [rdi+2],al
    mov byte [rdi+3],255
    inc dword [rsp+20]
    jmp .pixel
.sample_again:
    mov rdi,r12
    mov rsi,r13
    mov rdx,r14
    call sensor_sample
    ret
.next_row:
    inc dword [rsp+16]
    jmp .row
.done:
    mov rax,[rsp+8]
    add rsp,96
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad:
    xor eax,eax
    add rsp,96
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; IN data,len,desc,x,y. Coordinates clamp to the sensor boundary.
; OUT normalized 0..65535.
global sensor_sample
sensor_sample:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14d,ecx
    mov r15d,r8d
    test r14d,r14d
    jns .x_upper
    xor r14d,r14d
.x_upper:
    cmp r14d,[r13+SensorImageDesc.width]
    jb .y_lower
    mov r14d,[r13+SensorImageDesc.width]
    dec r14d
.y_lower:
    test r15d,r15d
    jns .y_upper
    xor r15d,r15d
.y_upper:
    cmp r15d,[r13+SensorImageDesc.height]
    jb .address
    mov r15d,[r13+SensorImageDesc.height]
    dec r15d
.address:
    add r14d,[r13+SensorImageDesc.crop_x]
    add r15d,[r13+SensorImageDesc.crop_y]
    add rbx,[r13+SensorImageDesc.data_offset]
    mov eax,[r13+SensorImageDesc.stride]
    imul eax,r15d
    add rbx,rax
    cmp dword [r13+SensorImageDesc.packing],SENSOR_PACK_LSB_BITS
    je .packed_lsb
    cmp dword [r13+SensorImageDesc.packing],SENSOR_PACK_MSB_BITS
    je .packed_msb
    cmp dword [r13+SensorImageDesc.packing],SENSOR_PACK_UNPACKED_BE
    je .word_be
    cmp dword [r13+SensorImageDesc.bit_depth],8
    ja .word
    movzx eax,byte [rbx+r14]
    jmp .normalize
.word:
    movzx eax,word [rbx+r14*2]
    jmp .normalize
.word_be:
    movzx eax,word [rbx+r14*2]
    xchg al,ah
    jmp .normalize
.packed_lsb:
    mov eax,r14d
    imul eax,[r13+SensorImageDesc.bit_depth]
    mov ecx,eax
    and ecx,7
    shr eax,3
    mov edx,[rbx+rax]
    shr edx,cl
    mov ecx,[r13+SensorImageDesc.bit_depth]
    mov eax,1
    shl eax,cl
    dec eax
    and eax,edx
    jmp .normalize
.packed_msb:
    mov eax,r14d
    imul eax,[r13+SensorImageDesc.bit_depth]
    mov ecx,eax
    and ecx,7
    shr eax,3
    mov edx,[rbx+rax]
    bswap edx
    mov eax,32
    sub eax,[r13+SensorImageDesc.bit_depth]
    sub eax,ecx
    mov ecx,eax
    shr edx,cl
    mov ecx,[r13+SensorImageDesc.bit_depth]
    mov eax,1
    shl eax,cl
    dec eax
    and eax,edx
.normalize:
    sub eax,[r13+SensorImageDesc.black_level]
    jns .positive
    xor eax,eax
.positive:
    mov ecx,[r13+SensorImageDesc.white_level]
    sub ecx,[r13+SensorImageDesc.black_level]
    cmp eax,ecx
    jbe .scale
    mov eax,ecx
.scale:
    imul rax,65535
    xor edx,edx
    div rcx
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global sensor_version
sensor_version: dq 0x010000
