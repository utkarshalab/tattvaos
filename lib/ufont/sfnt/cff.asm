; =============================================================================
; Utkarsha OS — lib/ufont/sfnt/cff.asm
; =============================================================================
; CFF outlines (OpenType fonts with a 'CFF ' table, Type 2 charstrings), as
; tools/cff.py models them.
;
;   ufl_cff_open (rbx = UfontFont*, its CFF table found) -> eax 1 usable
;       The header; the Name, Top DICT, String and Global Subr INDEXes; from
;       the Top DICT the CharStrings INDEX and, for a CID-keyed font (ROS),
;       the FDArray and FDSelect, else the Private DICT's local Subrs.
;   ufl_cff_outline(font, glyph, path, scale) -> rax 0, -errno
;       The glyph's charstring run: every drawing operator (moves, lines,
;       curves, the four flexes), stems and hint masks counted to skip
;       their bytes, the advance width dropped from the first
;       stack-clearing operator, subroutines (local - for a CID font its
;       Font DICT's, by FDSelect formats 0 and 3 - and global, biased, 10
;       deep), endchar. Numbers are doubles (integers, 16.16 fixed); points
;       are summed as the operators give them and drawn at scale, y down.
;       seac and the arithmetic operators end the glyph.
; Every INDEX, DICT, offset and charstring byte is checked against the
; table before it is read.
; =============================================================================

%include "ugfx.inc"
%include "ufont.inc"

extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_cubic_to
extern ugfx_path_close

%define CFF_MAX_STACK   48
%define CFF_MAX_DEPTH   10

; an INDEX as found (in UfontFont_cffix)
%define IX_COUNT        0               ; u32
%define IX_OSZ          4               ; u32 offset size
%define IX_OFFS         8               ; its offsets
%define IX_BASE         16              ; an item at IX_BASE + its offset
%define IX_SIZE         24
%define CX_CS           0               ; CharStrings
%define CX_GSUBR        24              ; Global Subrs
%define CX_LSUBR        48              ; local Subrs (not CID)
%define CX_FDARRAY      72              ; FDArray (CID)

section .rodata
align 8
cff_fixed:  dq 0x3EF0000000000000       ; 1 / 65536

section .text

; a big-endian u16, zero-extended
%macro BE16 2
    movzx %1, word %2
    bswap %1
    shr %1, 16
%endmacro

; ----------------------------------------------------------------------------
; cff_index — rdi = where an INDEX starts, rsi = the table's end, rdx = an
;   IX record -> rax = the byte after it (0: damaged)
; ----------------------------------------------------------------------------
cff_index:
    lea rax, [rdi + 2]
    cmp rax, rsi
    ja .bad
    BE16 ecx, [rdi]
    mov [rdx + IX_COUNT], ecx
    mov dword [rdx + IX_OSZ], 0
    test ecx, ecx
    jz .out
    lea rax, [rdi + 3]
    cmp rax, rsi
    ja .bad
    movzx r8d, byte [rdi + 2]
    test r8d, r8d
    jz .bad
    cmp r8d, 4
    ja .bad
    mov [rdx + IX_OSZ], r8d
    lea r9, [rdi + 3]
    mov [rdx + IX_OFFS], r9
    lea eax, [rcx + 1]
    imul rax, r8
    add rax, r9                         ; past the offsets
    cmp rax, rsi
    ja .bad
    dec rax
    mov [rdx + IX_BASE], rax
    push rsi
    mov rdi, rdx
    mov esi, ecx
    call cff_offset                     ; the last offset: the data's end
    pop rsi
    add rax, [rdi + IX_BASE]
    cmp rax, rsi
    ja .bad
.out:
    ret
.bad:
    xor eax, eax
    ret

; rdi = IX, esi = i -> rax = offset i (big-endian, IX_OSZ bytes)
cff_offset:
    mov r8d, [rdi + IX_OSZ]
    mov r9, [rdi + IX_OFFS]
    mov eax, esi
    imul rax, r8
    add r9, rax
    xor eax, eax
.byte:
    test r8d, r8d
    jz .out
    shl rax, 8
    movzx r10d, byte [r9]
    or rax, r10
    inc r9
    dec r8d
    jmp .byte
.out:
    ret

; ----------------------------------------------------------------------------
; cff_item — rdi = IX, esi = i, rdx = the table's end -> rax = the item's
;   start, rdx = its end (rax 0: no such item, or damaged)
; ----------------------------------------------------------------------------
cff_item:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    cmp r12d, [rbx + IX_COUNT]
    jae .bad
    call cff_offset
    mov rcx, rax
    lea esi, [r12 + 1]
    mov rdi, rbx
    push rcx
    call cff_offset
    pop rcx
    test rcx, rcx
    jz .bad
    cmp rax, rcx
    jb .bad
    mov rdx, [rbx + IX_BASE]
    add rax, rdx
    cmp rax, r13
    ja .bad
    add rcx, rdx
    mov rdx, rax
    mov rax, rcx
    jmp .out
