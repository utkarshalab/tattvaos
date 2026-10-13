; ============================================================================
; Outline - TrueType Point Decoding to Verb Streams
; Coords scratch layout: [nPoints u32][pad u32][flags nB][xs n*4][ys n*4]
; Verb records: (verb u8, x i32, y i32) = 9 bytes each in verbs buffer
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"

section .text

; ---------------------------------------------------------------------------
; outline_decode_points
;   IN: rdi = flags src, rsi = nPoints, rdx = GlyfOut*
;   Expands flags (repeat-aware), decodes delta X/Y, writes scratch header
; ---------------------------------------------------------------------------
global outline_decode_points
outline_decode_points:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi  ; src
    mov r12d, esi ; n
    mov r13, rdx  ; out
    ASSERT_PTR rbx
    ASSERT_PTR r13
    test r12d, r12d
    jz .done
    mov rax, [r13 + GlyfOut.coords]
    test rax, rax
    jz .fail
    mov r14, rax
    mov [r14 + 0], r12d  ; header: nPoints
    lea r15, [r14 + 8]   ; flags dest
    ; pass 1: expand flags, count source bytes
    xor ecx, ecx  ; dest count
    xor edx, edx  ; src used
.expand:
    cmp ecx, r12d
    jae .expand_done
    movzx eax, byte [rbx + rdx]
    inc edx
    mov [r15 + rcx], al
    inc ecx
    test al, GLYPH_REPEAT
    jz .expand
    movzx eax, byte [rbx + rdx]
    inc edx
    mov r8d, eax
    movzx eax, byte [r15 + rcx - 1]
.rep:
    test r8d, r8d
    jz .expand
    cmp ecx, r12d
    jae .expand_done
    mov [r15 + rcx], al
    inc ecx
    dec r8d
    jmp .rep
.expand_done:
    ; rdx = flag bytes consumed; xs dest = flags + n
    lea r8, [r15 + r12]       ; xs dest (caller sized)
    lea r9, [rbx + rdx]       ; x src
    xor ecx, ecx              ; i
    xor r10d, r10d            ; acc
.x_loop:
    cmp ecx, r12d
    jae .x_done
    movzx eax, byte [r15 + rcx]
    test al, GLYPH_X_SHORT
    jz .x_long
    movzx edx, byte [r9]
    inc r9
    test al, GLYPH_X_SAME
    jz .x_neg
    add r10d, edx
    jmp .x_store
.x_neg:
    sub r10d, edx
    jmp .x_store
.x_long:
    test al, GLYPH_X_SAME
    jnz .x_zero
    movzx edx, word [r9]
    xchg dl, dh
    movsx edx, dx
    add r9, 2
    add r10d, edx
    jmp .x_store
.x_zero:
    ; delta 0
.x_store:
    mov [r8 + rcx * 4], r10d
    inc ecx
    jmp .x_loop
.x_done:
    ; ys dest = xs + n*4
    mov rax, r12
    shl rax, 2
    lea r8, [r8 + rax]
    xor ecx, ecx
    xor r10d, r10d
.y_loop:
    cmp ecx, r12d
    jae .y_done
    movzx eax, byte [r15 + rcx]
    test al, GLYPH_Y_SHORT
    jz .y_long
    movzx edx, byte [r9]
    inc r9
    test al, GLYPH_Y_SAME
    jz .y_neg
    add r10d, edx
    jmp .y_store
.y_neg:
    sub r10d, edx
    jmp .y_store
.y_long:
    test al, GLYPH_Y_SAME
    jnz .y_zero
    movzx edx, word [r9]
    xchg dl, dh
    movsx edx, dx
    add r9, 2
    add r10d, edx
    jmp .y_store
.y_zero:
.y_store:
    mov [r8 + rcx * 4], r10d
    inc ecx
    jmp .y_loop
.y_done:
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; outline_flag / outline_x / outline_y helpers
;   IN: rdi = GlyfOut*, rsi = index — OUT: eax = value
; ---------------------------------------------------------------------------
global outline_flag
outline_flag:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    mov rax, [rbx + GlyfOut.coords]
    movzx eax, byte [rax + 8 + rsi]
    EPILOGUE_RESTORE rbx
    ret

global outline_x
outline_x:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    mov rax, [rbx + GlyfOut.coords]
    mov ecx, [rax + 0]  ; n
    lea rax, [rax + 8 + rcx]
    mov eax, [rax + r12 * 4]
    EPILOGUE_RESTORE rbx, r12
    ret

