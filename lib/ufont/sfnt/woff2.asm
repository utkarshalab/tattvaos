; =============================================================================
; Utkarsha OS — lib/ufont/sfnt/woff2.asm
; =============================================================================
; WOFF2 fonts (W3C WOFF File Format 2.0): unpacked into the font they wrap,
; which ufont_open then reads.
;
;   ufl_woff2_unpack(arena, data, length) -> rax = the sfnt's bytes (in the
;       arena), rdx = its length; rax 0: damaged, unsupported (a
;       collection), or out of memory
;
; The header and the table directory (known-tag indexes, UIntBase128
; lengths, transform versions); every table from one Brotli stream
; (sfnt/brotli.asm). Transformed glyf / loca rebuilt: the seven streams
; (contour counts, point counts, flags, glyph data, composites, bounding
; boxes, instructions), simple glyphs from their point triplets (the 128
; encodings), instructions, explicit or computed boxes, the overlap bit;
; composites copied with their instructions; glyphs 4-byte aligned, loca in
; the index format given. Transformed hmtx rebuilt, left side bearings left
; out taken from the glyphs' xMin. The tables go 4-byte aligned after a
; fresh table directory.
; =============================================================================

%include "ufont.inc"

extern arena_alloc
extern ufl_brotli

%define W2_HEADER       48
%define W2_MAX          (256 * 1024 * 1024)

; a table (WT_*)
%define WT_TAG          0
%define WT_XF           4               ; u32 1: transformed
%define WT_ORIG         8               ; u32 its length
%define WT_TLEN         12              ; u32 its length in the stream
%define WT_SRC          16              ; its bytes in the stream
%define WT_OUT          24              ; its bytes in the font (rebuilt ones)
%define WT_OUTLEN       32              ; u32
%define WT_SIZE         40

section .rodata
align 4
w2_tags:
    dd 'cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ', 'fpgm', 'glyf', 'loca'
    dd 'prep', 'CFF ', 'VORG', 'EBDT', 'EBLC', 'gasp', 'hdmx', 'kern', 'LTSH', 'PCLT', 'VDMX', 'vhea'
    dd 'vmtx', 'BASE', 'GDEF', 'GPOS', 'GSUB', 'EBSC', 'JSTF', 'MATH', 'CBDT', 'CBLC', 'COLR', 'CPAL'
    dd 'SVG ', 'sbix', 'acnt', 'avar', 'bdat', 'bloc', 'bsln', 'cvar', 'fdsc', 'feat', 'fmtx', 'fvar'
    dd 'gvar', 'hsty', 'just', 'lcar', 'mort', 'morx', 'opbd', 'prop', 'trak', 'Zapf', 'Silf', 'Glat'
    dd 'Gloc', 'Feat', 'Sill'

section .text

; ----------------------------------------------------------------------------
; ufl_woff2_unpack — rdi = arena, rsi = data, rdx = length
; ----------------------------------------------------------------------------
%define WF_ARENA    0
%define WF_DATA     8
%define WF_LEN      16
%define WF_N        24                  ; u32 tables
%define WF_TABLES   32
%define WF_STREAM   40                  ; the decompressed tables
%define WF_SLEN     48
%define WF_GLYF     56                  ; WT of glyf / loca / hmtx / hhea (0: none)
%define WF_LOCA     64
%define WF_HMTX     72
%define WF_HHEA     80
%define WF_XMIN     88                  ; i16 per glyph (the rebuilt glyf's)
%define WF_NGLYPHS  96                  ; u32
%define WF_OUT      104
%define WF_SIZE     112
%define WF_AT       120
%define WF_P        128
%define WF_FRAME    144

global ufl_woff2_unpack
ufl_woff2_unpack:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, WF_FRAME + 8
    mov [rsp + WF_ARENA], rdi
    mov [rsp + WF_DATA], rsi
    mov [rsp + WF_LEN], rdx
    xor eax, eax
    mov [rsp + WF_GLYF], rax
    mov [rsp + WF_LOCA], rax
    mov [rsp + WF_HMTX], rax
    mov [rsp + WF_HHEA], rax
    mov [rsp + WF_XMIN], rax
    mov r12, rsi
    cmp rdx, W2_HEADER
    jb .bad
    cmp dword [r12], 'wOF2'
    jne .bad
    cmp dword [r12 + 4], 'ttcf'
    je .bad                             ; collections: not read
    movzx eax, word [r12 + 12]
    xchg al, ah
    test eax, eax
    jz .bad
    mov [rsp + WF_N], eax
    imul esi, eax, WT_SIZE
    mov rdi, [rsp + WF_ARENA]
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rsp + WF_TABLES], rax
    ; the directory
    lea r13, [r12 + W2_HEADER]          ; p
    mov r14, r12
    add r14, [rsp + WF_LEN]             ; end
    xor r15d, r15d                      ; the stream's length so far
    xor ebx, ebx
.entry:
    cmp ebx, [rsp + WF_N]
    jae .entries
    imul ebp, ebx, WT_SIZE
    add rbp, [rsp + WF_TABLES]
    cmp r13, r14
    jae .bad
    movzx ecx, byte [r13]
    inc r13
    mov edx, ecx
    shr edx, 6                          ; transform version
    and ecx, 63
    cmp ecx, 63
    jne .known
    lea rax, [r13 + 4]
    cmp rax, r14
    ja .bad
    mov eax, [r13]
    add r13, 4
    jmp .tagged
