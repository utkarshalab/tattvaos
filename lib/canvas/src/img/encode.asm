; ============================================================================
; Image Encoders — PNG and QOI, for Screenshots and Export
; ============================================================================
; MED-11. Each takes a PixBuf of premultiplied BGRA (decision 0002) and
; writes a file into memory from an arena, alpha straightened on the way
; (each channel times 255 over alpha, rounded; nothing where alpha is 0).
;
; png_encode: 8-bit RGBA, no interlace, each row's filter none, in one
; IDAT: a zlib stream of stored deflate blocks (deflate_stored), its Adler-32
; after; every chunk's CRC-32 (crc32_ieee). Not small, but exact and quick.
;
; qoi_encode: the QOI 1.0 format: runs, the 64-entry index, small and luma
; differences, RGB and RGBA, the 8-byte end.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "ugfx.inc"

extern arena_alloc
extern deflate_stored
extern adler32
extern crc32_ieee

section .text

; ---------------------------------------------------------------------------
; png_encode
;   IN:  rdi = arena, rsi = PixBuf*
;   OUT: rax = the file, negative error (-EINVAL, -ENOMEM); rdx = its bytes
; ---------------------------------------------------------------------------
%define P_RAW       0                   ; the rows as PNG wants them
%define P_RAW_LEN   8
%define P_OUT       16
%define P_TOTAL     24
global png_encode
png_encode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 40                         ; locals; 16-byte aligned
    mov r15, rdi                        ; arena
    mov rbx, rsi                        ; PixBuf
    mov rax, -(EINVAL)
    mov r12, [rbx + PixBuf_width]
    mov r13, [rbx + PixBuf_height]
    test r12, r12
    jz .out
    test r13, r13
    jz .out

    ; The rows: a filter byte (0), then RGBA
    lea rax, [r12 * 4 + 1]
    imul rax, r13
    mov [rsp + P_RAW_LEN], rax
    mov rdi, r15
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rsp + P_RAW], rax
    mov rdi, rax                        ; written to
    xor r14d, r14d                      ; row
.row:
    cmp r14, r13
    jae .rows_done
    mov byte [rdi], 0
    inc rdi
    mov rsi, r14
    imul rsi, [rbx + PixBuf_stride]
    add rsi, [rbx + PixBuf_data]
    xor ecx, ecx
.pixel:
    cmp rcx, r12
    jae .next_row
    mov eax, [rsi + rcx * 4]
    call straight                       ; eax: R, G, B, A in byte order
    mov [rdi], eax
    add rdi, 4
    inc rcx
    jmp .pixel
.next_row:
    inc r14
    jmp .row
.rows_done:

    ; The file's size: signature, IHDR, IDAT (zlib: 2, the blocks with 5
    ; bytes each over the data, 4), IEND
    mov rax, [rsp + P_RAW_LEN]
    xor edx, edx
    mov ecx, 65535
    div rcx
    test rdx, rdx
    jz .blocks
    inc rax
.blocks:
    imul rax, rax, 5
    add rax, [rsp + P_RAW_LEN]
    add rax, 8 + 25 + 12 + 2 + 4 + 12
    mov [rsp + P_TOTAL], rax
    mov rdi, r15
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .oom
    mov [rsp + P_OUT], rax
    mov r14, rax

    ; Signature and IHDR
    mov rax, 0x0A1A0A0D474E5089
    mov [r14], rax
    mov dword [r14 + 8], 0x0D000000     ; 13, big-endian
    mov dword [r14 + 12], 'IHDR'
    mov eax, r12d
    bswap eax
    mov [r14 + 16], eax
    mov eax, r13d
    bswap eax
    mov [r14 + 20], eax
    mov dword [r14 + 24], 0x00000608    ; depth 8, RGBA, 0, 0
    mov byte [r14 + 28], 0              ; no interlace
    lea rdi, [r14 + 12]
    mov esi, 17
    call crc32_ieee
    bswap eax
    mov [r14 + 29], eax

    ; IDAT: zlib's header, the stored blocks, the Adler-32
    mov dword [r14 + 37], 'IDAT'
    mov word [r14 + 41], 0x0178         ; 78 01: deflate, 32K window, no dictionary
    lea rdi, [r14 + 43]
    mov rsi, [rsp + P_RAW]
    mov rdx, [rsp + P_RAW_LEN]
    mov rcx, [rsp + P_TOTAL]
    sub rcx, 43 + 4 + 12 + 4
    call deflate_stored
    test rax, rax
    js .out
    mov r13, rax                        ; deflate bytes (the height not needed again)
    mov rdi, [rsp + P_RAW]
    mov rsi, [rsp + P_RAW_LEN]
    mov edx, 1
    call adler32
    bswap eax
    mov [r14 + 43 + r13], eax
    lea rax, [r13 + 6]                  ; the chunk's data: 2 + blocks + 4
    mov r12, rax
    bswap eax
    mov [r14 + 33], eax
    lea rdi, [r14 + 37]
    lea rsi, [r12 + 4]
    call crc32_ieee
    bswap eax
    lea rcx, [r14 + 41 + r12]
    mov [rcx], eax

    ; IEND
    mov dword [rcx + 4], 0
    mov dword [rcx + 8], 'IEND'
    mov dword [rcx + 12], 0x826042AE    ; its CRC, big-endian
    lea rdx, [rcx + 16]
    sub rdx, r14
    mov rax, r14
    jmp .out
