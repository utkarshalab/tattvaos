; ============================================================================
; GIF — GIF89a Decoder (first frame, palette + LZW + transparency)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/image.inc"

extern arena_alloc
extern lzw_decode_gif
extern memcopy
extern pixbuf_create
extern fill_solid
extern blit_copy

section .text

; ---------------------------------------------------------------------------
; gif_probe
; ---------------------------------------------------------------------------
global gif_probe
gif_probe:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 6
    jb .no
    mov eax, [rdi]
    cmp eax, 0x38464947  ; "GIF8"
    jne .no
    movzx eax, word [rdi + 4]
    cmp ax, 0x6137  ; "7a"
    je .yes
    cmp ax, 0x6139  ; "9a"
    je .yes
.no:
    xor rax, rax
    leave
    ret
.yes:
    mov rax, 1
    leave
    ret

; Validate the complete GIF block stream and return animation metadata.
; IN rdi=data, rsi=len, rdx=GifAnimationInfo*. OUT rax=0 or negative errno.
global gif_inspect_animation
gif_inspect_animation:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    ASSERT_PTR r12
    ASSERT_PTR r14
    cmp r13, 13
    jb .inspect_invalid
    mov rdi, r12
    mov rsi, r13
    call gif_probe
    test eax, eax
    jz .inspect_invalid
    movzx eax, word [r12 + 6]
    test eax, eax
    jz .inspect_invalid
    mov [r14 + GifAnimationInfo.width], eax
    movzx eax, word [r12 + 8]
    test eax, eax
    jz .inspect_invalid
    mov [r14 + GifAnimationInfo.height], eax
    mov dword [r14 + GifAnimationInfo.frame_count], 0
    mov dword [r14 + GifAnimationInfo.loop_count], 1
    mov qword [r14 + GifAnimationInfo.duration_cs], 0
    mov dword [rsp], 0
    movzx eax, byte [r12 + 10]
    lea r12, [r12 + 13]
    sub r13, 13
    test al, 0x80
    jz .inspect_blocks
    mov ecx, eax
    and ecx, 7
    mov eax, 6
    shl eax, cl
    cmp r13, rax
    jb .inspect_invalid
    add r12, rax
    sub r13, rax
.inspect_blocks:
    test r13, r13
    jz .inspect_invalid
    movzx eax, byte [r12]
    cmp al, 0x3B
    je .inspect_trailer
    cmp al, 0x2C
    je .inspect_image
    cmp al, 0x21
    jne .inspect_invalid
    cmp r13, 2
    jb .inspect_invalid
    movzx eax, byte [r12 + 1]
    cmp al, 0xF9
    je .inspect_gce
    cmp al, 0xFF
    je .inspect_application
    add r12, 2
    sub r13, 2
    jmp .inspect_skip_subblocks
.inspect_gce:
    cmp r13, 8
    jb .inspect_invalid
    cmp byte [r12 + 2], 4
    jne .inspect_invalid
    cmp byte [r12 + 7], 0
    jne .inspect_invalid
    movzx eax, word [r12 + 4]
    mov [rsp], eax
    add r12, 8
    sub r13, 8
    jmp .inspect_blocks
.inspect_application:
    cmp r13, 19
    jb .inspect_generic_extension
    cmp byte [r12 + 2], 11
    jne .inspect_generic_extension
    cmp dword [r12 + 3], 0x5354454E
    jne .inspect_generic_extension
    cmp dword [r12 + 7], 0x45504143
    jne .inspect_generic_extension
    cmp word [r12 + 11], 0x2E32
    jne .inspect_generic_extension
    cmp byte [r12 + 13], 0x30
    jne .inspect_generic_extension
    cmp byte [r12 + 14], 3
    jne .inspect_generic_extension
    cmp byte [r12 + 15], 1
    jne .inspect_generic_extension
    cmp byte [r12 + 18], 0
    jne .inspect_generic_extension
    movzx eax, word [r12 + 16]
    mov [r14 + GifAnimationInfo.loop_count], eax
    add r12, 19
    sub r13, 19
    jmp .inspect_blocks
.inspect_generic_extension:
    add r12, 2
    sub r13, 2
.inspect_skip_subblocks:
    test r13, r13
    jz .inspect_invalid
    movzx eax, byte [r12]
    inc r12
    dec r13
    test eax, eax
    jz .inspect_blocks
    cmp rax, r13
    ja .inspect_invalid
    add r12, rax
    sub r13, rax
    jmp .inspect_skip_subblocks
