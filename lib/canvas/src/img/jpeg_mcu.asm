; ============================================================================
; JPEG MCU primitives — baseline sequential coefficient block decoding
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"

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

; ---------------------------------------------------------------------------
; jpeg_upsample_row
;   One output row of a component at full resolution, as the reference
;   decoders make it ("fancy" upsampling): half width (2x1) or half width
;   and height (2x2) by a triangle filter, 3/4 of the nearer sample and 1/4
;   of the next, with their exact integer rounding; half height alone (1x2)
;   likewise down only; full resolution copied; any other ratio repeats
;   samples. Past the first and last real sample the edge one is repeated.
;   IN:  rdi = JpegPlane*, esi = output y, rdx = int16 destination,
;        ecx = samples wanted (at most the image's width)
;   OUT: rax = 0, -EINVAL for a sampling factor of 0
; ---------------------------------------------------------------------------
%define U_Y     0
%define U_SH    4                       ; 1, 2, or 0: samples repeated
%define U_SV    8
%define U_BV    12                      ; the bias of a column (1x2)
%define U_B0    16                      ; an even output's bias, an odd's (2x)
%define U_B1    20
global jpeg_upsample_row
jpeg_upsample_row:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 40
    mov rbx, rdi
    mov r12, rdx
    mov r13d, ecx
    mov [rsp + U_Y], esi
    movzx eax, byte [rbx + JpegPlane.h]
    movzx ecx, byte [rbx + JpegPlane.max_h]
    call ratio
    js .invalid
    mov [rsp + U_SH], eax
    movzx eax, byte [rbx + JpegPlane.v]
    movzx ecx, byte [rbx + JpegPlane.max_v]
    call ratio
    js .invalid
    mov [rsp + U_SV], eax
    test eax, eax
    jz .nearest
    cmp dword [rsp + U_SH], 0
    je .nearest

    ; the row, and the one beyond it towards this output row (2x down)
    mov eax, [rsp + U_Y]
    mov r10d, eax
    mov r11d, eax
    cmp dword [rsp + U_SV], 2
    jne .rows
    shr r10d, 1
    lea r11d, [r10 - 1]
    test eax, 1
    jz .far_clamp
    lea r11d, [r10 + 1]
.far_clamp:
    test r11d, r11d
    jns .not_top
    xor r11d, r11d
.not_top:
    mov eax, [rbx + JpegPlane.height]
    dec eax
    cmp r11d, eax
    jle .rows
    mov r11d, eax
.rows:
    mov r8d, [rbx + JpegPlane.stride]
    mov eax, r10d
    imul rax, r8
    mov r14, [rbx + JpegPlane.data]
    lea r14, [r14 + rax * 2]
    mov eax, r11d
    imul rax, r8
    mov r15, [rbx + JpegPlane.data]
    lea r15, [r15 + rax * 2]
    ; a column is 3 x this + far: 4 x the sample when not halved down
    cmp dword [rsp + U_SV], 2
    jne .full_height
    mov eax, [rsp + U_Y]
    and eax, 1
    inc eax
    mov [rsp + U_BV], eax               ; 1 above, 2 below
    mov dword [rsp + U_B0], 8
    mov dword [rsp + U_B1], 7
    jmp .biased
.full_height:
    mov dword [rsp + U_BV], 0
    mov dword [rsp + U_B0], 4           ; (3a + b + 1) >> 2, x 4
    mov dword [rsp + U_B1], 8           ; (3a + b + 2) >> 2, x 4
.biased:
    mov r9d, [rbx + JpegPlane.width]
    dec r9d                             ; the last column
    xor ecx, ecx
    cmp dword [rsp + U_SH], 2
    je .half
.whole:
    cmp ecx, r13d
    jae .done
    mov edx, ecx
    call column
    add eax, [rsp + U_BV]
    sar eax, 2
    mov [r12 + rcx * 2], ax
    inc ecx
    jmp .whole
.half:
    cmp ecx, r13d
    jae .done
    mov edx, ecx
    shr edx, 1
    cmp edx, r9d
    jbe .inside
    mov edx, r9d
.inside:
    call column
    lea r10d, [rax + rax * 2]
    mov eax, [rsp + U_B0]
    test ecx, 1
    jnz .right
    test edx, edx                       ; even: the one to the left
    jz .neighbour
    dec edx
    jmp .neighbour
.right:
    mov eax, [rsp + U_B1]               ; odd: the one to the right
    cmp edx, r9d
    jae .neighbour
    inc edx
.neighbour:
    add r10d, eax
    call column
    add eax, r10d
    sar eax, 4
    mov [r12 + rcx * 2], ax
    inc ecx
    jmp .half

.nearest:                               ; samples repeated
    mov eax, [rsp + U_Y]
    movzx ecx, byte [rbx + JpegPlane.v]
    imul eax, ecx
    xor edx, edx
    movzx ecx, byte [rbx + JpegPlane.max_v]
    div ecx
    mov r8d, [rbx + JpegPlane.stride]
    imul rax, r8
    mov r14, [rbx + JpegPlane.data]
    lea r14, [r14 + rax * 2]
    xor r10d, r10d
.near:
    cmp r10d, r13d
    jae .done
    movzx eax, byte [rbx + JpegPlane.h]
    imul eax, r10d
    xor edx, edx
    movzx ecx, byte [rbx + JpegPlane.max_h]
    div ecx
    movzx edx, word [r14 + rax * 2]
    mov [r12 + r10 * 2], dx
    inc r10d
    jmp .near
.done:
    xor eax, eax
    jmp .out
.invalid:
    mov rax, -EINVAL
.out:
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; eax = a factor, ecx = the largest -> eax = 1 the same, 2 half, 0 other;
; SF set for a factor of 0
ratio:
    test eax, eax
    jz .zero
    test ecx, ecx
    jz .zero
    cmp eax, ecx
    je .one
    add eax, eax
    cmp eax, ecx
    je .two
    xor eax, eax
    ret
.one:
    mov eax, 1
    ret
.two:
    mov eax, 2
    ret
.zero:
    or eax, -1
    ret

; jpeg_upsample_row's: edx = a column -> eax = 3 x this row + the far one
column:
    movsx eax, word [r14 + rdx * 2]
    lea eax, [rax + rax * 2]
    movsx r8d, word [r15 + rdx * 2]
    add eax, r8d
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