.known:
    lea rax, [rel w2_tags]
    mov eax, [rax + rcx * 4]
.tagged:
    mov [rbp + WT_TAG], eax
    ; transformed: glyf / loca at version 0; others at a version > 0 (hmtx 1)
    xor ecx, ecx
    cmp eax, 'glyf'
    je .glyf_like
    cmp eax, 'loca'
    je .glyf_like
    test edx, edx
    setnz cl
    jz .xf
    cmp eax, 'hmtx'
    jne .bad
    cmp edx, 1
    jne .bad
    jmp .xf
.glyf_like:
    test edx, edx
    setz cl
    jz .xf
    cmp edx, 3
    jne .bad
.xf:
    mov [rbp + WT_XF], ecx
    call w2_base128
    jc .bad
    mov [rbp + WT_ORIG], eax
    mov [rbp + WT_TLEN], eax
    cmp dword [rbp + WT_XF], 0
    je .length
    call w2_base128
    jc .bad
    mov [rbp + WT_TLEN], eax
    cmp dword [rbp + WT_TAG], 'loca'
    jne .length
    test eax, eax
    jnz .bad                            ; a transformed loca has no data
.length:
    mov eax, [rbp + WT_TLEN]
    mov [rbp + WT_SRC], r15             ; (its offset, for now)
    add r15, rax
    cmp r15, W2_MAX
    ja .bad
    ; the tables the rebuilding needs
    mov eax, [rbp + WT_TAG]
    cmp eax, 'glyf'
    jne .not_glyf
    mov [rsp + WF_GLYF], rbp
.not_glyf:
    cmp eax, 'loca'
    jne .not_loca
    mov [rsp + WF_LOCA], rbp
.not_loca:
    cmp eax, 'hmtx'
    jne .not_hmtx
    mov [rsp + WF_HMTX], rbp
.not_hmtx:
    cmp eax, 'hhea'
    jne .next_entry
    mov [rsp + WF_HHEA], rbp
.next_entry:
    inc ebx
    jmp .entry
.entries:
    ; the compressed stream
    mov [rsp + WF_SLEN], r15
    mov eax, [r12 + 20]
    bswap eax                           ; totalCompressedSize
    lea rcx, [r13 + rax]
    cmp rcx, r14
    ja .bad
    mov rbx, rax
    mov rdi, [rsp + WF_ARENA]
    lea rsi, [r15 + 8]
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rsp + WF_STREAM], rax
    mov rdi, [rsp + WF_ARENA]
    mov rsi, r13
    mov rdx, rbx
    mov rcx, rax
    mov r8, r15
    call ufl_brotli
    cmp rax, r15
    jne .bad
    ; the tables' bytes in it
    xor ebx, ebx
.place:
    cmp ebx, [rsp + WF_N]
    jae .placed
    imul ebp, ebx, WT_SIZE
    add rbp, [rsp + WF_TABLES]
    mov rax, [rsp + WF_STREAM]
    add [rbp + WT_SRC], rax
    mov rax, [rbp + WT_SRC]
    mov [rbp + WT_OUT], rax
    mov eax, [rbp + WT_ORIG]
    mov [rbp + WT_OUTLEN], eax          ; (rebuilt tables set theirs)
    inc ebx
    jmp .place
.placed:
    ; rebuild: glyf and loca, then hmtx
    mov rbx, [rsp + WF_GLYF]
    test rbx, rbx
    jz .no_glyf
    cmp dword [rbx + WT_XF], 0
    je .glyf_null
    mov rax, [rsp + WF_LOCA]
    test rax, rax
    jz .bad
    cmp dword [rax + WT_XF], 0
    je .bad
    lea rdi, [rsp]
    call w2_glyf
    test eax, eax
    jz .bad
    jmp .no_glyf
.glyf_null:
    mov rax, [rsp + WF_LOCA]
    test rax, rax
    jz .no_glyf
    cmp dword [rax + WT_XF], 0
    jne .bad
.no_glyf:
    mov rbx, [rsp + WF_HMTX]
    test rbx, rbx
    jz .assemble
    cmp dword [rbx + WT_XF], 0
    je .assemble
    lea rdi, [rsp]
    call w2_hmtx
    test eax, eax
    jz .bad
.assemble:
    ; the size: the directory, every table 4-byte aligned
    mov eax, [rsp + WF_N]
    shl rax, 4
    add rax, 12
    mov r13, rax
    xor ebx, ebx
.size:
    cmp ebx, [rsp + WF_N]
    jae .sized
    imul ebp, ebx, WT_SIZE
    add rbp, [rsp + WF_TABLES]
    mov eax, [rbp + WT_OUTLEN]
    add rax, 3
    and rax, -4
    add r13, rax
    cmp r13, W2_MAX
    ja .bad
    inc ebx
    jmp .size
.sized:
    mov [rsp + WF_SIZE], r13
    mov rdi, [rsp + WF_ARENA]
    mov rsi, r13
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rsp + WF_OUT], rax
    mov rdi, rax
    mov rcx, r13
    xor eax, eax
    rep stosb
    mov r15, [rsp + WF_OUT]
    mov eax, [r12 + 4]
    mov [r15], eax                      ; the flavor
    mov eax, [rsp + WF_N]
    xchg al, ah
    mov [r15 + 4], ax
    mov eax, [rsp + WF_N]
    shl rax, 4
    add rax, 12
    mov [rsp + WF_AT], rax
    xor ebx, ebx
