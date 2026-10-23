; ============================================================================
; Inflate — DEFLATE decompressor (RFC 1951: stored, fixed and dynamic blocks)
; Canonical Huffman decoding with count/symbol tables, one code bit at a time;
; every length, distance and table is bounds-checked against hostile input.
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

; Decoder state, kept on the stack of inflate and addressed through rbx.
%define S_SRC       0
%define S_SRCLEN    8
%define S_SRCPOS    16
%define S_BITBUF    24
%define S_BITCNT    32
%define S_ERR       36                ; set when input runs out
%define S_OUT       40
%define S_OUTCAP    48
%define S_OUTPOS    56
%define S_LASTBLK   64
%define S_LENCNT    72                ; u16 count[16] of the literal/length code
%define S_LENSYM    104               ; u16 symbol[288]
%define S_DISTCNT   680               ; u16 count[16] of the distance code
%define S_DISTSYM   712               ; u16 symbol[32]
%define S_LENGTHS   776               ; u8 code lengths, nlen + ndist <= 316
%define S_OFFS      1096              ; u16 offs[16], scratch for construction
%define S_SIZE      1136

%define INF_MAXBITS 15

section .text

; ---------------------------------------------------------------------------
; inflate
;   IN: rdi=arena (unused), rsi=src, rdx=src_len, rcx=out, r8=out_cap
;   OUT: rax = bytes written, -EINVAL on malformed input, -ENOSPC if out fills
; ---------------------------------------------------------------------------
global inflate
inflate:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, S_SIZE
    mov rbx, rsp
    test rsi, rsi
    jz .bad
    test rcx, rcx
    jz .bad
    mov [rbx + S_SRC], rsi
    mov [rbx + S_SRCLEN], rdx
    mov [rbx + S_OUT], rcx
    mov [rbx + S_OUTCAP], r8
    xor eax, eax
    mov [rbx + S_SRCPOS], rax
    mov [rbx + S_BITBUF], rax
    mov [rbx + S_BITCNT], eax
    mov [rbx + S_ERR], eax
    mov [rbx + S_OUTPOS], rax
.block:
    mov ecx, 1
    call inf_bits
    mov [rbx + S_LASTBLK], eax
    mov ecx, 2
    call inf_bits
    cmp eax, 0
    je .stored
    cmp eax, 1
    je .fixed
    cmp eax, 2
    je .dynamic
    jmp .bad
.stored:
    call inf_stored
    jmp .block_done
.fixed:
    call inf_fixed
    jmp .block_done
.dynamic:
    call inf_dynamic
.block_done:
    test eax, eax
    jnz .error
    cmp dword [rbx + S_ERR], 0
    jne .bad
    cmp dword [rbx + S_LASTBLK], 0
    je .block
    mov rax, [rbx + S_OUTPOS]
    add rsp, S_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.error:
    movsxd rax, eax
    add rsp, S_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
.bad:
    mov rax, -(EINVAL)
    add rsp, S_SIZE
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; inf_bits — rbx=state, ecx=count (0..13) -> eax = bits, LSB first.
;   Past the end of input it supplies zeros and sets S_ERR.
;   Clobbers rax, rcx, rdx, r8.
; ---------------------------------------------------------------------------
inf_bits:
    mov eax, [rbx + S_BITCNT]
.fill:
    cmp eax, ecx
    jae .have
    mov rdx, [rbx + S_SRCPOS]
    cmp rdx, [rbx + S_SRCLEN]
    jae .eof
    mov r8, [rbx + S_SRC]
    movzx r8d, byte [r8 + rdx]
    inc rdx
    mov [rbx + S_SRCPOS], rdx
    xchg ecx, eax
    shl r8, cl
    xchg ecx, eax
    or [rbx + S_BITBUF], r8
    add eax, 8
    jmp .fill
.eof:
    mov dword [rbx + S_ERR], 1
    add eax, 8
    jmp .fill
.have:
    sub eax, ecx
    mov [rbx + S_BITCNT], eax
    mov r8, [rbx + S_BITBUF]
    mov rdx, r8
    shr rdx, cl
    mov [rbx + S_BITBUF], rdx
    mov eax, 1
    shl eax, cl
    dec eax
    and eax, r8d
    ret

