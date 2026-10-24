; ============================================================================
; Sniff — Image Format Detection (magic bytes)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/canvas_client.inc"

extern camera_probe
extern modern_probe
extern png_decode
extern jpeg_decode
extern gif_decode_first
extern bmp_decode
extern svg_probe
extern svg_render
extern qoi_decode
extern tga_decode
extern pnm_decode
extern farbfeld_decode
extern tiff_decode
extern pcx_decode
extern ico_decode
extern dds_decode
extern ktx_decode
extern ktx2_decode
extern hdr_decode
extern exr_decode
extern psd_decode
extern webp_decode
extern camera_decode
extern pixbuf_premultiply

section .text

; ---------------------------------------------------------------------------
; image_sniff
;   IN: rdi = data, rsi = len — OUT: rax = IMAGE_FMT_*
; ---------------------------------------------------------------------------
global image_sniff
image_sniff:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 8
    jb image_sniff_short_formats
    push rdi
    push rsi
    call camera_probe
    pop rsi
    pop rdi
    test eax,eax
    jnz .sniff_return
    push rdi
    push rsi
    call modern_probe
    pop rsi
    pop rdi
    test eax,eax
    jnz .sniff_return
    cmp rsi,12
    jb .not_webp
    cmp dword [rdi],0x46464952       ; RIFF
    jne .not_webp
    cmp dword [rdi+8],0x50424557     ; WEBP
    jne .not_webp
    mov rax,IMAGE_FMT_WEBP
    jmp .sniff_return
.not_webp:
    ; PNG
    mov eax, [rdi]
    cmp eax, 0x474E5089  ; 89 'P' 'N' 'G' LE
    jne image_sniff_chk_qoi
    mov eax, [rdi + 4]
    cmp eax, 0x0A1A0A0D
    jne image_sniff_chk_jpeg
    mov rax, IMAGE_FMT_PNG
.sniff_return:
    leave
    ret

; Decode any self-describing supported image.
; IN rdi=arena, rsi=data, rdx=len, rcx=requested SVG width, r8=SVG height.
; OUT rax=PixBuf* or 0.
global image_decode
image_decode:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov r15,r8
    mov rdi,r12
    mov rsi,r13
    call image_sniff
    cmp eax,IMAGE_FMT_PNG
    je .decode_png
    cmp eax,IMAGE_FMT_JPEG
    je .decode_jpeg
    cmp eax,IMAGE_FMT_GIF
    je .decode_gif
    cmp eax,IMAGE_FMT_BMP
    je .decode_bmp
    cmp eax,IMAGE_FMT_SVG
    je .decode_svg
    cmp eax,IMAGE_FMT_QOI
    je .decode_qoi
    cmp eax,IMAGE_FMT_TGA
    je .decode_tga
    cmp eax,IMAGE_FMT_PNM
    je .decode_pnm
    cmp eax,IMAGE_FMT_FARBFELD
    je .decode_farbfeld
    cmp eax,IMAGE_FMT_TIFF
    je .decode_tiff
    cmp eax,IMAGE_FMT_PCX
    je .decode_pcx
    cmp eax,IMAGE_FMT_ICO
    je .decode_ico
    cmp eax,IMAGE_FMT_DDS
    je .decode_dds
    cmp eax,IMAGE_FMT_KTX
    je .decode_ktx
    cmp eax,IMAGE_FMT_KTX2
    je .decode_ktx2
    cmp eax,IMAGE_FMT_HDR
    je .decode_hdr
    cmp eax,IMAGE_FMT_EXR
    je .decode_exr
    cmp eax,IMAGE_FMT_PSD
    je .decode_psd
    cmp eax,IMAGE_FMT_WEBP
    je .decode_webp
    cmp eax,IMAGE_FMT_CR2
    jb .not_camera
    cmp eax,IMAGE_FMT_RW2
    jbe .decode_camera
.not_camera:
    ; AVIF/HEIF/JXL are recognized but intentionally deferred (Decision 0011).
    xor eax,eax
    jmp .decode_done
.decode_png:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call png_decode
    jmp .decode_done
.decode_jpeg:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call jpeg_decode
    jmp .decode_done
.decode_gif:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call gif_decode_first
    jmp .decode_done
.decode_bmp:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call bmp_decode
    jmp .decode_done
.decode_svg:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    mov rcx,r14
    mov r8,r15
    call svg_render
    jmp .decode_return                  ; ugfx draws premultiplied already
.decode_qoi:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call qoi_decode
    jmp .decode_done
.decode_tga:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call tga_decode
    jmp .decode_done
.decode_pnm:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call pnm_decode
    jmp .decode_done
.decode_farbfeld:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call farbfeld_decode
    jmp .decode_done
.decode_tiff:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call tiff_decode
    jmp .decode_done
.decode_pcx:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call pcx_decode
    jmp .decode_done
.decode_ico:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call ico_decode
    jmp .decode_done
.decode_dds:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call dds_decode
    jmp .decode_done
.decode_ktx:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call ktx_decode
    jmp .decode_done
.decode_ktx2:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call ktx2_decode
    jmp .decode_done
.decode_hdr:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call hdr_decode
    jmp .decode_done
.decode_exr:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call exr_decode
    jmp .decode_done
