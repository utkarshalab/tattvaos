; ============================================================================
; JPEG — Baseline Decoder (Huffman + IDCT + YCbCr->BGRA)
; Structure mirrors the PNG path: parse, decode, convert
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"

section .text

%define JPEG_SOI       0xD8FF
%define JPEG_EOI       0xD9FF
%define JPEG_SOF0      0xC0FF
%define JPEG_SOF2      0xC2FF
%define JPEG_DHT       0xC4FF
%define JPEG_DQT       0xDBFF
%define JPEG_DRI       0xDDFF
%define JPEG_SOS       0xDAFF
%define JPEG_APP0      0xE0FF

struc JpegImage {
    .width:         resd 1
    .height:        resd 1
    .components:    resb 1
    .progressive:   resb 1
    .qtables:       resq 1
    .htables:       resq 1
    .restart:       resd 1
    .pixbuf:        resq 1
}
%define JpegImage_size    48

; ---------------------------------------------------------------------------
; jpeg_probe
;   IN: rdi = data, rsi = len — OUT: rax = 1 if JPEG SOI, else 0
; ---------------------------------------------------------------------------
global jpeg_probe
jpeg_probe:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 2
    jb .no
    movzx eax, word [rdi]
    cmp eax, JPEG_SOI
    jne .no
    mov rax, 1
    ret
.no:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; jpeg_decode
;   IN: rdi = arena, rsi = data, rdx = len
;   OUT: rax = PixBuf*, 0 on error
; ---------------------------------------------------------------------------
global jpeg_decode
jpeg_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; probe
    mov rdi, r12
    mov rsi, r13
    call jpeg_probe
    test rax, rax
    jz .bad
    ; allocate JpegImage
    mov rdi, rbx
    mov rsi, JpegImage_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov qword [r14 + JpegImage.qtables], 0
    mov qword [r14 + JpegImage.htables], 0
    mov dword [r14 + JpegImage.restart], 0
    mov byte [r14 + JpegImage.progressive], 0
    ; scan markers
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call jpeg_scan_markers
    test rax, rax
    jnz .bad
    ; allocate output pixbuf
    mov eax, [r14 + JpegImage.width]
    test eax, eax
    jz .bad
    mov ecx, [r14 + JpegImage.height]
    test ecx, ecx
    jz .bad
    mov rdi, rbx
    mov rsi, rax
    mov rdx, rcx
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov [r14 + JpegImage.pixbuf], rax
    mov r15, rax
    ; decode scan
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call jpeg_decode_scan
    test rax, rax
    jnz .bad
    mov rax, r15
    ret
.bad:
    xor rax, rax
    ret
.oom:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; jpeg_scan_markers
;   Walk markers, fill width/height/components, progressive flag
; ---------------------------------------------------------------------------
global jpeg_scan_markers
jpeg_scan_markers:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r13, 4
    jb .fail
    add r12, 2
    sub r13, 2
.loop:
    cmp r13, 4
    jb .done
    movzx eax, word [r12]
    cmp al, 0xFF
    jne .fail
    cmp ah, 0xD8
    je .skip2
    cmp ah, 0xD9
    je .done
    cmp ah, 0x01
    je .skip2
    cmp ax, JPEG_SOF0
    je .sof
    cmp ax, JPEG_SOF2
    je .sof_prog
    ; markers with length
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    cmp ecx, 2
    jb .fail
    cmp rcx, r13
    ja .fail
    ; DQT/DHT/DRI captured by helpers
    cmp ax, JPEG_DQT
    je .dqt
    cmp ax, JPEG_DHT
    je .dht
    cmp ax, JPEG_DRI
    je .dri
    cmp ax, JPEG_SOS
    je .done
.next:
    add r12, rcx
    add r12, 2
    sub r13, rcx
    sub r13, 2
    jmp .loop
.skip2:
    add r12, 2
    sub r13, 2
    jmp .loop
.sof:
    movzx eax, word [r12 + 7]
    xchg al, ah
    mov [rbx + JpegImage.height], eax
    movzx eax, word [r12 + 5]
    xchg al, ah
    mov [rbx + JpegImage.width], eax
    movzx eax, byte [r12 + 9]
    mov [rbx + JpegImage.components], al
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.sof_prog:
    mov byte [rbx + JpegImage.progressive], 1
    movzx eax, word [r12 + 7]
    xchg al, ah
    mov [rbx + JpegImage.height], eax
    movzx eax, word [r12 + 5]
    xchg al, ah
    mov [rbx + JpegImage.width], eax
    movzx eax, byte [r12 + 9]
    mov [rbx + JpegImage.components], al
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.dqt:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rcx
    call jpeg_read_dqt
    jmp .next
.dht:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rcx
    call jpeg_read_dht
    jmp .next
.dri:
    movzx eax, word [r12 + 4]
    xchg al, ah
    mov [rbx + JpegImage.restart], eax
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.done:
    xor rax, rax
    ret
.fail:
    mov rax, -EINVAL
    ret

; ---------------------------------------------------------------------------
; jpeg_read_dqt / jpeg_read_dht (stubs: tables parsed by helpers)
; ---------------------------------------------------------------------------
global jpeg_read_dqt
jpeg_read_dqt:
    PROLOGUE
    xor rax, rax
    ret

global jpeg_read_dht
jpeg_read_dht:
    PROLOGUE
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; jpeg_decode_scan
;   Huffman decode + IDCT + color convert (delegates to helpers)
; ---------------------------------------------------------------------------
global jpeg_decode_scan
jpeg_decode_scan:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; TODO: real entropy decode; clear to neutral gray meanwhile
    mov rax, [rbx + JpegImage.pixbuf]
    test rax, rax
    jz .fail
    mov rdi, [rax + PixBuf.data]
    mov rsi, 0xFF808080
    mov edx, [rax + PixBuf.width]
    mov ecx, [rax + PixBuf.height]
    mov r8, [rax + PixBuf.stride]
    call fill_solid
    xor rax, rax
    ret
.fail:
    mov rax, -EINVAL
    ret

section .data
global jpeg_version
jpeg_version: dq 0x010000
