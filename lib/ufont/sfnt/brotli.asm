; =============================================================================
; Utkarsha OS — lib/ufont/sfnt/brotli.asm
; =============================================================================
; Brotli decompression (RFC 7932), for WOFF2 fonts, as tools/brotlimodel.py
; models it (tests/host/brotli_check.py checks both against the brotli
; module).
;
;   ufl_brotli(arena, data, length, out, capacity) -> rax = bytes written,
;       -1 for a damaged stream or one that does not fit
;
; The stream header's window; meta-blocks: last / empty, metadata skipped,
; uncompressed, compressed - block types and counts for literals,
; insert-and-copy codes and distances, the distance parameters, literal
; context modes, context maps (zero runs, inverse move-to-front), prefix
; codes (simple, and complex through the code length code), then the
; commands: literals by context, distances (the last four, the short
; codes, direct and postfix codes) and references into the static
; dictionary through its 121 transforms (sfnt/brotli_tables.asm). The end:
; zero padding, nothing after. Prefix codes decode a bit at a time,
; canonically (DEFLATE's convention). The whole output is the window.
; Its tables (some 800 KB) come from the arena.
; =============================================================================

extern arena_alloc
extern ufl_br_lut0
extern ufl_br_lut1
extern ufl_br_lut2
extern ufl_br_ndbits
extern ufl_br_dictoff
extern ufl_br_transforms
extern ufl_br_pool
extern ufl_br_dict

; a prefix code
%define CODE_COUNT      0               ; u16 x 16 codes per length
%define CODE_SINGLE     32              ; i32 the one symbol (0 bits), -1
%define CODE_SYMS       36              ; u16 symbols by length, then value
%define CODE_STRIDE(n)  ((36 + 2 * (n) + 3) & ~3)

%define LSTRIDE         CODE_STRIDE(256)
%define ISTRIDE         CODE_STRIDE(704)
%define DSTRIDE         CODE_STRIDE(520)
%define TSTRIDE         CODE_STRIDE(258)
%define CSTRIDE         CODE_STRIDE(26)
%define MSTRIDE         CODE_STRIDE(272)
%define CLSTRIDE        CODE_STRIDE(18)

; a block category
%define CT_N            0               ; u32 block types
%define CT_TYPE         4
%define CT_PREV         8
%define CT_COUNT        12
%define CT_TCODE        16              ; its block type code
%define CT_CCODE        24              ; its block count code
%define CT_SIZE         32

; the state (r15)
%define BR_SRC          0
%define BR_LEN          8
%define BR_POS          16
%define BR_BIT          24              ; u32
%define BR_ERR          28              ; u32
%define BR_OUT          32
%define BR_CAP          40
%define BR_N            48              ; bytes written
%define BR_END          56              ; the meta-block's end
%define BR_MAXBACK      64
%define BR_DIST         72              ; u32 x 4, the last last
%define BR_NPOST        88              ; u32
%define BR_NDIRECT      92
%define BR_NTREESL      96
%define BR_NTREESD      100
%define BR_LAST         104
%define BR_DSIZE        108
%define BR_CAT          112             ; CT x 3: literals, insert-and-copy, distances
%define BR_LCODES       208
%define BR_ICODES       216
%define BR_DCODES       224
%define BR_CMAPL        232             ; u8 x 64 x 256
%define BR_CMAPD        240             ; u8 x 4 x 256
%define BR_LENS         248             ; u8 x 704
%define BR_CLC          256             ; the code length code
%define BR_CMC          264             ; a context map's code
%define BR_MODES        272             ; u8 x 256
%define BR_MTF          280             ; u8 x 256
%define BR_ICMD         288             ; u32 the command
%define BR_ILEN         292
%define BR_CLEN         296
%define BR_SIZE         320

%define BR_TABLES       (256 * (LSTRIDE + ISTRIDE + DSTRIDE) + 3 * (TSTRIDE + CSTRIDE) + MSTRIDE + CLSTRIDE + 64 * 256 + 4 * 256 + 704 + 256 + 256 + 64)

section .rodata
br_cl_order:    db 1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15
align 4
br_block_off:   dd 1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753
                dd 1265, 2289, 4337, 8433, 16625
br_block_bits:  db 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 24
br_ins_bits:    db 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24
align 4
br_ins_off:     dd 0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210
                dd 22594
br_copy_bits:   db 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24
align 4
br_copy_off:    dd 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094
                dd 2118
; per 64-code cell: insert code base, copy code base
br_cells:       db 0, 0, 0, 8, 0, 0, 0, 8, 8, 0, 8, 8, 0, 16, 16, 0, 8, 16, 16, 8, 16, 16
; short distance codes: which of the last four (0 the last), delta
br_short:       db 0, 0, 1, 0, 2, 0, 3, 0, 0, -1, 0, 1, 0, -2, 0, 2, 0, -3, 0, 3, 1, -1, 1, 1, 1, -2, 1, 2
                db 1, -3, 1, 3

section .text

; ----------------------------------------------------------------------------
; ufl_brotli — rdi = arena, rsi = data, rdx = length, rcx = out, r8 = capacity
; ----------------------------------------------------------------------------
global ufl_brotli
ufl_brotli:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, BR_SIZE + 8
    mov r15, rsp
    mov [r15 + BR_SRC], rsi
    mov [r15 + BR_LEN], rdx
    mov [r15 + BR_OUT], rcx
    mov [r15 + BR_CAP], r8
    xor eax, eax
    mov [r15 + BR_POS], rax
    mov [r15 + BR_BIT], eax
    mov [r15 + BR_ERR], eax
    mov [r15 + BR_N], rax
    ; the tables
    mov esi, BR_TABLES
    call arena_alloc
    test rax, rax
    jz .bad
    mov [r15 + BR_LCODES], rax
    add rax, 256 * LSTRIDE
    mov [r15 + BR_ICODES], rax
    add rax, 256 * ISTRIDE
    mov [r15 + BR_DCODES], rax
    add rax, 256 * DSTRIDE
    lea rcx, [r15 + BR_CAT]
    xor edx, edx
.cat_codes:
    mov [rcx + CT_TCODE], rax
    add rax, TSTRIDE
    mov [rcx + CT_CCODE], rax
    add rax, CSTRIDE
    add rcx, CT_SIZE
    inc edx
    cmp edx, 3
    jb .cat_codes
    mov [r15 + BR_CMC], rax
    add rax, MSTRIDE
    mov [r15 + BR_CLC], rax
    add rax, CLSTRIDE
    mov [r15 + BR_CMAPL], rax
    add rax, 64 * 256
    mov [r15 + BR_CMAPD], rax
    add rax, 4 * 256
    mov [r15 + BR_LENS], rax
    add rax, 704
    mov [r15 + BR_MODES], rax
    add rax, 256
    mov [r15 + BR_MTF], rax
    ; WBITS
    mov ecx, 1
    call br_bits
    mov ebx, 16
    test eax, eax
    jz .window
    mov ecx, 3
    call br_bits
    lea ebx, [rax + 17]
    test eax, eax
    jnz .window
    mov ecx, 3
    call br_bits
    cmp eax, 1
    je .bad
    lea ebx, [rax + 8]
    test eax, eax
    jnz .window
    mov ebx, 17
.window:
    mov eax, 1
    mov ecx, ebx
    shl rax, cl
    sub rax, 16
    mov [r15 + BR_MAXBACK], rax
    mov dword [r15 + BR_DIST], 16
    mov dword [r15 + BR_DIST + 4], 15
    mov dword [r15 + BR_DIST + 8], 11
    mov dword [r15 + BR_DIST + 12], 4
.meta:
    cmp dword [r15 + BR_ERR], 0
    jne .bad
    mov ecx, 1
    call br_bits
    mov [r15 + BR_LAST], eax
    test eax, eax
    jz .not_last
    mov ecx, 1
    call br_bits
    test eax, eax
    jnz .end                            ; last and empty
.not_last:
    mov ecx, 2
    call br_bits
    cmp eax, 3
    je .metadata
    lea ebx, [rax + 4]                  ; nibbles
    xor r12d, r12d                      ; MLEN - 1
    xor ebp, ebp
.nibble:
    cmp ebp, ebx
    jae .mlen
    mov ecx, 4
    call br_bits
    lea ecx, [rbp + 1]
    cmp ecx, ebx
    jne .nibble_put
    cmp ebx, 4
    je .nibble_put
    test eax, eax
    jz .bad                             ; a last nibble 0 past four
.nibble_put:
    lea ecx, [rbp * 4]
    shl eax, cl
    or r12d, eax
    inc ebp
    jmp .nibble
.mlen:
    inc r12                             ; MLEN
    mov rax, [r15 + BR_N]
    add rax, r12
    cmp rax, [r15 + BR_CAP]
    ja .bad
    mov [r15 + BR_END], rax
    cmp dword [r15 + BR_LAST], 0
    jne .compressed
    mov ecx, 1
    call br_bits
    test eax, eax
    jz .compressed
    ; uncompressed: from the next byte
    call br_align
    cmp dword [r15 + BR_ERR], 0
    jne .bad
    mov rsi, [r15 + BR_POS]
    lea rax, [rsi + r12]
    cmp rax, [r15 + BR_LEN]
    ja .bad
    mov [r15 + BR_POS], rax
    add rsi, [r15 + BR_SRC]
    mov rdi, [r15 + BR_OUT]
    add rdi, [r15 + BR_N]
    mov rcx, r12
    rep movsb
    add [r15 + BR_N], r12
    jmp .meta
.metadata:
    mov ecx, 1
    call br_bits
    test eax, eax
    jnz .bad                            ; reserved
    mov ecx, 2
    call br_bits
    mov ebx, eax                        ; skip bytes
    xor r12d, r12d
    xor ebp, ebp
.skip_byte:
    cmp ebp, ebx
    jae .skip_len
    mov ecx, 8
    call br_bits
    lea ecx, [rbp + 1]
    cmp ecx, ebx
    jne .skip_put
    cmp ebx, 1
    jbe .skip_put
    test eax, eax
    jz .bad
.skip_put:
    lea ecx, [rbp * 8]
    shl eax, cl
    or r12d, eax
    inc ebp
    jmp .skip_byte
.skip_len:
    test ebx, ebx
    jz .skipping
    inc r12
.skipping:
    call br_align
    mov rax, [r15 + BR_POS]
    add rax, r12
    cmp rax, [r15 + BR_LEN]
    ja .bad
    mov [r15 + BR_POS], rax
    cmp dword [r15 + BR_LAST], 0
    jne .end
    jmp .meta
.compressed:
    call br_header
    cmp dword [r15 + BR_ERR], 0
    jne .bad
    call br_commands
    cmp dword [r15 + BR_ERR], 0
    jne .bad
    cmp dword [r15 + BR_LAST], 0
    je .meta
.end:
    ; zero padding to the byte, nothing after
    call br_align
    cmp dword [r15 + BR_ERR], 0
    jne .bad
    mov rax, [r15 + BR_POS]
    cmp rax, [r15 + BR_LEN]
    jne .bad
    mov rax, [r15 + BR_N]
    jmp .out
.bad:
    mov rax, -1
.out:
    add rsp, BR_SIZE + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; bits
; ----------------------------------------------------------------------------
; ecx = n (0..24) -> eax the next n bits (past the end: BR_ERR, zeros)
br_bits:
    xor eax, eax
    xor edx, edx
    mov r8, [r15 + BR_SRC]
    mov r9, [r15 + BR_POS]
    mov r10d, [r15 + BR_BIT]
.bit:
    cmp edx, ecx
    jae .done
    cmp r9, [r15 + BR_LEN]
    jae .past
    movzx r11d, byte [r8 + r9]
    push rcx
    mov ecx, r10d
    shr r11d, cl
    and r11d, 1
    mov ecx, edx
    shl r11d, cl
    pop rcx
    or eax, r11d
    inc r10d
    cmp r10d, 8
    jb .next
    xor r10d, r10d
    inc r9
.next:
    inc edx
    jmp .bit
.past:
    mov dword [r15 + BR_ERR], 1
.done:
    mov [r15 + BR_POS], r9
    mov [r15 + BR_BIT], r10d
    ret

; to the next byte: the bits skipped must be zero
br_align:
    mov ecx, [r15 + BR_BIT]
    test ecx, ecx
    jz .out
    mov rax, [r15 + BR_POS]
    cmp rax, [r15 + BR_LEN]
    jae .bad
    add rax, [r15 + BR_SRC]
    movzx eax, byte [rax]
    shr eax, cl
    jnz .bad
    mov dword [r15 + BR_BIT], 0
    inc qword [r15 + BR_POS]
.out:
    ret
.bad:
    mov dword [r15 + BR_ERR], 1
    ret

; ----------------------------------------------------------------------------
; prefix codes
; ----------------------------------------------------------------------------
; rdi = code -> eax its next symbol
br_read:
    push rbx
    push r12
    push r13
    push r14
    push rbp
    mov rbx, rdi
    mov eax, [rbx + CODE_SINGLE]
    test eax, eax
    jns .out
    xor r12d, r12d                      ; code
    xor r13d, r13d                      ; first
    xor r14d, r14d                      ; index
    mov ebp, 1                          ; length
.len:
    cmp ebp, 15
    ja .bad
    mov ecx, 1
    call br_bits
    or r12d, eax
    movzx ecx, word [rbx + CODE_COUNT + rbp * 2]
    lea eax, [r13 + rcx]
    cmp r12d, eax
    jl .found
    add r14d, ecx
    add r13d, ecx
    shl r13d, 1
    shl r12d, 1
    inc ebp
    jmp .len
.found:
    mov eax, r12d
    sub eax, r13d
    add eax, r14d
    movzx eax, word [rbx + CODE_SYMS + rax * 2]
    jmp .out
.bad:
    mov dword [r15 + BR_ERR], 1
    xor eax, eax
.out:
    pop rbp
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rdi = code, rsi = lengths (u8), edx = symbols: the canonical code built
br_build:
    push rbx
    sub rsp, 80                         ; u32 offsets x 16
    mov rbx, rdi
    mov dword [rbx + CODE_SINGLE], -1
    xor eax, eax
    mov ecx, 8
.zero:
    mov [rbx + CODE_COUNT + rcx * 4 - 4], eax
    dec ecx
    jnz .zero
    xor ecx, ecx
.count:
    cmp ecx, edx
    jae .counted
    movzx eax, byte [rsi + rcx]
    inc word [rbx + CODE_COUNT + rax * 2]
    inc ecx
    jmp .count
.counted:
    mov word [rbx + CODE_COUNT], 0
    xor eax, eax
    mov [rsp + 4], eax                  ; offsets[1] = 0
    mov ecx, 1
.offs:
    cmp ecx, 15
    jae .place
    movzx r8d, word [rbx + CODE_COUNT + rcx * 2]
    add eax, r8d
    mov [rsp + rcx * 4 + 4], eax
    inc ecx
    jmp .offs
.place:
    xor ecx, ecx
.sym:
    cmp ecx, edx
    jae .out
    movzx eax, byte [rsi + rcx]
    test eax, eax
    jz .sym_next
    mov r8d, [rsp + rax * 4]
    inc dword [rsp + rax * 4]
    mov [rbx + CODE_SYMS + r8 * 2], cx
.sym_next:
    inc ecx
    jmp .sym
.out:
    add rsp, 80
    pop rbx
    ret

; ----------------------------------------------------------------------------
; br_code — rdi = code, esi = alphabet size: a prefix code read and built
; ----------------------------------------------------------------------------
br_code:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 48                         ; [0..15] symbols (u32 x 4), [16] code length lengths (18)
    mov rbx, rdi
    mov r12d, esi
    mov ecx, 2
    call br_bits
    mov r13d, eax                       ; HSKIP
    cmp eax, 1
    jne .complex
    ; simple: up to four symbols of the alphabet's bits
    lea eax, [r12 - 1]
    bsr r14d, eax
    inc r14d                            ; bits (size >= 2)
    mov ecx, 2
    call br_bits
    lea ebp, [rax + 1]                  ; NSYM
    xor r13d, r13d
.simple_sym:
    cmp r13d, ebp
    jae .simple_check
    mov ecx, r14d
    call br_bits
    cmp eax, r12d
    jae .bad
    mov [rsp + r13 * 4], eax
    inc r13d
    jmp .simple_sym
.simple_check:
    ; distinct
    xor ecx, ecx
.di:
    cmp ecx, ebp
    jae .distinct
    lea edx, [rcx + 1]
.dj:
    cmp edx, ebp
    jae .di_next
    mov eax, [rsp + rcx * 4]
    cmp eax, [rsp + rdx * 4]
    je .bad
    inc edx
    jmp .dj
.di_next:
    inc ecx
    jmp .di
.distinct:
    cmp ebp, 1
    jne .simple_lens
    mov rdi, rbx
    mov rsi, [r15 + BR_LENS]
    xor edx, edx
    call br_build
    mov eax, [rsp]
    mov [rbx + CODE_SINGLE], eax
    jmp .out
.simple_lens:
    call .zero_lens
    mov rdi, [r15 + BR_LENS]
    mov eax, [rsp]
    mov byte [rdi + rax], 1
    mov eax, [rsp + 4]
    cmp ebp, 2
    jne .three
    mov byte [rdi + rax], 1
    jmp .build
.three:
    mov byte [rdi + rax], 2
    mov eax, [rsp + 8]
    mov byte [rdi + rax], 2
    cmp ebp, 3
    je .build
    ; four: 2, 2, 2, 2, or with the tree select bit 1, 2, 3, 3
    mov eax, [rsp + 12]
    mov byte [rdi + rax], 2
    mov eax, [rsp]
    mov byte [rdi + rax], 2
    mov ecx, 1
    call br_bits
    test eax, eax
    jz .build
    mov rdi, [r15 + BR_LENS]
    mov eax, [rsp]
    mov byte [rdi + rax], 1
    mov eax, [rsp + 8]
    mov byte [rdi + rax], 3
    mov eax, [rsp + 12]
    mov byte [rdi + rax], 3
    jmp .build
.complex:
    ; the code length code's lengths, in their order from HSKIP
    xor eax, eax
    mov [rsp + 16], rax
    mov [rsp + 24], rax
    mov [rsp + 32], eax
    mov r14d, 32                        ; space
    xor ebp, ebp                        ; codes
.cl:
    cmp r13d, 18
    jae .cl_done
    mov ecx, 1
    call br_bits
    test eax, eax
    jnz .cl_1
    mov ecx, 1
    call br_bits
    lea eax, [rax * 2 + rax]            ; 0 -> 0, 1 -> 3
    jmp .cl_have
.cl_1:
    mov ecx, 1
    call br_bits
    test eax, eax
    jnz .cl_11
    mov eax, 4
    jmp .cl_have
.cl_11:
    mov ecx, 1
    call br_bits
    test eax, eax
    jnz .cl_111
    mov eax, 2
    jmp .cl_have
.cl_111:
    mov ecx, 1
    call br_bits
    lea eax, [rax * 4 + 1]              ; 0 -> 1, 1 -> 5
.cl_have:
    lea rcx, [rel br_cl_order]
    movzx ecx, byte [rcx + r13]
    mov [rsp + 16 + rcx], al
    inc r13d
    test eax, eax
    jz .cl
    mov ecx, eax
    mov eax, 32
    shr eax, cl
    sub r14d, eax
    inc ebp
    test r14d, r14d
    jg .cl
.cl_done:
    cmp ebp, 1
    je .cl_ok
    test r14d, r14d
    jnz .bad
.cl_ok:
    mov rdi, [r15 + BR_CLC]
    lea rsi, [rsp + 16]
    mov edx, 18
    call br_build
    cmp ebp, 1
    jne .lengths
    xor ecx, ecx
.one:
    cmp byte [rsp + 16 + rcx], 0
    jne .one_have
    inc ecx
    jmp .one
.one_have:
    mov rax, [r15 + BR_CLC]
    mov [rax + CODE_SINGLE], ecx
.lengths:
    ; the symbols' lengths: repeats of the last nonzero (16) or of zeros (17)
    call .zero_lens
    xor r13d, r13d                      ; symbol
    mov dword [rsp], 8                  ; the last nonzero length
    mov dword [rsp + 4], 0              ; repeat
    mov dword [rsp + 8], 0              ; the repeated length
    mov r14d, 32768                     ; space
.sym:
    cmp r13d, r12d
    jae .sym_done
    test r14d, r14d
    jle .sym_done
    cmp dword [r15 + BR_ERR], 0
    jne .bad
    mov rdi, [r15 + BR_CLC]
    call br_read
    cmp eax, 16
    jae .repeat
    mov dword [rsp + 4], 0
    mov rdi, [r15 + BR_LENS]
    mov [rdi + r13], al
    inc r13d
    test eax, eax
    jz .sym
    mov [rsp], eax
    mov ecx, eax
    mov eax, 32768
    shr eax, cl
    sub r14d, eax
    jmp .sym
.repeat:
    mov ebp, 2                          ; extra bits
    mov edx, [rsp]                      ; 16: the last nonzero
    cmp eax, 16
    je .rep_len
    mov ebp, 3
    xor edx, edx
.rep_len:
    cmp edx, [rsp + 8]
    je .rep_same
    mov dword [rsp + 4], 0
    mov [rsp + 8], edx
.rep_same:
    mov eax, [rsp + 4]
    mov [rsp + 12], eax                 ; old
    test eax, eax
    jz .rep_add
    sub eax, 2
    mov ecx, ebp
    shl eax, cl
.rep_add:
    mov [rsp + 4], eax
    mov ecx, ebp
    call br_bits
    add eax, 3
    add [rsp + 4], eax
    mov eax, [rsp + 4]
    sub eax, [rsp + 12]                 ; delta
    lea ecx, [r13 + rax]
    cmp ecx, r12d
    ja .bad
    mov rdi, [r15 + BR_LENS]
    mov edx, [rsp + 8]
    mov ecx, eax
.rep_fill:
    test ecx, ecx
    jz .rep_space
    mov [rdi + r13], dl
    inc r13d
    dec ecx
    jmp .rep_fill
.rep_space:
    test edx, edx
    jz .sym
    mov ecx, 15
    sub ecx, edx
    shl eax, cl
    sub r14d, eax
    jmp .sym
.sym_done:
    test r14d, r14d
    jnz .bad
.build:
    mov rdi, rbx
    mov rsi, [r15 + BR_LENS]
    mov edx, r12d
    call br_build
    jmp .out
.bad:
    mov dword [r15 + BR_ERR], 1
.out:
    add rsp, 48
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.zero_lens:
    mov rdi, [r15 + BR_LENS]
    mov ecx, r12d
    xor eax, eax
    rep stosb
    ret

; -> eax NBLTYPES / NTREES (1 .. 256)
br_count:
    push rbx
    mov ecx, 1
    call br_bits
    mov ebx, 1
    test eax, eax
    jz .out
    mov ecx, 3
    call br_bits
    mov ebx, 1
    mov ecx, eax
    shl ebx, cl
    call br_bits
    add ebx, eax
    inc ebx
.out:
    mov eax, ebx
    pop rbx
    ret

; rdi = a block count code -> eax a block count
br_block_count:
    push rbx
    call br_read
    cmp eax, 26
    jae .bad
    lea rcx, [rel br_block_off]
    mov ebx, [rcx + rax * 4]
    lea rcx, [rel br_block_bits]
    movzx ecx, byte [rcx + rax]
    call br_bits
    add eax, ebx
    pop rbx
    ret
.bad:
    mov dword [r15 + BR_ERR], 1
    xor eax, eax
    pop rbx
    ret

; rdi = the map, esi = its size, edx = trees: a context map
br_context_map:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    cmp r13d, 2
    jae .coded
    mov ecx, r12d
    xor eax, eax
    rep stosb
    jmp .out
.coded:
    xor r14d, r14d                      ; RLEMAX
    mov ecx, 1
    call br_bits
    test eax, eax
    jz .rle
    mov ecx, 4
    call br_bits
    lea r14d, [rax + 1]
.rle:
    mov rdi, [r15 + BR_CMC]
    lea esi, [r13 + r14]
    call br_code
    xor ebp, ebp
.entry:
    cmp ebp, r12d
    jae .mtf
    cmp dword [r15 + BR_ERR], 0
    jne .out
    mov rdi, [r15 + BR_CMC]
    call br_read
    test eax, eax
    jz .zero
    cmp eax, r14d
    ja .tree
    mov ecx, eax                        ; a run of zeros
    mov edx, 1
    shl edx, cl
    push rdx
    sub rsp, 8
    call br_bits
    add rsp, 8
    pop rdx
    add eax, edx
    lea ecx, [rbp + rax]
    cmp ecx, r12d
    ja .bad
.zeros:
    mov byte [rbx + rbp], 0
    inc ebp
    dec eax
    jnz .zeros
    jmp .entry
.zero:
    mov byte [rbx + rbp], 0
    inc ebp
    jmp .entry
.tree:
    sub eax, r14d
    mov [rbx + rbp], al
    inc ebp
    jmp .entry
.mtf:
    mov ecx, 1
    call br_bits
    test eax, eax
    jz .out
    ; inverse move-to-front
    mov rdi, [r15 + BR_MTF]
    xor ecx, ecx
.mtf_init:
    mov [rdi + rcx], cl
    inc ecx
    cmp ecx, 256
    jb .mtf_init
    xor ebp, ebp
.imtf:
    cmp ebp, r12d
    jae .out
    movzx edx, byte [rbx + rbp]         ; v
    movzx eax, byte [rdi + rdx]         ; mtf[v]
    mov [rbx + rbp], al
    test edx, edx
    jz .imtf_next
.shift:
    mov cl, [rdi + rdx - 1]
    mov [rdi + rdx], cl
    dec edx
    jnz .shift
    mov [rdi], al
.imtf_next:
    inc ebp
    jmp .imtf
.bad:
    mov dword [r15 + BR_ERR], 1
.out:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; br_header: a compressed meta-block's header - categories, distance
;   parameters, context modes, context maps, prefix codes
; ----------------------------------------------------------------------------
br_header:
    push rbx
    push rbp
    push r12
    sub rsp, 16
    xor ebx, ebx
.cat:
    cmp ebx, 3
    jae .params
    imul r12d, ebx, CT_SIZE
    lea r12, [r15 + BR_CAT + r12]
    call br_count
    mov [r12 + CT_N], eax
    mov dword [r12 + CT_TYPE], 0
    mov dword [r12 + CT_PREV], 1
    mov dword [r12 + CT_COUNT], 1 << 24
    cmp eax, 2
    jb .cat_next
    mov rdi, [r12 + CT_TCODE]
    lea esi, [rax + 2]
    call br_code
    mov rdi, [r12 + CT_CCODE]
    mov esi, 26
    call br_code
    mov rdi, [r12 + CT_CCODE]
    call br_block_count
    mov [r12 + CT_COUNT], eax
.cat_next:
    inc ebx
    jmp .cat
.params:
    mov ecx, 2
    call br_bits
    mov [r15 + BR_NPOST], eax
    mov ecx, 4
    call br_bits
    mov ecx, [r15 + BR_NPOST]
    shl eax, cl
    mov [r15 + BR_NDIRECT], eax
    ; the distance alphabet: 16 + NDIRECT + 48 << NPOSTFIX
    mov edx, 48
    shl edx, cl
    lea eax, [rax + rdx + 16]
    mov [r15 + BR_DSIZE], eax
    ; context modes
    xor ebx, ebx
.mode:
    cmp ebx, [r15 + BR_CAT + CT_N]
    jae .maps
    mov ecx, 2
    call br_bits
    mov rcx, [r15 + BR_MODES]
    mov [rcx + rbx], al
    inc ebx
    jmp .mode
.maps:
    call br_count
    mov [r15 + BR_NTREESL], eax
    mov rdi, [r15 + BR_CMAPL]
    mov esi, [r15 + BR_CAT + CT_N]
    shl esi, 6
    mov edx, eax
    call br_context_map
    call br_count
    mov [r15 + BR_NTREESD], eax
    mov rdi, [r15 + BR_CMAPD]
    mov esi, [r15 + BR_CAT + 2 * CT_SIZE + CT_N]
    shl esi, 2
    mov edx, eax
    call br_context_map
    ; the prefix codes
    xor ebx, ebx
.lcode:
    cmp ebx, [r15 + BR_NTREESL]
    jae .icode0
    imul edi, ebx, LSTRIDE
    add rdi, [r15 + BR_LCODES]
    mov esi, 256
    call br_code
    inc ebx
    jmp .lcode
.icode0:
    xor ebx, ebx
.icode:
    cmp ebx, [r15 + BR_CAT + CT_SIZE + CT_N]
    jae .dcode0
    imul edi, ebx, ISTRIDE
    add rdi, [r15 + BR_ICODES]
    mov esi, 704
    call br_code
    inc ebx
    jmp .icode
.dcode0:
    xor ebx, ebx
.dcode:
    cmp ebx, [r15 + BR_NTREESD]
    jae .out
    imul edi, ebx, DSTRIDE
    add rdi, [r15 + BR_DCODES]
    mov esi, [r15 + BR_DSIZE]
    call br_code
    inc ebx
    jmp .dcode
.out:
    add rsp, 16
    pop r12
    pop rbp
    pop rbx
    ret

; edi = a category: a block switch when its count is out, one taken
br_next:
    push rbx
    push r12
    sub rsp, 8
    imul ebx, edi, CT_SIZE
    lea rbx, [r15 + BR_CAT + rbx]
    cmp dword [rbx + CT_COUNT], 0
    jne .take
    mov rdi, [rbx + CT_TCODE]
    call br_read
    mov r12d, [rbx + CT_PREV]
    test eax, eax
    jz .typed
    mov r12d, [rbx + CT_TYPE]
    inc r12d
    cmp eax, 1
    jne .explicit
    cmp r12d, [rbx + CT_N]
    jb .typed
    xor r12d, r12d
    jmp .typed
.explicit:
    lea r12d, [rax - 2]
.typed:
    cmp r12d, [rbx + CT_N]
    jae .bad
    mov eax, [rbx + CT_TYPE]
    mov [rbx + CT_PREV], eax
    mov [rbx + CT_TYPE], r12d
    mov rdi, [rbx + CT_CCODE]
    call br_block_count
    mov [rbx + CT_COUNT], eax
.take:
    dec dword [rbx + CT_COUNT]
    jmp .out
.bad:
    mov dword [r15 + BR_ERR], 1
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; br_commands: the meta-block's commands, to BR_END
; ----------------------------------------------------------------------------
br_commands:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    sub rsp, 32
.command:
    mov rax, [r15 + BR_N]
    cmp rax, [r15 + BR_END]
    jae .out
    cmp dword [r15 + BR_ERR], 0
    jne .out
    mov edi, 1
    call br_next
    mov eax, [r15 + BR_CAT + CT_SIZE + CT_TYPE]
    imul edi, eax, ISTRIDE
    add rdi, [r15 + BR_ICODES]
    call br_read
    mov [r15 + BR_ICMD], eax
    ; insert and copy codes from the cell
    mov ecx, eax
    shr ecx, 6
    cmp ecx, 11
    jae .bad
    lea rdx, [rel br_cells]
    movzx ebx, byte [rdx + rcx * 2]     ; insert code
    movzx ebp, byte [rdx + rcx * 2 + 1] ; copy code
    mov ecx, eax
    shr ecx, 3
    and ecx, 7
    add ebx, ecx
    and eax, 7
    add ebp, eax
    lea rdx, [rel br_ins_bits]
    movzx ecx, byte [rdx + rbx]
    call br_bits
    lea rdx, [rel br_ins_off]
    add eax, [rdx + rbx * 4]
    mov [r15 + BR_ILEN], eax
    lea rdx, [rel br_copy_bits]
    movzx ecx, byte [rdx + rbp]
    call br_bits
    lea rdx, [rel br_copy_off]
    add eax, [rdx + rbp * 4]
    mov [r15 + BR_CLEN], eax
    ; the literals
    mov r12d, [r15 + BR_ILEN]
.literal:
    test r12d, r12d
    jz .copy
    cmp dword [r15 + BR_ERR], 0
    jne .out
    dec r12d
    xor edi, edi
    call br_next
    ; the context from the last two bytes by the block type's mode
    mov rdx, [r15 + BR_OUT]
    mov rcx, [r15 + BR_N]
    xor r8d, r8d                        ; p1
    xor r9d, r9d                        ; p2
    test rcx, rcx
    jz .ctx
    movzx r8d, byte [rdx + rcx - 1]
    cmp rcx, 1
    je .ctx
    movzx r9d, byte [rdx + rcx - 2]
.ctx:
    mov eax, [r15 + BR_CAT + CT_TYPE]
    mov rcx, [r15 + BR_MODES]
    movzx ecx, byte [rcx + rax]
    test ecx, ecx
    jnz .not_lsb
    mov eax, r8d
    and eax, 0x3F
    jmp .ctx_have
.not_lsb:
    cmp ecx, 1
    jne .not_msb
    mov eax, r8d
    shr eax, 2
    jmp .ctx_have
.not_msb:
    cmp ecx, 2
    jne .signed
    lea rax, [rel ufl_br_lut0]
    movzx eax, byte [rax + r8]
    lea rcx, [rel ufl_br_lut1]
    movzx ecx, byte [rcx + r9]
    or eax, ecx
    jmp .ctx_have
.signed:
    lea rcx, [rel ufl_br_lut2]
    movzx eax, byte [rcx + r8]
    shl eax, 3
    movzx ecx, byte [rcx + r9]
    or eax, ecx
.ctx_have:
    mov ecx, [r15 + BR_CAT + CT_TYPE]
    shl ecx, 6
    add eax, ecx
    mov rcx, [r15 + BR_CMAPL]
    movzx eax, byte [rcx + rax]         ; the tree
    cmp eax, [r15 + BR_NTREESL]
    jae .bad
    imul edi, eax, LSTRIDE
    add rdi, [r15 + BR_LCODES]
    call br_read
    mov rdx, [r15 + BR_OUT]
    mov rcx, [r15 + BR_N]
    mov [rdx + rcx], al
    inc rcx
    mov [r15 + BR_N], rcx
    cmp rcx, [r15 + BR_END]
    jae .out                            ; the meta-block full: the copy dropped
    jmp .literal
.copy:
    ; the distance
    xor r13d, r13d                      ; dcode
    cmp dword [r15 + BR_ICMD], 128
    jb .distance
    mov edi, 2
    call br_next
    mov eax, [r15 + BR_CLEN]
    sub eax, 2
    cmp eax, 3
    jbe .dctx
    mov eax, 3
.dctx:
    mov ecx, [r15 + BR_CAT + 2 * CT_SIZE + CT_TYPE]
    lea eax, [rax + rcx * 4]
    mov rcx, [r15 + BR_CMAPD]
    movzx eax, byte [rcx + rax]
    cmp eax, [r15 + BR_NTREESD]
    jae .bad
    imul edi, eax, DSTRIDE
    add rdi, [r15 + BR_DCODES]
    call br_read
    mov r13d, eax
.distance:
    cmp r13d, 16
    jae .not_short
    lea rcx, [rel br_short]
    movzx eax, byte [rcx + r13 * 2]     ; which
    movsx edx, byte [rcx + r13 * 2 + 1] ; delta
    mov ecx, 3
    sub ecx, eax
    mov r14d, [r15 + BR_DIST + rcx * 4]
    add r14d, edx
    test r14d, r14d
    jle .bad
    jmp .have_distance
.not_short:
    mov eax, r13d
    sub eax, 16
    cmp eax, [r15 + BR_NDIRECT]
    jae .coded
    lea r14d, [r13 - 15]
    jmp .have_distance
.coded:
    sub eax, [r15 + BR_NDIRECT]         ; x
    mov ebx, eax
    mov ecx, [r15 + BR_NPOST]
    inc ecx
    shr eax, cl
    inc eax                             ; nbits
    mov ebp, eax
    mov eax, ebx
    mov ecx, [r15 + BR_NPOST]
    shr eax, cl                         ; hcode
    and eax, 1
    add eax, 2
    mov ecx, ebp
    shl eax, cl
    sub eax, 4                          ; offset
    mov r14d, eax
    mov ecx, ebp
    call br_bits
    add r14d, eax
    mov ecx, [r15 + BR_NPOST]
    shl r14d, cl
    mov eax, 1
    shl eax, cl
    dec eax
    and ebx, eax                        ; lcode
    add r14d, ebx
    add r14d, [r15 + BR_NDIRECT]
    inc r14d
.have_distance:
    ; within the window and the output: a copy; else the dictionary
    mov rax, [r15 + BR_N]
    cmp rax, [r15 + BR_MAXBACK]
    jbe .mx
    mov rax, [r15 + BR_MAXBACK]
.mx:
    mov r14d, r14d
    cmp r14, rax
    ja .dictionary
    test r13d, r13d
    jz .copy_go
    mov eax, [r15 + BR_DIST + 4]        ; pushed: the ring moves on
    mov [r15 + BR_DIST], eax
    mov eax, [r15 + BR_DIST + 8]
    mov [r15 + BR_DIST + 4], eax
    mov eax, [r15 + BR_DIST + 12]
    mov [r15 + BR_DIST + 8], eax
    mov [r15 + BR_DIST + 12], r14d
.copy_go:
    mov ecx, [r15 + BR_CLEN]
    mov rax, [r15 + BR_N]
    add rax, rcx
    cmp rax, [r15 + BR_END]
    ja .bad
    mov rdi, [r15 + BR_OUT]
    add rdi, [r15 + BR_N]
    mov rsi, rdi
    sub rsi, r14
    mov [r15 + BR_N], rax
.bytes:
    mov al, [rsi]                       ; (overlapping: byte by byte)
    mov [rdi], al
    inc rsi
    inc rdi
    dec ecx
    jnz .bytes
    jmp .command
.dictionary:
    mov ecx, [r15 + BR_CLEN]
    cmp ecx, 4
    jb .bad
    cmp ecx, 24
    ja .bad
    sub r14, rax
    dec r14                             ; the offset
    lea rdx, [rel ufl_br_ndbits]
    movzx edx, byte [rdx + rcx]
    mov rbx, r14
    mov eax, 1
    push rcx
    mov ecx, edx
    shl eax, cl
    dec eax
    and ebx, eax                        ; the word
    shr r14, cl                         ; the transform
    pop rcx
    cmp r14, 121
    jae .bad
    lea rdx, [rel ufl_br_dictoff]
    mov eax, [rdx + rcx * 4]
    imul ebx, ecx
    add eax, ebx
    lea rsi, [rel ufl_br_dict]
    add rsi, rax                        ; the word's bytes, clen long
    mov edi, r14d
    mov edx, ecx
    call br_transform
    jmp .command
.bad:
    mov dword [r15 + BR_ERR], 1
.out:
    add rsp, 32
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; br_transform — edi = transform, rsi = a dictionary word, edx = its length:
;   prefix, the word transformed, suffix onto the output (within the
;   meta-block)
br_transform:
    push rbx
    push r12
    push r13
    push r14
    lea rbx, [rel ufl_br_transforms]
    lea rbx, [rbx + rdi * 8]
    movzx r12d, byte [rbx + 3]          ; type
    mov r13, rsi                        ; the word
    mov r14d, edx                       ; its length
    cmp r12d, 3
    jb .kept
    cmp r12d, 11
    ja .omit_last
    lea ecx, [r12 - 2]                  ; omit first 1..9
    cmp ecx, r14d
    jbe .first
    mov ecx, r14d
.first:
    add r13, rcx
    sub r14d, ecx
    jmp .kept
.omit_last:
    lea ecx, [r12 - 11]
    cmp ecx, r14d
    jbe .last
    mov ecx, r14d
.last:
    sub r14d, ecx
.kept:
    ; room for all of it
    movzx eax, byte [rbx + 2]
    movzx ecx, byte [rbx + 6]
    add eax, ecx
    add eax, r14d
    mov rcx, [r15 + BR_N]
    add rcx, rax
    cmp rcx, [r15 + BR_END]
    ja .bad
    mov rdi, [r15 + BR_OUT]
    add rdi, [r15 + BR_N]
    mov [r15 + BR_N], rcx
    ; prefix
    movzx esi, word [rbx]
    lea rax, [rel ufl_br_pool]
    add rsi, rax
    movzx ecx, byte [rbx + 2]
    rep movsb
    ; the word
    mov rdx, rdi                        ; where it starts
    mov rsi, r13
    mov ecx, r14d
    rep movsb
    ; uppercase: the first character, or all
    cmp r12d, 1
    je .ferment
    cmp r12d, 2
    jne .suffix
.ferment:
    xor ecx, ecx
.f:
    cmp ecx, r14d
    jae .suffix
    movzx eax, byte [rdx + rcx]
    cmp eax, 192
    jae .f2
    cmp eax, 97
    jb .f1
    cmp eax, 122
    ja .f1
    xor byte [rdx + rcx], 32
.f1:
    mov eax, 1
    jmp .f_step
.f2:
    cmp eax, 224
    jae .f3
    lea eax, [rcx + 1]
    cmp eax, r14d
    jae .f2_step
    xor byte [rdx + rcx + 1], 32
.f2_step:
    mov eax, 2
    jmp .f_step
.f3:
    lea eax, [rcx + 2]
    cmp eax, r14d
    jae .f3_step
    xor byte [rdx + rcx + 2], 5
.f3_step:
    mov eax, 3
.f_step:
    cmp r12d, 1
    je .suffix
    add ecx, eax
    jmp .f
.suffix:
    movzx esi, word [rbx + 4]
    lea rax, [rel ufl_br_pool]
    add rsi, rax
    movzx ecx, byte [rbx + 6]
    rep movsb
    jmp .out
.bad:
    mov dword [r15 + BR_ERR], 1
.out:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
