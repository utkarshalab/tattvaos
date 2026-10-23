; ============================================================================
; PNG Filter - Unfilter Scanlines (None/Sub/Up/Average/Paeth) + BGRA Convert
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern pixbuf_create

section .text

global png_unfilter_row
png_unfilter_row:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    movzx r15d, byte [rbx - 1]
    cmp r15d, 4
    ja .bad
    xor ecx, ecx
.loop:
    cmp ecx, r13d
    jae .done
    movzx eax, byte [rbx + rcx]
    cmp r15d, 0
    je .store
    xor edx, edx
    mov r8d, ecx
    sub r8d, r14d
    js .no_a
    movzx edx, byte [rbx + r8]
.no_a:
    xor r9d, r9d
    test r12, r12
    jz .no_b
    movzx r9d, byte [r12 + rcx]
.no_b:
    xor r10d, r10d
    test r12, r12
    jz .have_abc
    mov r11d, ecx
    sub r11d, r14d
    js .have_abc
    movzx r10d, byte [r12 + r11]
.have_abc:
    cmp r15d, 1
    je .f_sub
    cmp r15d, 2
    je .f_up
    cmp r15d, 3
    je .f_avg
    mov r11d, edx
    add r11d, r9d
    sub r11d, r10d
    mov esi, r11d
    sub esi, edx
    cmp esi, 0
    jge .pa_ok
    neg esi
.pa_ok:
    mov edi, r11d
    sub edi, r9d
    cmp edi, 0
    jge .pb_ok
    neg edi
.pb_ok:
    mov r8d, r11d
    sub r8d, r10d
    cmp r8d, 0
    jge .pc_ok
    neg r8d
.pc_ok:
    cmp esi, edi
    jg .cmp_bc
    cmp esi, r8d
    jg .use_c
    mov r11d, edx
    jmp .use_pr
.cmp_bc:
    cmp edi, r8d
    jg .use_c
    mov r11d, r9d
    jmp .use_pr
.use_c:
    mov r11d, r10d
.use_pr:
    add eax, r11d
    jmp .store
.f_sub:
    add eax, edx
    jmp .store
.f_up:
    add eax, r9d
    jmp .store
.f_avg:
    add edx, r9d
    shr edx, 1
    add eax, edx
.store:
    mov [rbx + rcx], al
    inc ecx
    jmp .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global png_unfilter
png_unfilter:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    push r12
    mov r14d, [r12 + PngImage.width]
    mov r15d, [r12 + PngImage.height]
    movzx eax, byte [r12 + PngImage.channels]
    movzx ecx,byte [r12 + PngImage.bit_depth]
    imul eax,ecx
    add eax,7
    shr eax,3
    mov r10d,eax
    test r10d,r10d
    jnz .bpp_ready
    mov r10d,1
.bpp_ready:
    mov eax,r14d
    movzx ecx,byte [r12 + PngImage.channels]
    imul eax,ecx
    movzx ecx,byte [r12 + PngImage.bit_depth]
    imul eax,ecx
    add eax,7
    shr eax,3
    mov r11d, eax
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov r14, rax
    pop r12
    push r12
    push r14
    xor ecx, ecx
.row_loop:
    cmp ecx, [r12 + PngImage.height]
    jae .convert
    mov eax, ecx
    mov edx, r11d
    inc edx
    imul eax, edx
    lea rsi, [r13 + rax]
    movzx eax, byte [rsi]
    cmp eax, 4
    ja .bad2
    inc rsi
    test ecx, ecx
    jz .first_row
    mov eax, ecx
    dec eax
    mov edx, r11d
    inc edx
    imul eax, edx
    lea rdi, [r13 + rax + 1]
    jmp .do_row
.first_row:
    xor edi, edi
.do_row:
    push rcx
    push r13
    mov rdx, rsi
    mov rsi, rdi
    mov rdi, rdx
    mov edx, r11d
    mov ecx, r10d
    call png_unfilter_row
    pop r13
    pop rcx
    test rax, rax
    jnz .bad2
    inc ecx
    jmp .row_loop
