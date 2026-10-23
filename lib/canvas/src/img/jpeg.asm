; ============================================================================
; JPEG — Baseline Decoder (Huffman + IDCT + YCbCr->BGRA)
; Structure mirrors the PNG path: parse, decode, convert
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/image.inc"

extern arena_alloc
extern pixbuf_create
extern fill_solid
extern jpeg_huff_build
extern jpeg_bits_init
extern jpeg_decode_block
extern jpeg_decode_component_mcu
extern jpeg_upsample_component
extern jpeg_write_color_mcu
extern jpeg_expect_restart

; struct offsets (hoisted above use)
%define JPEG_SOI       0xD8FF
%define JPEG_EOI       0xD9FF
%define JPEG_SOF0      0xC0FF
%define JPEG_SOF2      0xC2FF
%define JPEG_DHT       0xC4FF
%define JPEG_DQT       0xDBFF
%define JPEG_DRI       0xDDFF
%define JPEG_SOS       0xDAFF
%define JPEG_APP0      0xE0FF
%define JPEG_HUFF_TABLE_SIZE 1556

section .text


struc JpegImage
    .width:         resd 1
    .height:        resd 1
    .components:    resb 1
    .progressive:   resb 1
    .qtables:       resq 1
    .htables:       resq 1
    .restart:       resd 1
    .pixbuf:        resq 1
    .arena:         resq 1
    .component_id:  resb 4
    .component_h:   resb 4
    .component_v:   resb 4
    .component_qt:  resb 4
    .max_h:         resb 1
    .max_v:         resb 1
    .scan_count:    resb 1
    .scan_id:       resb 4
    .scan_dc:       resb 4
    .scan_ac:       resb 4
    .entropy:       resq 1
    .entropy_end:   resq 1
endstruc

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
    leave
    ret
.no:
    xor rax, rax
    leave
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
    mov rdi, r14
    xor eax, eax
    mov ecx, JpegImage_size
    rep stosb
    mov [r14 + JpegImage.arena], rbx
    ; Four 64-entry quantization tables.
    mov rdi, rbx
    mov esi, 1024
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r14 + JpegImage.qtables], rax
    mov rdi, rax
    xor eax, eax
    mov ecx, 128
    rep stosq
    ; Four DC plus four AC canonical Huffman tables.
    mov rdi, rbx
    mov esi, JPEG_HUFF_TABLE_SIZE * 8
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r14 + JpegImage.htables], rax
    mov rdi, rax
    xor eax, eax
    mov ecx, (JPEG_HUFF_TABLE_SIZE * 8) / 8
    rep stosq
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
    js .oom
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
    lea rax, [r12 + r13]
    mov [rbx + JpegImage.entropy_end], rax
    add r12, 2
    sub r13, 2
.loop:
    cmp r13, 4
    jb .done
    movzx eax, word [r12]
    mov r14d, eax
    cmp al, 0xFF
    jne .fail
    cmp ah, 0xD8
    je .skip2
    cmp ah, 0xD9
    je .done
    cmp ah, 0x01
    je .skip2
    ; markers with length
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    cmp ecx, 2
    jb .fail
    lea rax, [rcx + 2]
    cmp rax, r13
    ja .fail
    cmp r14w, JPEG_SOF0
    je .sof
    cmp r14w, JPEG_SOF2
    je .sof_prog
    ; DQT/DHT/DRI captured by helpers
    cmp r14w, JPEG_DQT
    je .dqt
    cmp r14w, JPEG_DHT
    je .dht
    cmp r14w, JPEG_DRI
    je .dri
    cmp r14w, JPEG_SOS
    je .sos
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
    cmp ecx, 11
    jb .fail
    cmp byte [r12 + 4], 8
    jne .fail
    ; SOF payload: precision, height, width, component count.
    movzx eax, word [r12 + 5]
    xchg al, ah
    mov [rbx + JpegImage.height], eax
    movzx eax, word [r12 + 7]
    xchg al, ah
    mov [rbx + JpegImage.width], eax
    movzx eax, byte [r12 + 9]
    cmp eax, 1
    je .sof_components_ok
    cmp eax, 3
    jne .fail
