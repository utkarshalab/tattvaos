; ============================================================================
; JPEG MCU primitives — baseline sequential coefficient block decoding
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern jpeg_huff_decode_stream
extern jpeg_receive_extend
extern jpeg_idct8x8

section .text

; Decode and transform one baseline 8x8 block.
; rdi=JpegBitReader*, rsi=DC HuffTable*, rdx=AC HuffTable*
; rcx=int32 DC predictor*, r8=uint32 quant[64], r9=int16 block[64]
global jpeg_decode_block
jpeg_decode_block:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov r12, rdi                    ; reader
    mov rbx, rsi                    ; DC table
    mov [rsp], rdx                  ; AC table
    mov r14, rcx                    ; predictor
    mov r13, r8                     ; quantization table
    mov r15, r9                     ; coefficient/output block
    ASSERT_PTR r12
    ASSERT_PTR rbx
    ASSERT_PTR rdx
    ASSERT_PTR r14
    ASSERT_PTR r13
    ASSERT_PTR r15

    mov rdi, r15
    xor eax, eax
    mov ecx, 16
    rep stosq

    mov rdi, rbx
    mov rsi, r12
    call jpeg_huff_decode_stream
    test rax, rax
    js .out
    cmp eax, 11
    ja .invalid
    mov rdi, r12
    mov esi, eax
    call jpeg_receive_extend
    test edx, edx
    jnz .out
    add eax, [r14]
    mov [r14], eax
    cmp eax, -32768
    jl .invalid
    cmp eax, 32767
    jg .invalid
    mov [r15], ax

    mov dword [rsp + 8], 1          ; zigzag coefficient index
.ac_symbol:
    mov rdi, [rsp]
    mov rsi, r12
    call jpeg_huff_decode_stream
    test rax, rax
    js .out
    test al, al
    jz .transform                   ; EOB
    mov edx, eax
    and eax, 0x0F                   ; amplitude size
    shr edx, 4                      ; zero run
    test eax, eax
    jnz .have_amplitude
    cmp edx, 15                     ; ZRL advances 16 coefficients
    jne .invalid
    add dword [rsp + 8], 16
    cmp dword [rsp + 8], 64
    ja .invalid
    je .transform
    jmp .ac_symbol
.have_amplitude:
    cmp eax, 10
    ja .invalid
    add [rsp + 8], edx
    cmp dword [rsp + 8], 63
    ja .invalid
    mov rdi, r12
    mov esi, eax
    call jpeg_receive_extend
    test edx, edx
    jnz .out
    mov ecx, [rsp + 8]
    lea rdx, [rel jpeg_zigzag]
    movzx edx, byte [rdx + rcx]
    mov [r15 + rdx * 2], ax
    inc dword [rsp + 8]
    cmp dword [rsp + 8], 64
    jb .ac_symbol
.transform:
    mov rdi, r15
    mov rsi, r13
    call jpeg_idct8x8
    jmp .out
.invalid:
    mov rax, -EINVAL
.out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; rdi=component plane, rsi=8x8 block, rdx=block x, rcx=block y,
; r8=plane stride in samples.
global jpeg_place_block
jpeg_place_block:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    shl rdx, 3
    shl rcx, 3
    imul rcx, r8
    add rcx, rdx
    lea rbx, [rbx + rcx * 2]
    xor r9d, r9d
.place_row:
    cmp r9d, 8
    jae .place_done
    mov eax, r9d
    imul rax, r8
    lea rdi, [rbx + rax * 2]
    mov eax, r9d
    shl eax, 4
    lea rsi, [r12 + rax]
    mov ecx, 4
    rep movsd
    inc r9d
    jmp .place_row
.place_done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12
    ret