.convert:
    pop r14
    pop r12
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call png_convert_bgra
    test rax, rax
    jz .bad
    mov [r12 + PngImage.pixbuf], rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad2:
    add rsp, 16
.bad:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    add rsp, 8
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global png_convert_bgra
png_convert_bgra:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov rsi, rsi
    mov r13, rdx
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    mov r14d, [r12 + PngImage.width]
    mov r15d, [r12 + PngImage.height]
    mov eax, r14d
    movzx ecx,byte [r12 + PngImage.channels]
    imul eax,ecx
    movzx ecx,byte [r12 + PngImage.bit_depth]
    imul eax,ecx
    add eax,7
    shr eax,3
    inc eax
    mov r11d, eax
    push r12
    mov r12, [rbx + PixBuf.data]
    mov rdi, [rbx + PixBuf.stride]
    xor ecx, ecx
.y_loop:
    cmp ecx, r15d
    jae .done
    mov rax,[rsp]
    movzx r9d,byte [rax + PngImage.channels]
    imul r9d,[rax + PngImage.width]
    movzx r10d,byte [rax + PngImage.bit_depth]
    imul r9d,r10d
    add r9d,7
    shr r9d,3
    inc r9d
    mov eax, ecx
    imul eax,r9d
    lea rsi, [r13 + rax]
    inc rsi
    mov eax, ecx
    imul eax, edi
    lea rdx, [r12 + rax]
    xor r8d, r8d
    mov rax,[rsp]
    cmp byte [rax + PngImage.bit_depth],8
    jb .row_packed
    cmp byte [rax + PngImage.bit_depth],16
    je .row_16
    movzx eax,byte [rax + PngImage.color_type]
    cmp eax,6
    je .row_rgba
    cmp eax,2
    je .row_rgb
    cmp eax,4
    je .row_gray_alpha
    cmp eax,3
    je .row_palette
.x_gray:
    cmp r8d, r14d
    jae .next_row
    movzx eax, byte [rsi + r8]
    mov [rdx + r8 * 4], al
    mov [rdx + r8 * 4 + 1], al
    mov [rdx + r8 * 4 + 2], al
    mov byte [rdx + r8 * 4 + 3], 255
    mov rax,[rsp]
    mov r9,[rax + PngImage.transparency]
    test r9,r9
    jz .gray_next
    mov al,[rsi+r8]
    cmp al,[r9+1]
    jne .gray_next
    mov byte [rdx+r8*4+3],0
.gray_next:
    inc r8d
    jmp .x_gray
.row_packed:
    push rcx
    push r15
    movzx r10d,byte [rax + PngImage.bit_depth]
    mov ecx,r10d
    mov r11d,1
    shl r11d,cl
    dec r11d
    mov r9d,255
    cmp r10d,2
    jne .packed_not_2
    mov r9d,85
.packed_not_2:
    cmp r10d,4
    jne .x_packed
    mov r9d,17
.x_packed:
    cmp r8d,r14d
    jae .packed_done
    mov eax,r8d
    imul eax,r10d
    mov ecx,eax
    and ecx,7
    shr eax,3
    movzx eax,byte [rsi+rax]
    mov r15d,8
    sub r15d,r10d
    sub r15d,ecx
    mov ecx,r15d
    shr eax,cl
    and eax,r11d
    mov r15d,eax
    mov rcx,[rsp+16]
    cmp byte [rcx + PngImage.color_type],3
    je .packed_palette
    imul eax,r9d
    mov [rdx+r8*4],al
    mov [rdx+r8*4+1],al
    mov [rdx+r8*4+2],al
    mov byte [rdx+r8*4+3],255
    mov rax,[rcx + PngImage.transparency]
    test rax,rax
    jz .packed_next
    movzx ecx,word [rax]
    rol cx,8
    cmp r15d,ecx
    jne .packed_next
    mov byte [rdx+r8*4+3],0
    jmp .packed_next