.sof_components_ok:
    lea edx, [rax + rax * 2 + 8]
    cmp ecx, edx
    jne .fail
    mov [rbx + JpegImage.components], al
    xor edx, edx
    mov byte [rbx + JpegImage.max_h], 0
    mov byte [rbx + JpegImage.max_v], 0
.sof_component_loop:
    movzx eax, byte [rbx + JpegImage.components]
    cmp edx, eax
    jae .sof_component_done
    lea r8d, [rdx + rdx * 2]
    movzx r9d, byte [r12 + r8 + 10]
    mov [rbx + JpegImage.component_id + rdx], r9b
    movzx r9d, byte [r12 + r8 + 11]
    mov r10d, r9d
    shr r9d, 4
    and r10d, 15
    test r9d, r9d
    jz .fail
    test r10d, r10d
    jz .fail
    cmp r9d, 4
    ja .fail
    cmp r10d, 4
    ja .fail
    mov [rbx + JpegImage.component_h + rdx], r9b
    mov [rbx + JpegImage.component_v + rdx], r10b
    cmp r9b, [rbx + JpegImage.max_h]
    jbe .sof_check_v
    mov [rbx + JpegImage.max_h], r9b
.sof_check_v:
    cmp r10b, [rbx + JpegImage.max_v]
    jbe .sof_component_qt
    mov [rbx + JpegImage.max_v], r10b
.sof_component_qt:
    movzx r9d, byte [r12 + r8 + 12]
    cmp r9d, 3
    ja .fail
    mov [rbx + JpegImage.component_qt + rdx], r9b
    inc edx
    jmp .sof_component_loop
.sof_component_done:
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.sof_prog:
    cmp ecx, 11
    jb .fail
    cmp byte [r12 + 4], 8
    jne .fail
    mov byte [rbx + JpegImage.progressive], 1
    movzx eax, word [r12 + 5]
    xchg al, ah
    mov [rbx + JpegImage.height], eax
    movzx eax, word [r12 + 7]
    xchg al, ah
    mov [rbx + JpegImage.width], eax
    movzx eax, byte [r12 + 9]
    cmp eax, 1
    je .sof_prog_components_ok
    cmp eax, 3
    jne .fail
.sof_prog_components_ok:
    lea edx, [rax + rax * 2 + 8]
    cmp ecx, edx
    jne .fail
    mov [rbx + JpegImage.components], al
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.dqt:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rcx
    call jpeg_read_dqt
    test rax, rax
    jnz .fail
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.dht:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rcx
    call jpeg_read_dht
    test rax, rax
    jnz .fail
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.dri:
    cmp ecx, 4
    jne .fail
    movzx eax, word [r12 + 4]
    xchg al, ah
    mov [rbx + JpegImage.restart], eax
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    jmp .next
.sos:
    cmp ecx, 8
    jb .fail
    movzx eax, byte [r12 + 4]
    test eax, eax
    jz .fail
    movzx edx, byte [rbx + JpegImage.components]
    cmp eax, edx
    ja .fail
    lea edx, [rax + rax + 6]
    cmp ecx, edx
    jne .fail
    mov [rbx + JpegImage.scan_count], al
    xor edx, edx
.sos_component:
    cmp edx, eax
    jae .sos_params
    lea r8d, [rdx + rdx]
    movzx r9d, byte [r12 + r8 + 5]
    mov [rbx + JpegImage.scan_id + rdx], r9b
    movzx r9d, byte [r12 + r8 + 6]
    mov r10d, r9d
    shr r9d, 4
    and r10d, 0x0F
    cmp r9d, 3
    ja .fail
    cmp r10d, 3
    ja .fail
    mov [rbx + JpegImage.scan_dc + rdx], r9b
    mov [rbx + JpegImage.scan_ac + rdx], r10b
    inc edx
    jmp .sos_component