.write:
    cmp ebx, [rsp + WF_N]
    jae .done
    imul ebp, ebx, WT_SIZE
    add rbp, [rsp + WF_TABLES]
    mov eax, ebx
    shl eax, 4
    lea rdi, [r15 + rax + 12]           ; its directory entry
    mov eax, [rbp + WT_TAG]
    mov [rdi], eax
    mov rax, [rsp + WF_AT]
    bswap eax
    mov [rdi + 8], eax
    mov eax, [rbp + WT_OUTLEN]
    bswap eax
    mov [rdi + 12], eax
    mov rdi, [rsp + WF_AT]
    add rdi, r15
    mov rsi, [rbp + WT_OUT]
    mov ecx, [rbp + WT_OUTLEN]
    rep movsb
    mov eax, [rbp + WT_OUTLEN]
    add rax, 3
    and rax, -4
    add [rsp + WF_AT], rax
    inc ebx
    jmp .write
.done:
    mov rax, [rsp + WF_OUT]
    mov rdx, [rsp + WF_SIZE]
    jmp .out
.bad:
    xor eax, eax
    xor edx, edx
.out:
    add rsp, WF_FRAME + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; r13 = p, r14 = end -> eax a UIntBase128 (CF: damaged), r13 past it
w2_base128:
    xor eax, eax
    xor ecx, ecx
.byte:
    cmp ecx, 5
    jae .bad
    cmp r13, r14
    jae .bad
    movzx edx, byte [r13]
    inc r13
    test ecx, ecx
    jnz .not_first
    cmp edx, 0x80                       ; no leading zeros
    je .bad
.not_first:
    test eax, 0xFE000000
    jnz .bad                            ; would overflow
    shl eax, 7
    mov r8d, edx
    and r8d, 0x7F
    or eax, r8d
    inc ecx
    test edx, 0x80
    jnz .byte
    clc
    ret
.bad:
    stc
    ret

; ----------------------------------------------------------------------------
; a stream: cur, end (16 bytes) in the w2_glyf frame
; ----------------------------------------------------------------------------
; rsi = a stream -> eax its next byte (CF: none left)
w2_u8:
    mov rdx, [rsi]
    cmp rdx, [rsi + 8]
    jae .none
    movzx eax, byte [rdx]
    inc qword [rsi]
    clc
    ret
.none:
    xor eax, eax
    stc
    ret

; rsi = a stream -> eax its next big-endian u16
w2_u16:
    mov rdx, [rsi]
    lea rax, [rdx + 2]
    cmp rax, [rsi + 8]
    ja .none
    mov [rsi], rax
    movzx eax, word [rdx]
    xchg al, ah
    clc
    ret
.none:
    xor eax, eax
    stc
    ret

; rsi = a stream -> eax a 255UInt16
w2_255:
    call w2_u8
    jc .out
    cmp eax, 253
    je .word
    cmp eax, 255
    je .plus253
    cmp eax, 254
    je .plus506
    clc
    ret
.word:
    jmp w2_u16
.plus253:
    call w2_u8
    jc .out
    add eax, 253
    ret
.plus506:
    call w2_u8
    jc .out
    add eax, 506
.out:
    ret

; ----------------------------------------------------------------------------
; w2_glyf — rdi = the unpack frame: the transformed glyf rebuilt into glyf
;   and loca (their WT_OUT / WT_OUTLEN), the glyphs' xMin kept -> eax 1, 0
;   damaged
; ----------------------------------------------------------------------------
%define GS_NC       0                   ; streams: cur, end
%define GS_NP       16
%define GS_FL       32
%define GS_GL       48
%define GS_CO       64
%define GS_BB       80
%define GS_IN       96
%define GF_UF       112                 ; the unpack frame
%define GF_NG       120                 ; u32 glyphs
%define GF_IF       124                 ; u32 index format
%define GF_OPT      128                 ; u32 option flags
%define GF_BITMAP   136                 ; the bbox bitmap
%define GF_OVERLAP  144                 ; the overlap bitmap (0: none)
%define GF_OUT      152                 ; glyf
%define GF_CAP      160
%define GF_AT       168                 ; bytes written
%define GF_LOCA     176
%define GF_PX       184                 ; i32 x per point (scratch)
%define GF_PY       192
%define GF_PON      200                 ; u8 on curve
%define GF_PCAP     208                 ; u32 points the scratch holds
%define GF_G        212                 ; u32 the glyph
%define GF_NCONT    216                 ; i32
%define GF_NPTS     220                 ; u32
%define GF_BOX      224                 ; i16 x 4 (xMin, yMin, xMax, yMax)
%define GF_INSTR    232                 ; u32 instruction length
%define GF_SIZE     240

w2_glyf:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, GF_SIZE + 8
    mov [rsp + GF_UF], rdi
    mov rax, [rdi + WF_GLYF]
    mov r12, [rax + WT_SRC]             ; the transformed table
    mov r13d, [rax + WT_TLEN]
    add r13, r12                        ; its end
    lea rax, [r12 + 36]
    cmp rax, r13
    ja .bad
    movzx eax, word [r12 + 2]
    xchg al, ah
    mov [rsp + GF_OPT], eax
    movzx eax, word [r12 + 4]
    xchg al, ah
    mov [rsp + GF_NG], eax
    mov [rdi + WF_NGLYPHS], eax
    test eax, eax
    jz .bad
    movzx eax, word [r12 + 6]
    xchg al, ah
    cmp eax, 1
    ja .bad
    mov [rsp + GF_IF], eax
    ; the seven streams, one after the other
    lea r14, [r12 + 36]
    xor ebx, ebx