.packed_palette:
    cmp r15,[rcx + PngImage.palette_entries]
    jae .packed_bad
    mov rax,[rcx + PngImage.palette]
    lea r15,[r15+r15*2]
    mov cl,[rax+r15]
    mov [rdx+r8*4+2],cl
    mov cl,[rax+r15+1]
    mov [rdx+r8*4+1],cl
    mov cl,[rax+r15+2]
    mov [rdx+r8*4],cl
    mov byte [rdx+r8*4+3],255
    mov rcx,[rsp+16]
    mov r9,[rcx + PngImage.transparency]
    test r9,r9
    jz .packed_next
    mov eax,r8d
    imul eax,r10d
    mov ecx,eax
    and ecx,7
    shr eax,3
    movzx r15d,byte [rsi+rax]
    mov eax,8
    sub eax,r10d
    sub eax,ecx
    mov ecx,eax
    shr r15d,cl
    and r15d,r11d
    mov rcx,[rsp+16]
    cmp r15,[rcx + PngImage.transparency_len]
    jae .packed_next
    mov al,[r9+r15]
    mov [rdx+r8*4+3],al
.packed_next:
    inc r8d
    jmp .x_packed
.packed_done:
    pop r15
    pop rcx
    jmp .next_row
.packed_bad:
    pop r15
    pop rcx
    jmp .bad_convert
.row_16:
    movzx eax,byte [rax + PngImage.color_type]
    cmp eax,6
    je .row_rgba16
    cmp eax,2
    je .row_rgb16
    cmp eax,4
    je .row_gray_alpha16
.x_gray16:
    cmp r8d,r14d
    jae .next_row
    mov rax,r8
    shl rax,1
    mov al,[rsi+rax]
    mov [rdx+r8*4],al
    mov [rdx+r8*4+1],al
    mov [rdx+r8*4+2],al
    mov byte [rdx+r8*4+3],255
    mov r10,[rsp]
    mov r10,[r10 + PngImage.transparency]
    test r10,r10
    jz .gray16_next
    mov r9w,[rsi+rax]
    cmp r9w,[r10]
    jne .gray16_next
    mov byte [rdx+r8*4+3],0
.gray16_next:
    inc r8d
    jmp .x_gray16
.row_gray_alpha16:
.x_gray_alpha16:
    cmp r8d,r14d
    jae .next_row
    mov rax,r8
    shl rax,2
    mov r9b,[rsi+rax]
    mov [rdx+r8*4],r9b
    mov [rdx+r8*4+1],r9b
    mov [rdx+r8*4+2],r9b
    mov r9b,[rsi+rax+2]
    mov [rdx+r8*4+3],r9b
    inc r8d
    jmp .x_gray_alpha16
.row_rgb16:
.x_rgb16:
    cmp r8d,r14d
    jae .next_row
    mov rax,r8
    imul rax,6
    mov r9b,[rsi+rax]
    mov [rdx+r8*4+2],r9b
    mov r9b,[rsi+rax+2]
    mov [rdx+r8*4+1],r9b
    mov r9b,[rsi+rax+4]
    mov [rdx+r8*4],r9b
    mov byte [rdx+r8*4+3],255
    mov r10,[rsp]
    mov r10,[r10 + PngImage.transparency]
    test r10,r10
    jz .rgb16_next
    mov r9w,[rsi+rax]
    cmp r9w,[r10]
    jne .rgb16_next
    mov r9w,[rsi+rax+2]
    cmp r9w,[r10+2]
    jne .rgb16_next
    mov r9w,[rsi+rax+4]
    cmp r9w,[r10+4]
    jne .rgb16_next
    mov byte [rdx+r8*4+3],0
.rgb16_next:
    inc r8d
    jmp .x_rgb16
