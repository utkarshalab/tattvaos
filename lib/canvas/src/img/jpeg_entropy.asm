; ============================================================================
; JPEG Entropy Reader — bounded bits, byte stuffing, marker detection
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

struc JpegBitReader
    .ptr:       resq 1
    .end:       resq 1
    .buffer:    resq 1
    .bits:      resd 1
    .marker:    resd 1
endstruc

section .text

; rdi=reader, rsi=data, rdx=len
global jpeg_bits_init
jpeg_bits_init:
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov [rdi + JpegBitReader.ptr], rsi
    add rsi, rdx
    mov [rdi + JpegBitReader.end], rsi
    mov qword [rdi + JpegBitReader.buffer], 0
    mov dword [rdi + JpegBitReader.bits], 0
    mov dword [rdi + JpegBitReader.marker], 0
    xor eax, eax
    ret

; rdi=reader, rsi=count (0..16), returns value or negative errno.
global jpeg_bits_get
jpeg_bits_get:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    cmp r12d, 16
    ja .invalid
    test r12d, r12d
    jz .zero
.refill:
    cmp [rbx + JpegBitReader.bits], r12d
    jae .extract
    mov rsi, [rbx + JpegBitReader.ptr]
    cmp rsi, [rbx + JpegBitReader.end]
    jae .truncated
    movzx r13d, byte [rsi]
    inc rsi
    cmp r13b, 0xFF
    jne .append
    cmp rsi, [rbx + JpegBitReader.end]
    jae .truncated
.skip_fill:
    cmp rsi, [rbx + JpegBitReader.end]
    jae .truncated
    movzx eax, byte [rsi]
    inc rsi
    cmp al, 0xFF
    je .skip_fill
    test al, al
    jz .stuffed_ff
    movzx eax, al
    mov [rbx + JpegBitReader.marker], eax
    mov [rbx + JpegBitReader.ptr], rsi
    mov rax, -EPIPE
    jmp .out
.stuffed_ff:
    mov r13d, 0xFF
.append:
    mov [rbx + JpegBitReader.ptr], rsi
    mov rax, [rbx + JpegBitReader.buffer]
    shl rax, 8
    or rax, r13
    mov [rbx + JpegBitReader.buffer], rax
    add dword [rbx + JpegBitReader.bits], 8
    jmp .refill
.extract:
    mov ecx, [rbx + JpegBitReader.bits]
    sub ecx, r12d
    mov rax, [rbx + JpegBitReader.buffer]
    shr rax, cl
    mov edx, 1
    mov ecx, r12d
    shl edx, cl
    dec edx
    and eax, edx
    sub [rbx + JpegBitReader.bits], r12d
    mov ecx, [rbx + JpegBitReader.bits]
    test ecx, ecx
    jz .clear_buffer
    mov rdx, 1
    shl rdx, cl
    dec rdx
    and [rbx + JpegBitReader.buffer], rdx
    jmp .out
.clear_buffer:
    mov qword [rbx + JpegBitReader.buffer], 0
    jmp .out
.zero:
    xor eax, eax
    jmp .out
.invalid:
    mov rax, -EINVAL
    jmp .out
.truncated:
    mov rax, -EPIPE
.out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; rdi=reader, rsi=amplitude bit count. Returns JPEG sign-extended value.
global jpeg_receive_extend
jpeg_receive_extend:
    PROLOGUE_SAVE rbx
    mov ebx, esi
    test ebx, ebx
    jz .zero
    cmp ebx, 16
    ja .invalid
    call jpeg_bits_get
    test rax, rax
    js .read_error
    mov ecx, ebx
    dec ecx
    mov edx, 1
    shl edx, cl
    cmp eax, edx
    jae .success
    shl edx, 1
    dec edx
    sub eax, edx
.success:
    xor edx, edx
    jmp .out
.zero:
    xor eax, eax
    xor edx, edx
    jmp .out
.invalid:
    mov rax, -EINVAL
    mov edx, 1
    jmp .out
.read_error:
    mov edx, 1
.out:
    EPILOGUE_RESTORE rbx
    ret

; Discard pad bits after a scan/restart boundary.
global jpeg_bits_align
jpeg_bits_align:
    ASSERT_PTR rdi
    mov qword [rdi + JpegBitReader.buffer], 0
    mov dword [rdi + JpegBitReader.bits], 0
    xor eax, eax
    ret

; Align and consume the expected restart marker. rsi=sequence number 0..7.
global jpeg_expect_restart
jpeg_expect_restart:
    ASSERT_PTR rdi
    cmp esi, 7
    ja .restart_invalid
    mov qword [rdi + JpegBitReader.buffer], 0
    mov dword [rdi + JpegBitReader.bits], 0
    mov r8, [rdi + JpegBitReader.ptr]
    mov r9, [rdi + JpegBitReader.end]
    cmp r8, r9
    jae .restart_truncated
    cmp byte [r8], 0xFF
    jne .restart_invalid
.restart_fill:
    inc r8
    cmp r8, r9
    jae .restart_truncated
    cmp byte [r8], 0xFF
    je .restart_fill
    movzx eax, byte [r8]
    lea edx, [rsi + 0xD0]
    cmp eax, edx
    jne .restart_invalid
    inc r8
    mov [rdi + JpegBitReader.ptr], r8
    mov [rdi + JpegBitReader.marker], eax
    xor eax, eax
    ret
.restart_truncated:
    mov rax, -EPIPE
    ret
.restart_invalid:
    mov rax, -EINVAL
    ret

section .data
global jpeg_entropy_version
jpeg_entropy_version: dq 0x010000