.sos_params:
    lea r8d, [rax + rax]
    cmp byte [r12 + r8 + 5], 0
    jne .fail
    cmp byte [r12 + r8 + 6], 63
    jne .fail
    cmp byte [r12 + r8 + 7], 0
    jne .fail
    lea rax, [r12 + rcx + 2]
    cmp rax, [rbx + JpegImage.entropy_end]
    ja .fail
    mov [rbx + JpegImage.entropy], rax
    jmp .done
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    mov rax, -EINVAL
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; jpeg_read_dqt / jpeg_read_dht — validate and retain encoded table sets.
; ---------------------------------------------------------------------------
global jpeg_read_dqt
jpeg_read_dqt:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r13, 67
    jb .table_bad
    lea r8, [r12 + 4]
    lea r9, [r12 + r13 + 2]
    mov r15, [rbx + JpegImage.qtables]
    test r15, r15
    jz .table_bad
.dqt_table:
    cmp r8, r9
    jae .dqt_ok
    movzx eax, byte [r8]
    mov ecx, eax
    and ecx, 0x0F
    cmp ecx, 3
    ja .table_bad
    shr eax, 4
    cmp eax, 1
    ja .table_bad
    inc r8
    mov r14d, eax                   ; precision: 0=8-bit, 1=16-bit
    mov eax, ecx
    shl eax, 8
    lea r13, [r15 + rax]            ; decoded table destination
    mov eax, 64
    test r14d, r14d
    jz .dqt_have_bytes
    shl eax, 1
.dqt_have_bytes:
    lea rdx, [r8 + rax]
    cmp rdx, r9
    ja .table_bad
    xor ecx, ecx
.dqt_value:
    test r14d, r14d
    jnz .dqt_value16
    movzx eax, byte [r8]
    inc r8
    jmp .dqt_store
.dqt_value16:
    movzx eax, word [r8]
    xchg al, ah
    add r8, 2
.dqt_store:
    test eax, eax
    jz .table_bad
    lea rdx, [rel jpeg_zigzag_order]
    movzx edx, byte [rdx + rcx]
    mov [r13 + rdx * 4], eax
    inc ecx
    cmp ecx, 64
    jb .dqt_value
    jmp .dqt_table
.dqt_ok:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.table_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global jpeg_read_dht
jpeg_read_dht:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r13, 20
    jb .huff_bad
    lea r14, [r12 + 4]
    lea r15, [r12 + r13 + 2]
.huff_table:
    cmp r14, r15
    jae .huff_ok
    lea rax, [r14 + 17]
    cmp rax, r15
    ja .huff_bad
    movzx eax, byte [r14]
    mov ecx, eax
    and ecx, 0x0F
    cmp ecx, 3
    ja .huff_bad
    shr eax, 4
    cmp eax, 1
    ja .huff_bad
    lea r8, [r14 + 1]               ; counts
    mov r10d, eax                   ; class
    mov r11d, ecx                   ; destination id
    xor ecx, ecx
    xor edx, edx
.sum_counts:
    cmp ecx, 16
    jae .have_count
    movzx eax, byte [r8 + rcx]
    add edx, eax
    inc ecx
    jmp .sum_counts
.have_count:
    cmp edx, 256
    ja .huff_bad
    lea r9, [r8 + 16]               ; symbols
    lea r14, [r9 + rdx]             ; next encoded table
    cmp r14, r15
    ja .huff_bad
    mov eax, r10d
    shl eax, 2
    add eax, r11d
    imul eax, JPEG_HUFF_TABLE_SIZE
    mov rdi, [rbx + JpegImage.htables]
    test rdi, rdi
    jz .huff_bad
    add rdi, rax
    mov rsi, r8
    ; rdx already contains symbol count
    mov rcx, rdx
    mov rdx, r9
    call jpeg_huff_build
    test rax, rax
    jnz .huff_bad
    jmp .huff_table