.oom:
    mov rax, -(ENOMEM)
.out:
    add rsp, 40
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; qoi_encode
;   IN:  rdi = arena, rsi = PixBuf*
;   OUT: rax = the file, negative error (-EINVAL, -ENOMEM); rdx = its bytes
; ---------------------------------------------------------------------------
%define Q_INDEX     0                   ; 64 pixels seen, by hash
%define Q_PREV      256
%define Q_RUN       260
%define Q_COUNT     264                 ; pixels left
%define Q_FRAME     280
global qoi_encode
qoi_encode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, Q_FRAME                    ; locals; 16-byte aligned
    mov r15, rdi
    mov rbx, rsi
    mov rax, -(EINVAL)
    mov r12, [rbx + PixBuf_width]
    mov r13, [rbx + PixBuf_height]
    test r12, r12
    jz .out
    test r13, r13
    jz .out
    mov rax, r12                        ; at most 5 bytes a pixel, the header,
    imul rax, r13                       ; the end
    mov [rsp + Q_COUNT], rax
    lea rsi, [rax * 4 + rax + 14 + 8]
    mov rdi, r15
    call arena_alloc
    test rax, rax
    jz .oom
    mov r15, rax                        ; the file (the arena not needed again)
    lea rdi, [rsp + Q_INDEX]
    xor eax, eax
    mov ecx, 64
    rep stosd
    mov dword [rsp + Q_PREV], 0xFF000000    ; R 0, G 0, B 0, A 255
    mov dword [rsp + Q_RUN], 0
    mov dword [r15], 'qoif'
    mov eax, r12d
    bswap eax
    mov [r15 + 4], eax
    mov eax, r13d
    bswap eax
    mov [r15 + 8], eax
    mov word [r15 + 12], 0x0004         ; 4 channels, sRGB with linear alpha
    lea rdi, [r15 + 14]                 ; written to
    xor r14d, r14d                      ; row
.row:
    cmp r14, r13
    jae .end
    mov r8, r14
    imul r8, [rbx + PixBuf_stride]
    add r8, [rbx + PixBuf_data]
    xor r9d, r9d                        ; column
.pixel:
    cmp r9, r12
    jae .next_row
    mov eax, [r8 + r9 * 4]
    call straight
    dec qword [rsp + Q_COUNT]
    cmp eax, [rsp + Q_PREV]
    jne .different
    inc dword [rsp + Q_RUN]             ; the same again: a run
    cmp dword [rsp + Q_RUN], 62
    je .flush
    cmp qword [rsp + Q_COUNT], 0
    jne .next
.flush:
    call run_out
    jmp .next
.different:
    call run_out
    mov r10d, eax                       ; its hash: (r 3 + g 5 + b 7 + a 11) % 64
    movzx ecx, al
    imul r11d, ecx, 3
    movzx ecx, ah
    imul ecx, ecx, 5
    add r11d, ecx
    mov ecx, eax
    shr ecx, 16
    movzx ecx, cl
    imul ecx, ecx, 7
    add r11d, ecx
    mov ecx, eax
    shr ecx, 24
    imul ecx, ecx, 11
    add r11d, ecx
    and r11d, 63
    cmp [rsp + Q_INDEX + r11 * 4], eax
    jne .not_indexed
    mov [rdi], r11b                     ; QOI_OP_INDEX
    inc rdi
    jmp .seen