.bad:
    xor eax, eax
    xor edx, edx
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; cff_dict — rdi = a DICT's start, rsi = its end, edx = an operator (12 x:
;   1200 + x) -> eax 1 found, rcx / r8 = its first two operands (integers;
;   reals as 0)
; ----------------------------------------------------------------------------
cff_dict:
    push rbx
    push r12
    mov r12d, edx
    xor ebx, ebx                        ; operands
    xor ecx, ecx
    xor r8d, r8d
.loop:
    cmp rdi, rsi
    jae .none
    movzx eax, byte [rdi]
    cmp eax, 21
    ja .operand
    inc rdi
    cmp eax, 12
    jne .op
    cmp rdi, rsi
    jae .none
    movzx eax, byte [rdi]
    inc rdi
    add eax, 1200
.op:
    cmp eax, r12d
    je .found
    xor ebx, ebx
    jmp .loop
.operand:
    cmp eax, 28
    je .int16
    cmp eax, 29
    je .int32
    cmp eax, 30
    je .real
    cmp eax, 32
    jb .reserved
    cmp eax, 246
    jbe .small
    cmp eax, 250
    jbe .pos
    cmp eax, 254
    jbe .neg
.reserved:
    inc rdi
    jmp .loop
.small:
    sub eax, 139
    inc rdi
    jmp .push
.pos:
    lea r9, [rdi + 2]
    cmp r9, rsi
    ja .none
    sub eax, 247
    shl eax, 8
    movzx r9d, byte [rdi + 1]
    add eax, r9d
    add eax, 108
    add rdi, 2
    jmp .push
.neg:
    lea r9, [rdi + 2]
    cmp r9, rsi
    ja .none
    sub eax, 251
    shl eax, 8
    movzx r9d, byte [rdi + 1]
    add eax, r9d
    add eax, 108
    neg eax
    add rdi, 2
    jmp .push
.int16:
    lea r9, [rdi + 3]
    cmp r9, rsi
    ja .none
    movzx eax, word [rdi + 1]
    xchg al, ah
    movsx eax, ax
    add rdi, 3
    jmp .push
.int32:
    lea r9, [rdi + 5]
    cmp r9, rsi
    ja .none
    mov eax, [rdi + 1]
    bswap eax
    add rdi, 5
    jmp .push
.real:
    ; nibbles to the 0xF end; the value is not needed
    inc rdi
.real_byte:
    cmp rdi, rsi
    jae .real_done
    movzx r9d, byte [rdi]
    inc rdi
    mov r10d, r9d
    shr r10d, 4
    cmp r10d, 15
    je .real_done
    and r9d, 15
    cmp r9d, 15
    jne .real_byte
.real_done:
    xor eax, eax
.push:
    movsxd rax, eax
    test ebx, ebx
    jnz .second
    mov rcx, rax
    jmp .pushed
.second:
    cmp ebx, 1
    jne .pushed
    mov r8, rax
.pushed:
    inc ebx
    jmp .loop
.found:
    mov eax, 1
    jmp .out
.none:
    xor eax, eax
.out:
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufl_cff_open — rbx = UfontFont* (UfontFont_cff set) -> eax 1 usable, 0 not
; ----------------------------------------------------------------------------
%define CO_TOP      0                   ; the Top DICT
%define CO_TOPEND   8
%define CO_IX       16                  ; scratch INDEX
%define CO_SIZE     48

