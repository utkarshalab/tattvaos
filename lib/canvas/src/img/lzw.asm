; ============================================================================
; LZW — Lempel-Ziv-Welch Decoder (GIF variant, LSB-first codes)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define LZW_MAX_BITS     12
%define LZW_TABLE_SIZE   4096
%define LzwState_SIZE    16384

section .text


; LzwState struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; ------------------
; ---------------------------------------------------------------------------
; lzw_decode_gif
;   IN: rdi=arena, rsi=data, rdx=len, rcx=min_code_size,
;       r8=out_buf, r9=out_len
;   OUT: rax = bytes written, negative error
; ---------------------------------------------------------------------------
global lzw_decode_gif
lzw_decode_gif:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov r10, rdi
    mov r12, rsi
    mov r13, rdx
    mov r11d, ecx
    mov r14, r8
    mov r15, r9
    ASSERT_PTR r10
    ASSERT_PTR r12
    ASSERT_PTR r14
    cmp r11d, 2
    jb .fail
    cmp r11d, 8
    ja .fail
    mov rdi, r10
    mov rsi, LzwState_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    sub rsp, 80
    mov qword [rsp + 0], 0       ; bit buffer
    mov qword [rsp + 8], 0       ; available bits
    mov qword [rsp + 16], 0      ; input position
    mov qword [rsp + 24], 0      ; output position
    mov eax, 1
    mov ecx, r11d
    shl eax, cl
    mov [rsp + 36], eax          ; clear code
    lea edx, [eax + 1]
    mov [rsp + 40], edx          ; EOI code
    add eax, 2
    mov [rsp + 44], eax          ; next code
    inc r11d
    mov [rsp + 32], r11d         ; code size
    mov dword [rsp + 48], -1     ; previous code
    mov dword [rsp + 52], 0      ; first byte
    xor ecx, ecx
.init_loop:
    cmp ecx, [rsp + 36]
    jae .init_done
    mov [rbx + rcx * 2], cx
    mov [rbx + 8192 + rcx], cl
    inc ecx
    jmp .init_loop
.init_done:
    ; GIF codes are packed least-significant bit first.
.code_loop:
    mov ecx, [rsp + 32]
.refill:
    cmp [rsp + 8], rcx
    jae .extract
    mov rax, [rsp + 16]
    cmp rax, r13
    jae .truncated
    movzx edx, byte [r12 + rax]
    inc qword [rsp + 16]
    mov rcx, [rsp + 8]
    shl rdx, cl
    or [rsp + 0], rdx
    add qword [rsp + 8], 8
    mov ecx, [rsp + 32]
    jmp .refill
.extract:
    mov eax, 1
    shl eax, cl
    dec eax
    and eax, dword [rsp + 0]
    shr qword [rsp + 0], cl
    sub [rsp + 8], rcx
    cmp eax, [rsp + 36]
    je .clear
    cmp eax, [rsp + 40]
    je .decoded
    mov r10d, eax                ; original current code
    mov edx, [rsp + 48]
    cmp edx, -1
    jne .expand
    cmp eax, [rsp + 36]
    jae .invalid_stream
    cmp [rsp + 24], r15
    jae .output_full
    mov [r14], al
    inc r14
    inc qword [rsp + 24]
    mov [rsp + 52], eax
    mov [rsp + 48], eax
    jmp .code_loop
.expand:
    xor r9d, r9d                 ; temporary stack length
    cmp eax, [rsp + 44]
    jb .unwind
    jne .invalid_stream
    mov ecx, [rsp + 52]
    mov [rbx + 12288 + r9], cl
    inc r9d
    mov eax, [rsp + 48]
.unwind:
    cmp eax, [rsp + 36]
    jb .root
    cmp eax, [rsp + 44]
    jae .invalid_stream
    cmp r9d, 4095
    jae .invalid_stream
    mov cl, [rbx + 8192 + rax]
    mov [rbx + 12288 + r9], cl
    inc r9d
    movzx eax, word [rbx + rax * 2]
    jmp .unwind
.root:
    mov [rsp + 52], eax
    mov [rbx + 12288 + r9], al
    inc r9d
.emit:
    test r9d, r9d
    jz .add_entry
    cmp [rsp + 24], r15
    jae .output_full
    dec r9d
    mov al, [rbx + 12288 + r9]
    mov [r14], al
    inc r14
    inc qword [rsp + 24]
    jmp .emit
.add_entry:
    mov eax, [rsp + 44]
    cmp eax, LZW_TABLE_SIZE
    jae .set_previous
    mov dx, [rsp + 48]
    mov [rbx + rax * 2], dx
    mov edx, [rsp + 52]
    mov [rbx + 8192 + rax], dl
    inc eax
    mov [rsp + 44], eax
    mov ecx, [rsp + 32]
    cmp ecx, LZW_MAX_BITS
    jae .set_previous
    mov edx, 1
    shl edx, cl
    cmp eax, edx
    jne .set_previous
    inc dword [rsp + 32]
.set_previous:
    mov [rsp + 48], r10d
    jmp .code_loop
.clear:
    mov eax, [rsp + 36]
    add eax, 2
    mov [rsp + 44], eax
    mov eax, [rsp + 36]
    bsr ecx, eax
    inc ecx
    mov [rsp + 32], ecx
    mov dword [rsp + 48], -1
    jmp .code_loop
.decoded:
    mov rax, [rsp + 24]
    add rsp, 80
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.truncated:
.invalid_stream:
    add rsp, 80
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.output_full:
    add rsp, 80
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global lzw_version
lzw_version: dq 0x010000