.not_indexed:
    mov [rsp + Q_INDEX + r11 * 4], eax
    mov ecx, eax                        ; the same alpha as before?
    xor ecx, [rsp + Q_PREV]
    shr ecx, 24
    jnz .rgba
    movzx r10d, al                      ; dr, dg, db as signed bytes
    movzx ecx, byte [rsp + Q_PREV]
    sub r10d, ecx
    movsx r10d, r10b
    mov r11d, eax
    shr r11d, 8
    movzx r11d, r11b
    movzx ecx, byte [rsp + Q_PREV + 1]
    sub r11d, ecx
    movsx r11d, r11b
    mov edx, eax
    shr edx, 16
    movzx edx, dl
    movzx ecx, byte [rsp + Q_PREV + 2]
    sub edx, ecx
    movsx edx, dl
    lea ecx, [r10 + 2]                  ; QOI_OP_DIFF: each -2 to 1
    cmp ecx, 3
    ja .luma
    lea ecx, [r11 + 2]
    cmp ecx, 3
    ja .luma
    lea ecx, [rdx + 2]
    cmp ecx, 3
    ja .luma
    lea ecx, [r10 + 2]
    shl ecx, 4
    lea esi, [r11 + 2]
    shl esi, 2
    or ecx, esi
    lea esi, [rdx + 2]
    or ecx, esi
    or ecx, 0x40
    mov [rdi], cl
    inc rdi
    jmp .seen
.luma:
    lea ecx, [r11 + 32]                 ; QOI_OP_LUMA: dg -32 to 31, dr and
    cmp ecx, 63                         ; db within -8 to 7 of it
    ja .rgb
    mov esi, r10d
    sub esi, r11d
    add esi, 8
    cmp esi, 15
    ja .rgb
    mov ecx, edx
    sub ecx, r11d
    add ecx, 8
    cmp ecx, 15
    ja .rgb
    shl esi, 4
    or esi, ecx
    lea ecx, [r11 + 32]
    or ecx, 0x80
    mov [rdi], cl
    mov [rdi + 1], sil
    add rdi, 2
    jmp .seen
.rgb:
    mov byte [rdi], 0xFE                ; QOI_OP_RGB
    mov [rdi + 1], ax
    mov ecx, eax
    shr ecx, 16
    mov [rdi + 3], cl
    add rdi, 4
    jmp .seen
.rgba:
    mov byte [rdi], 0xFF                ; QOI_OP_RGBA
    mov [rdi + 1], eax
    add rdi, 5
.seen:
    mov [rsp + Q_PREV], eax
.next:
    inc r9
    jmp .pixel
.next_row:
    inc r14
    jmp .row
.end:
    call run_out
    mov qword [rdi], 0                  ; seven 0s and a 1
    mov byte [rdi + 7], 1
    lea rdx, [rdi + 8]
    sub rdx, r15
    mov rax, r15
    jmp .out
.oom:
    mov rax, -(ENOMEM)
.out:
    add rsp, Q_FRAME
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; qoi_encode's run, if one is open, written (QOI_OP_RUN) and closed:
; rdi = where to write, moved past it; its frame at rsp + 8. eax kept.
run_out:
    mov ecx, [rsp + 8 + Q_RUN]
    test ecx, ecx
    jz .none
    dec ecx
    or ecx, 0xC0
    mov [rdi], cl
    inc rdi
    mov dword [rsp + 8 + Q_RUN], 0
.none:
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; eax = a premultiplied BGRA pixel (0xAARRGGBB) -> eax = it straight, as the
; bytes R, G, B, A (0xAABBGGRR); rdx, r10, r11 used
straight:
    mov r10d, eax
    shr r10d, 24                        ; alpha
    jz .clear
    cmp r10d, 255
    je .swap
    push rcx
    push r8
    mov r11d, eax                       ; the pixel
    mov ecx, r10d
    mov eax, r11d                       ; R
    shr eax, 16
    movzx eax, al
    call unpremultiply
    mov r8d, eax
    mov eax, r11d                       ; G
    shr eax, 8
    movzx eax, al
    call unpremultiply
    shl eax, 8
    or r8d, eax
    movzx eax, r11b                     ; B
    call unpremultiply
    shl eax, 16
    or r8d, eax
    mov eax, r10d                       ; A
    shl eax, 24
    or eax, r8d
    pop r8
    pop rcx
    ret
.swap:
    mov edx, eax                        ; 0xAARRGGBB -> 0xAABBGGRR
    bswap edx                           ; 0xBBGGRRAA
    shr edx, 8                          ; 0x00BBGGRR
    and eax, 0xFF000000
    or eax, edx
    ret
.clear:
    xor eax, eax
    ret

; eax = a premultiplied channel, ecx = alpha (1 to 254) -> eax = it straight:
; x 255 / alpha, rounded, at most 255; rdx used
unpremultiply:
    imul eax, eax, 255
    mov edx, ecx
    shr edx, 1
    add eax, edx
    xor edx, edx
    div ecx
    cmp eax, 255
    jbe .done
    mov eax, 255
.done:
    ret