.inspect_image:
    cmp r13, 11
    jb .inspect_invalid
    movzx eax, word [r12 + 5]
    test eax, eax
    jz .inspect_invalid
    movzx edx, word [r12 + 1]
    add edx, eax
    jc .inspect_invalid
    cmp edx, [r14 + GifAnimationInfo.width]
    ja .inspect_invalid
    movzx eax, word [r12 + 7]
    test eax, eax
    jz .inspect_invalid
    movzx edx, word [r12 + 3]
    add edx, eax
    jc .inspect_invalid
    cmp edx, [r14 + GifAnimationInfo.height]
    ja .inspect_invalid
    movzx eax, byte [r12 + 9]
    add r12, 10
    sub r13, 10
    test al, 0x80
    jz .inspect_image_data
    mov ecx, eax
    and ecx, 7
    mov eax, 6
    shl eax, cl
    cmp r13, rax
    jb .inspect_invalid
    add r12, rax
    sub r13, rax
.inspect_image_data:
    cmp r13, 2
    jb .inspect_invalid
    movzx eax, byte [r12]
    cmp eax, 2
    jb .inspect_invalid
    cmp eax, 8
    ja .inspect_invalid
    inc r12
    dec r13
    inc dword [r14 + GifAnimationInfo.frame_count]
    mov eax, [rsp]
    add [r14 + GifAnimationInfo.duration_cs], rax
    mov dword [rsp], 0
    jmp .inspect_skip_subblocks
.inspect_trailer:
    cmp dword [r14 + GifAnimationInfo.frame_count], 0
    jz .inspect_invalid
    xor eax, eax
    jmp .inspect_out
.inspect_invalid:
    mov rax, -EINVAL
.inspect_out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; Apply the previous frame's disposal before drawing the next frame.
; rdi=canvas, rsi=saved canvas (method 3), rdx=left, rcx=top,
; r8=width, r9=height, r10=method, r11d=background BGRA.
global gif_apply_disposal
gif_apply_disposal:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    test r15, r15
    jz .dispose_invalid
    test r9, r9
    jz .dispose_invalid
    mov rax, r13
    add rax, r15
    jc .dispose_invalid
    cmp rax, [rbx + PixBuf_width]
    ja .dispose_invalid
    mov rax, r14
    add rax, r9
    jc .dispose_invalid
    cmp rax, [rbx + PixBuf_height]
    ja .dispose_invalid
    cmp r10d, 1
    jbe .dispose_keep
    cmp r10d, 2
    je .dispose_background
    cmp r10d, 3
    je .dispose_restore
.dispose_invalid:
    mov rax, -EINVAL
    jmp .dispose_out
.dispose_keep:
    xor eax, eax                    ; methods 0/1 retain the canvas
    jmp .dispose_out
.dispose_background:
    mov rax, r14
    imul rax, [rbx + PixBuf_stride]
    add rax, [rbx + PixBuf_data]
    lea rdi, [rax + r13 * 4]
    mov esi, r11d
    mov rdx, r15
    mov rcx, r9
    mov r8, [rbx + PixBuf_stride]
    call fill_solid
    jmp .dispose_out
.dispose_restore:
    test r12, r12
    jz .dispose_invalid
    mov rax, r14
    imul rax, [rbx + PixBuf_stride]
    add rax, [rbx + PixBuf_data]
    lea rdi, [rax + r13 * 4]
    mov rax, r14
    imul rax, [r12 + PixBuf_stride]
    add rax, [r12 + PixBuf_data]
    lea rsi, [rax + r13 * 4]
    mov rdx, r15
    mov rcx, r9
    mov r8, [rbx + PixBuf_stride]
    mov r9, [r12 + PixBuf_stride]
    call blit_copy
    jmp .dispose_out
.dispose_out:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; Clone a canvas for animation snapshots or disposal method 3.
; IN rdi=arena, rsi=PixBuf*. OUT rax=new PixBuf* or negative errno.
global gif_clone_canvas
gif_clone_canvas:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, [r12 + PixBuf_width]
    mov rdx, [r12 + PixBuf_height]
    mov rcx, [r12 + PixBuf_format]
    call pixbuf_create
    test rax, rax
    js .clone_out
    jz .clone_oom
    mov r13, rax
    mov rdi, [r13 + PixBuf_data]
    mov rsi, [r12 + PixBuf_data]
    mov rdx, [r12 + PixBuf_width]
    mov rcx, [r12 + PixBuf_height]
    mov r8, [r13 + PixBuf_stride]
    mov r9, [r12 + PixBuf_stride]
    call blit_copy
    test rax, rax
    jnz .clone_out
    mov rax, r13
    jmp .clone_out
.clone_oom:
    mov rax, -ENOMEM