.huff_ok:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.huff_bad:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; jpeg_decode_scan
;   Huffman decode + IDCT + color convert (delegates to helpers)
; ---------------------------------------------------------------------------
global jpeg_decode_scan
jpeg_decode_scan:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 192
    mov rbx, rdi
    ASSERT_PTR rbx
    cmp byte [rbx + JpegImage.progressive], 0
    jne .unsupported
    cmp byte [rbx + JpegImage.components], 1
    jne .maybe_color
    cmp byte [rbx + JpegImage.scan_count], 1
    jne .fail
    mov al, [rbx + JpegImage.scan_id]
    cmp al, [rbx + JpegImage.component_id]
    jne .fail
    cmp byte [rbx + JpegImage.component_h], 1
    jne .unsupported
    cmp byte [rbx + JpegImage.component_v], 1
    jne .unsupported
    mov rsi, [rbx + JpegImage.entropy]
    test rsi, rsi
    je .fail
    mov rdx, [rbx + JpegImage.entropy_end]
    sub rdx, rsi
    jbe .fail
    mov rdi, rsp
    call jpeg_bits_init
    test rax, rax
    jnz .fail

    movzx eax, byte [rbx + JpegImage.scan_dc]
    imul eax, JPEG_HUFF_TABLE_SIZE
    mov r12, [rbx + JpegImage.htables]
    add r12, rax
    movzx eax, byte [rbx + JpegImage.scan_ac]
    add eax, 4
    imul eax, JPEG_HUFF_TABLE_SIZE
    mov r13, [rbx + JpegImage.htables]
    add r13, rax
    movzx eax, byte [rbx + JpegImage.component_qt]
    shl eax, 8
    mov r14, [rbx + JpegImage.qtables]
    add r14, rax
    cmp dword [r12 + 272], 0       ; HuffTable.max_syms
    je .fail
    cmp dword [r13 + 272], 0
    jz .fail
    mov r15, [rbx + JpegImage.pixbuf]
    test r15, r15
    jz .fail
    mov dword [rsp + 160], 0       ; DC predictor
    mov dword [rsp + 172], 0       ; decoded MCU count
    mov dword [rsp + 176], 0       ; expected RST sequence
    mov dword [rsp + 164], 0       ; block y
.gray_block_y:
    mov eax, [rbx + JpegImage.height]
    add eax, 7
    shr eax, 3
    cmp [rsp + 164], eax
    jae .success
    mov dword [rsp + 168], 0       ; block x
.gray_block_x:
    mov eax, [rbx + JpegImage.width]
    add eax, 7
    shr eax, 3
    cmp [rsp + 168], eax
    jae .gray_next_row
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    lea rcx, [rsp + 160]
    mov r8, r14
    lea r9, [rsp + 32]
    call jpeg_decode_block
    test rax, rax
    jnz .fail
    xor r10d, r10d                 ; local y
.gray_copy_y:
    mov eax, [rsp + 164]
    shl eax, 3
    add eax, r10d
    cmp eax, [rbx + JpegImage.height]
    jae .gray_block_done
    mov r8d, eax
    imul r8, [r15 + PixBuf_stride]
    add r8, [r15 + PixBuf_data]
    xor r11d, r11d                 ; local x
.gray_copy_x:
    mov eax, [rsp + 168]
    shl eax, 3
    add eax, r11d
    cmp eax, [rbx + JpegImage.width]
    jae .gray_copy_next_y
    mov edx, r10d
    shl edx, 3
    add edx, r11d
    movzx ecx, word [rsp + 32 + rdx * 2]
    imul eax, 4
    mov [r8 + rax], cl
    mov [r8 + rax + 1], cl
    mov [r8 + rax + 2], cl
    mov byte [r8 + rax + 3], 0xFF
    inc r11d
    cmp r11d, 8
    jb .gray_copy_x
.gray_copy_next_y:
    inc r10d
    cmp r10d, 8
    jb .gray_copy_y
.gray_block_done:
    inc dword [rsp + 172]
    mov ecx, [rbx + JpegImage.restart]
    test ecx, ecx
    jz .gray_advance
    mov eax, [rsp + 172]
    xor edx, edx
    div ecx
    test edx, edx
    jnz .gray_advance
    ; Restart markers occur between intervals, never after the final MCU.
    mov eax, [rbx + JpegImage.width]
    add eax, 7
    shr eax, 3
    mov ecx, eax
    mov eax, [rbx + JpegImage.height]
    add eax, 7
    shr eax, 3
    imul eax, ecx
    cmp [rsp + 172], eax
    jae .gray_advance
    mov rdi, rsp
    mov esi, [rsp + 176]
    call jpeg_expect_restart
    test rax, rax
    jnz .fail
    mov dword [rsp + 160], 0
    inc dword [rsp + 176]
    and dword [rsp + 176], 7