.row_rgba16:
.x_rgba16:
    cmp r8d,r14d
    jae .next_row
    mov rax,r8
    shl rax,3
    mov r9b,[rsi+rax]
    mov [rdx+r8*4+2],r9b
    mov r9b,[rsi+rax+2]
    mov [rdx+r8*4+1],r9b
    mov r9b,[rsi+rax+4]
    mov [rdx+r8*4],r9b
    mov r9b,[rsi+rax+6]
    mov [rdx+r8*4+3],r9b
    inc r8d
    jmp .x_rgba16
.row_gray_alpha:
.x_gray_alpha:
    cmp r8d,r14d
    jae .next_row
    mov r9,r8
    shl r9,1
    movzx eax,byte [rsi+r9]
    mov [rdx+r8*4],al
    mov [rdx+r8*4+1],al
    mov [rdx+r8*4+2],al
    mov al,[rsi+r9+1]
    mov [rdx+r8*4+3],al
    inc r8d
    jmp .x_gray_alpha
.row_palette:
    mov rax,[rsp]
    mov r9,[rax + PngImage.palette]
    mov r10,[rax + PngImage.palette_entries]
    mov r11,[rax + PngImage.transparency]
    push rcx
    push r15
.x_palette:
    cmp r8d,r14d
    jae .palette_row_done
    movzx eax,byte [rsi+r8]
    cmp rax,r10
    jae .palette_bad
    lea r15,[rax+rax*2]
    mov cl,[r9+r15]
    mov [rdx+r8*4+2],cl
    mov cl,[r9+r15+1]
    mov [rdx+r8*4+1],cl
    mov cl,[r9+r15+2]
    mov [rdx+r8*4],cl
    mov byte [rdx+r8*4+3],255
    test r11,r11
    jz .palette_next
    mov rcx,[rsp+16]
    cmp rax,[rcx + PngImage.transparency_len]
    jae .palette_next
    mov cl,[r11+rax]
    mov [rdx+r8*4+3],cl
.palette_next:
    inc r8d
    jmp .x_palette
.palette_row_done:
    pop r15
    pop rcx
    jmp .next_row
.palette_bad:
    pop r15
    pop rcx
    jmp .bad_convert
.row_rgba:
.x_rgba:
    cmp r8d, r14d
    jae .next_row
    mov eax, [rsi + r8 * 4]
    mov r9d, eax
    shr r9d, 16
    and r9d, 0xFF
    mov r10d, eax
    and r10d, 0xFF
    mov [rdx + r8 * 4], r9b
    shr eax, 8
    mov [rdx + r8 * 4 + 1], al
    mov [rdx + r8 * 4 + 2], r10b
    shr eax, 16
    mov [rdx + r8 * 4 + 3], al
    inc r8d
    jmp .x_rgba
.row_rgb:
.x_rgb:
    cmp r8d, r14d
    jae .next_row
    mov rax,r8
    lea rax,[rax+rax*2]
    movzx r9d,byte [rsi+rax]
    mov [rdx+r8*4+2],r9b
    movzx r9d,byte [rsi+rax+1]
    mov [rdx + r8 * 4 + 1], r9b
    movzx r9d,byte [rsi+rax+2]
    mov [rdx + r8 * 4], r9b
    mov byte [rdx + r8 * 4 + 3], 255
    mov r10,[rsp]
    mov r10,[r10 + PngImage.transparency]
    test r10,r10
    jz .rgb_next
    mov r9b,[rsi+rax]
    cmp r9b,[r10+1]
    jne .rgb_next
    mov r9b,[rsi+rax+1]
    cmp r9b,[r10+3]
    jne .rgb_next
    mov r9b,[rsi+rax+2]
    cmp r9b,[r10+5]
    jne .rgb_next
    mov byte [rdx+r8*4+3],0
.rgb_next:
    inc r8d
    jmp .x_rgb
.next_row:
    inc ecx
    jmp .y_loop
.done:
    mov rax, rbx
    add rsp,8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_convert:
    xor eax,eax
    add rsp,8
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

section .data
global png_filter_version
png_filter_version: dq 0x010000