.stream:
    cmp ebx, 7
    jae .streams
    mov eax, [r12 + 8 + rbx * 4]
    bswap eax
    lea rcx, [r14 + rax]
    cmp rcx, r13
    ja .bad
    mov edx, ebx
    shl edx, 4
    mov [rsp + rdx], r14
    mov [rsp + rdx + 8], rcx
    mov r14, rcx
    inc ebx
    jmp .stream
.streams:
    ; the overlap bitmap after them, when flagged
    mov qword [rsp + GF_OVERLAP], 0
    test dword [rsp + GF_OPT], 1
    jz .bbox
    mov eax, [rsp + GF_NG]
    add eax, 7
    shr eax, 3
    lea rcx, [r14 + rax]
    cmp rcx, r13
    ja .bad
    mov [rsp + GF_OVERLAP], r14
.bbox:
    ; the bbox stream starts with its bitmap (4 x ((glyphs + 31) / 32) bytes)
    mov eax, [rsp + GF_NG]
    add eax, 31
    shr eax, 5
    shl eax, 2
    mov rcx, [rsp + GS_BB]
    mov [rsp + GF_BITMAP], rcx
    add rcx, rax
    cmp rcx, [rsp + GS_BB + 8]
    ja .bad
    mov [rsp + GS_BB], rcx
    ; the space: points (from the point counts), contours, the other streams
    mov rsi, [rsp + GS_NC]
    mov rdi, [rsp + GS_NP]
    xor r14d, r14d                      ; points in all
    xor r15d, r15d                      ; the largest glyph's
    xor ebx, ebx                        ; contours in all
    mov ebp, [rsp + GF_NG]
.count:
    test ebp, ebp
    jz .counted
    dec ebp
    lea rax, [rsi + 2]
    cmp rax, [rsp + GS_NC + 8]
    ja .bad
    movzx eax, word [rsi]
    xchg al, ah
    movsx eax, ax
    add rsi, 2
    test eax, eax
    jle .count
    add ebx, eax
    xor r8d, r8d                        ; this glyph's points
    mov ecx, eax
.count_contour:
    test ecx, ecx
    jz .count_glyph
    dec ecx
    push rsi
    push rcx
    lea rsi, [rsp + 16 + GS_NP]
    push qword [rsi]
    sub rsp, 8
    mov [rsi], rdi
    call w2_255
    mov rdi, [rsi]
    lea rsp, [rsp + 8]                  ; (the carry kept)
    pop qword [rsi]
    pop rcx
    pop rsi
    jc .bad
    add r8d, eax
    jmp .count_contour
.count_glyph:
    add r14, r8
    cmp r8d, r15d
    cmovae r15d, r8d
    jmp .count
.counted:
    ; scratch for the largest glyph's points
    lea esi, [r15 * 8 + r15 + 16]
    mov rdi, [rsp + GF_UF]
    mov rdi, [rdi + WF_ARENA]
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rsp + GF_PX], rax
    lea rax, [rax + r15 * 4]
    mov [rsp + GF_PY], rax
    lea rax, [rax + r15 * 4]
    mov [rsp + GF_PON], rax
    mov [rsp + GF_PCAP], r15d
    ; glyf: 12 + 2 contours + 5 points per glyph worst, plus the composites
    ; and instructions as they are
    mov eax, [rsp + GF_NG]
    imul rax, rax, 16
    lea rax, [rax + rbx * 2]
    imul rcx, r14, 5
    add rax, rcx
    mov rcx, [rsp + GS_CO + 8]
    sub rcx, [rsp + GS_CO]
    add rax, rcx
    mov rcx, [rsp + GS_IN + 8]
    sub rcx, [rsp + GS_IN]
    add rax, rcx
    cmp rax, W2_MAX
    ja .bad
    mov [rsp + GF_CAP], rax
    mov rdi, [rsp + GF_UF]
    mov rdi, [rdi + WF_ARENA]
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rsp + GF_OUT], rax
    mov qword [rsp + GF_AT], 0
    ; loca and the xMin
    mov eax, [rsp + GF_NG]
    inc eax
    mov ecx, [rsp + GF_IF]
    inc ecx
    shl eax, cl                         ; (glyphs + 1) x 2 or 4
    mov esi, eax
    mov rdi, [rsp + GF_UF]
    mov rdi, [rdi + WF_ARENA]
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rsp + GF_LOCA], rax
    mov esi, [rsp + GF_NG]
    add esi, esi
    mov rdi, [rsp + GF_UF]
    mov rdi, [rdi + WF_ARENA]
    call arena_alloc
    test rax, rax
    jz .bad
    mov rcx, [rsp + GF_UF]
    mov [rcx + WF_XMIN], rax
    ; each glyph
    mov dword [rsp + GF_G], 0