global ufl_cff_open
ufl_cff_open:
    push r12
    push r13
    push r14
    sub rsp, CO_SIZE
    mov r12, [rbx + UfontFont_cff]
    mov r13, [rbx + UfontFont_cff_len]
    add r13, r12                        ; the table's end
    lea rax, [r12 + 4]
    cmp rax, r13
    ja .bad
    cmp byte [r12], 1                   ; major version 1
    jne .bad
    movzx edi, byte [r12 + 2]           ; header size
    add rdi, r12
    ; Name INDEX, Top DICT INDEX (its first item), String INDEX, Global Subrs
    mov rsi, r13
    lea rdx, [rsp + CO_IX]
    call cff_index
    test rax, rax
    jz .bad
    mov rdi, rax
    mov rsi, r13
    lea rdx, [rsp + CO_IX]
    call cff_index
    test rax, rax
    jz .bad
    mov r14, rax
    lea rdi, [rsp + CO_IX]
    xor esi, esi
    mov rdx, r13
    call cff_item
    test rax, rax
    jz .bad
    mov [rsp + CO_TOP], rax
    mov [rsp + CO_TOPEND], rdx
    mov rdi, r14
    mov rsi, r13
    lea rdx, [rsp + CO_IX]
    call cff_index                      ; String
    test rax, rax
    jz .bad
    mov rdi, rax
    mov rsi, r13
    lea rdx, [rbx + UfontFont_cffix + CX_GSUBR]
    call cff_index
    test rax, rax
    jz .bad
    ; CharStrings
    mov rdi, [rsp + CO_TOP]
    mov rsi, [rsp + CO_TOPEND]
    mov edx, 17
    call cff_dict
    test eax, eax
    jz .bad
    test rcx, rcx
    jle .bad
    lea rdi, [r12 + rcx]
    cmp rdi, r13
    jae .bad
    mov rsi, r13
    lea rdx, [rbx + UfontFont_cffix + CX_CS]
    call cff_index
    test rax, rax
    jz .bad
    ; CID-keyed (ROS): FDArray and FDSelect
    mov rdi, [rsp + CO_TOP]
    mov rsi, [rsp + CO_TOPEND]
    mov edx, 1230
    call cff_dict
    test eax, eax
    jz .plain
    mov dword [rbx + UfontFont_cid], 1
    mov rdi, [rsp + CO_TOP]
    mov rsi, [rsp + CO_TOPEND]
    mov edx, 1236
    call cff_dict
    test eax, eax
    jz .bad
    test rcx, rcx
    jle .bad
    lea rdi, [r12 + rcx]
    cmp rdi, r13
    jae .bad
    mov rsi, r13
    lea rdx, [rbx + UfontFont_cffix + CX_FDARRAY]
    call cff_index
    test rax, rax
    jz .bad
    mov rdi, [rsp + CO_TOP]
    mov rsi, [rsp + CO_TOPEND]
    mov edx, 1237
    call cff_dict
    test eax, eax
    jz .bad
    test rcx, rcx
    jle .bad
    lea rax, [r12 + rcx]
    cmp rax, r13
    jae .bad
    mov [rbx + UfontFont_fdselect], rax
    jmp .ok
.plain:
    ; the Private DICT's local Subrs
    mov dword [rbx + UfontFont_cffix + CX_LSUBR + IX_COUNT], 0
    mov rdi, [rsp + CO_TOP]
    mov rsi, [rsp + CO_TOPEND]
    lea rdx, [rbx + UfontFont_cffix + CX_LSUBR]
    call cff_private
.ok:
    mov eax, 1
    jmp .out
.bad:
    xor eax, eax
.out:
    add rsp, CO_SIZE
    pop r14
    pop r13
    pop r12
    ret

; cff_private — rdi / rsi = a DICT with a Private entry (Top or Font DICT),
;   rdx = an IX for its local Subrs, rbx = font: the IX filled (count 0:
;   none)
cff_private:
    push r12
    push r13
    push r14
    mov r14, rdx
    mov dword [r14 + IX_COUNT], 0
    mov edx, 18
    call cff_dict
    test eax, eax
    jz .out
    ; rcx = size, r8 = offset
    mov r12, [rbx + UfontFont_cff]
    mov r13, [rbx + UfontFont_cff_len]
    test rcx, rcx
    jle .out
    test r8, r8
    jle .out
    lea rax, [r8 + rcx]
    cmp rax, r13
    ja .out
    lea rdi, [r12 + r8]                 ; the Private DICT
    lea rsi, [rdi + rcx]
    push rdi
    sub rsp, 8
    mov edx, 19
    call cff_dict
    add rsp, 8
    pop rdi
    test eax, eax
    jz .out
    test rcx, rcx
    jle .out
    add rdi, rcx                        ; Subrs: from the Private DICT
    add r13, r12
    cmp rdi, r13
    jae .out
    mov rsi, r13
    mov rdx, r14
    call cff_index
    test rax, rax
    jnz .out
    mov dword [r14 + IX_COUNT], 0
.out:
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------------
; ufl_cff_outline — rdi = UfontFont*, esi = glyph, rdx = UgfxPath*, xmm0 =
;   scale -> rax = 0, -errno (a damaged charstring ends the glyph there)
; ----------------------------------------------------------------------------
%define CS_STACK    0                   ; f64 x 48
%define CS_SP       384                 ; u32
%define CS_OPEN     388                 ; u32 a contour is open
%define CS_X        392
%define CS_Y        400
%define CS_STEMS    408                 ; u32
%define CS_WIDTHED  412                 ; u32 the first stack-clearing operator came
%define CS_SCALE    416
%define CS_PATH     424
%define CS_FONT     432
%define CS_END      440                 ; the table's end
%define CS_ERR      448                 ; i64 a path error
%define CS_LOCAL    456                 ; IX
%define CS_SIZE     480

global ufl_cff_outline
ufl_cff_outline:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, CS_SIZE
    mov r15, rsp
    mov rbx, rdi
    mov [r15 + CS_FONT], rdi
    mov [r15 + CS_PATH], rdx
    movsd [r15 + CS_SCALE], xmm0
    mov r12d, esi
    xor eax, eax
    mov [r15 + CS_SP], eax
    mov [r15 + CS_OPEN], eax
    mov [r15 + CS_STEMS], eax
    mov [r15 + CS_WIDTHED], eax
    mov [r15 + CS_X], rax
    mov [r15 + CS_Y], rax
    mov [r15 + CS_ERR], rax
    mov rax, [rbx + UfontFont_cff]
    add rax, [rbx + UfontFont_cff_len]
    mov [r15 + CS_END], rax
    ; its local Subrs
    cmp dword [rbx + UfontFont_cid], 0
    jne .cid
    lea rsi, [rbx + UfontFont_cffix + CX_LSUBR]
    lea rdi, [r15 + CS_LOCAL]
    mov ecx, IX_SIZE
    rep movsb
    jmp .charstring
