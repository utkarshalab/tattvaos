; ============================================================================
; JPEG Encoder — baseline JFIF, for screenshots and export
; ============================================================================
; MED-11. jpeg_encode writes a baseline sequential JPEG (JFIF 1.01) from a
; PixBuf of premultiplied BGRA: YCbCr (JFIF's full-range matrix) at 4:2:0,
; chroma the average of each 2x2; each 8x8 block level-shifted, through a
; forward DCT in doubles (the separable basis, dct_basis), divided by its
; quantizer and rounded; the example tables of ITU T.81 Annex K, scaled by
; quality as the reference encoder scales them (5000 / q below 50, else
; 200 - 2q, then each (t x s + 50) / 100 within 1 to 255), and Annex K's
; Huffman tables. Edges repeat the last row and column. Alpha is not kept:
; premultiplied, a see-through pixel is its colour over black.
;
; The entropy coder runs twice: once only counting the bytes, then into an
; allocation of exactly that many.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc

struc JEnc
    .image:     resq 1
    .out:       resq 1                  ; 0 while counting
    .pos:       resq 1
    .acc:       resq 1                  ; bits not yet whole bytes
    .bits:      resd 1
    .pred:      resd 3                  ; DC by component
    .mx:        resd 1
    .my:        resd 1
    .mcux:      resd 1
    .mcuy:      resd 1
    .run:       resd 1
    .k:         resd 1
    .quant:     resw 128                ; luma then chroma, zigzag order
    .code:      resw 1024               ; Huffman codes: DC Y, AC Y, DC C, AC C
    .size:      resb 1024               ; their lengths
    .y:         resq 256                ; an MCU: four Y blocks
    .cb:        resq 256                ; Cb, Cr at full resolution, by rows
    .cr:        resq 256
    .blk:       resq 64                 ; a block to code
    .tmp:       resq 64
    .coef:      resd 64                 ; quantized, zigzag order
endstruc

%define T_DC_Y  0
%define T_AC_Y  1
%define T_DC_C  2
%define T_AC_C  3

section .text

; ---------------------------------------------------------------------------
; jpeg_encode
;   IN:  rdi = arena*, rsi = PixBuf* (BGRA, premultiplied), edx = quality
;        (1 to 100; outside, clamped)
;   OUT: rax = the file (arena), rdx = its length; rax negative error
; ---------------------------------------------------------------------------
global jpeg_encode
jpeg_encode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov rax, [r13 + PixBuf.width]
    test rax, rax
    jz .invalid
    cmp rax, 65535
    ja .invalid
    mov rax, [r13 + PixBuf.height]
    test rax, rax
    jz .invalid
    cmp rax, 65535
    ja .invalid
    mov rdi, r12
    mov esi, JEnc_size
    call arena_alloc
    test rax, rax
    jz .oom
    js .oom
    mov rbx, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, JEnc_size
    rep stosb
    mov [rbx + JEnc.image], r13
    mov eax, [r13 + PixBuf.width]
    add eax, 15
    shr eax, 4
    mov [rbx + JEnc.mcux], eax
    mov eax, [r13 + PixBuf.height]
    add eax, 15
    shr eax, 4
    mov [rbx + JEnc.mcuy], eax
    mov edi, r14d
    call quant_tables
    call huffman_codes
    call encode                         ; counting
    mov rsi, [rbx + JEnc.pos]
    mov r15, rsi
    mov rdi, r12
    call arena_alloc
    test rax, rax
    jz .oom
    js .oom
    mov [rbx + JEnc.out], rax
    call encode
    mov rax, [rbx + JEnc.out]
    mov rdx, r15
    jmp .out
.invalid:
    mov rax, -EINVAL
    jmp .out
.oom:
    mov rax, -ENOMEM
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; Local: rbx = JEnc throughout
; ---------------------------------------------------------------------------

; edi = quality: base_quant scaled into JEnc.quant
quant_tables:
    cmp edi, 1
    jge .low_ok
    mov edi, 1
.low_ok:
    cmp edi, 100
    jle .high_ok
    mov edi, 100
.high_ok:
    mov eax, 5000                       ; the scale
    xor edx, edx
    div edi
    cmp edi, 50
    jb .scaled
    mov eax, 200
    sub eax, edi
    sub eax, edi
.scaled:
    mov r8d, eax
    lea rsi, [rel base_quant]
    xor ecx, ecx
.entry:
    movzx eax, byte [rsi + rcx]
    imul eax, r8d
    add eax, 50
    xor edx, edx
    mov r9d, 100
    div r9d
    test eax, eax
    jnz .not_zero
    mov eax, 1
.not_zero:
    cmp eax, 255
    jbe .stored
    mov eax, 255
.stored:
    mov [rbx + JEnc.quant + rcx * 2], ax
    inc ecx
    cmp ecx, 128
    jb .entry
    ret

; each of dht_tables' four tables' codes and lengths (T.81 C.2)
huffman_codes:
    lea rsi, [rel dht_tables]
    xor r8d, r8d                        ; the table
.table:
    lea r9, [rsi + 17]                  ; its symbols
    xor ecx, ecx                        ; the code
    mov r10d, 1                         ; its length
.length:
    movzx r11d, byte [rsi + r10]        ; codes of this length
.symbol:
    test r11d, r11d
    jz .longer
    movzx eax, byte [r9]
    inc r9
    mov edx, r8d
    shl edx, 8
    add edx, eax
    mov [rbx + JEnc.code + rdx * 2], cx
    mov [rbx + JEnc.size + rdx], r10b
    inc ecx
    dec r11d
    jmp .symbol
.longer:
    shl ecx, 1
    inc r10d
    cmp r10d, 16
    jbe .length
    mov rsi, r9                         ; the next table
    inc r8d
    cmp r8d, 4
    jb .table
    ret

; the whole file, counted or written
encode:
    push r12
    push r13
    push r14
    sub rsp, 16
    xor eax, eax
    mov [rbx + JEnc.pos], rax
    mov [rbx + JEnc.acc], rax
    mov [rbx + JEnc.bits], eax
    mov [rbx + JEnc.pred], eax
    mov [rbx + JEnc.pred + 4], eax
    mov [rbx + JEnc.pred + 8], eax
    lea rsi, [rel head_jfif]            ; SOI, APP0
    mov ecx, head_jfif_len
    call put_bytes
    lea rsi, [rel head_dqt]             ; DQT: both tables
    mov ecx, head_dqt_len
    call put_bytes
    xor r12d, r12d
.dqt:
    cmp r12d, 64
    jne .dqt_value
    mov al, 1
    call put_byte
.dqt_value:
    movzx eax, word [rbx + JEnc.quant + r12 * 2]
    call put_byte
    inc r12d
    cmp r12d, 128
    jb .dqt
    lea rsi, [rel head_sof]             ; SOF0: precision, height, width
    mov ecx, head_sof_len
    call put_bytes
    mov r13, [rbx + JEnc.image]
    mov eax, [r13 + PixBuf.height]
    call put_word
    mov eax, [r13 + PixBuf.width]
    call put_word
    lea rsi, [rel head_components]
    mov ecx, head_components_len
    call put_bytes
    lea rsi, [rel head_dht]             ; DHT
    mov ecx, head_dht_len
    call put_bytes
    lea rsi, [rel dht_tables]
    mov ecx, dht_tables_len
    call put_bytes
    lea rsi, [rel head_sos]             ; SOS
    mov ecx, head_sos_len
    call put_bytes
    mov dword [rbx + JEnc.my], 0
.mcu_row:
    mov eax, [rbx + JEnc.my]
    cmp eax, [rbx + JEnc.mcuy]
    jae .scan_done
    mov dword [rbx + JEnc.mx], 0
.mcu:
    mov eax, [rbx + JEnc.mx]
    cmp eax, [rbx + JEnc.mcux]
    jae .next_row
    call load_mcu
    xor r12d, r12d                      ; Y: four blocks
.luma:
    mov eax, r12d
    shl eax, 9
    lea rsi, [rbx + JEnc.y + rax]
    lea rdi, [rbx + JEnc.blk]
    mov ecx, 64
    rep movsq
    xor edi, edi
    call code_block
    inc r12d
    cmp r12d, 4
    jb .luma
    lea rsi, [rbx + JEnc.cb]
    call average
    mov edi, 1
    call code_block
    lea rsi, [rbx + JEnc.cr]
    call average
    mov edi, 2
    call code_block
    inc dword [rbx + JEnc.mx]
    jmp .mcu
.next_row:
    inc dword [rbx + JEnc.my]
    jmp .mcu_row
.scan_done:
    mov ecx, [rbx + JEnc.bits]          ; the last byte filled with 1s
    and ecx, 7
    jz .padded
    mov esi, 8
    sub esi, ecx
    mov edi, 1
    mov ecx, esi
    shl edi, cl
    dec edi
    call put_bits
.padded:
    mov al, 0xFF                        ; EOI
    call put_byte
    mov al, 0xD9
    call put_byte
    add rsp, 16
    pop r14
    pop r13
    pop r12
    ret

; the MCU at [mx], [my]: Y level-shifted into four blocks, Cb and Cr at
; full resolution; outside the image, its last row and column again
load_mcu:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r13, [rbx + JEnc.image]
    xor r12d, r12d                      ; py
.row:
    mov eax, [rbx + JEnc.my]
    shl eax, 4
    add eax, r12d
    mov ecx, [r13 + PixBuf.height]
    dec ecx
    cmp eax, ecx
    jbe .row_in
    mov eax, ecx
.row_in:
    imul rax, [r13 + PixBuf.stride]
    mov r14, [r13 + PixBuf.data]
    add r14, rax                        ; the source row
    xor r15d, r15d                      ; px
.pixel:
    mov eax, [rbx + JEnc.mx]
    shl eax, 4
    add eax, r15d
    mov ecx, [r13 + PixBuf.width]
    dec ecx
    cmp eax, ecx
    jbe .column_in
    mov eax, ecx
.column_in:
    movzx ecx, byte [r14 + rax * 4 + 2] ; R
    cvtsi2sd xmm0, ecx
    movzx ecx, byte [r14 + rax * 4 + 1] ; G
    cvtsi2sd xmm1, ecx
    movzx ecx, byte [r14 + rax * 4]     ; B
    cvtsi2sd xmm2, ecx
    ; Y block (py / 8) x 2 + px / 8, at (py % 8) x 8 + px % 8
    mov eax, r12d
    shr eax, 3
    add eax, eax
    mov ecx, r15d
    shr ecx, 3
    add eax, ecx
    shl eax, 6
    mov ecx, r12d
    and ecx, 7
    shl ecx, 3
    add eax, ecx
    mov ecx, r15d
    and ecx, 7
    add eax, ecx
    lea rdi, [rel ycc]
    movsd xmm3, [rdi]                   ; Y - 128
    mulsd xmm3, xmm0
    movsd xmm4, [rdi + 8]
    mulsd xmm4, xmm1
    addsd xmm3, xmm4
    movsd xmm4, [rdi + 16]
    mulsd xmm4, xmm2
    addsd xmm3, xmm4
    subsd xmm3, [rel c_128]
    movsd [rbx + JEnc.y + rax * 8], xmm3
    mov eax, r12d                       ; Cb, Cr at py x 16 + px
    shl eax, 4
    add eax, r15d
    movsd xmm3, [rdi + 24]
    mulsd xmm3, xmm0
    movsd xmm4, [rdi + 32]
    mulsd xmm4, xmm1
    addsd xmm3, xmm4
    movsd xmm4, [rdi + 40]
    mulsd xmm4, xmm2
    addsd xmm3, xmm4
    movsd [rbx + JEnc.cb + rax * 8], xmm3
    movsd xmm3, [rdi + 48]
    mulsd xmm3, xmm0
    movsd xmm4, [rdi + 56]
    mulsd xmm4, xmm1
    addsd xmm3, xmm4
    movsd xmm4, [rdi + 64]
    mulsd xmm4, xmm2
    addsd xmm3, xmm4
    movsd [rbx + JEnc.cr + rax * 8], xmm3
    inc r15d
    cmp r15d, 16
    jb .pixel
    inc r12d
    cmp r12d, 16
    jb .row
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; rsi = 16x16 chroma -> JEnc.blk: each 2x2's average
average:
    xor ecx, ecx                        ; the block's sample
.sample:
    mov eax, ecx
    shr eax, 3                          ; y
    shl eax, 5                          ; x 2 rows of 16
    mov edx, ecx
    and edx, 7
    add edx, edx
    add eax, edx                        ; (2y) x 16 + 2x
    movsd xmm0, [rsi + rax * 8]
    addsd xmm0, [rsi + rax * 8 + 8]
    addsd xmm0, [rsi + rax * 8 + 128]
    addsd xmm0, [rsi + rax * 8 + 136]
    mulsd xmm0, [rel c_quarter]
    movsd [rbx + JEnc.blk + rcx * 8], xmm0
    inc ecx
    cmp ecx, 64
    jb .sample
    ret

; edi = component 0 (Y), 1 or 2: JEnc.blk transformed, quantized and coded
code_block:
    push r12
    push r13
    push r14
    mov r12d, edi
    ; tmp[y][u] = sum over x of B[u][x] blk[y][x]
    lea r8, [rel dct_basis]
    xor ecx, ecx
.rows:
    mov eax, ecx
    shr eax, 3                          ; y
    mov edx, ecx
    and edx, 7                          ; u
    shl eax, 6                          ; y x 8 doubles
    shl edx, 6                          ; u x 8 doubles
    xorpd xmm0, xmm0
    xor r9d, r9d
.row_sum:
    lea r10, [rax + r9 * 8]
    movsd xmm1, [rbx + JEnc.blk + r10]
    lea r10, [rdx + r9 * 8]
    mulsd xmm1, [r8 + r10]
    addsd xmm0, xmm1
    inc r9d
    cmp r9d, 8
    jb .row_sum
    movsd [rbx + JEnc.tmp + rcx * 8], xmm0
    inc ecx
    cmp ecx, 64
    jb .rows
    ; F[v][u] = sum over y of B[v][y] tmp[y][u], quantized into zigzag
    lea r11, [rel zigzag]
    xor ecx, ecx                        ; zigzag index
.coefficient:
    movzx r13d, byte [r11 + rcx]        ; natural index v x 8 + u
    mov eax, r13d
    shr eax, 3
    shl eax, 6                          ; v x 8 doubles
    mov edx, r13d
    and edx, 7                          ; u
    xorpd xmm0, xmm0
    xor r9d, r9d
.column_sum:
    lea r10, [rax + r9 * 8]
    movsd xmm1, [r8 + r10]              ; B[v][y]
    lea r10d, [r9 * 8 + rdx]
    mulsd xmm1, [rbx + JEnc.tmp + r10 * 8]
    addsd xmm0, xmm1
    inc r9d
    cmp r9d, 8
    jb .column_sum
    mov eax, r12d                       ; luma table, or chroma's
    test eax, eax
    jz .table
    mov eax, 64
.table:
    add eax, ecx
    movzx eax, word [rbx + JEnc.quant + rax * 2]
    cvtsi2sd xmm1, eax
    divsd xmm0, xmm1
    cvtsd2si eax, xmm0
    cmp ecx, 0
    je .stored
    cmp eax, 1023                       ; AC: at most 10 bits
    jle .not_high
    mov eax, 1023
.not_high:
    cmp eax, -1023
    jge .stored
    mov eax, -1023
.stored:
    mov [rbx + JEnc.coef + rcx * 4], eax
    inc ecx
    cmp ecx, 64
    jb .coefficient
    ; DC: the difference from the last of this component
    mov r13d, T_DC_Y
    mov r14d, T_AC_Y
    test r12d, r12d
    jz .tables
    mov r13d, T_DC_C
    mov r14d, T_AC_C
.tables:
    mov eax, [rbx + JEnc.coef]
    mov edx, eax
    sub eax, [rbx + JEnc.pred + r12 * 4]
    mov [rbx + JEnc.pred + r12 * 4], edx
    mov edi, r13d
    call put_value
    ; AC: runs of zeros, sixteen at a time, then the end
    mov dword [rbx + JEnc.run], 0
    mov dword [rbx + JEnc.k], 1
.ac:
    mov ecx, [rbx + JEnc.k]
    mov eax, [rbx + JEnc.coef + rcx * 4]
    test eax, eax
    jnz .nonzero
    inc dword [rbx + JEnc.run]
    jmp .ac_next
.nonzero:
    cmp dword [rbx + JEnc.run], 15
    jbe .run_ok
    mov edi, r14d                       ; ZRL
    mov esi, 0xF0
    call put_huff
    sub dword [rbx + JEnc.run], 16
    jmp .nonzero
.run_ok:
    mov ecx, [rbx + JEnc.k]
    mov eax, [rbx + JEnc.coef + rcx * 4]
    mov edi, r14d
    mov esi, [rbx + JEnc.run]
    shl esi, 4
    call put_ac
    mov dword [rbx + JEnc.run], 0
.ac_next:
    inc dword [rbx + JEnc.k]
    cmp dword [rbx + JEnc.k], 64
    jb .ac
    cmp dword [rbx + JEnc.run], 0
    je .done
    mov edi, r14d                       ; EOB
    xor esi, esi
    call put_huff
.done:
    pop r14
    pop r13
    pop r12
    ret

; eax = a value, edi = its DC table: its size's code, then its bits
put_value:
    xor esi, esi
    ; fall into put_ac with no run
; eax = a value, edi = a table, esi = the run x 16: (run, size)'s code and
; the value's bits (negative ones less 1)
put_ac:
    push r12
    push r13
    push r14
    mov r12d, eax
    mov r13d, edi
    mov r14d, esi
    mov ecx, eax                        ; the size: bits of |value|
    test ecx, ecx
    jns .positive
    neg ecx
.positive:
    xor edx, edx
    test ecx, ecx
    jz .sized
    bsr edx, ecx
    inc edx
.sized:
    push rdx
    mov edi, r13d
    lea esi, [r14 + rdx]
    call put_huff
    pop rsi                             ; the size
    test esi, esi
    jz .out
    mov edi, r12d
    test edi, edi
    jns .bits
    dec edi
.bits:
    mov ecx, esi
    mov eax, 1
    shl eax, cl
    dec eax
    and edi, eax
    call put_bits
.out:
    pop r14
    pop r13
    pop r12
    ret

; edi = a table, esi = a symbol: its code
put_huff:
    shl edi, 8
    add edi, esi
    movzx esi, byte [rbx + JEnc.size + rdi]
    movzx edi, word [rbx + JEnc.code + rdi * 2]
    ; fall into put_bits
; edi = bits, esi = how many (at most 24): into the stream, each 0xFF byte
; followed by 0
put_bits:
    mov rax, [rbx + JEnc.acc]
    mov ecx, esi
    shl rax, cl
    or rax, rdi
    mov [rbx + JEnc.acc], rax
    add [rbx + JEnc.bits], esi
.byte:
    mov ecx, [rbx + JEnc.bits]
    cmp ecx, 8
    jb .out
    sub ecx, 8
    mov [rbx + JEnc.bits], ecx
    mov rax, [rbx + JEnc.acc]
    shr rax, cl
    push rax
    call put_byte
    pop rax
    cmp al, 0xFF
    jne .byte
    xor eax, eax
    call put_byte
    jmp .byte
.out:
    ret

; ax = a big-endian 16-bit value
put_word:
    push rax
    shr eax, 8
    call put_byte
    pop rax
    ; fall into put_byte
; al = a byte: written (counted while counting)
put_byte:
    mov rdx, [rbx + JEnc.out]
    test rdx, rdx
    jz .counted
    mov rcx, [rbx + JEnc.pos]
    mov [rdx + rcx], al
.counted:
    inc qword [rbx + JEnc.pos]
    ret

; rsi = bytes, ecx = how many
put_bytes:
    test ecx, ecx
    jz .out
    push rsi
    push rcx
    mov al, [rsi]
    call put_byte
    pop rcx
    pop rsi
    inc rsi
    dec ecx
    jmp put_bytes
.out:
    ret

section .rodata
align 8
; JFIF's YCbCr from R, G, B: Y, Cb - 128, Cr - 128 by rows
ycc:
    dq 0.299, 0.587, 0.114
    dq -0.168735892, -0.331264108, 0.5
    dq 0.5, -0.418687589, -0.081312411
c_128:      dq 128.0
c_quarter:  dq 0.25
head_jfif:
    db 0xFF, 0xD8
    db 0xFF, 0xE0, 0x00, 0x10, 'JFIF', 0, 1, 1, 0, 0, 1, 0, 1, 0, 0
head_jfif_len equ $ - head_jfif
head_dqt:
    db 0xFF, 0xDB, 0x00, 0x84, 0x00     ; two 8-bit tables; the first
head_dqt_len equ $ - head_dqt
head_sof:
    db 0xFF, 0xC0, 0x00, 0x11, 8
head_sof_len equ $ - head_sof
head_components:                        ; Y 2x2 table 0; Cb, Cr 1x1 table 1
    db 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1
head_components_len equ $ - head_components
head_dht:
    db 0xFF, 0xC4, (dht_tables_len + 2) >> 8, (dht_tables_len + 2) & 0xFF
head_dht_len equ $ - head_dht
head_sos:
    db 0xFF, 0xDA, 0x00, 0x0C, 3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0
head_sos_len equ $ - head_sos
; a zigzag index -> the coefficient's natural one
zigzag:
    db 0, 1, 8, 16, 9, 2, 3, 10
    db 17, 24, 32, 25, 18, 11, 4, 5
    db 12, 19, 26, 33, 40, 48, 41, 34
    db 27, 20, 13, 6, 7, 14, 21, 28
    db 35, 42, 49, 56, 57, 50, 43, 36
    db 29, 22, 15, 23, 30, 37, 44, 51
    db 58, 59, 52, 45, 38, 31, 39, 46
    db 53, 60, 61, 54, 47, 55, 62, 63
; ITU T.81 Annex K: the quantization tables (luma, chroma; zigzag order),
; its four Huffman tables as a DHT segment's payload (DC 0, AC 0, DC 1,
; AC 1) and the DCT's basis
base_quant:
    db 0x10, 0x0B, 0x0C, 0x0E, 0x0C, 0x0A, 0x10, 0x0E, 0x0D, 0x0E, 0x12, 0x11, 0x10, 0x13, 0x18, 0x28
    db 0x1A, 0x18, 0x16, 0x16, 0x18, 0x31, 0x23, 0x25, 0x1D, 0x28, 0x3A, 0x33, 0x3D, 0x3C, 0x39, 0x33
    db 0x38, 0x37, 0x40, 0x48, 0x5C, 0x4E, 0x40, 0x44, 0x57, 0x45, 0x37, 0x38, 0x50, 0x6D, 0x51, 0x57
    db 0x5F, 0x62, 0x67, 0x68, 0x67, 0x3E, 0x4D, 0x71, 0x79, 0x70, 0x64, 0x78, 0x5C, 0x65, 0x67, 0x63
    db 0x11, 0x12, 0x12, 0x18, 0x15, 0x18, 0x2F, 0x1A, 0x1A, 0x2F, 0x63, 0x42, 0x38, 0x42, 0x63, 0x63
    db 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63
    db 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63
    db 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63, 0x63