; Expand one component plane to the maximum MCU sampling grid.
; rdi=destination int16[], rsi=source int16[], rdx=component H,
; rcx=component V, r8=max H, r9=max V.
global jpeg_upsample_component
jpeg_upsample_component:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    mov [rsp], r9d
    test r13d, r13d
    jz .sample_invalid
    test r14d, r14d
    jz .sample_invalid
    cmp r13d, r15d
    ja .sample_invalid
    cmp r14d, [rsp]
    ja .sample_invalid
    mov eax, r13d
    shl eax, 3
    mov [rsp + 4], eax              ; source width
    xor r10d, r10d                  ; output y
.sample_y:
    mov eax, [rsp]
    shl eax, 3
    cmp r10d, eax
    jae .sample_done
    mov eax, r10d
    imul eax, r14d
    xor edx, edx
    div dword [rsp]
    imul eax, [rsp + 4]
    mov r11d, eax                   ; source row base
    xor ecx, ecx                    ; output x
.sample_x:
    mov eax, r15d
    shl eax, 3
    cmp ecx, eax
    jae .sample_next_y
    mov eax, ecx
    imul eax, r13d
    xor edx, edx
    div r15d
    add eax, r11d
    movzx edx, word [r12 + rax * 2]
    mov eax, r10d
    imul eax, r15d
    shl eax, 3
    add eax, ecx
    mov [rbx + rax * 2], dx
    inc ecx
    jmp .sample_x
.sample_next_y:
    inc r10d
    jmp .sample_y
.sample_done:
    xor eax, eax
    jmp .sample_out
.sample_invalid:
    mov rax, -EINVAL
.sample_out:
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; Decode all blocks belonging to one component in an interleaved MCU.
; rdi=reader, rsi=DC table, rdx=AC table, rcx=predictor, r8=quant,
; r9=component plane, r10=H blocks, r11=V blocks.
global jpeg_decode_component_mcu
jpeg_decode_component_mcu:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 160
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9
    mov [rsp + 8], r10d
    mov [rsp + 12], r11d
    test r10d, r10d
    jz .component_invalid
    test r11d, r11d
    jz .component_invalid
    cmp r10d, 4
    ja .component_invalid
    cmp r11d, 4
    ja .component_invalid

    ; Clear exactly H*8 by V*8 samples.
    mov eax, r10d
    imul eax, r11d
    shl eax, 4                      ; blocks * 128 bytes / 8
    mov ecx, eax
    mov rdi, r9
    xor eax, eax
    rep stosq
    mov dword [rsp + 16], 0         ; block y
.component_y:
    mov eax, [rsp + 16]
    cmp eax, [rsp + 12]
    jae .component_done
    mov dword [rsp + 20], 0         ; block x
.component_x:
    mov eax, [rsp + 20]
    cmp eax, [rsp + 8]
    jae .component_next_y
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, r15
    lea r9, [rsp + 32]
    call jpeg_decode_block
    test rax, rax
    jnz .component_out
    mov rdi, [rsp]
    lea rsi, [rsp + 32]
    mov edx, [rsp + 20]
    mov ecx, [rsp + 16]
    mov r8d, [rsp + 8]
    shl r8d, 3
    call jpeg_place_block
    test rax, rax
    jnz .component_out
    inc dword [rsp + 20]
    jmp .component_x
.component_next_y:
    inc dword [rsp + 16]
    jmp .component_y
.component_done:
    xor eax, eax
    jmp .component_out
.component_invalid:
    mov rax, -EINVAL
.component_out:
    add rsp, 160
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .rodata
; Spectral order -> row-major coefficient index.
jpeg_zigzag:
    db 0, 1, 8, 16, 9, 2, 3, 10
    db 17, 24, 32, 25, 18, 11, 4, 5
    db 12, 19, 26, 33, 40, 48, 41, 34
    db 27, 20, 13, 6, 7, 14, 21, 28
    db 35, 42, 49, 56, 57, 50, 43, 36
    db 29, 22, 15, 23, 30, 37, 44, 51
    db 58, 59, 52, 45, 38, 31, 39, 46
    db 53, 60, 61, 54, 47, 55, 62, 63

section .data
global jpeg_mcu_version
jpeg_mcu_version: dq 0x010000
