; ============================================================================
; PNG — PNG Decoder (8-bit indexed/gray/gray-alpha/RGB/RGBA, filters 0-4)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define PNG_SIG0  0x474E5089
%define PNG_SIG1  0x0A1A0A0D
%define PNG_CT_GRAY       0
%define PNG_CT_RGB        2
%define PNG_CT_PALETTE    3
%define PNG_CT_GRAY_ALPHA 4
%define PNG_CT_RGBA       6

section .text


; PngImage struct layout (manual offsets)\n; Offsets defined in inc/struct_offsets.inc\n\n; ----------\n


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
    leave
    ret
.no:
    xor rax, rax
    leave
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
    mov qword [r14 + PngImage.palette], 0
    mov qword [r14 + PngImage.palette_entries], 0
    mov qword [r14 + PngImage.transparency], 0
    mov qword [r14 + PngImage.transparency_len], 0
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
    imul rax,rdx
    movzx ecx,byte [r14 + PngImage.bit_depth]
    imul rax,rcx
    add rax,7
    shr rax,3
    inc rax
    mov r15,rax
    mov eax,[r14 + PngImage.height]
    imul rax,r15
    jo .bad
    mov r13,rax
    cmp byte [r14 + PngImage.interlace],0
    je .raw_capacity_ready
    mov eax,[r14 + PngImage.height]
    imul rax,14
    jo .bad
    add r13,rax
    jc .bad
.raw_capacity_ready:
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
    mov r8,r13
    call zlib_decompress
    test rax, rax
    js .bad
    cmp byte [r14 + PngImage.interlace],0
    jne .decode_adam7
    cmp rax,r13
    jne .bad
    ; unfilter into pixbuf
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r12
    call png_unfilter
    jmp .decoded
.decode_adam7:
    mov rdi,rbx
    mov rsi,r14
    mov rdx,r12
    mov rcx,rax
    call png_adam7_expand
.decoded:
    test rax, rax
    jz .bad
    mov rax, [r14 + PngImage.pixbuf]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
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
    xor r15d, r15d  ; bit0 IEND, bit1 IDAT, bit2 IDAT ended, bit3 PLTE, bit4 tRNS
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
    push r10
    push r11
    lea rdi,[r12+4]
    lea rsi,[r10+4]
    call crc32_ieee
    pop r11
    pop r10
    mov edx,[r12+r10+8]
    bswap edx
    cmp eax,edx
    jne .fail
    mov eax,[r12+4]
    test r14d,r14d
    jnz .after_first
    cmp eax,0x52444849
    jne .fail
.after_first:
    cmp eax,0x54414449
    je .idat_order
    test r15d,2
    jz .dispatch
    or r15d,4
    jmp .dispatch
.idat_order:
    test r15d,4
    jnz .fail
.dispatch:
    cmp eax, 0x52444849  ; "IHDR" LE bytes? 'I','H','D','R' = 0x52444849 LE
    je .ihdr
    cmp eax, 0x54414449  ; "IDAT"
    je .idat
    cmp eax, 0x45544C50  ; "PLTE"
    je .plte
    cmp eax, 0x534E5274  ; "tRNS"
    je .trns
    cmp eax, 0x444E4549  ; "IEND"
    je .iend
    test byte [r12+4],0x20
    jz .fail
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
    cmp al,1
    je .depth_ok
    cmp al,2
    je .depth_ok
    cmp al,4
    je .depth_ok
    cmp al,8
    je .depth_ok
    cmp al,16
    jne .fail
.depth_ok:
    movzx eax, byte [r12 + 17]  ; color type
    mov [rbx + PngImage.color_type], al
    cmp al, PNG_CT_RGB
    je .ch3
    cmp al, PNG_CT_RGBA
    je .ch4
    cmp al, PNG_CT_GRAY
    je .ch1
    cmp al, PNG_CT_PALETTE
    je .ch1
    cmp al, PNG_CT_GRAY_ALPHA
    je .ch2
    jmp .fail
.ch3:
    cmp byte [rbx + PngImage.bit_depth],8
    je .ch3_ok
    cmp byte [rbx + PngImage.bit_depth],16
    jne .fail