.clone_out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; Composite an equally-sized transparent GIF frame over the working canvas.
; Pixels emitted by gif_decode_first are either transparent or opaque.
global gif_composite_canvas
gif_composite_canvas:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [rbx + PixBuf_width]
    cmp rax, [r12 + PixBuf_width]
    jne .composite_invalid
    mov r13, [rbx + PixBuf_height]
    cmp r13, [r12 + PixBuf_height]
    jne .composite_invalid
    xor r14d, r14d
.composite_row:
    cmp r14, r13
    jae .composite_done
    mov rax, r14
    imul rax, [rbx + PixBuf_stride]
    add rax, [rbx + PixBuf_data]
    mov rdi, rax
    mov rax, r14
    imul rax, [r12 + PixBuf_stride]
    add rax, [r12 + PixBuf_data]
    mov rsi, rax
    xor r15d, r15d
.composite_pixel:
    cmp r15, [rbx + PixBuf_width]
    jae .composite_next_row
    mov eax, [rsi + r15 * 4]
    test eax, 0xFF000000
    jz .composite_skip
    mov [rdi + r15 * 4], eax
.composite_skip:
    inc r15
    jmp .composite_pixel
.composite_next_row:
    inc r14
    jmp .composite_row
.composite_done:
    xor eax, eax
    jmp .composite_out
.composite_invalid:
    mov rax, -EINVAL
.composite_out:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; gif_decode_first
;   IN: rdi = arena, rsi = data, rdx = len — OUT: rax = PixBuf*
; ---------------------------------------------------------------------------
global gif_decode_first
gif_decode_first:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r13, 13
    jb .new_bad
    mov rdi, r12
    mov rsi, r13
    call gif_probe
    test rax, rax
    jz .new_bad
    sub rsp, 96
    movzx eax, word [r12 + 6]
    mov [rsp], eax              ; canvas width
    movzx eax, word [r12 + 8]
    mov [rsp + 4], eax          ; canvas height
    test dword [rsp], 0xFFFFFFFF
    jz .new_bad_stack
    test dword [rsp + 4], 0xFFFFFFFF
    jz .new_bad_stack
    mov qword [rsp + 24], 0     ; palette
    mov qword [rsp + 32], 0     ; palette entries
    mov qword [rsp + 40], -1    ; transparent index
    movzx eax, byte [r12 + 10]
    lea r14, [r12 + 13]
    lea r15, [r13 - 13]
    test al, 0x80
    jz .new_scan
    mov ecx, eax
    and ecx, 7
    mov eax, 2
    shl eax, cl
    mov [rsp + 32], rax
    mov [rsp + 24], r14
    lea rdx, [rax + rax * 2]
    cmp r15, rdx
    jb .new_bad_stack
    add r14, rdx
    sub r15, rdx
.new_scan:
    cmp r15, 2
    jb .new_bad_stack
    cmp byte [r14], 0x2C
    je .new_descriptor
    cmp byte [r14], 0x3B
    je .new_bad_stack
    cmp byte [r14], 0x21
    jne .new_bad_stack
    cmp r15, 8
    jb .new_bad_stack
    cmp byte [r14 + 1], 0xF9
    jne .new_skip_extension
    cmp byte [r14 + 2], 4
    jne .new_skip_extension
    test byte [r14 + 3], 1
    jz .new_skip_extension
    movzx eax, byte [r14 + 6]
    mov [rsp + 40], rax
.new_skip_extension:
    add r14, 2
    sub r15, 2
.new_skip_subblocks:
    test r15, r15
    jz .new_bad_stack
    movzx eax, byte [r14]
    inc r14
    dec r15
    test eax, eax
    jz .new_scan
    cmp rax, r15
    ja .new_bad_stack
    add r14, rax
    sub r15, rax
    jmp .new_skip_subblocks
.new_descriptor:
    cmp r15, 11
    jb .new_bad_stack
    movzx eax, word [r14 + 1]
    mov [rsp + 8], eax          ; left
    movzx eax, word [r14 + 3]
    mov [rsp + 12], eax         ; top
    movzx eax, word [r14 + 5]
    mov [rsp + 16], eax         ; image width
    movzx eax, word [r14 + 7]
    mov [rsp + 20], eax         ; image height
    movzx eax, byte [r14 + 9]
    mov [rsp + 44], eax         ; packed/interlace
    mov ecx,[rsp + 8]
    add ecx,[rsp + 16]
    jc .new_bad_stack
    cmp ecx,[rsp]
    ja .new_bad_stack
    mov ecx,[rsp + 12]
    add ecx,[rsp + 20]
    jc .new_bad_stack
    cmp ecx,[rsp + 4]
    ja .new_bad_stack
    add r14, 10
    sub r15, 10
    test al, 0x80
    jz .new_palette_ready
    mov ecx, eax
    and ecx, 7
    mov eax, 2
    shl eax, cl
    mov [rsp + 32], rax
    mov [rsp + 24], r14
    lea rdx, [rax + rax * 2]
    cmp r15, rdx
    jb .new_bad_stack
    add r14, rdx
    sub r15, rdx