.cid:
    mov edi, r12d
    call cff_fd                         ; -> eax the Font DICT (-1 none)
    cmp eax, -1
    je .done
    lea rdi, [rbx + UfontFont_cffix + CX_FDARRAY]
    mov esi, eax
    mov rdx, [r15 + CS_END]
    call cff_item
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rdx
    lea rdx, [r15 + CS_LOCAL]
    call cff_private
.charstring:
    lea rdi, [rbx + UfontFont_cffix + CX_CS]
    mov esi, r12d
    mov rdx, [r15 + CS_END]
    call cff_item
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rdx
    xor edx, edx
    call cs_run
    ; the last contour closed
    call cs_close
.done:
    mov rax, [r15 + CS_ERR]
    add rsp, CS_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; cff_fd — edi = glyph, rbx = font -> eax its Font DICT by FDSelect (format
;   0 or 3; -1 none)
cff_fd:
    mov rsi, [rbx + UfontFont_fdselect]
    mov rdx, [rbx + UfontFont_cff]
    add rdx, [rbx + UfontFont_cff_len]  ; end
    movzx eax, byte [rsi]
    test eax, eax
    jz .format0
    cmp eax, 3
    jne .none
    lea rax, [rsi + 3]
    cmp rax, rdx
    ja .none
    BE16 ecx, [rsi + 1]                 ; ranges
    lea r8, [rsi + 3]
.range:
    test ecx, ecx
    jz .none
    lea rax, [r8 + 5]
    cmp rax, rdx
    ja .none
    BE16 eax, [r8]                      ; first
    BE16 r9d, [r8 + 3]                  ; the next range's first (or the sentinel)
    cmp edi, eax
    jb .next
    cmp edi, r9d
    jae .next
    movzx eax, byte [r8 + 2]
    ret
.next:
    add r8, 3
    dec ecx
    jmp .range
.format0:
    lea rax, [rsi + 1 + rdi]
    cmp rax, rdx
    jae .none
    movzx eax, byte [rax]
    ret
.none:
    mov eax, -1
    ret

; ----------------------------------------------------------------------------
; cs_run — rdi = a charstring's start, rsi = its end, edx = depth, r15 =
;   state -> eax 0 it returned, 1 the glyph ends
; ----------------------------------------------------------------------------
cs_run:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi                        ; p
    mov r13, rsi                        ; end
    mov r14d, edx                       ; depth
.next:
    cmp r12, r13
    jae .returned
    movzx eax, byte [r12]
    cmp eax, 28
    je .int16
    cmp eax, 32
    jae .number
    ; an operator
    inc r12
    cmp eax, 12
    jne .op
    cmp r12, r13
    jae .end
    movzx eax, byte [r12]
    inc r12
    add eax, 1200
.op:
    cmp eax, 1
    je .stem
    cmp eax, 3
    je .stem
    cmp eax, 18
    je .stem
    cmp eax, 23
    je .stem
    cmp eax, 19
    je .hintmask
    cmp eax, 20
    je .hintmask
    cmp eax, 21
    je .rmoveto
    cmp eax, 22
    je .hmoveto
    cmp eax, 4
    je .vmoveto
    cmp eax, 5
    je .rlineto
    cmp eax, 6
    je .hlineto
    cmp eax, 7
    je .vlineto
    cmp eax, 8
    je .rrcurveto
    cmp eax, 27
    je .hhcurveto
    cmp eax, 26
    je .vvcurveto
    cmp eax, 31
    je .hvcurveto
    cmp eax, 30
    je .vhcurveto
    cmp eax, 24
    je .rcurveline
    cmp eax, 25
    je .rlinecurve
    cmp eax, 1235
    je .flex
    cmp eax, 1234
    je .hflex
    cmp eax, 1236
    je .hflex1
    cmp eax, 1237
    je .flex1
    cmp eax, 10
    je .callsubr
    cmp eax, 29
    je .callgsubr
    cmp eax, 11
    je .returned
    jmp .end                            ; endchar, seac, arithmetic, reserved

; ---- numbers
.int16:
    lea rax, [r12 + 3]
    cmp rax, r13
    ja .end
    movzx eax, word [r12 + 1]
    xchg al, ah
    movsx eax, ax
    add r12, 3
    cvtsi2sd xmm0, eax
    jmp .push
.number:
    cmp eax, 246
    ja .wide
    sub eax, 139
    inc r12
    cvtsi2sd xmm0, eax
    jmp .push