.ch3_ok:
    mov byte [rbx + PngImage.channels], 3
    jmp .ihdr_tail
.ch4:
    cmp byte [rbx + PngImage.bit_depth],8
    je .ch4_ok
    cmp byte [rbx + PngImage.bit_depth],16
    jne .fail
.ch4_ok:
    mov byte [rbx + PngImage.channels], 4
    jmp .ihdr_tail
.ch1:
    cmp al,PNG_CT_PALETTE
    jne .ch1_depth_ok
    cmp byte [rbx + PngImage.bit_depth],8
    jne .fail
.ch1_depth_ok:
    mov byte [rbx + PngImage.channels], 1
    jmp .ihdr_tail
.ch2:
    cmp byte [rbx + PngImage.bit_depth],8
    je .ch2_ok
    cmp byte [rbx + PngImage.bit_depth],16
    jne .fail
.ch2_ok:
    mov byte [rbx + PngImage.channels], 2
.ihdr_tail:
    movzx eax, byte [r12 + 18]  ; compression (must be 0)
    mov [rbx + PngImage.compression],al
    test eax, eax
    jnz .fail
    movzx eax, byte [r12 + 19]  ; filter (must be 0)
    mov [rbx + PngImage.filter],al
    test eax, eax
    jnz .fail
    movzx eax, byte [r12 + 20]
    cmp eax,1
    ja .fail
    mov [rbx + PngImage.interlace],al
    mov r14d, 1
    jmp .next
.plte:
    test r14d,r14d
    jz .fail
    test r15d,10
    jnz .fail
    test r10d,r10d
    jz .fail
    cmp r10d,768
    ja .fail
    mov eax,r10d
    xor edx,edx
    mov ecx,3
    div ecx
    test edx,edx
    jnz .fail
    mov edx,eax
    lea rax,[r12+8]
    mov [rbx + PngImage.palette],rax
    mov [rbx + PngImage.palette_entries],rdx
    or r15d,8
    jmp .next
.trns:
    test r14d,r14d
    jz .fail
    test r15d,18
    jnz .fail
    movzx eax,byte [rbx + PngImage.color_type]
    cmp eax,PNG_CT_PALETTE
    je .trns_palette
    cmp eax,PNG_CT_GRAY
    je .trns_gray
    cmp eax,PNG_CT_RGB
    jne .fail
    cmp r10d,6
    jne .fail
    jmp .trns_store
.trns_gray:
    cmp r10d,2
    jne .fail
    jmp .trns_store
.trns_palette:
    test r15d,8
    jz .fail
    cmp r10,[rbx + PngImage.palette_entries]
    ja .fail
.trns_store:
    lea rax,[r12+8]
    mov [rbx + PngImage.transparency],rax
    mov [rbx + PngImage.transparency_len],r10
    or r15d,16
    jmp .next
.idat:
    test r14d, r14d
    jz .fail
    cmp byte [rbx + PngImage.color_type],PNG_CT_PALETTE
    jne .idat_palette_ok
    cmp qword [rbx + PngImage.palette],0
    je .fail
.idat_palette_ok:
    or r15d,2
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
    push rcx
    mov rdi, [rbx + PngImage.arena]
    mov rsi, rcx
    call arena_alloc
    pop rcx
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
    push rax
    push r10
    push rcx
    call memcopy
    pop rcx
    pop r10
    pop rax
.no_copy:
    mov [rbx + PngImage.idat_buf], rax
    mov [rbx + PngImage.idat_cap], rcx
.idat_fit:
    mov rdi, [rbx + PngImage.idat_buf]
    add rdi, [rbx + PngImage.idat_len]
    mov rsi, r12
    add rsi, 8
    mov rdx, r10
    push r10
    call memcopy
    pop r10
    add [rbx + PngImage.idat_len], r10
    jmp .next
.iend:
    test r10d,r10d
    jnz .fail
    test r15d,2
    jz .fail
    cmp r11,r13
    jne .fail
    or r15d,1
    jmp .done
.next:
    mov eax,[r12]
    bswap eax
    add rax,12
    add r12,rax
    sub r13,rax
    jmp .loop
.done:
    test r14d, r14d
    jz .fail
    test r15d,1
    jz .fail
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global png_version
png_version: dq 0x010000
