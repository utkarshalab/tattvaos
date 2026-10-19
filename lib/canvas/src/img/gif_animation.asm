; ============================================================================
; GIF Animation — frame iteration, disposal, compositing, snapshots
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

extern arena_alloc
extern memcopy
extern pixbuf_create
extern fill_solid
extern gif_inspect_animation
extern gif_decode_first
extern gif_apply_disposal
extern gif_clone_canvas
extern gif_composite_canvas

section .text

; IN rdi=arena, rsi=data, rdx=len. OUT rax=GifAnimation* or 0.
global gif_decode_animation
gif_decode_animation:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 160
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    lea rdx, [rsp]
    mov rdi, r12
    mov rsi, r13
    call gif_inspect_animation
    test rax, rax
    jnz .fail

    mov rdi, rbx
    mov esi, GifAnimation_size
    call arena_alloc
    test rax, rax
    jz .fail
    mov r15, rax
    mov eax, [rsp + GifAnimationInfo.width]
    mov [r15 + GifAnimation.width], eax
    mov eax, [rsp + GifAnimationInfo.height]
    mov [r15 + GifAnimation.height], eax
    mov eax, [rsp + GifAnimationInfo.frame_count]
    mov [r15 + GifAnimation.frame_count], eax
    mov eax, [rsp + GifAnimationInfo.loop_count]
    mov [r15 + GifAnimation.loop_count], eax
    mov rax, [rsp + GifAnimationInfo.duration_cs]
    mov [r15 + GifAnimation.duration_cs], rax
    mov [r15 + GifAnimation.arena], rbx

    mov edi, [r15 + GifAnimation.frame_count]
    lea rsi, [rdi * 8]
    mov rdi, rbx
    call arena_alloc
    test rax, rax
    jz .fail
    mov [r15 + GifAnimation.frames], rax
    mov edi, [r15 + GifAnimation.frame_count]
    lea rsi, [rdi * 4]
    mov rdi, rbx
    call arena_alloc
    test rax, rax
    jz .fail
    mov [r15 + GifAnimation.delays_cs], rax
    mov esi, [r15 + GifAnimation.frame_count]
    mov rdi, rbx
    call arena_alloc
    test rax, rax
    jz .fail
    mov [r15 + GifAnimation.disposals], rax

    ; Prefix is header + logical screen descriptor + global color table.
    movzx eax, byte [r12 + 10]
    mov qword [rsp + 24], 13
    mov qword [rsp + 32], 0         ; global palette
    mov qword [rsp + 40], 0         ; palette entries
    test al, 0x80
    jz .prefix_ready
    mov ecx, eax
    and ecx, 7
    mov eax, 2
    shl eax, cl
    mov [rsp + 40], rax
    lea rcx, [rax + rax * 2]
    add [rsp + 24], rcx
    lea rax, [r12 + 13]
    mov [rsp + 32], rax
.prefix_ready:
    mov rax, [rsp + 24]
    cmp rax, r13
    ja .fail
    lea r14, [r12 + rax]
    mov [rsp + 104], r13
    sub [rsp + 104], rax

    ; Resolve logical-screen background color.
    mov dword [rsp + 92], 0
    mov rax, [rsp + 32]
    test rax, rax
    jz .canvas
    movzx ecx, byte [r12 + 11]
    cmp rcx, [rsp + 40]
    jae .canvas
    lea rax, [rax + rcx * 2]
    add rax, rcx
    movzx edx, byte [rax + 2]
    shl edx, 16
    mov dh, [rax + 1]
    mov dl, [rax]
    or edx, 0xFF000000
    mov [rsp + 92], edx
.canvas:
    mov rdi, rbx
    mov esi, [r15 + GifAnimation.width]
    mov edx, [r15 + GifAnimation.height]
    mov ecx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jle .fail
    mov [rsp + 56], rax             ; working canvas
    mov rdi, [rax + PixBuf_data]
    mov esi, [rsp + 92]
    mov edx, [r15 + GifAnimation.width]
    mov ecx, [r15 + GifAnimation.height]
    mov r8, [rax + PixBuf_stride]
    call fill_solid
    mov qword [rsp + 48], 0         ; pending GCE pointer
    mov qword [rsp + 64], 0         ; saved pre-frame canvas
    mov dword [rsp + 88], 0         ; previous disposal
    mov dword [rsp + 128], 0        ; previous left
    mov dword [rsp + 132], 0        ; previous top
    mov dword [rsp + 136], 0        ; previous width
    mov dword [rsp + 140], 0        ; previous height
    mov dword [rsp + 96], 0         ; frame index

.blocks:
    mov r11, [rsp + 104]
    test r11, r11
    jz .fail
    movzx eax, byte [r14]
    cmp al, 0x3B
    je .done
    cmp al, 0x2C
    je .image
    cmp al, 0x21
    jne .fail
    cmp r11, 2
    jb .fail
    cmp byte [r14 + 1], 0xF9
    jne .skip_extension
    cmp r11, 8
    jb .fail
    cmp byte [r14 + 2], 4
    jne .fail
    cmp byte [r14 + 7], 0
    jne .fail
    mov [rsp + 48], r14
    add r14, 8
    sub qword [rsp + 104], 8
    jmp .blocks
.skip_extension:
    add r14, 2
    sub qword [rsp + 104], 2
.skip_subblocks:
    cmp qword [rsp + 104], 0
    je .fail
    movzx eax, byte [r14]
    inc r14
    dec qword [rsp + 104]
    test eax, eax
    jz .blocks
    cmp rax, [rsp + 104]
    ja .fail
    add r14, rax
    sub [rsp + 104], rax
    jmp .skip_subblocks