; ---------------------------------------------------------------------------
; inf_decode — rbx=state, rdi=count[16], rsi=symbol[] -> eax = symbol or -1.
;   Codes are read MSB-first; canonical codes of each length are consecutive.
;   Clobbers rax, rcx, rdx, r8, r9, r10, r11.
; ---------------------------------------------------------------------------
inf_decode:
    push r12
    xor r9d, r9d                      ; code
    xor r10d, r10d                    ; first code of this length
    xor r11d, r11d                    ; index of first symbol of this length
    mov r12d, 1
.decode_len:
    mov ecx, 1
    call inf_bits
    or r9d, eax
    movzx eax, word [rdi + r12 * 2]
    mov edx, r9d
    sub edx, r10d
    cmp edx, eax
    jb .decode_found
    add r11d, eax
    add r10d, eax
    shl r10d, 1
    shl r9d, 1
    inc r12d
    cmp r12d, INF_MAXBITS
    jbe .decode_len
    mov eax, -1                       ; ran out of codes: invalid
    pop r12
    ret
.decode_found:
    add edx, r11d
    movzx eax, word [rsi + rdx * 2]
    pop r12
    ret

; ---------------------------------------------------------------------------
; inf_construct — rbx=state, rdi=count[16], rsi=symbol[], rdx=lengths, ecx=n
;   -> eax = 0 complete code, > 0 incomplete, < 0 over-subscribed.
;   Clobbers rax, rcx, rdx, r8, r9.
; ---------------------------------------------------------------------------
inf_construct:
    push r12
    push r13
    mov r12, rdx
    mov r13d, ecx
    xor eax, eax
    xor ecx, ecx
.zero_counts:
    mov word [rdi + rcx * 2], ax
    inc ecx
    cmp ecx, 16
    jb .zero_counts
    xor ecx, ecx
.count:
    cmp ecx, r13d
    jae .counted
    movzx edx, byte [r12 + rcx]
    inc word [rdi + rdx * 2]
    inc ecx
    jmp .count
.counted:
    movzx eax, word [rdi]
    cmp eax, r13d
    je .construct_empty               ; no codes: complete, but decodes nothing
    mov eax, 1                        ; codes left to assign
    mov ecx, 1
.check:
    shl eax, 1
    movzx edx, word [rdi + rcx * 2]
    sub eax, edx
    js .construct_done                ; over-subscribed
    inc ecx
    cmp ecx, INF_MAXBITS
    jbe .check
    mov word [rbx + S_OFFS + 2], 0
    mov ecx, 1
.offsets:
    movzx edx, word [rbx + S_OFFS + rcx * 2]
    add dx, [rdi + rcx * 2]
    mov [rbx + S_OFFS + rcx * 2 + 2], dx
    inc ecx
    cmp ecx, INF_MAXBITS
    jb .offsets
    xor ecx, ecx
.symbols:
    cmp ecx, r13d
    jae .construct_done
    movzx edx, byte [r12 + rcx]
    test edx, edx
    jz .next_symbol
    movzx r8d, word [rbx + S_OFFS + rdx * 2]
    mov [rsi + r8 * 2], cx
    inc word [rbx + S_OFFS + rdx * 2]
.next_symbol:
    inc ecx
    jmp .symbols
.construct_empty:
    xor eax, eax
.construct_done:
    pop r13
    pop r12
    ret

; ---------------------------------------------------------------------------
; inf_stored — rbx=state -> eax = 0 or -errno. Copies one stored block.
; ---------------------------------------------------------------------------
inf_stored:
    mov qword [rbx + S_BITBUF], 0     ; drop the rest of the current byte
    mov dword [rbx + S_BITCNT], 0
    mov rdx, [rbx + S_SRCPOS]
    lea rax, [rdx + 4]
    cmp rax, [rbx + S_SRCLEN]
    ja .stored_bad
    mov r8, [rbx + S_SRC]
    movzx ecx, word [r8 + rdx]        ; LEN
    movzx eax, word [r8 + rdx + 2]    ; NLEN
    xor eax, 0xFFFF
    cmp eax, ecx
    jne .stored_bad
    add rdx, 4
    lea rax, [rdx + rcx]
    cmp rax, [rbx + S_SRCLEN]
    ja .stored_bad
    mov rax, [rbx + S_OUTPOS]
    add rax, rcx
    cmp rax, [rbx + S_OUTCAP]
    ja .stored_full
    mov rsi, r8
    add rsi, rdx
    mov rdi, [rbx + S_OUT]
    add rdi, [rbx + S_OUTPOS]
    add rdx, rcx
    mov [rbx + S_SRCPOS], rdx
    mov [rbx + S_OUTPOS], rax
    rep movsb
    xor eax, eax
    ret
