; ============================================================================
; Inflate — DEFLATE Decompressor (stored, fixed, dynamic Huffman)
; Bit reader state: {buf u64, nbits u64, src ptr, remain u64}
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)
%define BitState_SIZE 32
%define INFLATE_MAX_WINDOW  32768

section .text

struc BitState
    .buf:      resq 1
    .nbits:    resq 1
    .src:      resq 1
    .remain:   resq 1
endstruc


; ---------------------------------------------------------------------------
; inflate_bits
;   IN: rdi = BitState*, rsi = n (<=16) — OUT: rax = bits (LSB-first)
; ---------------------------------------------------------------------------
global inflate_bits
inflate_bits:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    cmp r12, 16
    ja .fail
.refill:
    mov rax, [rbx + BitState.nbits]
    cmp rax, r12
    jae .have
    mov rax, [rbx + BitState.remain]
    test rax, rax
    jz .fail
    mov rdx, [rbx + BitState.src]
    movzx edx, byte [rdx]
    inc qword [rbx + BitState.src]
    dec qword [rbx + BitState.remain]
    mov ecx, [rbx + BitState.nbits]
    shl rdx, cl
    or [rbx + BitState.buf], rdx
    add qword [rbx + BitState.nbits], 8
    jmp .refill
.have:
    mov rax, [rbx + BitState.buf]
    mov ecx, r12d
    mov edx, 1
    shl edx, cl
    dec edx
    and eax, edx
    shr qword [rbx + BitState.buf], cl
    sub qword [rbx + BitState.nbits], r12
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -1
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; inflate
;   IN: rdi=arena, rsi=src, rdx=src_len, rcx=out, r8=out_cap
;   OUT: rax = bytes written, negative error
; ---------------------------------------------------------------------------
global inflate
inflate:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    ; alloc bitstate + window is caller out buffer (sliding via out itself)
    sub rsp, BitState_size + HuffDec_size * 2 + 64
    mov rdi, rsp
    mov qword [rdi + BitState.buf], 0
    mov qword [rdi + BitState.nbits], 0
    mov qword [rdi + BitState.src], r12
    mov qword [rdi + BitState.remain], r13
    lea r12, [rsp + BitState_size]              ; litlen table
    lea r13, [rsp + BitState_size + HuffDec_size] ; dist table
    xor r14d, r14d  ; out pos in r14d? use rbx saved out base below
    mov rbx, r14    ; out base
    xor r14d, r14d
.block:
    ; BFINAL + BTYPE
    mov rdi, rsp
    mov rsi, 1
    call inflate_bits
    cmp rax, -1
    je .fail
    push rax  ; final
    mov rdi, rsp
    mov rsi, 2
    call inflate_bits
    cmp rax, -1
    je .fail2
    cmp eax, 0
    je .stored
    cmp eax, 1
    je .fixed
    cmp eax, 2
    je .dynamic
    jmp .fail2
.stored:
    ; align to byte
    mov rax, [rsp + BitState.nbits]
    and rax, 7
    mov cl, al
    shr qword [rsp + BitState.buf], cl
    sub qword [rsp + BitState.nbits], rax
    mov qword [rsp + BitState.buf], 0
    mov qword [rsp + BitState.nbits], 0
    ; LEN + NLEN
    mov rdi, [rsp + BitState.src]
    mov rax, [rsp + BitState.remain]
    cmp rax, 4
    jb .fail2
    movzx ecx, word [rdi]
    movzx edx, word [rdi + 2]
    not edx
    and edx, 0xFFFF
    cmp ecx, edx
    jne .fail2
    add qword [rsp + BitState.src], 4
    sub qword [rsp + BitState.remain], 4
    ; copy
    mov rax, [rsp + BitState.remain]
    cmp rax, rcx
    jb .fail2
    mov rax, r14
    add rax, rcx
    cmp rax, r15
    ja .full
    mov rdi, rbx
    add rdi, r14
    mov rsi, [rsp + BitState.src]
    mov rdx, rcx
    call memcopy
    add qword [rsp + BitState.src], rcx
    sub qword [rsp + BitState.remain], rcx
    add r14, rcx
    pop rax
    test rax, rax
    jnz .finish
    jmp .block
.fixed:
    ; build fixed tables
    mov rdi, r12
    call huff_fixed_litlen
    mov rdi, r13
    call huff_fixed_dist
    pop rax
    push rax
    jmp .codes
.dynamic:
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call inflate_dynamic
    test rax, rax
    jnz .fail2
    pop rax
    push rax
.codes:
    ; decode symbols until end-of-block
.sym:
    mov rdi, r12
    mov rsi, rsp
    call huff_decode
    test rax, rax
    js .fail2
    cmp eax, 256
    jb .literal
    je .endblock
    ; length/distance
    mov r8d, eax
    mov edi, r8d
    call inflate_length
    test rax, rax
    js .fail2
    mov r9d, eax        ; base length
    mov r10d, edx       ; extra bits
    test r10d, r10d
    jz .len_done
    mov rdi, rsp
    mov rsi, r10
    call inflate_bits
    cmp rax, -1
    je .fail2
    add r9d, eax