.glyph:
    mov eax, [rsp + GF_G]
    cmp eax, [rsp + GF_NG]
    jae .loca_last
    call .loca_put                      ; its start
    lea rsi, [rsp + GS_NC]
    call w2_u16
    jc .bad
    movsx eax, ax
    mov [rsp + GF_NCONT], eax
    mov word [rsp + GF_BOX], 0          ; xMin for an empty glyph
    test eax, eax
    jz .glyph_empty
    cmp eax, -1
    je .composite
    jl .bad
    call w2_simple
    test eax, eax
    jz .bad
    jmp .glyph_done
.composite:
    call w2_composite
    test eax, eax
    jz .bad
    jmp .glyph_done
.glyph_empty:
    ; an empty glyph has no box
    call .has_box
    jnz .bad
.glyph_done:
    ; xMin kept, 4-byte aligned
    mov rcx, [rsp + GF_UF]
    mov rcx, [rcx + WF_XMIN]
    mov eax, [rsp + GF_G]
    mov dx, [rsp + GF_BOX]
    mov [rcx + rax * 2], dx
    mov rax, [rsp + GF_AT]
    add rax, 3
    and rax, -4
    mov [rsp + GF_AT], rax
    inc dword [rsp + GF_G]
    jmp .glyph
.loca_last:
    call .loca_put
    ; glyf and loca as rebuilt
    mov rcx, [rsp + GF_UF]
    mov rax, [rcx + WF_GLYF]
    mov rdx, [rsp + GF_OUT]
    mov [rax + WT_OUT], rdx
    mov rdx, [rsp + GF_AT]
    mov [rax + WT_OUTLEN], edx
    mov rax, [rcx + WF_LOCA]
    mov rdx, [rsp + GF_LOCA]
    mov [rax + WT_OUT], rdx
    mov edx, [rsp + GF_NG]
    inc edx
    mov ecx, [rsp + GF_IF]
    inc ecx
    shl edx, cl
    mov [rax + WT_OUTLEN], edx
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    add rsp, GF_SIZE + 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; loca[GF_G] = GF_AT (short: halved, within 0x1FFFE) (frame at rsp + 8)
.loca_put:
    mov eax, [rsp + 8 + GF_G]
    mov rdx, [rsp + 8 + GF_AT]
    mov rcx, [rsp + 8 + GF_LOCA]
    cmp dword [rsp + 8 + GF_IF], 0
    jne .loca_long
    cmp rdx, 0x1FFFE
    ja .loca_bad
    shr edx, 1
    xchg dl, dh
    mov [rcx + rax * 2], dx
    ret
.loca_long:
    bswap edx
    mov [rcx + rax * 4], edx
    ret
.loca_bad:
    add rsp, 8
    jmp .bad
; ZF clear when glyph GF_G has an explicit box (frame at rsp + 8)
.has_box:
    mov eax, [rsp + 8 + GF_G]
    mov rcx, [rsp + 8 + GF_BITMAP]
    mov edx, eax
    shr edx, 3
    movzx edx, byte [rcx + rdx]
    and eax, 7
    mov ecx, 7
    sub ecx, eax
    shr edx, cl
    and edx, 1
    ret

; ----------------------------------------------------------------------------
; w2_simple — (in the w2_glyf frame at rsp + 8) a simple glyph rebuilt ->
;   eax 1, 0 damaged
; ----------------------------------------------------------------------------
%define WS          (8 + 8 * 6 + 8)     ; w2_glyf's frame from here

w2_simple:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    lea r15, [rsp + WS]                 ; the w2_glyf frame
    ; the end points: point counts per contour
    mov r12d, [r15 + GF_NCONT]
    ; room: header, end points
    mov rbx, [r15 + GF_OUT]
    add rbx, [r15 + GF_AT]              ; the glyph
    lea rax, [r12 * 2 + 12]
    add rax, [r15 + GF_AT]
    cmp rax, [r15 + GF_CAP]
    ja .bad
    xor ebp, ebp                        ; points
    xor r13d, r13d
.contour:
    cmp r13d, r12d
    jae .points
    lea rsi, [r15 + GS_NP]
    call w2_255
    jc .bad
    add ebp, eax
    cmp ebp, 0xFFFF
    ja .bad
    lea eax, [rbp - 1]
    xchg al, ah
    mov [rbx + 10 + r13 * 2], ax
    inc r13d
    jmp .contour
.points:
    cmp ebp, [r15 + GF_PCAP]
    ja .bad
    mov [r15 + GF_NPTS], ebp
    ; flags and triplets
    xor r13d, r13d                      ; point
    xor r10d, r10d                      ; x
    xor r11d, r11d                      ; y
.point:
    cmp r13d, ebp
    jae .instructions
    lea rsi, [r15 + GS_FL]
    call w2_u8
    jc .bad
    mov r14d, eax
    mov rcx, [r15 + GF_PON]
    xor edx, edx
    test eax, 0x80
    sete dl                             ; on the curve: bit 7 clear
    mov [rcx + r13], dl
    and r14d, 0x7F
    push r10
    push r11
    call w2_triplet                     ; -> eax dx, edx dy (CF: damaged)
    pop r11
    pop r10
    jc .bad
    add r10d, eax
    add r11d, edx
    mov rcx, [r15 + GF_PX]
    mov [rcx + r13 * 4], r10d
    mov rcx, [r15 + GF_PY]
    mov [rcx + r13 * 4], r11d
    inc r13d
    jmp .point