.gray_advance:
    inc dword [rsp + 168]
    jmp .gray_block_x
.gray_next_row:
    inc dword [rsp + 164]
    jmp .gray_block_y
.success:
    xor rax, rax
    add rsp, 192
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.maybe_color:
    cmp byte [rbx + JpegImage.components], 3
    jne .unsupported
    mov rdi, rbx
    call jpeg_decode_color_scan
    add rsp, 192
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -EINVAL
    add rsp, 192
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.unsupported:
    mov rax, -ENOTSUP
    add rsp, 192
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; jpeg_decode_color_scan — interleaved three-component baseline scans
; ---------------------------------------------------------------------------
jpeg_decode_color_scan:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 80
    mov r13, rdi
    cmp byte [r13 + JpegImage.scan_count], 3
    jne .color_fail
    movzx eax, byte [r13 + JpegImage.max_h]
    test eax, eax
    jz .color_fail
    shl eax, 3
    mov [rsp + 56], eax             ; MCU width
    movzx eax, byte [r13 + JpegImage.max_v]
    test eax, eax
    jz .color_fail
    shl eax, 3
    mov [rsp + 60], eax             ; MCU height

    mov rsi, [r13 + JpegImage.entropy]
    test rsi, rsi
    jz .color_fail
    mov rdx, [r13 + JpegImage.entropy_end]
    sub rdx, rsi
    jbe .color_fail
    mov rdi, rsp
    call jpeg_bits_init
    test rax, rax
    jnz .color_fail
    mov dword [rsp + 32], 0
    mov dword [rsp + 36], 0
    mov dword [rsp + 40], 0         ; independent DC predictors
    mov dword [rsp + 64], 0         ; decoded MCU count
    mov dword [rsp + 68], 0         ; expected RST sequence

    ; Three maximum-size source planes plus three expanded planes.
    mov rdi, [r13 + JpegImage.arena]
    mov esi, 12288
    call arena_alloc
    test rax, rax
    jz .color_oom
    js .color_oom
    mov r12, rax
    mov rbx, [r13 + JpegImage.pixbuf]
    test rbx, rbx
    jz .color_fail
    mov dword [rsp + 48], 0         ; MCU y
.color_mcu_y:
    mov eax, [r13 + JpegImage.height]
    add eax, [rsp + 60]
    dec eax
    xor edx, edx
    div dword [rsp + 60]
    cmp [rsp + 48], eax
    jae .color_ok
    mov dword [rsp + 44], 0         ; MCU x
.color_mcu_x:
    mov eax, [r13 + JpegImage.width]
    add eax, [rsp + 56]
    dec eax
    xor edx, edx
    div dword [rsp + 56]
    cmp [rsp + 44], eax
    jae .color_next_mcu_row
    mov dword [rsp + 52], 0         ; frame component index
.color_component:
    mov ecx, [rsp + 52]
    cmp ecx, 3
    jae .color_emit
    mov al, [r13 + JpegImage.component_id + rcx]
    xor edx, edx
.color_find_scan:
    cmp edx, 3
    jae .color_fail
    cmp al, [r13 + JpegImage.scan_id + rdx]
    je .color_have_scan
    inc edx
    jmp .color_find_scan
