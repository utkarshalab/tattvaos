; ============================================================================
; Scanline — Even-Odd Scanline Fill of Verb Records to Coverage Mask
; Verbs: MOVE/LINE/QEND/CLOSE records (9B); QUAD control consumed by flatten
; IN: verbs must already be flattened (LINE/CLOSE only) — see flatten.asm
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/font.inc"

section .text

; ---------------------------------------------------------------------------
; scanline_fill
;   IN: rdi = verbs, rsi = nrecs, rdx = out mask (w*h bytes),
;       rcx = width, r8 = height
;   Fills even-odd coverage (0/255). Caller clears mask first.
; ---------------------------------------------------------------------------
global scanline_fill
scanline_fill:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r13
    test r12, r12
    jz .done
    ; current point
    xor r8d, r8d   ; cur_x
    xor r9d, r9d   ; cur_y
    xor r10d, r10d ; rec index
.rec_loop:
    cmp r10, r12
    jae .done
    mov rax, r10
    imul rax, 9
    add rax, rbx
    movzx ecx, byte [rax + 0]
    cmp ecx, VERB_CLOSE
    je .rec_next
    cmp ecx, VERB_MOVE
    je .do_move
    cmp ecx, VERB_LINE
    je .do_line
    ; QUAD/QEND should not reach here (flatten first); skip
    jmp .rec_next
.do_move:
    mov r8d, [rax + 1]
    mov r9d, [rax + 5]
    jmp .rec_next
.do_line:
    mov edx, [rax + 1]  ; x1
    mov esi, [rax + 5]  ; y1
    push r8
    push r9
    push r10
    push r12
    push r13
    push r14
    push r15
    push rdx
    push rsi
    mov rdi, r13
    mov r10d, r14d
    mov r11d, r15d
    ; r8d=x0, r9d=y0, edx=x1, esi=y1
    call scanline_edge
    pop rsi
    pop rdx
    pop r15
    pop r14
    pop r13
    pop r12
    pop r10
    pop r9
    pop r8
    mov r8d, edx  ; cur = endpoint
    mov r9d, esi
.rec_next:
    inc r10
    jmp .rec_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; scanline_edge
;   XOR-fill edge (x0,y0)-(x1,y1) into mask
;   IN: rdi=mask, r8d=x0, r9d=y0, edx=x1, esi=y1, r10d=w, r11d=h
; ---------------------------------------------------------------------------
global scanline_edge
scanline_edge:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi   ; mask
    ; horizontal edges do not toggle (even-odd)
    cmp r9d, esi
    je .done
    ; ensure y0 < y1 (swap)
    cmp r9d, esi
    jl .ordered
    xchg r8d, edx
    xchg r9d, esi
.ordered:
    ; clip y to [0, h)
    cmp esi, 0
    jle .done
    cmp r9d, r11d
    jge .done
    mov r12d, r9d
    test r12d, r12d
    jns .y0_ok
    xor r12d, r12d
.y0_ok:
    mov r13d, esi
    cmp r13d, r11d
    jl .y1_ok
    mov r13d, r11d
.y1_ok:
    ; walk y, x = x0 + (y-y0)*dx/dy
    mov r14d, edx
    sub r14d, r8d   ; dx
    mov r15d, esi
    sub r15d, r9d   ; dy (>0)
.y_loop:
    cmp r12d, r13d
    jae .done
    ; x = x0 + (y-y0)*dx/dy
    mov eax, r12d
    sub eax, r9d
    imul eax, r14d
    mov ecx, r15d
    test ecx, ecx
    jz .next_y
    cdq
    idiv ecx
    add eax, r8d
    ; toggle span [x, w)
    cmp eax, 0
    jl .next_y
    cmp eax, r10d
    jge .next_y
    push r12
    push r13
    mov ecx, r12d
    imul ecx, r10d
    add ecx, eax
    add rcx, rbx
.toggle:
    cmp eax, r10d
    jae .span_done
    xor byte [rcx], 255
    inc rcx
    inc eax
    jmp .toggle
.span_done:
    pop r13
    pop r12
.next_y:
    inc r12d
    jmp .y_loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global scanline_version
scanline_version: dq 0x010000