.wide:
    cmp eax, 255
    je .fixed
    lea rcx, [r12 + 2]
    cmp rcx, r13
    ja .end
    movzx ecx, byte [r12 + 1]
    add r12, 2
    cmp eax, 250
    ja .negative
    sub eax, 247
    shl eax, 8
    add eax, ecx
    add eax, 108
    cvtsi2sd xmm0, eax
    jmp .push
.negative:
    sub eax, 251
    shl eax, 8
    add eax, ecx
    add eax, 108
    neg eax
    cvtsi2sd xmm0, eax
    jmp .push
.fixed:
    lea rcx, [r12 + 5]
    cmp rcx, r13
    ja .end
    mov eax, [r12 + 1]
    bswap eax
    add r12, 5
    cvtsi2sd xmm0, eax
    mulsd xmm0, [rel cff_fixed]
.push:
    mov eax, [r15 + CS_SP]
    cmp eax, CFF_MAX_STACK
    jae .end
    movsd [r15 + CS_STACK + rax * 8], xmm0
    inc dword [r15 + CS_SP]
    jmp .next

; ---- hints
.stem:
    mov ecx, [r15 + CS_SP]
    and ecx, 1
    call cs_width
    mov eax, [r15 + CS_SP]
    shr eax, 1
    add [r15 + CS_STEMS], eax
    jmp .clear
.hintmask:
    mov ecx, [r15 + CS_SP]
    and ecx, 1
    call cs_width
    mov eax, [r15 + CS_SP]
    shr eax, 1
    add [r15 + CS_STEMS], eax
    mov eax, [r15 + CS_STEMS]
    add eax, 7
    shr eax, 3
    add r12, rax                        ; its mask bytes
    jmp .clear

; ---- moves
.rmoveto:
    xor ecx, ecx
    cmp dword [r15 + CS_SP], 2
    seta cl
    call cs_width
    mov eax, [r15 + CS_SP]
    cmp eax, 2
    jb .end
    movsd xmm0, [r15 + CS_STACK + rax * 8 - 16]
    movsd xmm1, [r15 + CS_STACK + rax * 8 - 8]
    call cs_move
    jmp .clear
.hmoveto:
    xor ecx, ecx
    cmp dword [r15 + CS_SP], 1
    seta cl
    call cs_width
    mov eax, [r15 + CS_SP]
    test eax, eax
    jz .end
    movsd xmm0, [r15 + CS_STACK + rax * 8 - 8]
    xorpd xmm1, xmm1
    call cs_move
    jmp .clear
.vmoveto:
    xor ecx, ecx
    cmp dword [r15 + CS_SP], 1
    seta cl
    call cs_width
    mov eax, [r15 + CS_SP]
    test eax, eax
    jz .end
    xorpd xmm0, xmm0
    movsd xmm1, [r15 + CS_STACK + rax * 8 - 8]
    call cs_move
    jmp .clear

; ---- lines
.rlineto:
    xor ebx, ebx
.rl:
    lea eax, [rbx + 1]
    cmp eax, [r15 + CS_SP]
    jae .clear
    movsd xmm0, [r15 + CS_STACK + rbx * 8]
    movsd xmm1, [r15 + CS_STACK + rbx * 8 + 8]
    call cs_line
    add ebx, 2
    jmp .rl
.hlineto:
    xor ecx, ecx                        ; 0: horizontal first
    jmp .hvl
.vlineto:
    mov ecx, 1
.hvl:
    xor ebx, ebx
    mov [rsp], ecx
.hvl_each:
    cmp ebx, [r15 + CS_SP]
    jae .clear
    movsd xmm2, [r15 + CS_STACK + rbx * 8]
    xorpd xmm0, xmm0
    xorpd xmm1, xmm1
    cmp dword [rsp], 0
    jne .hvl_v
    movsd xmm0, xmm2
    jmp .hvl_go
.hvl_v:
    movsd xmm1, xmm2
.hvl_go:
    call cs_line
    xor dword [rsp], 1
    inc ebx
    jmp .hvl_each

; ---- curves (cs_curve takes xmm0 .. xmm5)
.rrcurveto:
    xor ebx, ebx
.rr:
    lea eax, [rbx + 5]
    cmp eax, [r15 + CS_SP]
    jae .clear
    call .six
    call cs_curve
    add ebx, 6
    jmp .rr
.hhcurveto:
    xor ebx, ebx
    xorpd xmm6, xmm6                    ; dy1
    test dword [r15 + CS_SP], 1
    jz .hh
    movsd xmm6, [r15 + CS_STACK]
    mov ebx, 1
.hh:
    lea eax, [rbx + 4]
    cmp eax, [r15 + CS_SP]
    ja .clear
    movsd xmm0, [r15 + CS_STACK + rbx * 8]
    movsd xmm1, xmm6
    movsd xmm2, [r15 + CS_STACK + rbx * 8 + 8]
    movsd xmm3, [r15 + CS_STACK + rbx * 8 + 16]
    movsd xmm4, [r15 + CS_STACK + rbx * 8 + 24]
    xorpd xmm5, xmm5
    call cs_curve
    xorpd xmm6, xmm6
    add ebx, 4
    jmp .hh