; DHT payload 416 bytes
dht_tables:
    db 0x00, 0x00, 0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x10, 0x00, 0x02
    db 0x01, 0x03, 0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D, 0x01, 0x02
    db 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06, 0x13, 0x51, 0x61, 0x07, 0x22, 0x71
    db 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08, 0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33
    db 0x62, 0x72, 0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2A
    db 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A, 0x53
    db 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73
    db 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8A, 0x92
    db 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9
    db 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7
    db 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2, 0xE3, 0xE4
    db 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA
    db 0x01, 0x00, 0x03, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x11, 0x00, 0x02
    db 0x01, 0x02, 0x04, 0x04, 0x03, 0x04, 0x07, 0x05, 0x04, 0x04, 0x00, 0x01, 0x02, 0x77, 0x00, 0x01
    db 0x02, 0x03, 0x11, 0x04, 0x05, 0x21, 0x31, 0x06, 0x12, 0x41, 0x51, 0x07, 0x61, 0x71, 0x13, 0x22
    db 0x32, 0x81, 0x08, 0x14, 0x42, 0x91, 0xA1, 0xB1, 0xC1, 0x09, 0x23, 0x33, 0x52, 0xF0, 0x15, 0x62
    db 0x72, 0xD1, 0x0A, 0x16, 0x24, 0x34, 0xE1, 0x25, 0xF1, 0x17, 0x18, 0x19, 0x1A, 0x26, 0x27, 0x28
    db 0x29, 0x2A, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x4A
    db 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A
    db 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89
    db 0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7
    db 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5
    db 0xC6, 0xC7, 0xC8, 0xC9, 0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE2, 0xE3
    db 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF2, 0xF3, 0xF4, 0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA
dht_tables_len equ $ - dht_tables
; B[u][x] = c(u) / 2 cos((2x + 1) u pi / 16), c(0) = 1 / sqrt 2
dct_basis:
    dq 0.35355339059327373, 0.35355339059327373, 0.35355339059327373, 0.35355339059327373, 0.35355339059327373, 0.35355339059327373, 0.35355339059327373, 0.35355339059327373
    dq 0.4903926402016152, 0.4157348061512726, 0.27778511650980114, 0.09754516100806417, -0.0975451610080641, -0.277785116509801, -0.4157348061512727, -0.4903926402016152
    dq 0.46193976625564337, 0.19134171618254492, -0.19134171618254486, -0.46193976625564337, -0.4619397662556434, -0.19134171618254517, 0.191341716182545, 0.46193976625564326
    dq 0.4157348061512726, -0.0975451610080641, -0.4903926402016152, -0.2777851165098011, 0.2777851165098009, 0.4903926402016152, 0.09754516100806439, -0.41573480615127256
    dq 0.3535533905932738, -0.35355339059327373, -0.35355339059327384, 0.3535533905932737, 0.35355339059327384, -0.35355339059327334, -0.35355339059327356, 0.3535533905932733
    dq 0.27778511650980114, -0.4903926402016152, 0.09754516100806415, 0.41573480615127273, -0.41573480615127256, -0.09754516100806401, 0.4903926402016153, -0.27778511650980076
    dq 0.19134171618254492, -0.4619397662556434, 0.46193976625564326, -0.19134171618254495, -0.19134171618254528, 0.46193976625564337, -0.4619397662556432, 0.19134171618254478
    dq 0.09754516100806417, -0.2777851165098011, 0.41573480615127273, -0.4903926402016153, 0.4903926402016152, -0.4157348061512725, 0.27778511650980076, -0.09754516100806429

section .data
global jpeg_encode_version
jpeg_encode_version: dq 0x010000