.instructions:
    lea rsi, [r15 + GS_GL]
    call w2_255
    jc .bad
    mov [r15 + GF_INSTR], eax
    ; the box: given, or from the points
    mov eax, [r15 + GF_G]
    call w2_box
    jc .bad
    ; header
    mov ax, [r15 + GF_NCONT]
    xchg al, ah
    mov [rbx], ax
    xor ecx, ecx
.hdr_box:
    mov ax, [r15 + GF_BOX + rcx * 2]
    xchg al, ah
    mov [rbx + 2 + rcx * 2], ax
    inc ecx
    cmp ecx, 4
    jb .hdr_box
    lea rdi, [rbx + 10 + r12 * 2]
    ; instructions
    mov ecx, [r15 + GF_INSTR]
    lea rax, [rdi + 2 + rcx]
    imul rdx, rbp, 5
    add rax, rdx
    sub rax, [r15 + GF_OUT]
    cmp rax, [r15 + GF_CAP]
    ja .bad
    mov eax, ecx
    xchg al, ah
    mov [rdi], ax
    add rdi, 2
    mov rsi, [r15 + GS_IN]
    lea rax, [rsi + rcx]
    cmp rax, [r15 + GS_IN + 8]
    ja .bad
    mov [r15 + GS_IN], rax
    rep movsb
    ; flags: on curve, short / same x and y; overlap on the first
    xor r13d, r13d
    xor r10d, r10d                      ; previous x
    xor r11d, r11d                      ; previous y
    mov r14, rdi                        ; the flags
.flag:
    cmp r13d, ebp
    jae .xs
    mov rcx, [r15 + GF_PON]
    movzx r8d, byte [rcx + r13]         ; 1 on the curve
    mov rcx, [r15 + GF_PX]
    mov eax, [rcx + r13 * 4]
    sub eax, r10d
    add r10d, eax
    call .axis
    or r8d, edx                         ; x bits: 0x02 short, 0x10 same / positive
    mov rcx, [r15 + GF_PY]
    mov eax, [rcx + r13 * 4]
    sub eax, r11d
    add r11d, eax
    call .axis
    shl edx, 1                          ; y bits: 0x04, 0x20
    or r8d, edx
    test r13d, r13d
    jnz .flag_put
    mov rcx, [r15 + GF_OVERLAP]
    test rcx, rcx
    jz .flag_put
    mov eax, [r15 + GF_G]
    mov edx, eax
    shr edx, 3
    movzx edx, byte [rcx + rdx]
    and eax, 7
    mov ecx, 7
    sub ecx, eax
    shr edx, cl
    test edx, 1
    jz .flag_put
    or r8d, 0x40
.flag_put:
    mov [rdi], r8b
    inc rdi
    inc r13d
    jmp .flag
.xs:
    ; x coordinates, then y
    mov rsi, [r15 + GF_PX]
    call .coords
    mov rsi, [r15 + GF_PY]
    call .coords
    sub rdi, [r15 + GF_OUT]
    mov [r15 + GF_AT], rdi
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
; eax = a delta -> edx its x flag bits (0x10 same, 0x02 short (+0x10
;   positive))
.axis:
    xor edx, edx
    test eax, eax
    jnz .axis_nz
    mov edx, 0x10
    ret
.axis_nz:
    cmp eax, -255
    jl .axis_out
    cmp eax, 255
    jg .axis_out
    mov edx, 0x02
    test eax, eax
    jle .axis_out
    or edx, 0x10
.axis_out:
    ret
; rsi = the points' coordinates (x or y): their deltas as the flags say
.coords:
    xor ecx, ecx
    xor r10d, r10d
.c:
    cmp ecx, ebp
    jae .c_out
    mov eax, [rsi + rcx * 4]
    sub eax, r10d
    add r10d, eax
    test eax, eax
    jz .c_next
    cmp eax, -255
    jl .c_word
    cmp eax, 255
    jg .c_word
    mov edx, eax                        ; short: its size
    neg edx
    cmovl edx, eax
    mov [rdi], dl
    inc rdi
    jmp .c_next
.c_word:
    xchg al, ah
    mov [rdi], ax
    add rdi, 2
.c_next:
    inc ecx
    jmp .c
.c_out:
    ret

; r14d = a triplet's flag (7 bits), r15 = the w2_glyf frame -> eax dx, edx
;   dy (CF: damaged), its bytes from the glyph stream
w2_triplet:
    push rbx
    push r12
    sub rsp, 24                         ; up to 4 bytes
    lea rsi, [r15 + GS_GL]
    mov ebx, 1
    cmp r14d, 84
    jb .read
    mov ebx, 2
    cmp r14d, 120
    jb .read
    mov ebx, 3
    cmp r14d, 124
    jb .read
    mov ebx, 4
.read:
    xor r12d, r12d
.byte:
    cmp r12d, ebx
    jae .decode
    call w2_u8
    jc .bad
    mov [rsp + r12], al
    inc r12d
    jmp .byte
.decode:
    movzx r8d, byte [rsp]
    movzx r9d, byte [rsp + 1]
    movzx r10d, byte [rsp + 2]
    movzx r11d, byte [rsp + 3]
    cmp r14d, 10
    jae .t10
    ; dx 0, dy ((flag & 14) << 7) + b0
    xor eax, eax
    mov edx, r14d
    and edx, 14
    shl edx, 7
    add edx, r8d
    mov ecx, r14d
    jmp .sign_y