.len_done:
    mov rdi, r13
    mov rsi, rsp
    call huff_decode
    test rax, rax
    js .fail2
    mov rdi, rax
    call inflate_dist
    test rax, rax
    js .fail2
    mov r11d, eax       ; base distance
    mov r10d, edx
    test r10d, r10d
    jz .dist_done
    mov rdi, rsp
    mov rsi, r10
    call inflate_bits
    cmp rax, -1
    je .fail2
    add r11d, eax
.dist_done:
    mov r8d, r9d        ; length
    mov r9d, r11d       ; distance
    jmp .copy_match
.literal:
    mov edx, r14d
    cmp rdx, r15
    jae .full2
    mov [rbx + r14], al
    inc r14d
    jmp .sym
.endblock:
    pop rax
    test rax, rax
    jnz .finish
    jmp .block
.copy_match:
    ; r8d = length, r9d = distance; validate + copy (overlap-safe)
    test r8d, r8d
    jz .fail2
    test r9d, r9d
    jz .fail2
    mov eax, r14d
    cmp r9d, eax
    ja .fail2           ; distance beyond start
    mov eax, r14d
    add eax, r8d
    cmp rax, r15
    ja .full2
    mov r10d, r14d
    sub r10d, r9d       ; src index = outpos - dist
    lea r10, [rbx + r10]
    lea r11, [rbx + r14]
    mov ecx, r8d
.copy_byte:
    test ecx, ecx
    jz .copied
    mov al, [r10]
    mov [r11], al
    inc r10
    inc r11
    dec ecx
    jmp .copy_byte
.copied:
    add r14d, r8d
    jmp .sym
.finish:
    add rsp, BitState_size + HuffDec_size * 2 + 64
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail2:
    add rsp, 8
.fail:
    add rsp, BitState_size + HuffDec_size * 2 + 64
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.full:
    add rsp, 8
    add rsp, BitState_size + HuffDec_size * 2 + 64
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.full2:
    add rsp, 8
    add rsp, BitState_size + HuffDec_size * 2 + 64
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; huff_fixed_litlen / huff_fixed_dist
; ---------------------------------------------------------------------------
global huff_fixed_litlen
huff_fixed_litlen:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    sub rsp, 288
    mov r12, rsp
    xor eax, eax
    mov rcx, 144
.fill8:
    test rcx, rcx
    jz .f9
    mov byte [r12], 8
    inc r12
    dec rcx
    jmp .fill8
.f9:
    mov rcx, 112
.fill9:
    test rcx, rcx
    jz .f7
    mov byte [r12], 9
    inc r12
    dec rcx
    jmp .fill9
.f7:
    mov rcx, 24
.fill7:
    test rcx, rcx
    jz .f8b
    mov byte [r12], 7
    inc r12
    dec rcx
    jmp .fill7
.f8b:
    mov rcx, 8
.fill8b:
    test rcx, rcx
    jz .build
    mov byte [r12], 8
    inc r12
    dec rcx
    jmp .fill8b
.build:
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 288
    call huff_build
    add rsp, 288
    EPILOGUE_RESTORE rbx, r12
    ret

global huff_fixed_dist
huff_fixed_dist:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    sub rsp, 32
    mov rdi, rsp
    mov rcx, 32
    mov al, 5
    rep stosb
    mov rdi, rbx
    mov rsi, rsp
    mov rdx, 32
    call huff_build
    add rsp, 32
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; inflate_dynamic — build litlen+dist tables from header
; ---------------------------------------------------------------------------
global inflate_dynamic
inflate_dynamic:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi  ; bitstate
    mov r12, rsi  ; litlen table
    mov r13, rdx  ; dist table
    ; HLIT+257, HDIST+1, HCLEN+4
    mov rdi, rbx
    mov rsi, 5
    call inflate_bits
    cmp rax, -1
    je .fail
    add eax, 257
    mov r14d, eax
    mov rdi, rbx
    mov rsi, 5
    call inflate_bits
    cmp rax, -1
    je .fail
    inc eax
    mov r15d, eax
    mov rdi, rbx
    mov rsi, 4
    call inflate_bits
    cmp rax, -1
    je .fail
    add eax, 4
    mov r10d, eax  ; hclen
    cmp r14d, 288
    ja .fail
    cmp r15d, 32
    ja .fail
    ; order table on stack (19 bytes)
    sub rsp, 512
    mov rdi, rsp
    mov rcx, 64
    xor eax, eax
    rep stosq  ; zero 512
    lea rdi, [rsp + 320]  ; lengths buffer (up to 320)
    ; read hclen 3-bit lengths in perm order
    lea rsi, [cl_order]
    xor r8d, r8d