.color_have_scan:
    movzx eax, byte [r13 + JpegImage.scan_dc + rdx]
    imul eax, JPEG_HUFF_TABLE_SIZE
    mov rsi, [r13 + JpegImage.htables]
    add rsi, rax                    ; DC table
    cmp dword [rsi + 272], 0
    je .color_fail
    movzx eax, byte [r13 + JpegImage.scan_ac + rdx]
    add eax, 4
    imul eax, JPEG_HUFF_TABLE_SIZE
    mov rdx, [r13 + JpegImage.htables]
    add rdx, rax                    ; AC table
    cmp dword [rdx + 272], 0
    je .color_fail
    mov ecx, [rsp + 52]
    movzx eax, byte [r13 + JpegImage.component_qt + rcx]
    shl eax, 8
    mov r8, [r13 + JpegImage.qtables]
    add r8, rax
    lea rax, [rcx * 8]
    shl rax, 8                      ; component * 2048
    lea r9, [r12 + rax]
    movzx r10d, byte [r13 + JpegImage.component_h + rcx]
    movzx r11d, byte [r13 + JpegImage.component_v + rcx]
    mov rdi, rsp
    lea rcx, [rsp + 32 + rcx * 4]
    call jpeg_decode_component_mcu
    test rax, rax
    jnz .color_fail

    mov ecx, [rsp + 52]
    lea rax, [rcx * 8]
    shl rax, 8
    lea rsi, [r12 + rax]
    lea rdi, [r12 + 6144 + rax]
    movzx edx, byte [r13 + JpegImage.component_h + rcx]
    movzx ecx, byte [r13 + JpegImage.component_v + rcx]
    movzx r8d, byte [r13 + JpegImage.max_h]
    movzx r9d, byte [r13 + JpegImage.max_v]
    call jpeg_upsample_component
    test rax, rax
    jnz .color_fail
    inc dword [rsp + 52]
    jmp .color_component
.color_emit:
    mov rdi, rbx
    lea rsi, [r12 + 6144]
    lea rdx, [r12 + 8192]
    lea rcx, [r12 + 10240]
    mov r8d, [rsp + 44]
    imul r8d, [rsp + 56]
    mov r9d, [rsp + 48]
    imul r9d, [rsp + 60]
    mov r10d, [rsp + 56]
    mov r11d, [rsp + 60]
    call jpeg_write_color_mcu
    test rax, rax
    jnz .color_fail
    inc dword [rsp + 64]
    mov ecx, [r13 + JpegImage.restart]
    test ecx, ecx
    jz .color_advance
    mov eax, [rsp + 64]
    xor edx, edx
    div ecx
    test edx, edx
    jnz .color_advance
    mov eax, [r13 + JpegImage.width]
    add eax, [rsp + 56]
    dec eax
    xor edx, edx
    div dword [rsp + 56]
    mov ecx, eax
    mov eax, [r13 + JpegImage.height]
    add eax, [rsp + 60]
    dec eax
    xor edx, edx
    div dword [rsp + 60]
    imul eax, ecx
    cmp [rsp + 64], eax
    jae .color_advance
    mov rdi, rsp
    mov esi, [rsp + 68]
    call jpeg_expect_restart
    test rax, rax
    jnz .color_fail
    mov dword [rsp + 32], 0
    mov dword [rsp + 36], 0
    mov dword [rsp + 40], 0
    inc dword [rsp + 68]
    and dword [rsp + 68], 7
.color_advance:
    inc dword [rsp + 44]
    jmp .color_mcu_x
.color_next_mcu_row:
    inc dword [rsp + 48]
    jmp .color_mcu_y
.color_ok:
    xor eax, eax
    jmp .color_out
.color_unsupported:
    mov rax, -ENOTSUP
    jmp .color_out
.color_oom:
    mov rax, -ENOMEM
    jmp .color_out
.color_fail:
    mov rax, -EINVAL
.color_out:
    add rsp, 80
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .rodata
jpeg_zigzag_order:
    db 0, 1, 8, 16, 9, 2, 3, 10
    db 17, 24, 32, 25, 18, 11, 4, 5
    db 12, 19, 26, 33, 40, 48, 41, 34
    db 27, 20, 13, 6, 7, 14, 21, 28
    db 35, 42, 49, 56, 57, 50, 43, 36
    db 29, 22, 15, 23, 30, 37, 44, 51
    db 58, 59, 52, 45, 38, 31, 39, 46
    db 53, 60, 61, 54, 47, 55, 62, 63

section .data
global jpeg_version
jpeg_version: dq 0x010000