.stored_bad:
    mov eax, -(EINVAL)
    ret
.stored_full:
    mov eax, -(ENOSPC)
    ret

; ---------------------------------------------------------------------------
; inf_fixed — rbx=state -> eax = 0 or -errno. Block with the fixed codes.
; ---------------------------------------------------------------------------
inf_fixed:
    lea rdi, [rbx + S_LENGTHS]
    mov al, 8
    mov ecx, 144
    rep stosb
    mov al, 9
    mov ecx, 112
    rep stosb
    mov al, 7
    mov ecx, 24
    rep stosb
    mov al, 8
    mov ecx, 8
    rep stosb
    lea rdi, [rbx + S_LENCNT]
    lea rsi, [rbx + S_LENSYM]
    lea rdx, [rbx + S_LENGTHS]
    mov ecx, 288
    call inf_construct
    lea rdi, [rbx + S_LENGTHS]
    mov al, 5
    mov ecx, 30
    rep stosb
    lea rdi, [rbx + S_DISTCNT]
    lea rsi, [rbx + S_DISTSYM]
    lea rdx, [rbx + S_LENGTHS]
    mov ecx, 30
    call inf_construct
    jmp inf_codes

; ---------------------------------------------------------------------------
; inf_dynamic — rbx=state -> eax = 0 or -errno. Block with transmitted codes.
; ---------------------------------------------------------------------------
inf_dynamic:
    push r12
    push r13
    push r14
    push r15
    mov ecx, 5
    call inf_bits
    lea r12d, [rax + 257]             ; nlen
    mov ecx, 5
    call inf_bits
    lea r13d, [rax + 1]               ; ndist
    mov ecx, 4
    call inf_bits
    lea r14d, [rax + 4]               ; ncode
    cmp r12d, 286
    ja .dyn_bad
    cmp r13d, 30
    ja .dyn_bad
    ; code-length code lengths, in permuted order; unsent ones are zero
    lea rdi, [rbx + S_LENGTHS]
    xor eax, eax
    mov ecx, 19
    rep stosb
    xor r15d, r15d
.dyn_clen:
    cmp r15d, r14d
    jae .dyn_clen_done
    mov ecx, 3
    call inf_bits
    lea rdx, [rel inf_clen_order]
    movzx edx, byte [rdx + r15]
    mov [rbx + S_LENGTHS + rdx], al
    inc r15d
    jmp .dyn_clen
.dyn_clen_done:
    lea rdi, [rbx + S_LENCNT]
    lea rsi, [rbx + S_LENSYM]
    lea rdx, [rbx + S_LENGTHS]
    mov ecx, 19
    call inf_construct
    test eax, eax
    jnz .dyn_bad                      ; the code-length code must be complete
    ; literal/length and distance code lengths
    lea r14d, [r12 + r13]             ; total lengths to read
    xor r15d, r15d
.dyn_len:
    cmp r15d, r14d
    jae .dyn_len_done
    cmp dword [rbx + S_ERR], 0
    jne .dyn_bad
    lea rdi, [rbx + S_LENCNT]
    lea rsi, [rbx + S_LENSYM]
    call inf_decode
    test eax, eax
    js .dyn_bad
    cmp eax, 16
    jae .dyn_repeat
    mov [rbx + S_LENGTHS + r15], al
    inc r15d
    jmp .dyn_len
.dyn_repeat:
    cmp eax, 16
    jne .dyn_zeros
    test r15d, r15d
    jz .dyn_bad                       ; nothing to repeat
    movzx r8d, byte [rbx + S_LENGTHS + r15 - 1]
    push r8
    mov ecx, 2
    call inf_bits
    pop r8
    add eax, 3
    jmp .dyn_fill
.dyn_zeros:
    xor r8d, r8d
    cmp eax, 17
    jne .dyn_zeros_long
    push r8
    mov ecx, 3
    call inf_bits
    pop r8
    add eax, 3
    jmp .dyn_fill
.dyn_zeros_long:
    push r8
    mov ecx, 7
    call inf_bits
    pop r8
    add eax, 11
.dyn_fill:
    lea edx, [r15 + rax]
    cmp edx, r14d
    ja .dyn_bad                       ; too many lengths