.t10:
    cmp r14d, 20
    jae .t20
    lea eax, [r14 - 10]
    and eax, 14
    shl eax, 7
    add eax, r8d
    xor edx, edx
    mov ecx, r14d
    test ecx, 1
    jnz .done
    neg eax
    jmp .done
.t20:
    cmp r14d, 84
    jae .t84
    lea ecx, [r14 - 20]                 ; b0
    mov eax, ecx
    and eax, 0x30
    mov edx, r8d
    shr edx, 4
    lea eax, [rax + rdx + 1]
    mov edx, ecx
    and edx, 0x0C
    shl edx, 2
    mov r9d, r8d
    and r9d, 0x0F
    lea edx, [rdx + r9 + 1]
    jmp .sign_both
.t84:
    cmp r14d, 120
    jae .t120
    lea ecx, [r14 - 84]                 ; b0
    mov eax, ecx
    push rdx
    xor edx, edx
    push rcx
    mov r12d, 12
    div r12d                            ; eax b0 / 12, edx b0 % 12
    shl eax, 8
    lea eax, [rax + r8 + 1]
    shr edx, 2
    shl edx, 8
    lea edx, [rdx + r9 + 1]
    pop rcx
    add rsp, 8
    jmp .sign_both
.t120:
    cmp r14d, 124
    jae .t124
    mov eax, r8d
    shl eax, 4
    mov edx, r9d
    shr edx, 4
    add eax, edx
    mov edx, r9d
    and edx, 0x0F
    shl edx, 8
    add edx, r10d
    jmp .sign_both
.t124:
    mov eax, r8d
    shl eax, 8
    add eax, r9d
    mov edx, r10d
    shl edx, 8
    add edx, r11d
.sign_both:
    test r14d, 1                        ; x: bit 0 set positive
    jnz .x_pos
    neg eax
.x_pos:
    mov ecx, r14d
    shr ecx, 1
.sign_y:
    test ecx, 1                         ; y: (flag >> 1) bit 0 (flag for the first ten)
    jnz .done
    neg edx
.done:
    clc
    jmp .out
.bad:
    stc
.out:
    lea rsp, [rsp + 24]
    pop r12
    pop rbx
    ret

; eax = glyph, r15 = the w2_glyf frame (GF_NPTS points in GF_PX / GF_PY):
;   its box into GF_BOX - from the bbox stream when the bitmap says, else
;   from the points (CF: damaged)
w2_box:
    mov rcx, [r15 + GF_BITMAP]
    mov edx, eax
    shr edx, 3
    movzx edx, byte [rcx + rdx]
    and eax, 7
    mov ecx, 7
    sub ecx, eax
    shr edx, cl
    test edx, 1
    jz .computed
    lea rsi, [r15 + GS_BB]
    xor r8d, r8d
.given:
    call w2_u16
    jc .bad
    mov [r15 + GF_BOX + r8 * 2], ax
    inc r8d
    cmp r8d, 4
    jb .given
    clc
    ret
.computed:
    mov ecx, [r15 + GF_NPTS]
    xor eax, eax
    mov [r15 + GF_BOX], rax
    test ecx, ecx
    jz .ok
    mov rsi, [r15 + GF_PX]
    mov rdi, [r15 + GF_PY]
    mov r8d, [rsi]                      ; xMin, xMax
    mov r9d, r8d
    mov r10d, [rdi]                     ; yMin, yMax
    mov r11d, r10d
    xor edx, edx
.minmax:
    cmp edx, ecx
    jae .boxed
    mov eax, [rsi + rdx * 4]
    cmp eax, r8d
    cmovl r8d, eax
    cmp eax, r9d
    cmovg r9d, eax
    mov eax, [rdi + rdx * 4]
    cmp eax, r10d
    cmovl r10d, eax
    cmp eax, r11d
    cmovg r11d, eax
    inc edx
    jmp .minmax
.boxed:
    mov [r15 + GF_BOX], r8w
    mov [r15 + GF_BOX + 2], r10w
    mov [r15 + GF_BOX + 4], r9w
    mov [r15 + GF_BOX + 6], r11w
.ok:
    clc
    ret
.bad:
    stc
    ret

; ----------------------------------------------------------------------------
; w2_composite — (in the w2_glyf frame at rsp + 8) a composite glyph copied
;   from the composite stream, its box (always given), its instructions ->
;   eax 1, 0 damaged
; ----------------------------------------------------------------------------
w2_composite:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    lea r15, [rsp + WS]
    mov eax, [r15 + GF_G]
    mov rcx, [r15 + GF_BITMAP]
    mov edx, eax
    shr edx, 3
    movzx edx, byte [rcx + rdx]
    and eax, 7
    mov ecx, 7
    sub ecx, eax
    shr edx, cl
    test edx, 1
    jz .bad                             ; a composite's box is given
    mov dword [r15 + GF_NPTS], 0
    mov eax, [r15 + GF_G]
    call w2_box
    jc .bad
    ; the components: their length, whether instructions follow
    mov r12, [r15 + GS_CO]              ; start
    mov r13, r12
    xor ebp, ebp                        ; instructions
.component:
    lea rax, [r13 + 4]
    cmp rax, [r15 + GS_CO + 8]
    ja .bad
    movzx ebx, word [r13]
    xchg bl, bh
    add r13, 4                          ; flags, glyph
    test ebx, 0x100
    jz .args
    mov ebp, 1
