; ============================================================================
; PNG Filter - Unfilter Scanlines (None/Sub/Up/Average/Paeth) + BGRA Convert
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"

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
    ret
.bad:
    RETURN_ERROR EINVAL

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
    mov r10d, eax
    mov eax, r14d
    imul eax, r10d
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
    ja .bad
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
    ret
.bad2:
    add rsp, 16
.bad:
    xor rax, rax
    ret
.oom:
    add rsp, 8
    xor rax, rax
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
    movzx eax, byte [r12 + PngImage.channels]
    mov r10d, eax
    mov eax, r14d
    imul eax, r10d
    inc eax
    mov r11d, eax
    mov r12, [rbx + PixBuf.data]
    mov rdi, [rbx + PixBuf.stride]
    xor ecx, ecx
.y_loop:
    cmp ecx, r15d
    jae .done
    mov eax, ecx
    imul eax, r11d
    lea rsi, [r13 + rax]
    mov eax, ecx
    imul eax, edi
    lea rdx, [r12 + rax]
    xor r8d, r8d
    cmp r10d, 4
    je .row_rgba
    cmp r10d, 3
    je .row_rgb
.x_gray:
    cmp r8d, r14d
    jae .next_row
    movzx eax, byte [rsi + r8]
    mov [rdx + r8 * 4], al
    mov [rdx + r8 * 4 + 1], al
    mov [rdx + r8 * 4 + 2], al
    mov byte [rdx + r8 * 4 + 3], 255
    inc r8d
    jmp .x_gray
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
    mov [rdx + r8 * 4 + 3], ah
    inc r8d
    jmp .x_rgba
.row_rgb:
.x_rgb:
    cmp r8d, r14d
    jae .next_row
    movzx eax, byte [rsi + r8 * 3]
    movzx r9d, byte [rsi + r8 * 3 + 1]
    movzx r10d, byte [rsi + r8 * 3 + 2]
    mov [rdx + r8 * 4], r10b
    mov [rdx + r8 * 4 + 1], r9b
    mov [rdx + r8 * 4 + 2], al
    mov byte [rdx + r8 * 4 + 3], 255
    inc r8d
    jmp .x_rgb
.next_row:
    inc ecx
    jmp .y_loop
.done:
    mov rax, rbx
    ret

section .data
global png_filter_version
png_filter_version: dq 0x010000