.dyn_fill_one:
    mov [rbx + S_LENGTHS + r15], r8b
    inc r15d
    dec eax
    jnz .dyn_fill_one
    jmp .dyn_len
.dyn_len_done:
    cmp byte [rbx + S_LENGTHS + 256], 0
    je .dyn_bad                       ; no end-of-block code
    lea rdi, [rbx + S_LENCNT]
    lea rsi, [rbx + S_LENSYM]
    lea rdx, [rbx + S_LENGTHS]
    mov ecx, r12d
    call inf_construct
    test eax, eax
    js .dyn_bad
    jz .dyn_dist
    movzx edx, word [rbx + S_LENCNT]  ; incomplete only allowed for one code
    mov eax, r12d
    sub eax, edx
    cmp eax, 1
    jne .dyn_bad
.dyn_dist:
    lea rdi, [rbx + S_DISTCNT]
    lea rsi, [rbx + S_DISTSYM]
    lea rdx, [rbx + S_LENGTHS]
    add rdx, r12
    mov ecx, r13d
    call inf_construct
    test eax, eax
    js .dyn_bad
    jz .dyn_codes
    movzx edx, word [rbx + S_DISTCNT]
    mov eax, r13d
    sub eax, edx
    cmp eax, 1
    jne .dyn_bad
.dyn_codes:
    pop r15
    pop r14
    pop r13
    pop r12
    jmp inf_codes
.dyn_bad:
    mov eax, -(EINVAL)
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; ---------------------------------------------------------------------------
; inf_codes — rbx=state -> eax = 0 or -errno. Decodes literals and matches
;   until end of block using S_LENCNT/S_LENSYM and S_DISTCNT/S_DISTSYM.
; ---------------------------------------------------------------------------
inf_codes:
    push r12
    push r13
.codes_next:
    cmp dword [rbx + S_ERR], 0
    jne .codes_bad
    lea rdi, [rbx + S_LENCNT]
    lea rsi, [rbx + S_LENSYM]
    call inf_decode
    test eax, eax
    js .codes_bad
    cmp eax, 256
    jb .codes_literal
    je .codes_end
    sub eax, 257
    cmp eax, 29
    jae .codes_bad
    lea rdx, [rel inf_len_base]
    movzx r12d, word [rdx + rax * 2]
    lea rdx, [rel inf_len_extra]
    movzx ecx, byte [rdx + rax]
    call inf_bits
    add r12d, eax                     ; match length
    lea rdi, [rbx + S_DISTCNT]
    lea rsi, [rbx + S_DISTSYM]
    call inf_decode
    test eax, eax
    js .codes_bad
    cmp eax, 30
    jae .codes_bad
    lea rdx, [rel inf_dist_base]
    movzx r13d, word [rdx + rax * 2]
    lea rdx, [rel inf_dist_extra]
    movzx ecx, byte [rdx + rax]
    call inf_bits
    add r13d, eax                     ; match distance
    mov rax, [rbx + S_OUTPOS]
    cmp r13, rax
    ja .codes_bad                     ; reaches before the start of output
    lea rdx, [rax + r12]
    cmp rdx, [rbx + S_OUTCAP]
    ja .codes_full
    mov rdi, [rbx + S_OUT]
    add rdi, rax
    mov rsi, rdi
    sub rsi, r13
    mov ecx, r12d
    mov [rbx + S_OUTPOS], rdx
    rep movsb                         ; byte order makes overlapping copies repeat
    jmp .codes_next
.codes_literal:
    mov rdx, [rbx + S_OUTPOS]
    cmp rdx, [rbx + S_OUTCAP]
    jae .codes_full
    mov rcx, [rbx + S_OUT]
    mov [rcx + rdx], al
    inc rdx
    mov [rbx + S_OUTPOS], rdx
    jmp .codes_next
.codes_end:
    xor eax, eax
    pop r13
    pop r12
    ret
.codes_bad:
    mov eax, -(EINVAL)
    pop r13
    pop r12
    ret
.codes_full:
    mov eax, -(ENOSPC)
    pop r13
    pop r12
    ret

section .rodata

inf_clen_order:
    db 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
inf_len_base:
    dw 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31
    dw 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
inf_len_extra:
    db 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2
    db 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
inf_dist_base:
    dw 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193
    dw 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145
    dw 8193, 12289, 16385, 24577
inf_dist_extra:
    db 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6
    db 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13

section .data
global inflate_version
inflate_version: dq 0x020000
