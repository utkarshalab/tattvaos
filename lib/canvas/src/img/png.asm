; ============================================================================
; PNG — PNG Decoder (8-bit RGB/RGBA/gray, non-interlaced, filters 0-4)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"

section .text

%define PNG_SIG0  0x474E5089
%define PNG_SIG1  0x0A1A0A0D

struc PngImage {
    .width:         resd 1
    .height:        resd 1
    .bit_depth:     resb 1
    .color_type:    resb 1
    .channels:      resb 1
    .pad:           resb 1
    .stride:        resq 1
    .pixbuf:        resq 1
    .idat_buf:      resq 1
    .idat_len:      resq 1
    .idat_cap:      resq 1
    .arena:         resq 1
}
%define PngImage_size    72

%define PNG_CT_GRAY       0
%define PNG_CT_RGB        2
%define PNG_CT_PALETTE    3
%define PNG_CT_GRAY_ALPHA 4
%define PNG_CT_RGBA       6

; ---------------------------------------------------------------------------
; png_probe
; ---------------------------------------------------------------------------
global png_probe
png_probe:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 8
    jb .no
    mov eax, [rdi]
    cmp eax, PNG_SIG0
    jne .no
    mov eax, [rdi + 4]
    cmp eax, PNG_SIG1
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; png_decode
;   IN: rdi = arena, rsi = data, rdx = len — OUT: rax = PixBuf*
; ---------------------------------------------------------------------------
global png_decode
png_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, r13
    call png_probe
    test rax, rax
    jz .bad
    ; alloc image
    mov rdi, rbx
    mov rsi, PngImage_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov qword [r14 + PngImage.arena], rbx
    mov qword [r14 + PngImage.idat_buf], 0
    mov qword [r14 + PngImage.idat_len], 0
    mov qword [r14 + PngImage.idat_cap], 0
    ; walk chunks
    add r12, 8
    sub r13, 8
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call png_read_chunks
    test rax, rax
    jnz .bad
    ; validate header present
    mov eax, [r14 + PngImage.width]
    test eax, eax
    jz .bad
    ; concat IDAT already in one buffer; decompress
    ; stride = width*channels + 1 (filter byte)
    mov eax, [r14 + PngImage.width]
    movzx edx, byte [r14 + PngImage.channels]
    imul eax, edx
    inc eax
    mov r15d, eax
    mov eax, [r14 + PngImage.height]
    imul eax, r15d
    mov r13d, eax  ; raw size
    mov rdi, rbx
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov rdi, rbx
    mov rsi, [r14 + PngImage.idat_buf]
    mov rdx, [r14 + PngImage.idat_len]
    mov rcx, r12
    mov r8, r13
    call zlib_decompress
    test rax, rax
    js .bad
    cmp rax, r13
    jne .bad
    ; unfilter into pixbuf
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    call png_unfilter
    test rax, rax
    jz .bad
    mov rax, [r14 + PngImage.pixbuf]
    ret
.bad:
    xor rax, rax
    ret
.oom:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; png_read_chunks — fills IHDR fields + concatenates IDAT
; ---------------------------------------------------------------------------
global png_read_chunks
png_read_chunks:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor r14d, r14d  ; seen IHDR
    xor r15d, r15d  ; seen IEND
.loop:
    cmp r13, 12
    jb .fail
    mov eax, [r12]  ; length BE
    bswap eax
    mov r10d, eax
    mov eax, [r12 + 4]  ; type
    cmp r10d, 0x7FFFFFFF
    ja .fail
    mov r11, r10
    add r11, 12
    cmp r11, r13
    ja .fail
    cmp eax, 0x52444849  ; "IHDR" LE bytes? 'I','H','D','R' = 0x52444849 LE
    je .ihdr
    cmp eax, 0x54414449  ; "IDAT"
    je .idat
    cmp eax, 0x444E4549  ; "IEND"
    je .iend
    jmp .next
.ihdr:
    cmp r10d, 13
    jne .fail
    test r14d, r14d
    jnz .fail
    mov eax, [r12 + 8]  ; width BE
    bswap eax
    mov [rbx + PngImage.width], eax
    test eax, eax
    jz .fail
    cmp eax, 32768
    ja .fail
    mov eax, [r12 + 12]  ; height BE
    bswap eax
    mov [rbx + PngImage.height], eax
    test eax, eax
    jz .fail
    cmp eax, 32768
    ja .fail
    movzx eax, byte [r12 + 16]  ; bit depth
    mov [rbx + PngImage.bit_depth], al
    cmp al, 8
    jne .fail  ; only 8-bit supported
    movzx eax, byte [r12 + 17]  ; color type
    mov [rbx + PngImage.color_type], al
    cmp al, PNG_CT_RGB
    je .ch3
    cmp al, PNG_CT_RGBA
    je .ch4
    cmp al, PNG_CT_GRAY
    je .ch1
    jmp .fail  ; no palette/interlace support
.ch3:
    mov byte [rbx + PngImage.channels], 3
    jmp .ihdr_tail
.ch4:
    mov byte [rbx + PngImage.channels], 4
    jmp .ihdr_tail
.ch1:
    mov byte [rbx + PngImage.channels], 1
.ihdr_tail:
    movzx eax, byte [r12 + 18]  ; compression (must be 0)
    test eax, eax
    jnz .fail
    movzx eax, byte [r12 + 19]  ; filter (must be 0)
    test eax, eax
    jnz .fail
    movzx eax, byte [r12 + 20]  ; interlace (must be 0)
    test eax, eax
    jnz .fail
    mov r14d, 1
    jmp .next
.idat:
    test r14d, r14d
    jz .fail
    ; append to idat buffer (grow by doubling)
    mov rax, [rbx + PngImage.idat_len]
    add rax, r10
    cmp rax, [rbx + PngImage.idat_cap]
    jbe .idat_fit
    ; grow
    mov rcx, [rbx + PngImage.idat_cap]
    test rcx, rcx
    jnz .grow
    mov rcx, 8192
.grow:
.grow_loop:
    cmp rcx, rax
    jae .grown
    shl rcx, 1
    jmp .grow_loop
.grown:
    push rax
    push r10
    mov rdi, [rbx + PngImage.arena]
    mov rsi, rcx
    call arena_alloc
    pop r10
    pop rax
    test rax, rax
    jz .fail
    ; copy old
    mov rdi, rax
    mov rsi, [rbx + PngImage.idat_buf]
    mov rdx, [rbx + PngImage.idat_len]
    test rdx, rdx
    jz .no_copy
    call memcopy
.no_copy:
    mov [rbx + PngImage.idat_buf], rax
    mov [rbx + PngImage.idat_cap], rcx
.idat_fit:
    mov rdi, [rbx + PngImage.idat_buf]
    add rdi, [rbx + PngImage.idat_len]
    mov rsi, r12
    add rsi, 8
    mov rdx, r10
    call memcopy
    add [rbx + PngImage.idat_len], r10
    jmp .next
.iend:
    mov r15d, 1
    jmp .done
.next:
    add r12, r11
    sub r13, r11
    jmp .loop
.done:
    test r14d, r14d
    jz .fail
    test r15d, r15d
    jz .fail
    xor rax, rax
    ret
.fail:
    mov rax, -EINVAL
    ret

section .data
global png_version
png_version: dq 0x010000