.decode_psd:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call psd_decode
    jmp .decode_done
.decode_webp:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call webp_decode
    jmp .decode_done
.decode_camera:
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call camera_decode
.decode_done:
    ; Decoders produce straight alpha; Canvas buffers are premultiplied
    ; (SVG excepted: it is drawn premultiplied).
    test rax,rax
    jle .decode_return
    mov rbx,rax
    mov rdi,rax
    call pixbuf_premultiply
    mov rax,rbx
.decode_return:
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
image_sniff_chk_qoi:
    cmp word [rdi],0x4949
    jne .not_dng
    cmp word [rdi+2],42
    jne .not_dng
    mov rax,IMAGE_FMT_TIFF
    leave
    ret
.not_dng:
    cmp dword [rdi],0x62726166       ; "farb"
    jne image_sniff_not_farbfeld
    cmp dword [rdi+4],0x646C6566
    jne image_sniff_not_farbfeld
    mov rax,IMAGE_FMT_FARBFELD
    leave
    ret
image_sniff_not_farbfeld:
    cmp dword [rdi],0x53504238
    jne .not_psd
    mov rax,IMAGE_FMT_PSD
    leave
    ret
.not_psd:
    cmp dword [rdi],0x01312F76
    jne .not_exr
    mov rax,IMAGE_FMT_EXR
    leave
    ret
.not_exr:
    cmp dword [rdi],0x41523F23
    je .is_hdr
    cmp dword [rdi],0x47523F23
    jne .not_hdr
.is_hdr:
    mov rax,IMAGE_FMT_HDR
    leave
    ret
.not_hdr:
    cmp dword [rdi],0x20534444
    jne .not_dds
    mov rax,IMAGE_FMT_DDS
    leave
    ret
.not_dds:
    cmp dword [rdi],0x58544BAB
    jne .not_ktx
    cmp dword [rdi+4],0xBB313120
    je .is_ktx
    cmp dword [rdi+4],0xBB323020
    je .is_ktx2
    jmp .not_ktx
.is_ktx:
    mov rax,IMAGE_FMT_KTX
    leave
    ret
.is_ktx2:
    mov rax,IMAGE_FMT_KTX2
    leave
    ret
.not_ktx:
    cmp word [rdi],0
    jne .not_ico
    movzx eax,word [rdi+2]
    cmp eax,1
    je .is_ico
    cmp eax,2
    jne .not_ico
.is_ico:
    mov rax,IMAGE_FMT_ICO
    leave
    ret
.not_ico:
    cmp byte [rdi],10
    jne .not_pcx
    cmp byte [rdi+2],1
    jne .not_pcx
    cmp byte [rdi+3],8
    jne .not_pcx
    mov rax,IMAGE_FMT_PCX
    leave
    ret
.not_pcx:
    cmp dword [rdi], 0x66696F71 ; "qoif"
    jne image_sniff_chk_jpeg
    cmp rsi, 14
    jb image_sniff_unknown
    mov rax, IMAGE_FMT_QOI
    leave
    ret
image_sniff_chk_jpeg:
    cmp rsi, 2
    jb image_sniff_unknown
    movzx eax, word [rdi]
    cmp eax, 0xD8FF
    jne image_sniff_chk_gif
    mov rax, IMAGE_FMT_JPEG
    leave
    ret
image_sniff_chk_gif:
    cmp rsi, 6
    jb image_sniff_unknown
    mov eax, [rdi]
    cmp eax, 0x38464947
    jne image_sniff_chk_bmp
    mov rax, IMAGE_FMT_GIF
    leave
    ret
image_sniff_chk_bmp:
    cmp rsi, 2
    jb image_sniff_unknown
    movzx eax, word [rdi]
    cmp eax, 0x4D42
    jne image_sniff_chk_pnm
    mov rax, IMAGE_FMT_BMP
    leave
    ret
image_sniff_chk_pnm:
    cmp byte [rdi], 'P'
    jne image_sniff_chk_tga
    cmp byte [rdi + 1], '5'
    je image_sniff_pnm
    cmp byte [rdi + 1], '4'
    je image_sniff_pnm
    cmp byte [rdi + 1], '6'
    jne image_sniff_chk_tga
image_sniff_pnm:
    mov rax, IMAGE_FMT_PNM
    leave
    ret
image_sniff_chk_tga:
    cmp rsi, 18
    jb image_sniff_chk_svg
    mov al, [rdi + 2]
    cmp al, 2
    je image_sniff_tga
    cmp al, 3
    je image_sniff_tga
    cmp al, 10
    je image_sniff_tga
    cmp al, 11
    jne image_sniff_chk_svg
image_sniff_tga:
    mov rax, IMAGE_FMT_TGA
    leave
    ret
image_sniff_chk_svg:
    mov rdi, rdi
    call svg_probe
    test rax, rax
    jz image_sniff_unknown
    mov rax, IMAGE_FMT_SVG
    leave
    ret
image_sniff_unknown:
    xor rax, rax
    leave
    ret
image_sniff_short_formats:
    cmp rsi, 2
    jb image_sniff_unknown
    jmp image_sniff_chk_jpeg

section .data
global sniff_version
sniff_version: dq 0x010000