.vvcurveto:
    xor ebx, ebx
    xorpd xmm6, xmm6                    ; dx1
    test dword [r15 + CS_SP], 1
    jz .vv
    movsd xmm6, [r15 + CS_STACK]
    mov ebx, 1
.vv:
    lea eax, [rbx + 4]
    cmp eax, [r15 + CS_SP]
    ja .clear
    movsd xmm0, xmm6
    movsd xmm1, [r15 + CS_STACK + rbx * 8]
    movsd xmm2, [r15 + CS_STACK + rbx * 8 + 8]
    movsd xmm3, [r15 + CS_STACK + rbx * 8 + 16]
    xorpd xmm4, xmm4
    movsd xmm5, [r15 + CS_STACK + rbx * 8 + 24]
    call cs_curve
    xorpd xmm6, xmm6
    add ebx, 4
    jmp .vv
.hvcurveto:
    mov dword [rsp], 0                  ; horizontal first
    jmp .alt
.vhcurveto:
    mov dword [rsp], 1
.alt:
    xor ebx, ebx
.alt_each:
    lea eax, [rbx + 4]
    cmp eax, [r15 + CS_SP]
    ja .clear
    xorpd xmm6, xmm6                    ; the last curve's extra operand
    mov eax, [r15 + CS_SP]
    sub eax, ebx
    cmp eax, 5
    jne .alt_go
    movsd xmm6, [r15 + CS_STACK + rbx * 8 + 32]
.alt_go:
    movsd xmm2, [r15 + CS_STACK + rbx * 8 + 8]
    movsd xmm3, [r15 + CS_STACK + rbx * 8 + 16]
    cmp dword [rsp], 0
    jne .alt_v
    movsd xmm0, [r15 + CS_STACK + rbx * 8]
    xorpd xmm1, xmm1
    movsd xmm4, xmm6
    movsd xmm5, [r15 + CS_STACK + rbx * 8 + 24]
    jmp .alt_curve
.alt_v:
    xorpd xmm0, xmm0
    movsd xmm1, [r15 + CS_STACK + rbx * 8]
    movsd xmm4, [r15 + CS_STACK + rbx * 8 + 24]
    movsd xmm5, xmm6
.alt_curve:
    call cs_curve
    xor dword [rsp], 1
    add ebx, 4
    jmp .alt_each
.rcurveline:
    xor ebx, ebx
.rcl:
    lea eax, [rbx + 8]
    cmp eax, [r15 + CS_SP]
    ja .rcl_line
    call .six
    call cs_curve
    add ebx, 6
    jmp .rcl
.rcl_line:
    lea eax, [rbx + 2]
    cmp eax, [r15 + CS_SP]
    ja .clear
    movsd xmm0, [r15 + CS_STACK + rbx * 8]
    movsd xmm1, [r15 + CS_STACK + rbx * 8 + 8]
    call cs_line
    jmp .clear
.rlinecurve:
    xor ebx, ebx
.rlc:
    lea eax, [rbx + 8]
    cmp eax, [r15 + CS_SP]
    ja .rlc_curve
    movsd xmm0, [r15 + CS_STACK + rbx * 8]
    movsd xmm1, [r15 + CS_STACK + rbx * 8 + 8]
    call cs_line
    add ebx, 2
    jmp .rlc
.rlc_curve:
    lea eax, [rbx + 6]
    cmp eax, [r15 + CS_SP]
    ja .clear
    call .six
    call cs_curve
    jmp .clear

; ---- flexes
.flex:
    cmp dword [r15 + CS_SP], 12
    jb .clear
    xor ebx, ebx
    call .six
    call cs_curve
    mov ebx, 6
    call .six
    call cs_curve
    jmp .clear
.hflex:
    cmp dword [r15 + CS_SP], 7
    jb .clear
    movsd xmm0, [r15 + CS_STACK]
    xorpd xmm1, xmm1
    movsd xmm2, [r15 + CS_STACK + 8]
    movsd xmm3, [r15 + CS_STACK + 16]
    movsd xmm4, [r15 + CS_STACK + 24]
    xorpd xmm5, xmm5
    call cs_curve
    movsd xmm0, [r15 + CS_STACK + 32]
    xorpd xmm1, xmm1
    movsd xmm2, [r15 + CS_STACK + 40]
    xorpd xmm3, xmm3
    subsd xmm3, [r15 + CS_STACK + 16]
    movsd xmm4, [r15 + CS_STACK + 48]
    xorpd xmm5, xmm5
    call cs_curve
    jmp .clear