.image:
    mov r10, r14                    ; image block start
    mov r11, [rsp + 104]
    cmp r11, 11
    jb .fail
    movzx eax, word [r14 + 1]
    mov [rsp + 72], eax
    movzx eax, word [r14 + 3]
    mov [rsp + 76], eax
    movzx eax, word [r14 + 5]
    mov [rsp + 80], eax
    movzx eax, word [r14 + 7]
    mov [rsp + 84], eax
    movzx eax, byte [r14 + 9]
    add r14, 10
    sub qword [rsp + 104], 10
    test al, 0x80
    jz .image_codes
    mov ecx, eax
    and ecx, 7
    mov eax, 6
    shl eax, cl
    cmp [rsp + 104], rax
    jb .fail
    add r14, rax
    sub [rsp + 104], rax
.image_codes:
    cmp qword [rsp + 104], 2
    jb .fail
    inc r14                         ; minimum code size
    dec qword [rsp + 104]
.find_image_end:
    cmp qword [rsp + 104], 0
    je .fail
    movzx eax, byte [r14]
    inc r14
    dec qword [rsp + 104]
    test eax, eax
    jz .have_image
    cmp rax, [rsp + 104]
    ja .fail
    add r14, rax
    sub [rsp + 104], rax
    jmp .find_image_end
.have_image:
    mov [rsp + 112], r10            ; preserve start across calls
    mov [rsp + 120], r14            ; next block

    ; Dispose the previous displayed frame before drawing this one.
    mov rdi, [rsp + 56]
    mov rsi, [rsp + 64]
    mov edx, [rsp + 128]
    mov ecx, [rsp + 132]
    mov r8d, [rsp + 136]
    mov r9d, [rsp + 140]
    mov r10d, [rsp + 88]
    mov r11d, [rsp + 92]
    test r10d, r10d
    jz .current_gce
    call gif_apply_disposal
    test rax, rax
    jnz .fail
.current_gce:
    xor eax, eax
    xor edx, edx                    ; delay
    mov rsi, [rsp + 48]
    test rsi, rsi
    jz .gce_ready
    movzx eax, byte [rsi + 3]
    shr eax, 2
    and eax, 7                      ; disposal
    movzx edx, word [rsi + 4]
.gce_ready:
    mov [rsp + 88], eax
    mov ecx, [rsp + 96]
    mov rdi, [r15 + GifAnimation.delays_cs]
    mov [rdi + rcx * 4], edx
    mov rdi, [r15 + GifAnimation.disposals]
    mov [rdi + rcx], al

    ; Method 3 snapshots the canvas before the current frame is drawn.
    mov qword [rsp + 64], 0
    cmp eax, 3
    jne .build_frame
    mov rdi, rbx
    mov rsi, [rsp + 56]
    call gif_clone_canvas
    test rax, rax
    jle .fail
    mov [rsp + 64], rax
.build_frame:
    mov rax, [rsp + 120]
    sub rax, [rsp + 112]            ; image block length
    mov rcx, [rsp + 24]
    add rcx, rax
    cmp qword [rsp + 48], 0
    je .frame_size
    add rcx, 8
.frame_size:
    inc rcx                         ; trailer
    mov [rsp + 16], rcx
    mov rdi, rbx
    mov rsi, rcx
    call arena_alloc
    test rax, rax
    jz .fail
    mov [rsp + 8], rax
    mov rdi, rax
    mov rsi, r12
    mov rdx, [rsp + 24]
    call memcopy
    mov rdi, [rsp + 8]
    add rdi, [rsp + 24]
    mov rsi, [rsp + 48]
    test rsi, rsi
    jz .copy_image
    mov edx, 8
    call memcopy
    add qword [rsp + 24], 8         ; temporary destination offset
.copy_image:
    mov rdi, [rsp + 8]
    add rdi, [rsp + 24]
    mov rsi, [rsp + 112]
    mov rdx, [rsp + 120]
    sub rdx, rsi
    call memcopy
    mov rdi, [rsp + 8]
    mov rcx, [rsp + 16]
    mov byte [rdi + rcx - 1], 0x3B
    cmp qword [rsp + 48], 0
    je .decode_frame
    sub qword [rsp + 24], 8         ; restore prefix length
.decode_frame:
    mov rdi, rbx
    mov rsi, [rsp + 8]
    mov rdx, [rsp + 16]
    call gif_decode_first
    test rax, rax
    jz .fail
    mov rsi, rax
    mov rdi, [rsp + 56]
    call gif_composite_canvas
    test rax, rax
    jnz .fail
    mov rdi, rbx
    mov rsi, [rsp + 56]
    call gif_clone_canvas
    test rax, rax
    jle .fail
    mov ecx, [rsp + 96]
    mov rdi, [r15 + GifAnimation.frames]
    mov [rdi + rcx * 8], rax
    mov eax, [rsp + 72]
    mov [rsp + 128], eax
    mov eax, [rsp + 76]
    mov [rsp + 132], eax
    mov eax, [rsp + 80]
    mov [rsp + 136], eax
    mov eax, [rsp + 84]
    mov [rsp + 140], eax
    inc dword [rsp + 96]
    mov qword [rsp + 48], 0
    mov r14, [rsp + 120]
    jmp .blocks

.done:
    mov eax, [rsp + 96]
    cmp eax, [r15 + GifAnimation.frame_count]
    jne .fail
    mov rax, r15
    jmp .out
.fail:
    xor eax, eax
.out:
    add rsp, 160
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global gif_animation_version
gif_animation_version: dq 0x010000