global outline_y
outline_y:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    mov rax, [rbx + GlyfOut.coords]
    mov ecx, [rax + 0]
    lea rax, [rax + 8 + rcx + rcx * 4]
    mov eax, [rax + r12 * 4]
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; outline_emit_verb
;   IN: rdi=GlyfOut*, rsi=verb, rdx=x, rcx=y
; ---------------------------------------------------------------------------
global outline_emit_verb
outline_emit_verb:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov rax, [rbx + GlyfOut.count]
    cmp rax, [rbx + GlyfOut.cap]
    jae .full
    mov r12, [rbx + GlyfOut.verbs]
    test r12, r12
    jz .fail
    imul rax, 9
    add r12, rax
    mov [r12 + 0], sil
    mov [r12 + 1], edx
    mov [r12 + 5], ecx
    inc qword [rbx + GlyfOut.count]
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; outline_set_contours
;   IN: rdi = GlyfOut*, rsi = endPts BE u16 ptr, rdx = nContours
; ---------------------------------------------------------------------------
global outline_set_contours
outline_set_contours:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor r14d, r14d  ; contour
    xor r15d, r15d  ; start
.contour:
    cmp r14d, r13d
    jae .done
    mov rdi, r12
    movzx eax, word [r12 + r14 * 2]
    xchg al, ah
    mov r8d, eax
    inc r8d
    sub r8d, r15d  ; count
    mov rdi, rbx
    mov rsi, r15
    mov rdx, r8
    call outline_emit_contour
    test rax, rax
    jnz .fail
    movzx eax, word [r12 + r14 * 2]
    xchg al, ah
    inc eax
    mov r15d, eax
    inc r14d
    jmp .contour
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; outline_emit_contour
;   IN: rdi=GlyfOut*, rsi=start index, rdx=count
; ---------------------------------------------------------------------------
global outline_emit_contour
outline_emit_contour:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi   ; start
    mov r13, rdx   ; count
    ASSERT_PTR rbx
    test r13, r13
    jz .empty
    mov rax, r12
    add rax, r13
    dec rax
    mov r14, rax   ; last index
    ; starting point selection
    mov rdi, rbx
    mov rsi, r12
    call outline_flag
    test al, GLYPH_ON_CURVE
    jnz .start_first
    mov rdi, rbx
    mov rsi, r14
    call outline_flag
    test al, GLYPH_ON_CURVE
    jnz .start_last
    ; both off-curve: MOVE to midpoint(first,last), pending = first
    mov rdi, rbx
    mov rsi, r12
    call outline_x
    mov r10d, eax
    mov rdi, rbx
    mov rsi, r12
    call outline_y
    mov r11d, eax
    mov rdi, rbx
    mov rsi, r14
    call outline_x
    add r10d, eax
    sar r10d, 1
    mov rdi, rbx
    mov rsi, r14
    call outline_y
    add r11d, eax
    sar r11d, 1
    mov rdi, rbx
    mov rsi, VERB_MOVE
    mov rdx, r10
    mov rcx, r11
    call outline_emit_verb
    sub rsp, 48
    mov [rsp + 8], r12   ; contour start
    mov rax, r12
    add rax, r13
    mov [rsp + 32], rax  ; end (exclusive)
    mov [rsp + 20], r10d ; move x
    mov [rsp + 24], r11d ; move y
    mov [rsp + 0], r12   ; current = first
    mov [rsp + 16], r12  ; pending idx = first
    mov byte [rsp + 12], 1
    mov rax, r12
    inc rax
    mov [rsp + 40], rax  ; next
    jmp .walk
.start_first:
    mov rdi, rbx
    mov rsi, r12
    call outline_x
    mov r10d, eax
    mov rdi, rbx
    mov rsi, r12
    call outline_y
    mov r11d, eax
    mov rdi, rbx
    mov rsi, VERB_MOVE
    mov rdx, r10
    mov rcx, r11
    call outline_emit_verb
    sub rsp, 48
    mov [rsp + 8], r12
    mov rax, r12
    add rax, r13
    mov [rsp + 32], rax
    mov [rsp + 20], r10d
    mov [rsp + 24], r11d
    mov [rsp + 0], r12
    mov byte [rsp + 12], 0
    mov rax, r12
    inc rax
    mov [rsp + 40], rax
    jmp .walk