.cl_loop:
    cmp r8d, r10d
    jae .cl_done
    mov rdi, rbx
    mov rsi, 3
    call inflate_bits
    cmp rax, -1
    je .fail2
    movzx edx, byte [cl_order + r8]
    mov [rsp + 320 + rdx], al
    inc r8d
    jmp .cl_loop
.cl_done:
    ; build cl table at rsp+64 (HuffDec 304 bytes)
    lea rdi, [rsp + 64]
    lea rsi, [rsp + 320]
    mov rdx, 19
    call huff_build
    test rax, rax
    jnz .fail2
    ; decode hlit+hdist lengths into lengths buffer at rsp+384? reuse
    lea r9, [rsp + 400]  ; out lens (288+32 max 320)
    mov eax, r14d
    add eax, r15d
    mov r10d, eax  ; total
    xor r11d, r11d ; have
.lens:
    cmp r11d, r10d
    jae .split
    lea rdi, [rsp + 64]
    mov rsi, rbx
    call huff_decode
    test rax, rax
    js .fail2
    cmp eax, 15
    jbe .lit_len
    cmp eax, 16
    je .rep_prev
    cmp eax, 17
    je .rep_zero3
    cmp eax, 18
    je .rep_zero11
    jmp .fail2
.lit_len:
    mov [r9 + r11], al
    inc r11d
    jmp .lens
.rep_prev:
    ; copy previous 3-6 times
    mov rdi, rbx
    mov rsi, 2
    call inflate_bits
    cmp rax, -1
    je .fail2
    add eax, 3
    mov ecx, eax
    cmp r11d, 0
    je .fail2
    movzx edx, byte [r9 + r11 - 1]
.rep_p:
    test ecx, ecx
    jz .lens
    mov eax, r11d
    add eax, ecx
    cmp eax, r10d
    ja .fail2
    mov [r9 + r11], dl
    inc r11d
    dec ecx
    jmp .rep_p
.rep_zero3:
    mov rdi, rbx
    mov rsi, 3
    call inflate_bits
    cmp rax, -1
    je .fail2
    add eax, 3
    mov ecx, eax
    xor edx, edx
    jmp .rep_z
.rep_zero11:
    mov rdi, rbx
    mov rsi, 7
    call inflate_bits
    cmp rax, -1
    je .fail2
    add eax, 11
    mov ecx, eax
    xor edx, edx
.rep_z:
    mov eax, r11d
    add eax, ecx
    cmp eax, r10d
    ja .fail2
.rep_zloop:
    test ecx, ecx
    jz .lens
    mov [r9 + r11], dl
    inc r11d
    dec ecx
    jmp .rep_zloop
.split:
    ; split into litlen (hlit) + dist (hdist)
    mov rdi, r12
    mov rsi, r9
    mov rdx, r14
    call huff_build
    test rax, rax
    jnz .fail2
    ; single-distance-code edge: huff_build rejects incomplete; handle 1-sym
    mov rdi, r13
    lea rsi, [r9 + r14]
    mov rdx, r15
    call huff_build
    test rax, rax
    jnz .fail2
    add rsp, 512
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail2:
    add rsp, 512
.fail:
    mov rax, -1
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; inflate_length — length base + extra bits for symbol 257..285
;   IN: rdi = symbol — OUT: rax = base, rdx = extra bits count
; ---------------------------------------------------------------------------
global inflate_length
inflate_length:
    PROLOGUE
    mov eax, edi
    sub eax, 257
    cmp eax, 29
    ja .fail
    lea rdx, [length_base]
    mov eax, [rdx + rax * 4]
    push rax
    mov eax, edi
    sub eax, 257
    lea rdx, [length_extra]
    movzx edx, byte [rdx + rax]
    pop rax
    leave
    ret
.fail:
    mov rax, -1
    leave
    ret

; ---------------------------------------------------------------------------
; inflate_dist — distance base + extra for symbol 0..29
;   IN: rdi = symbol — OUT: rax = base, rdx = extra bits count
; ---------------------------------------------------------------------------
global inflate_dist
inflate_dist:
    PROLOGUE
    mov eax, edi
    cmp eax, 30
    jae .fail
    lea rdx, [dist_base]
    mov eax, [rdx + rax * 4]
    push rax
    lea rdx, [dist_extra]
    movzx edx, byte [rdx + rdi]
    pop rax
    leave
    ret
.fail:
    mov rax, -1
    leave
    ret

section .data
global inflate_version
inflate_version: dq 0x010000

section .rodata
align 4
cl_order: db 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15

length_base:
    dd 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31
    dd 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
length_extra:
    db 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2
    db 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
dist_base:
    dd 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193
    dd 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145
    dd 8193, 12289, 16385, 24577
dist_extra:
    db 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6
    db 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
