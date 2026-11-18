; ============================================================================
; JPEG Color Conversion — full-range YCbCr samples to opaque BGRA
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"

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

section .data
global jpeg_color_version
jpeg_color_version: dq 0x010000