.start_last:
    mov rdi, rbx
    mov rsi, r14
    call outline_x
    mov r10d, eax
    mov rdi, rbx
    mov rsi, r14
    call outline_y
    mov r11d, eax
    mov rdi, rbx
    mov rsi, VERB_MOVE
    mov rdx, r10
    mov rcx, r11
    call outline_emit_verb
    sub rsp, 48
    mov [rsp + 8], r12
    mov rax, r12
    add rax, r13
    mov [rsp + 32], rax
    mov [rsp + 20], r10d
    mov [rsp + 24], r11d
    mov [rsp + 0], r14
    mov byte [rsp + 12], 0
    mov [rsp + 40], r12
    jmp .walk
.walk:
    ; idx = next >= end ? start : next
    mov rax, [rsp + 40]
    cmp rax, [rsp + 32]
    jb .no_wrap
    mov rax, [rsp + 8]
.no_wrap:
    cmp rax, [rsp + 0]
    je .close
    mov [rsp + 40], rax
    inc qword [rsp + 40]
    mov r15, rax
    mov rdi, rbx
    mov rsi, r15
    call outline_flag
    test al, GLYPH_ON_CURVE
    jz .off_pt
    ; on-curve P=r15
    cmp byte [rsp + 12], 0
    je .line_to
    ; QUAD(pending, P)
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_x
    mov r10d, eax
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_y
    mov r11d, eax
    mov rdi, rbx
    mov rsi, r15
    call outline_x
    mov r12d, eax
    mov rdi, rbx
    mov rsi, r15
    call outline_y
    mov r13d, eax
    mov rdi, rbx
    mov rsi, r10
    mov rdx, r11
    mov rcx, r12
    mov r8, r13
    call outline_emit_quad
    mov byte [rsp + 12], 0
    mov [rsp + 0], r15
    jmp .walk
.line_to:
    mov rdi, rbx
    mov rsi, r15
    call outline_x
    mov r10d, eax
    mov rdi, rbx
    mov rsi, r15
    call outline_y
    mov rdi, rbx
    mov rsi, VERB_LINE
    movsxd rdx, r10d
    movsxd rcx, eax
    call outline_emit_verb
    mov [rsp + 0], r15
    jmp .walk
.off_pt:
    mov rdi, rbx
    mov rsi, r15
    call outline_x
    mov r10d, eax
    mov rdi, rbx
    mov rsi, r15
    call outline_y
    mov r11d, eax
    cmp byte [rsp + 12], 0
    je .hold
    ; QUAD(pending, midpoint(pending,Q))
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_x
    add r10d, eax
    sar r10d, 1
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_y
    add r11d, eax
    sar r11d, 1
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_x
    mov r12d, eax
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_y
    mov r13d, eax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r10
    mov r8, r11
    call outline_emit_quad
.hold:
    mov [rsp + 16], r15
    mov byte [rsp + 12], 1
    jmp .walk
.close:
    cmp byte [rsp + 12], 0
    je .emit_close
    ; QUAD(pending, move_pt)
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_x
    mov r10d, eax
    mov rdi, rbx
    mov rax, [rsp + 16]
    mov rsi, rax
    call outline_y
    mov r11d, eax
    mov rdi, rbx
    mov rsi, VERB_QUAD
    movsxd rdx, r10d
    movsxd rcx, eax
    call outline_emit_verb
    mov rdi, rbx
    mov rsi, VERB_QEND
    movsxd rdx, dword [rsp + 20]
    movsxd rcx, dword [rsp + 24]
    call outline_emit_verb
.emit_close:
    mov rdi, rbx
    mov rsi, VERB_CLOSE
    xor edx, edx
    xor ecx, ecx
    call outline_emit_verb
.done:
    add rsp, 48
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; outline_emit_quad
;   IN: rdi=GlyfOut*, rsi=cx, rdx=cy, rcx=ex, r8=ey
;   Emits QUAD(cx,cy) + QEND(ex,ey)
; ---------------------------------------------------------------------------
global outline_emit_quad
outline_emit_quad:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    mov rdi, rbx
    mov rsi, VERB_QUAD
    mov rdx, r12
    mov rcx, r13
    call outline_emit_verb
    test rax, rax
    jnz .fail
    mov rdi, rbx
    mov rsi, VERB_QEND
    mov rdx, r14
    mov rcx, r15
    call outline_emit_verb
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global outline_version
outline_version: dq 0x010000
