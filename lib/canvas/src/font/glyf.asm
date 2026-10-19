; ============================================================================
; glyf — Glyph Outline Extraction (simple + composite, loca-aware)
; Emits verb streams consumed by outline/flatten
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"
%include "inc/canvas_client.inc"

; struct offsets (hoisted above use)

section .text

; GlyfOut struct layout (manual offsets to avoid NASM preprocessor issues)
; Offsets defined in inc/struct_offsets.inc

; ---------------------------------------------------------------------------
; glyf_locate
;   IN: rdi = font*, rsi = glyph id — OUT: rax = glyph data ptr, rdx = len
; ---------------------------------------------------------------------------
global glyf_locate
glyf_locate:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    cmp r12d, [rbx + TtfFont.num_glyphs]
    jae .fail
    mov rax, [rbx + TtfFont.loca]
    mov r14, rax  ; loca base (r14 saved by PROLOGUE_SAVE? add it)
    mov edx, [rbx + TtfFont.loca_format]
    test edx, edx
    jz .short
    ; long: u32 offsets
    mov eax, [r14 + r12 * 4]
    bswap eax
    mov r13d, eax
    mov edx, [r14 + r12 * 4 + 4]
    bswap edx
    sub edx, r13d
    mov rax, [rbx + TtfFont.glyf]
    add rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.short:
    movzx eax, word [r14 + r12 * 2]
    xchg al, ah
    shl eax, 1
    mov r13d, eax
    movzx edx, word [r14 + r12 * 2 + 2]
    xchg dl, dh
    shl edx, 1
    sub edx, r13d
    mov rax, [rbx + TtfFont.glyf]
    add rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    xor rax, rax
    xor rdx, rdx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; glyf_outline
;   IN: rdi = font*, rsi = glyph id, rdx = GlyfOut* (arena-provided bufs)
;   OUT: rax = 0 ok (verbs/coords filled, composite flattened recursively)
; ---------------------------------------------------------------------------
global glyf_outline
glyf_outline:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r13
    mov rdi, rbx
    mov rsi, r12
    call glyf_locate
    test rax, rax
    jz .empty
    test rdx, rdx
    jz .empty
    mov r14, rax  ; glyph data
    mov r15, rdx  ; glyph len
    movsx eax, word [r14]  ; numContours (BE i16)
    xchg al, ah
    movsx eax, ax
    cmp eax, 0
    jl .composite
    test eax, eax
    jz .empty
    ; simple glyph
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, r13
    call glyf_simple
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.composite:
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, r13
    call glyf_composite
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.empty:
    mov qword [r13 + GlyfOut.count], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; glyf_simple — decode contours into verbs/coords
; ---------------------------------------------------------------------------
global glyf_simple
glyf_simple:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi  ; font (unused here)
    mov r12, rsi  ; glyph data
    mov r13, rdx  ; glyph len
    mov r14, rcx  ; GlyfOut
    ; bbox
    mov rdi, r12
    add rdi, 2
    call cmap_be16
    mov [r14 + GlyfOut.x_min], eax
    mov rdi, r12
    add rdi, 4
    call cmap_be16
    mov [r14 + GlyfOut.y_min], eax
    mov rdi, r12
    add rdi, 6
    call cmap_be16
    mov [r14 + GlyfOut.x_max], eax
    mov rdi, r12
    add rdi, 8
    call cmap_be16
    mov [r14 + GlyfOut.y_max], eax
    ; numContours
    mov rdi, r12
    call cmap_be16
    movsx r15d, ax
    ; endPts[contours] at +10
    ; instructionLength at +10+2*n; instructions skipped
    lea rax, [r12 + 10]
    mov ecx, r15d
    shl ecx, 1
    add rax, rcx
    mov rdi, rax
    call cmap_be16  ; instructionLength
    add rax, rdi
    add rax, 2
    ; rax = flags start; rsi = point count from last endPt
    mov rsi, rax
    mov rdi, r12
    add rdi, 10
    mov ecx, r15d
    dec ecx
    movzx ecx, word [rdi + rcx * 2]
    xchg cl, ch
    inc ecx  ; nPoints
    mov rdx, r14
    call outline_decode_points
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; glyf_composite — recurse into component glyphs with transforms
; ---------------------------------------------------------------------------
global glyf_composite
glyf_composite:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi  ; font
    mov r12, rsi  ; component data (after header)
    mov r13, rdx  ; remaining len
    mov r14, rcx  ; GlyfOut
    add r12, 10  ; skip numContours + bbox
    sub r13, 10
.loop:
    cmp r13, 4
    jb .done
    movzx eax, word [r12]  ; flags BE
    xchg al, ah
    mov r15d, eax
    movzx ecx, word [r12 + 2]  ; glyphIndex BE
    xchg cl, ch
    add r12, 4
    sub r13, 4
    ; args
    test r15d, 0x0001  ; ARG_1_AND_2_ARE_WORDS
    jz .args_byte
    cmp r13, 4
    jb .done
    add r12, 4
    sub r13, 4
    jmp .args_done
.args_byte:
    cmp r13, 2
    jb .done
    add r12, 2
    sub r13, 2
.args_done:
    ; transform (ignored scale for v1 rasterizer; offset applied via glyf)
    test r15d, 0x0008  ; WE_HAVE_A_SCALE
    jz .no_scale
    cmp r13, 2
    jb .done
    add r12, 2
    sub r13, 2
    jmp .have_transform
.no_scale:
    test r15d, 0x0040  ; WE_HAVE_AN_X_AND_Y_SCALE
    jz .no_xy
    cmp r13, 4
    jb .done
    add r12, 4
    sub r13, 4
    jmp .have_transform
.no_xy:
    test r15d, 0x0080  ; WE_HAVE_A_TWO_BY_TWO
    jz .have_transform
    cmp r13, 8
    jb .done
    add r12, 8
    sub r13, 8
.have_transform:
    ; recurse (offset args ignored in v1)
    push r12
    push r13
    push r15
    mov rdi, rbx
    mov esi, ecx
    mov rdx, r14
    call glyf_outline
    pop r15
    pop r13
    pop r12
    test r15d, 0x0020  ; MORE_COMPONENTS
    jnz .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global glyf_version
glyf_version: dq 0x010000
