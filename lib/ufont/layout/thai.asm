; =============================================================================
; Utkarsha OS — lib/ufont/layout/thai.asm
; =============================================================================
; The Thai shaper (Thai and Lao), as HarfBuzz's:
;
;   ufl_thai_preprocess   SARA AM (U+0E33 / U+0EB3) becomes NIKHAHIT + SARA AA,
;                         the nikhahit (a continuing nonspacing mark of class
;                         0) moved back over the above-base marks before it,
;                         clusters merged; then, for Thai when the font's GSUB
;                         has no thai script, marks and descenders shaped to
;                         the PUA glyphs old Thai fonts carry (Windows' code
;                         points, else the Mac's) by the above / below state
;                         machines
;
; GDEF marks' widths zeroed late; no fallback positioning, no kern table.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern ufl_buf_clear_output
extern ufl_buf_sync
extern ufl_buf_cur
extern ufl_buf_next_glyph
extern ufl_buf_output_glyph
extern ufl_buf_replace_glyph
extern ufl_buf_merge_out_clusters
extern ufl_norm_glyph
extern ufl_ucd_scripts

; consonant types
%define NC      0
%define AC      1
%define RC      2
%define DC      3
%define NOTC    4
; mark types
%define AV      0
%define BV      1
%define TM      2
%define NOTM    3
; actions
%define NOP     0
%define SD      1
%define SL      2
%define SDL     3
%define RD      4

section .rodata
; the state machines: [state][mark type] -> action, next state
th_above_start: db 0, 1, 0, 0, 3
th_above:
    db NOP, 3,  NOP, 0,  SD, 3
    db SL, 2,   NOP, 1,  SDL, 2
    db NOP, 3,  NOP, 2,  SL, 3
    db NOP, 3,  NOP, 3,  NOP, 3
th_below_start: db 0, 0, 1, 2, 2
th_below:
    db NOP, 0,  NOP, 2,  NOP, 0
    db NOP, 1,  RD, 2,   NOP, 1
    db NOP, 2,  SD, 2,   NOP, 2
; the character, its Windows PUA, its Mac PUA
th_sd:
    dd 0x0E48, 0xF70A, 0xF88B,  0x0E49, 0xF70B, 0xF88E,  0x0E4A, 0xF70C, 0xF891
    dd 0x0E4B, 0xF70D, 0xF894,  0x0E4C, 0xF70E, 0xF897,  0x0E38, 0xF718, 0xF89B
    dd 0x0E39, 0xF719, 0xF89C,  0x0E3A, 0xF71A, 0xF89D,  0
th_sdl:
    dd 0x0E48, 0xF705, 0xF88C,  0x0E49, 0xF706, 0xF88F,  0x0E4A, 0xF707, 0xF892
    dd 0x0E4B, 0xF708, 0xF895,  0x0E4C, 0xF709, 0xF898,  0
th_sl:
    dd 0x0E48, 0xF713, 0xF88A,  0x0E49, 0xF714, 0xF88D,  0x0E4A, 0xF715, 0xF890
    dd 0x0E4B, 0xF716, 0xF893,  0x0E4C, 0xF717, 0xF896,  0x0E31, 0xF710, 0xF884
    dd 0x0E34, 0xF701, 0xF885,  0x0E35, 0xF702, 0xF886,  0x0E36, 0xF703, 0xF887
    dd 0x0E37, 0xF704, 0xF888,  0x0E47, 0xF712, 0xF889,  0x0E4D, 0xF711, 0xF899,  0
th_rd:
    dd 0x0E0D, 0xF70F, 0xF89A,  0x0E10, 0xF700, 0xF89E,  0
th_tables: dq 0, th_sd, th_sl, th_sdl, th_rd

section .text

; ----------------------------------------------------------------------------
; ufl_thai_preprocess
; ----------------------------------------------------------------------------
global ufl_thai_preprocess
ufl_thai_preprocess:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    call ufl_buf_clear_output
.loop:
    mov eax, [r15 + S_IDX]
    cmp eax, [r15 + S_LEN]
    jae .sync
    call ufl_buf_cur
    mov ebx, [rax + GI_CP]
    mov ecx, ebx
    and ecx, ~0x80
    cmp ecx, 0x0E33
    je .sara_am
    call ufl_buf_next_glyph
    jmp .loop
.sara_am:
    ; NIKHAHIT, then SARA AA in its place (both with SARA AM's properties)
    mov esi, [rax + GI_GLYPH]
    mov ebp, esi
    call ufl_buf_output_glyph
    lea eax, [rbx - 0x0E33 + 0x0E4D]
    mov [rdi + GI_CP], eax
    mov byte [rdi + GI_GC], GC_MN
    mov byte [rdi + GI_MCC], 0
    or byte [rdi + GI_UF], UF_CONT
    mov esi, ebp
    call ufl_buf_replace_glyph
    lea eax, [rbx - 1]
    mov [rdi + GI_CP], eax
    mov r12d, [r15 + S_OUTLEN]          ; end
    cmp r12d, 2
    jb .loop                            ; out of memory
    lea r13d, [r12 - 2]                 ; start
    mov r14, [r15 + S_OUT]
.back:
    test r13d, r13d
    jz .moved
    mov eax, r13d
    shl rax, 5
    mov edi, [r14 + rax - 32 + GI_CP]
    call th_above_base
    test eax, eax
    jz .moved
    dec r13d
    jmp .back
.moved:
    lea eax, [r13 + 2]
    cmp eax, r12d
    jae .no_move
    ; the nikhahit (end - 2) to start
    mov esi, r13d
    mov edx, r12d
    call ufl_buf_merge_out_clusters
    mov r14, [r15 + S_OUT]
    lea eax, [r12 - 2]
    shl rax, 5
    movdqu xmm2, [r14 + rax]
    movdqu xmm3, [r14 + rax + 16]
.shift:
    mov ecx, eax
    shr ecx, 5
    cmp ecx, r13d
    jbe .put
    movdqu xmm0, [r14 + rax - 32]
    movdqu xmm1, [r14 + rax - 16]
    movdqu [r14 + rax], xmm0
    movdqu [r14 + rax + 16], xmm1
    sub rax, 32
    jmp .shift
.put:
    movdqu [r14 + rax], xmm2
    movdqu [r14 + rax + 16], xmm3
    jmp .loop
.no_move:
    ; decomposed, and the nikhahit combines: one cluster with the one before
    test r13d, r13d
    jz .loop
    lea esi, [r13 - 1]
    mov edx, r12d
    call ufl_buf_merge_out_clusters
    jmp .loop
.sync:
    call ufl_buf_sync
    ; Thai without the font's own thai GSUB script: the PUA glyphs
    mov eax, [r15 + S_SCRIPT]
    imul eax, eax, 12
    lea rdx, [rel ufl_ucd_scripts]
    cmp dword [rdx + rax], 'Thai'
    jne .done
    cmp dword [r15 + S_CHOSEN], 'thai'
    je .done
    call th_pua_shaping
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

; edi = code point -> eax 1 for an above-base mark (Thai, or Lao 0x80 on)
th_above_base:
    and edi, ~0x80
    mov eax, 1
    cmp edi, 0x0E31
    je .out
    cmp edi, 0x0E3B
    je .out
    lea ecx, [rdi - 0x0E34]
    cmp ecx, 3
    jbe .out
    lea ecx, [rdi - 0x0E47]
    cmp ecx, 7
    jbe .out
    xor eax, eax
.out:
    ret

; edi = code point -> eax = mark type
th_mark_type:
    mov eax, AV
    cmp edi, 0x0E31
    je .out
    lea ecx, [rdi - 0x0E34]
    cmp ecx, 3
    jbe .out
    cmp edi, 0x0E47
    je .out
    lea ecx, [rdi - 0x0E4D]
    cmp ecx, 1
    jbe .out
    mov eax, BV
    lea ecx, [rdi - 0x0E38]
    cmp ecx, 2
    jbe .out
    mov eax, TM
    lea ecx, [rdi - 0x0E48]
    cmp ecx, 4
    jbe .out
    mov eax, NOTM
.out:
    ret

; edi = code point -> eax = consonant type
th_consonant_type:
    mov eax, AC
    cmp edi, 0x0E1B
    je .out
    cmp edi, 0x0E1D
    je .out
    cmp edi, 0x0E1F
    je .out
    mov eax, RC
    cmp edi, 0x0E0D
    je .out
    cmp edi, 0x0E10
    je .out
    mov eax, DC
    cmp edi, 0x0E0E
    je .out
    cmp edi, 0x0E0F
    je .out
    mov eax, NC
    lea ecx, [rdi - 0x0E01]
    cmp ecx, 0x2D
    jbe .out
    mov eax, NOTC
.out:
    ret

; edi = code point, esi = action -> eax = the code point to use
th_pua_shape:
    push rbx
    push r12
    push r13
    mov eax, edi
    mov r12d, edi
    lea rcx, [rel th_tables]
    mov rbx, [rcx + rsi * 8]
    test rbx, rbx
    jz .out
.find:
    mov ecx, [rbx]
    test ecx, ecx
    jz .keep
    cmp ecx, r12d
    je .found
    add rbx, 12
    jmp .find
.found:
    mov edi, [rbx + 4]
    call ufl_norm_glyph
    mov r13d, [rbx + 4]
    test eax, eax
    jnz .use
    mov edi, [rbx + 8]
    call ufl_norm_glyph
    mov r13d, [rbx + 8]
    test eax, eax
    jnz .use
.keep:
    mov eax, r12d
    jmp .out
.use:
    mov eax, r13d
.out:
    pop r13
    pop r12
    pop rbx
    ret

; the above / below state machines over the buffer
th_pua_shaping:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    mov r12d, 3                         ; above state (not a consonant's)
    mov r13d, 2                         ; below state
    xor r14d, r14d                      ; base
    xor ebx, ebx
.each:
    cmp ebx, [r15 + S_LEN]
    jae .done
    mov rbp, rbx
    shl rbp, 5
    add rbp, [r15 + S_INFO]
    mov edi, [rbp + GI_CP]
    call th_mark_type
    cmp eax, NOTM
    jne .mark
    mov edi, [rbp + GI_CP]
    call th_consonant_type
    lea rcx, [rel th_above_start]
    movzx r12d, byte [rcx + rax]
    lea rcx, [rel th_below_start]
    movzx r13d, byte [rcx + rax]
    mov r14d, ebx
    jmp .next
.mark:
    ; edges: [state * 3 + mark type] * 2
    imul ecx, r12d, 3
    add ecx, eax
    lea rdx, [rel th_above]
    movzx esi, byte [rdx + rcx * 2]
    movzx r12d, byte [rdx + rcx * 2 + 1]
    imul ecx, r13d, 3
    add ecx, eax
    lea rdx, [rel th_below]
    movzx r8d, byte [rdx + rcx * 2]
    movzx r13d, byte [rdx + rcx * 2 + 1]
    test esi, esi
    cmovz esi, r8d
    cmp esi, RD
    jne .on_mark
    mov rbp, r14
    shl rbp, 5
    add rbp, [r15 + S_INFO]
.on_mark:
    mov edi, [rbp + GI_CP]
    call th_pua_shape
    mov [rbp + GI_CP], eax
.next:
    inc ebx
    jmp .each
.done:
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
