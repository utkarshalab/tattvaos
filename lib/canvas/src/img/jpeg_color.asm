; ============================================================================
; JPEG Color Conversion — full-range YCbCr samples to opaque BGRA
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

section .text

; rdi=BGRA destination, rsi=int16 Y, rdx=int16 Cb, rcx=int16 Cr, r8=count
global jpeg_ycbcr_to_bgra
jpeg_ycbcr_to_bgra:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    ASSERT_PTR r14
    xor r10d, r10d
.pixel:
    cmp r10, r15
    jae .done
    movsx r8d, word [r12 + r10 * 2]   ; Y
    movsx r9d, word [r13 + r10 * 2]   ; Cb
    movsx r11d, word [r14 + r10 * 2]  ; Cr
    sub r9d, 128
    sub r11d, 128

    ; B = Y + 1.77200 * Cb
    mov eax, r9d
    imul eax, 116130
    sar eax, 16
    add eax, r8d
    call jpeg_clamp_u8
    mov [rbx + r10 * 4], al

    ; G = Y - 0.34414 * Cb - 0.71414 * Cr
    mov eax, r9d
    imul eax, 22554
    mov edx, r11d
    imul edx, 46802
    add eax, edx
    sar eax, 16
    neg eax
    add eax, r8d
    call jpeg_clamp_u8
    mov [rbx + r10 * 4 + 1], al

    ; R = Y + 1.40200 * Cr
    mov eax, r11d
    imul eax, 91881
    sar eax, 16
    add eax, r8d
    call jpeg_clamp_u8
    mov [rbx + r10 * 4 + 2], al
    mov byte [rbx + r10 * 4 + 3], 0xFF
    inc r10
    jmp .pixel
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; eax=signed input, eax=0..255 output. Internal leaf helper.
jpeg_clamp_u8:
    test eax, eax
    jns .nonnegative
    xor eax, eax
    ret
.nonnegative:
    cmp eax, 255
    jle .clamped
    mov eax, 255
.clamped:
    ret

; Write one full-resolution MCU, clipping against the PixBuf dimensions.
; rdi=PixBuf, rsi=Y, rdx=Cb, rcx=Cr, r8=dst x, r9=dst y,
; r10=MCU width, r11=MCU height.
global jpeg_write_color_mcu
jpeg_write_color_mcu:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 32
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov [rsp], r8
    mov [rsp + 8], r9
    mov [rsp + 16], r10
    mov [rsp + 24], r11
    ASSERT_PTR rbx
    cmp r8, [rbx + PixBuf_width]
    jae .write_invalid
    cmp r9, [rbx + PixBuf_height]
    jae .write_invalid
    test r10, r10
    jz .write_invalid
    test r11, r11
    jz .write_invalid
    xor r15d, r15d
.write_row:
    cmp r15, [rsp + 24]
    jae .write_done
    mov rax, [rsp + 8]
    add rax, r15
    cmp rax, [rbx + PixBuf_height]
    jae .write_done
    imul rax, [rbx + PixBuf_stride]
    add rax, [rbx + PixBuf_data]
    mov rcx, [rsp]
    lea rdi, [rax + rcx * 4]
    mov rax, r15
    imul rax, [rsp + 16]
    lea rsi, [r12 + rax * 2]
    lea rdx, [r13 + rax * 2]
    lea rcx, [r14 + rax * 2]
    mov r8, [rbx + PixBuf_width]
    sub r8, [rsp]
    cmp r8, [rsp + 16]
    jbe .write_count_ready
    mov r8, [rsp + 16]
.write_count_ready:
    call jpeg_ycbcr_to_bgra
    test rax, rax
    jnz .write_out
    inc r15
    jmp .write_row
.write_done:
    xor eax, eax
    jmp .write_out
.write_invalid:
    mov rax, -EINVAL
.write_out:
    add rsp, 32
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global jpeg_color_version
jpeg_color_version: dq 0x010000