.new_palette_ready:
    cmp qword [rsp + 24], 0
    je .new_bad_stack
    cmp r15, 2
    jb .new_bad_stack
    movzx eax, byte [r14]
    mov [rsp + 48], eax         ; minimum code size
    inc r14
    dec r15
    mov rdi, rbx
    mov rsi, r15
    call arena_alloc
    test rax, rax
    jz .new_oom_stack
    mov [rsp + 56], rax
    xor r13d, r13d
.new_gather:
    test r15, r15
    jz .new_bad_stack
    movzx eax, byte [r14]
    inc r14
    dec r15
    test eax, eax
    jz .new_gathered
    cmp rax, r15
    ja .new_bad_stack
    mov rdi, [rsp + 56]
    add rdi, r13
    mov rsi, r14
    mov rdx, rax
    push rax
    call memcopy
    pop rax
    add r13, rax
    add r14, rax
    sub r15, rax
    jmp .new_gather
.new_gathered:
    mov eax, [rsp + 16]
    mov ecx, [rsp + 20]               ; height is a dword; palette follows it
    imul rax, rcx
    test rax, rax
    jz .new_bad_stack
    mov [rsp + 64], rax
    mov rdi, rbx
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .new_oom_stack
    mov [rsp + 72], rax
    mov rdi, rbx
    mov rsi, [rsp + 56]
    mov rdx, r13
    mov rcx, [rsp + 48]
    mov r8, [rsp + 72]
    mov r9, [rsp + 64]
    call lzw_decode_gif
    test rax, rax
    js .new_bad_stack                 ; negative errno
    cmp rax, [rsp + 64]
    jb .new_bad_stack
    mov rdi, rbx
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .new_oom_stack
    js .new_oom_stack
    mov [rsp + 80], rax
    mov rdi, [rax + PixBuf_data]
    xor esi, esi
    mov edx, [rsp]
    mov ecx, [rsp + 4]
    mov r8, [rax + PixBuf_stride]
    call fill_solid
    xor r13d, r13d             ; image y
.new_row:
    cmp r13d, [rsp + 20]
    jae .new_done
    mov eax,r13d
    test byte [rsp + 44],0x40
    jz .new_row_mapped
    mov ecx,[rsp + 20]
    add ecx,7
    shr ecx,3
    cmp eax,ecx
    jb .new_pass1
    sub eax,ecx
    mov ecx,[rsp + 20]
    add ecx,3
    shr ecx,3
    cmp eax,ecx
    jb .new_pass2
    sub eax,ecx
    mov ecx,[rsp + 20]
    add ecx,1
    shr ecx,2
    cmp eax,ecx
    jb .new_pass3
    sub eax,ecx
    lea eax,[rax*2+1]
    jmp .new_row_mapped
.new_pass1:
    shl eax,3
    jmp .new_row_mapped
.new_pass2:
    lea eax,[rax*8+4]
    jmp .new_row_mapped
.new_pass3:
    lea eax,[rax*4+2]
.new_row_mapped:
    mov [rsp + 88],eax
    xor r14d, r14d             ; image x
.new_pixel:
    cmp r14d, [rsp + 16]
    jae .new_next_row
    mov eax, r13d
    imul eax, [rsp + 16]
    add eax, r14d
    mov rdx, [rsp + 72]
    movzx ecx, byte [rdx + rax]
    cmp rcx, [rsp + 40]
    je .new_next_pixel
    cmp rcx, [rsp + 32]
    jae .new_next_pixel
    mov rdx, [rsp + 24]
    lea rdx, [rdx + rcx * 2]
    add rdx, rcx                      ; palette entry: R, G, B
    movzx eax, byte [rdx]
    shl eax, 16                       ; R into byte 2 of BGRA
    mov ah, [rdx + 1]
    mov al, [rdx + 2]
    or eax, 0xFF000000
    mov rdx, [rsp + 80]
    mov rdi, [rdx + PixBuf_data]
    mov ecx, [rsp + 88]
    add ecx, [rsp + 12]
    imul rcx, [rdx + PixBuf_stride]
    add rdi, rcx
    mov ecx, r14d
    add ecx, [rsp + 8]
    mov [rdi + rcx * 4], eax
.new_next_pixel:
    inc r14d
    jmp .new_pixel
.new_next_row:
    inc r13d
    jmp .new_row
.new_done:
    mov rax, [rsp + 80]
    add rsp, 96
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.new_bad_stack:
.new_oom_stack:
    add rsp, 96
.new_bad:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global gif_version
gif_version: dq 0x010000
