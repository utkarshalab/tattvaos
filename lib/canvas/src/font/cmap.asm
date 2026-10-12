; ============================================================================
; cmap - Character Map (format 4 + format 12)
; All multi-byte values big-endian; loaded via be16/be32 helpers
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"

section .text

; be16/be32 local helpers (ptr in rdi)
cmap_be16:
    movzx eax, word [rdi]
    xchg al, ah
    ret

cmap_be32:
    mov eax, [rdi]
    bswap eax
    ret

; ---------------------------------------------------------------------------
; cmap_glyph_id
;   IN: rdi = font*, rsi = codepoint - OUT: eax = glyph id (0 = missing)
; ---------------------------------------------------------------------------
global cmap_glyph_id
cmap_glyph_id:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15, r8, r9
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov r13, [rbx + TtfFont.cmap]
    test r13, r13
    jz .missing
    mov rdi, r13
    add rdi, 2
    call cmap_be16
    mov r14d, eax  ; numTables
    lea r13, [r13 + 4]
    xor r8d, r8d   ; fmt4 subtable
    xor r9, r9     ; fmt12 subtable
    xor ecx, ecx
.scan:
    cmp ecx, r14d
    jae .pick
    mov rdi, r13
    call cmap_be16
    mov r15d, eax  ; platform
    mov rdi, r13
    add rdi, 2
    call cmap_be16  ; encoding (ignored except MS table preference)
    mov rdi, r13
    add rdi, 4
    call cmap_be32  ; offset
    mov edx, eax
    cmp r15d, 0
    jne .next_enc
    ; platform 0 (Unicode): accept format 4 or 12 by peeking
    mov rax, [rbx + TtfFont.cmap]
    add rax, rdx
    mov rdi, rax
    call cmap_be16
    cmp eax, 12
    je .is12
    cmp eax, 4
    je .is4
    jmp .next_enc
.is12:
    mov rax, [rbx + TtfFont.cmap]
    add rax, rdx
    mov r9, rax
    jmp .next_enc
.is4:
    test r8d, r8d
    jnz .next_enc
    mov rax, [rbx + TtfFont.cmap]
    add rax, rdx
    mov r8, rax
.next_enc:
    add r13, 8
    inc ecx
    jmp .scan
.pick:
    test r9, r9
    jz .use4
    mov rdi, r9
    mov esi, r12d
    call cmap_format12
    ret
.use4:
    test r8, r8
    jz .missing
    mov rdi, r8
    mov esi, r12d
    call cmap_format4
    ret
.missing:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; cmap_format4
; ---------------------------------------------------------------------------
global cmap_format4
cmap_format4:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    cmp r12d, 0xFFFF
    ja .missing
    mov rdi, rbx
    call cmap_be16
    cmp eax, 4
    jne .missing
    mov rdi, rbx
    add rdi, 6
    call cmap_be16
    shr eax, 1
    mov r13d, eax  ; segCount
    lea r14, [rbx + 14]  ; endCode[]
    xor ecx, ecx
.search:
    cmp ecx, r13d
    jae .missing
    mov rdi, r14
    lea rdi, [r14 + rcx * 2]
    call cmap_be16
    cmp r12d, eax
    jbe .in_seg
    inc ecx
    jmp .search
.in_seg:
    ; startCode = endCode + 2 + segCount*2
    lea rdx, [r14 + r13 * 2 + 2]
    mov rdi, rdx
    lea rdi, [rdx + rcx * 2]
    call cmap_be16
    cmp r12d, eax
    jb .missing
    mov r10d, eax  ; start
    ; idDelta
    lea rdx, [r14 + r13 * 2 + 2 + r13 * 2]
    mov rdi, rdx
    lea rdi, [rdx + rcx * 2]
    call cmap_be16
    movsx r11d, ax  ; delta (signed)
    ; idRangeOffset
    lea rdx, [r14 + r13 * 2 + 2 + r13 * 2 + r13 * 2]
    lea rdx, [rdx + rcx * 2]
    mov rdi, rdx
    call cmap_be16
    test eax, eax
    jz .direct
    ; glyphAddr = &idRangeOffset + rangeOffset + 2*(c - start)
    mov esi, r12d
    sub esi, r10d
    shl esi, 1
    lea rdi, [rdx + rax + rsi]
    call cmap_be16
    test eax, eax
    jz .missing
    add eax, r11d
    and eax, 0xFFFF
    ret
.direct:
    mov eax, r12d
    add eax, r11d
    and eax, 0xFFFF
    ret
.missing:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; cmap_format12
; ---------------------------------------------------------------------------
global cmap_format12
cmap_format12:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov rdi, rbx
    call cmap_be16
    cmp eax, 12
    jne .missing
    mov rdi, rbx
    add rdi, 8
    call cmap_be32  ; nGroups
    mov r13d, eax
    lea rbx, [rbx + 16]
    xor ecx, ecx
.search:
    cmp ecx, r13d
    jae .missing
    mov rdi, rbx
    call cmap_be32  ; startChar
    mov r14d, eax
    mov rdi, rbx
    add rdi, 4
    call cmap_be32  ; endChar
    mov r15d, eax
    cmp r12d, r14d
    jb .next
    cmp r12d, r15d
    ja .next
    mov rdi, rbx
    add rdi, 8
    call cmap_be32  ; startGlyph
    sub r12d, r14d
    add eax, r12d
    ret
.next:
    add rbx, 12
    inc ecx
    jmp .search
.missing:
    xor eax, eax
    ret

section .data
global cmap_version
cmap_version: dq 0x010000