.hflex1:
    cmp dword [r15 + CS_SP], 9
    jb .clear
    movsd xmm0, [r15 + CS_STACK]
    movsd xmm1, [r15 + CS_STACK + 8]
    movsd xmm2, [r15 + CS_STACK + 16]
    movsd xmm3, [r15 + CS_STACK + 24]
    movsd xmm4, [r15 + CS_STACK + 32]
    xorpd xmm5, xmm5
    call cs_curve
    movsd xmm6, [r15 + CS_STACK + 8]    ; -(dy1 + dy2 + dy5)
    addsd xmm6, [r15 + CS_STACK + 24]
    addsd xmm6, [r15 + CS_STACK + 56]
    movsd xmm0, [r15 + CS_STACK + 40]
    xorpd xmm1, xmm1
    movsd xmm2, [r15 + CS_STACK + 48]
    movsd xmm3, [r15 + CS_STACK + 56]
    movsd xmm4, [r15 + CS_STACK + 64]
    xorpd xmm5, xmm5
    subsd xmm5, xmm6
    call cs_curve
    jmp .clear
.flex1:
    cmp dword [r15 + CS_SP], 11
    jb .clear
    ; the sums of the five dx and dy, in order
    movsd xmm6, [r15 + CS_STACK]
    addsd xmm6, [r15 + CS_STACK + 16]
    addsd xmm6, [r15 + CS_STACK + 32]
    addsd xmm6, [r15 + CS_STACK + 48]
    addsd xmm6, [r15 + CS_STACK + 64]
    movsd xmm7, [r15 + CS_STACK + 8]
    addsd xmm7, [r15 + CS_STACK + 24]
    addsd xmm7, [r15 + CS_STACK + 40]
    addsd xmm7, [r15 + CS_STACK + 56]
    addsd xmm7, [r15 + CS_STACK + 72]
    movsd [rsp], xmm6                   ; (the frame word: dx)
    sub rsp, 16
    movsd [rsp], xmm7
    movsd [rsp + 8], xmm6
    xor ebx, ebx
    call .six16
    call cs_curve
    movsd xmm6, [rsp + 8]               ; dx
    movsd xmm7, [rsp]                   ; dy
    add rsp, 16
    movsd xmm0, [r15 + CS_STACK + 48]
    movsd xmm1, [r15 + CS_STACK + 56]
    movsd xmm2, [r15 + CS_STACK + 64]
    movsd xmm3, [r15 + CS_STACK + 72]
    ; |dx| > |dy|: the last x from d6, y back; else the last y from d6
    movsd xmm8, xmm6
    andpd xmm8, [rel cs_abs]
    movsd xmm9, xmm7
    andpd xmm9, [rel cs_abs]
    ucomisd xmm8, xmm9
    jbe .flex1_v
    movsd xmm4, [r15 + CS_STACK + 80]
    xorpd xmm5, xmm5
    subsd xmm5, xmm7
    jmp .flex1_go
.flex1_v:
    xorpd xmm4, xmm4
    subsd xmm4, xmm6
    movsd xmm5, [r15 + CS_STACK + 80]
.flex1_go:
    call cs_curve
    jmp .clear

; ---- subroutines
.callsubr:
    lea rdi, [r15 + CS_LOCAL]
    jmp .call
.callgsubr:
    mov rdi, [r15 + CS_FONT]
    lea rdi, [rdi + UfontFont_cffix + CX_GSUBR]
.call:
    mov eax, [r15 + CS_SP]
    test eax, eax
    jz .end
    cmp r14d, CFF_MAX_DEPTH
    jae .end
    dec eax
    mov [r15 + CS_SP], eax
    cvttsd2si esi, [r15 + CS_STACK + rax * 8]
    ; the bias: 107, 1131 or 32768 by the count
    mov ecx, [rdi + IX_COUNT]
    mov eax, 107
    cmp ecx, 1240
    jb .biased
    mov eax, 1131
    cmp ecx, 33900
    jb .biased
    mov eax, 32768
.biased:
    add esi, eax
    js .end
    mov rdx, [r15 + CS_END]
    call cff_item
    test rax, rax
    jz .end
    mov rdi, rax
    mov rsi, rdx
    lea edx, [r14 + 1]
    call cs_run
    test eax, eax
    jnz .end
    jmp .next

.clear:
    mov dword [r15 + CS_SP], 0
    jmp .next
.returned:
    xor eax, eax
    jmp .out
.end:
    mov eax, 1
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; xmm0 .. xmm5 = the six operands from ebx (frame at rsp + 8 / + 24)
.six:
    movsd xmm0, [r15 + CS_STACK + rbx * 8]
    movsd xmm1, [r15 + CS_STACK + rbx * 8 + 8]
    movsd xmm2, [r15 + CS_STACK + rbx * 8 + 16]
    movsd xmm3, [r15 + CS_STACK + rbx * 8 + 24]
    movsd xmm4, [r15 + CS_STACK + rbx * 8 + 32]
    movsd xmm5, [r15 + CS_STACK + rbx * 8 + 40]
    ret
.six16:
    jmp .six

section .rodata
align 16
cs_abs: dq 0x7FFFFFFFFFFFFFFF, 0x7FFFFFFFFFFFFFFF
section .text