.args:
    mov eax, 2
    test ebx, 1                         ; words
    jz .arg_size
    mov eax, 4
.arg_size:
    add r13, rax
    test ebx, 8
    jz .xy
    add r13, 2
    jmp .more
.xy:
    test ebx, 0x40
    jz .two
    add r13, 4
    jmp .more
.two:
    test ebx, 0x80
    jz .more
    add r13, 8
.more:
    cmp r13, [r15 + GS_CO + 8]
    ja .bad
    test ebx, 0x20
    jnz .component
    mov [r15 + GS_CO], r13
    ; header and components
    mov r14, r13
    sub r14, r12                        ; their length
    xor eax, eax
    test ebp, ebp
    jz .length
    lea rsi, [r15 + GS_GL]
    call w2_255
    jc .bad
.length:
    mov [r15 + GF_INSTR], eax
    mov rdi, [r15 + GF_OUT]
    add rdi, [r15 + GF_AT]
    lea rax, [r14 + 10 + 2]
    add eax, [r15 + GF_INSTR]
    add rax, [r15 + GF_AT]
    cmp rax, [r15 + GF_CAP]
    ja .bad
    mov word [rdi], 0xFFFF              ; -1 contours
    xor ecx, ecx
.hdr:
    mov ax, [r15 + GF_BOX + rcx * 2]
    xchg al, ah
    mov [rdi + 2 + rcx * 2], ax
    inc ecx
    cmp ecx, 4
    jb .hdr
    add rdi, 10
    mov rsi, r12
    mov rcx, r14
    rep movsb
    test ebp, ebp
    jz .done
    mov eax, [r15 + GF_INSTR]
    mov ecx, eax
    xchg al, ah
    mov [rdi], ax
    add rdi, 2
    mov rsi, [r15 + GS_IN]
    lea rax, [rsi + rcx]
    cmp rax, [r15 + GS_IN + 8]
    ja .bad
    mov [r15 + GS_IN], rax
    rep movsb
.done:
    sub rdi, [r15 + GF_OUT]
    mov [r15 + GF_AT], rdi
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; ----------------------------------------------------------------------------
; w2_hmtx — rdi = the unpack frame: the transformed hmtx rebuilt (the left
;   side bearings left out from the glyphs' xMin) -> eax 1, 0 damaged
; ----------------------------------------------------------------------------
w2_hmtx:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r15, rdi
    cmp qword [r15 + WF_XMIN], 0
    je .bad                             ; needs the rebuilt glyf
    mov rax, [r15 + WF_HHEA]
    test rax, rax
    jz .bad
    cmp dword [rax + WT_ORIG], 36
    jb .bad
    mov rcx, [rax + WT_SRC]
    movzx eax, word [rcx + 34]
    xchg al, ah
    mov ebp, eax                        ; numberOfHMetrics
    mov r14d, [r15 + WF_NGLYPHS]
    test ebp, ebp
    jz .bad
    cmp ebp, r14d
    ja .bad
    mov rbx, [r15 + WF_HMTX]
    mov r12, [rbx + WT_SRC]
    mov r13d, [rbx + WT_TLEN]
    add r13, r12                        ; end
    cmp r12, r13
    jae .bad
    movzx eax, byte [r12]
    mov [rsp], eax                      ; flags
    inc r12
    ; the size: 4 per long metric, 2 per short one
    lea eax, [rbp * 2 + r14]
    add eax, eax
    mov [rbx + WT_OUTLEN], eax
    mov esi, eax
    mov rdi, [r15 + WF_ARENA]
    call arena_alloc
    test rax, rax
    jz .bad
    mov [rbx + WT_OUT], rax
    mov rdi, rax
    ; advances
    lea rax, [r12 + rbp * 2]
    cmp rax, r13
    ja .bad
    xor ecx, ecx
.adv:
    cmp ecx, ebp
    jae .lsb
    mov ax, [r12 + rcx * 2]
    mov [rdi + rcx * 4], ax
    inc ecx
    jmp .adv
.lsb:
    lea r12, [r12 + rbp * 2]
    ; the long metrics' bearings: given unless flag 1
    xor ecx, ecx
.lsb1:
    cmp ecx, ebp
    jae .lsb2_start
    test dword [rsp], 1
    jnz .lsb1_xmin
    lea rax, [r12 + 2]
    cmp rax, r13
    ja .bad
    mov ax, [r12]
    add r12, 2
    jmp .lsb1_put
.lsb1_xmin:
    mov rax, [r15 + WF_XMIN]
    mov ax, [rax + rcx * 2]
    xchg al, ah
.lsb1_put:
    mov [rdi + rcx * 4 + 2], ax
    inc ecx
    jmp .lsb1
.lsb2_start:
    lea rsi, [rdi + rbp * 4]
    mov ecx, ebp
.lsb2:
    cmp ecx, r14d
    jae .ok
    test dword [rsp], 2
    jnz .lsb2_xmin
    lea rax, [r12 + 2]
    cmp rax, r13
    ja .bad
    mov ax, [r12]
    add r12, 2
    jmp .lsb2_put
.lsb2_xmin:
    mov rax, [r15 + WF_XMIN]
    mov ax, [rax + rcx * 2]
    xchg al, ah
.lsb2_put:
    mov [rsi], ax
    add rsi, 2
    inc ecx
    jmp .lsb2
.ok:
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