; cs_width — ecx = 1 when the operator has one operand too many, r15 =
;   state: the first stack-clearing operator's extra operand (the width)
;   dropped
cs_width:
    cmp dword [r15 + CS_WIDTHED], 0
    jne .out
    mov dword [r15 + CS_WIDTHED], 1
    test ecx, ecx
    jz .out
    mov ecx, [r15 + CS_SP]
    test ecx, ecx
    jz .out
    dec ecx
    mov [r15 + CS_SP], ecx
    lea rsi, [r15 + CS_STACK + 8]
    lea rdi, [r15 + CS_STACK]
    shl ecx, 3
    rep movsb
.out:
    ret

; cs_close: the open contour closed
cs_close:
    cmp dword [r15 + CS_OPEN], 0
    je .out
    mov dword [r15 + CS_OPEN], 0
    sub rsp, 8
    mov rdi, [r15 + CS_PATH]
    call ugfx_path_close
    add rsp, 8
    call cs_err
.out:
    ret

; rax = a path call's result: the first error kept
cs_err:
    test rax, rax
    jz .out
    cmp qword [r15 + CS_ERR], 0
    jne .out
    mov [r15 + CS_ERR], rax
.out:
    ret

; xmm0 / xmm1 = font units -> the point at scale, y down
%macro AT_SCALE 0
    mulsd xmm0, [r15 + CS_SCALE]
    mulsd xmm1, [r15 + CS_SCALE]
    xorpd xmm7, xmm7
    subsd xmm7, xmm1
    movsd xmm1, xmm7
%endmacro

; cs_move — xmm0 / xmm1 = dx / dy: a new contour
cs_move:
    sub rsp, 24
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    call cs_close
    movsd xmm0, [r15 + CS_X]
    addsd xmm0, [rsp]
    movsd [r15 + CS_X], xmm0
    movsd xmm1, [r15 + CS_Y]
    addsd xmm1, [rsp + 8]
    movsd [r15 + CS_Y], xmm1
    AT_SCALE
    mov rdi, [r15 + CS_PATH]
    call ugfx_path_move_to
    call cs_err
    mov dword [r15 + CS_OPEN], 1
    add rsp, 24
    ret

; cs_start: a contour at the current point when none is open
cs_start:
    cmp dword [r15 + CS_OPEN], 0
    jne .out
    sub rsp, 8
    movsd xmm0, [r15 + CS_X]
    movsd xmm1, [r15 + CS_Y]
    AT_SCALE
    mov rdi, [r15 + CS_PATH]
    call ugfx_path_move_to
    call cs_err
    mov dword [r15 + CS_OPEN], 1
    add rsp, 8
.out:
    ret

; cs_line — xmm0 / xmm1 = dx / dy
cs_line:
    sub rsp, 24
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    call cs_start
    movsd xmm0, [r15 + CS_X]
    addsd xmm0, [rsp]
    movsd [r15 + CS_X], xmm0
    movsd xmm1, [r15 + CS_Y]
    addsd xmm1, [rsp + 8]
    movsd [r15 + CS_Y], xmm1
    AT_SCALE
    mov rdi, [r15 + CS_PATH]
    call ugfx_path_line_to
    call cs_err
    add rsp, 24
    ret

; cs_curve — xmm0 .. xmm5 = dxa, dya, dxb, dyb, dxc, dyc
cs_curve:
    sub rsp, 104
    movsd [rsp], xmm0
    movsd [rsp + 8], xmm1
    movsd [rsp + 16], xmm2
    movsd [rsp + 24], xmm3
    movsd [rsp + 32], xmm4
    movsd [rsp + 40], xmm5
    call cs_start
    ; the three points, each from the one before
    movsd xmm0, [r15 + CS_X]
    addsd xmm0, [rsp]
    movsd xmm1, [r15 + CS_Y]
    addsd xmm1, [rsp + 8]
    movsd [rsp + 48], xmm0              ; x1, y1
    movsd [rsp + 56], xmm1
    addsd xmm0, [rsp + 16]
    addsd xmm1, [rsp + 24]
    movsd [rsp + 64], xmm0              ; x2, y2
    movsd [rsp + 72], xmm1
    addsd xmm0, [rsp + 32]
    addsd xmm1, [rsp + 40]
    movsd [r15 + CS_X], xmm0
    movsd [r15 + CS_Y], xmm1
    AT_SCALE
    movsd [rsp + 80], xmm0
    movsd [rsp + 88], xmm1
    movsd xmm0, [rsp + 64]
    movsd xmm1, [rsp + 72]
    AT_SCALE
    movsd [rsp + 64], xmm0
    movsd [rsp + 72], xmm1
    movsd xmm0, [rsp + 48]
    movsd xmm1, [rsp + 56]
    AT_SCALE
    movsd xmm2, [rsp + 64]
    movsd xmm3, [rsp + 72]
    movsd xmm4, [rsp + 80]
    movsd xmm5, [rsp + 88]
    mov rdi, [r15 + CS_PATH]
    call ugfx_path_cubic_to
    call cs_err
    add rsp, 104
    ret
