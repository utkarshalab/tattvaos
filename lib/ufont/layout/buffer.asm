; =============================================================================
; Utkarsha OS — lib/ufont/layout/buffer.asm
; =============================================================================
; The shaping buffer: glyph records (GI_*) read from the input side (info,
; at idx) and written to the output side (out) while a lookup runs, then
; swapped (sync). Clusters are merged as glyphs combine (monotone grapheme
; clusters). Every routine takes the shaping state in r15 and keeps rbx,
; rbp, r12 - r15. Both arrays grow together from the arena; when it runs
; out S_ERR is set and writes go to a dummy record, so shaping finishes and
; ufont_shape reports -ENOMEM.
; =============================================================================

%include "ufont.inc"
%include "shape.inc"

extern arena_alloc

section .text

; ----------------------------------------------------------------------------
; buf_ensure — esi = records needed -> eax = 0, or -1 (out of memory)
; ----------------------------------------------------------------------------
global buf_ensure
buf_ensure:
    cmp esi, [r15 + S_CAP]
    jbe .ok
    cmp dword [r15 + S_MAXLEN], 0
    je .grow
    cmp esi, [r15 + S_MAXLEN]
    ja .too_long
.grow:
    push rbx
    push r12
    push r13
    mov ebx, [r15 + S_CAP]
    add ebx, ebx
    cmp ebx, esi
    jae .size
    mov ebx, esi
.size:
    add ebx, 16
    cmp ebx, 0x1000000                  ; 16 M glyphs at most
    ja .fail
    mov rdi, [r15 + S_ARENA]
    mov esi, ebx
    shl rsi, 5
    call arena_alloc
    test rax, rax
    jz .fail
    mov r12, rax
    mov rdi, [r15 + S_ARENA]
    mov esi, ebx
    shl rsi, 5
    call arena_alloc
    test rax, rax
    jz .fail
    mov r13, rax
    mov ecx, [r15 + S_CAP]
    shl rcx, 5
    mov rsi, [r15 + S_INFO]
    mov rdi, r12
    rep movsb
    mov ecx, [r15 + S_CAP]
    shl rcx, 5
    mov rsi, [r15 + S_OUT]
    mov rdi, r13
    rep movsb
    mov [r15 + S_INFO], r12
    mov [r15 + S_OUT], r13
    mov [r15 + S_CAP], ebx
    pop r13
    pop r12
    pop rbx
.ok:
    xor eax, eax
    ret
.too_long:
    mov byte [r15 + S_ERR], 1
    mov eax, -1
    ret
.fail:
    mov byte [r15 + S_ERR], 1
    pop r13
    pop r12
    pop rbx
    mov eax, -1
    ret

; ----------------------------------------------------------------------------
; buf_out_slot -> rdi = the next output record (S_OUTLEN counts it); the
;   dummy record when memory ran out
; ----------------------------------------------------------------------------
global buf_out_slot
buf_out_slot:
    mov esi, [r15 + S_OUTLEN]
    inc esi
    call buf_ensure
    test eax, eax
    jnz .dummy
    mov edi, [r15 + S_OUTLEN]
    inc dword [r15 + S_OUTLEN]
    shl rdi, 5
    add rdi, [r15 + S_OUT]
    ret
.dummy:
    lea rdi, [r15 + S_DUMMY]
    ret

; copy the record at rsi to rdi
%macro COPY_GI 0
    movdqu xmm0, [rsi]
    movdqu xmm1, [rsi + 16]
    movdqu [rdi], xmm0
    movdqu [rdi + 16], xmm1
%endmacro

; ----------------------------------------------------------------------------
; buf_clear_output / buf_sync
; ----------------------------------------------------------------------------
global buf_clear_output
buf_clear_output:
    mov dword [r15 + S_OUTLEN], 0
    mov byte [r15 + S_HAVEOUT], 1
    ret

global buf_sync
buf_sync:
    ; the rest of the input follows the output
    mov eax, [r15 + S_IDX]
.rest:
    cmp eax, [r15 + S_LEN]
    jae .swap
    push rax
    call buf_out_slot
    pop rax
    mov esi, eax
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    COPY_GI
    inc eax
    jmp .rest
.swap:
    mov rax, [r15 + S_INFO]
    mov rcx, [r15 + S_OUT]
    mov [r15 + S_INFO], rcx
    mov [r15 + S_OUT], rax
    mov eax, [r15 + S_OUTLEN]
    mov [r15 + S_LEN], eax
    mov dword [r15 + S_OUTLEN], 0
    mov dword [r15 + S_IDX], 0
    mov byte [r15 + S_HAVEOUT], 0
    ret

; ----------------------------------------------------------------------------
; buf_cur -> rax = &info[idx]
; ----------------------------------------------------------------------------
global buf_cur
buf_cur:
    mov eax, [r15 + S_IDX]
    shl rax, 5
    add rax, [r15 + S_INFO]
    ret

; ----------------------------------------------------------------------------
; buf_next_glyph: the current record to the output (when there is one)
; ----------------------------------------------------------------------------
global buf_next_glyph
buf_next_glyph:
    cmp byte [r15 + S_HAVEOUT], 0
    je .skip
    call buf_out_slot
    mov esi, [r15 + S_IDX]
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    COPY_GI
.skip:
    inc dword [r15 + S_IDX]
    ret

; esi = n
global buf_next_glyphs
buf_next_glyphs:
    push rbx
    mov ebx, esi
.loop:
    test ebx, ebx
    jz .done
    call buf_next_glyph
    dec ebx
    jmp .loop
.done:
    pop rbx
    ret

global buf_skip_glyph
buf_skip_glyph:
    inc dword [r15 + S_IDX]
    ret

; ----------------------------------------------------------------------------
; buf_output_glyph — esi = glyph: a copy of the current record with that glyph
;   to the output -> rdi = it. buf_replace_glyph also consumes the current.
; ----------------------------------------------------------------------------
global buf_output_glyph
buf_output_glyph:
    push rsi
    call buf_out_slot
    pop rdx
    mov esi, [r15 + S_IDX]
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    COPY_GI
    mov [rdi + GI_GLYPH], edx
    ret

global buf_replace_glyph
buf_replace_glyph:
    call buf_output_glyph
    inc dword [r15 + S_IDX]
    ret

; rsi = a record: copied to the output
global buf_output_info
buf_output_info:
    push rsi
    call buf_out_slot
    pop rsi
    COPY_GI
    ret

; ----------------------------------------------------------------------------
; buf_delete_glyph: the current record goes; its cluster joins a neighbour's
; ----------------------------------------------------------------------------
global buf_delete_glyph
buf_delete_glyph:
    mov rdx, [r15 + S_INFO]
    mov eax, [r15 + S_IDX]
    mov ecx, eax
    shl rcx, 5
    mov r8d, [rdx + rcx + GI_CLUSTER]
    lea r9d, [rax + 1]
    cmp r9d, [r15 + S_LEN]
    jae .no_next
    cmp r8d, [rdx + rcx + 32 + GI_CLUSTER]
    je .done                            ; the cluster lives on
.no_next:
    mov r10d, [r15 + S_OUTLEN]
    test r10d, r10d
    jz .forward
    mov r11, [r15 + S_OUT]
    mov rsi, r10
    shl rsi, 5
    mov r9d, [r11 + rsi - 32 + GI_CLUSTER]
    cmp r8d, r9d
    jae .done
    ; merge backward
.back:
    test r10d, r10d
    jz .done
    mov rsi, r10
    shl rsi, 5
    cmp [r11 + rsi - 32 + GI_CLUSTER], r9d
    jne .done
    mov [r11 + rsi - 32 + GI_CLUSTER], r8d
    dec r10d
    jmp .back
.forward:
    lea r9d, [rax + 1]
    cmp r9d, [r15 + S_LEN]
    jae .done
    mov esi, eax
    lea edx, [rax + 2]
    call buf_merge_clusters
.done:
    inc dword [r15 + S_IDX]
    ret

; ----------------------------------------------------------------------------
; buf_next_serial -> eax = a ligature serial (1 .. 255)
; ----------------------------------------------------------------------------
global buf_next_serial
buf_next_serial:
    movzx eax, byte [r15 + S_SERIAL]
    inc al
    jnz .ok
    inc al
.ok:
    mov [r15 + S_SERIAL], al
    ret

; ----------------------------------------------------------------------------
; buf_move_to — esi = output position: the output made exactly that long,
;   taking from or giving back to the input
; ----------------------------------------------------------------------------
global buf_move_to
buf_move_to:
    cmp byte [r15 + S_HAVEOUT], 0
    jne .out
    mov [r15 + S_IDX], esi
    ret
.out:
    push rbx
    push r12
    mov ebx, esi
    mov eax, [r15 + S_OUTLEN]
    cmp ebx, eax
    je .done
    jb .back
    ; forward: input records to the output
    mov r12d, ebx
    sub r12d, eax
.fwd:
    test r12d, r12d
    jz .done
    mov eax, [r15 + S_IDX]
    cmp eax, [r15 + S_LEN]
    jae .done
    call buf_next_glyph_forced
    dec r12d
    jmp .fwd
.back:
    mov r12d, eax
    sub r12d, ebx                       ; count
    mov eax, [r15 + S_IDX]
    cmp eax, r12d
    jae .room
    ; shift the rest of the input forward to make room
    mov esi, [r15 + S_LEN]
    add esi, r12d
    sub esi, eax
    call buf_ensure
    test eax, eax
    jnz .done
    mov ecx, [r15 + S_LEN]
    sub ecx, [r15 + S_IDX]              ; records to move
    mov edx, r12d
    sub edx, [r15 + S_IDX]              ; by
    mov rsi, [r15 + S_INFO]
    mov eax, [r15 + S_LEN]
    shl rax, 5
    add rsi, rax                        ; the end, moving down
    mov eax, edx
    shl rax, 5
    lea rdi, [rsi + rax]
    shl rcx, 5
    sub rsi, 1
    sub rdi, 1
    std
    rep movsb
    cld
    add [r15 + S_LEN], edx
    add [r15 + S_IDX], edx
.room:
    sub [r15 + S_IDX], r12d
    sub [r15 + S_OUTLEN], r12d
    mov esi, [r15 + S_OUTLEN]
    shl rsi, 5
    add rsi, [r15 + S_OUT]
    mov edi, [r15 + S_IDX]
    shl rdi, 5
    add rdi, [r15 + S_INFO]
    mov ecx, r12d
    shl rcx, 5
    rep movsb
.done:
    pop r12
    pop rbx
    ret

; next_glyph with the output on (move_to's copying)
buf_next_glyph_forced:
    call buf_out_slot
    mov esi, [r15 + S_IDX]
    shl rsi, 5
    add rsi, [r15 + S_INFO]
    COPY_GI
    inc dword [r15 + S_IDX]
    ret

; ----------------------------------------------------------------------------
; buf_merge_clusters — esi = start, edx = end (input positions): one cluster,
;   the smallest of theirs, spreading to neighbours sharing theirs
; ----------------------------------------------------------------------------
global buf_merge_clusters
buf_merge_clusters:
    mov eax, edx
    sub eax, esi
    cmp eax, 2
    jl .done
    mov r8, [r15 + S_INFO]
    ; the smallest cluster
    mov ecx, esi
    shl rcx, 5
    mov r9d, [r8 + rcx + GI_CLUSTER]
    lea ecx, [rsi + 1]
.min:
    cmp ecx, edx
    jae .have_min
    mov eax, ecx
    shl rax, 5
    mov eax, [r8 + rax + GI_CLUSTER]
    cmp eax, r9d
    jae .min_next
    mov r9d, eax
.min_next:
    inc ecx
    jmp .min
.have_min:
    ; extend the end
    mov eax, edx
    shl rax, 5
    cmp r9d, [r8 + rax - 32 + GI_CLUSTER]
    je .start
.end_more:
    cmp edx, [r15 + S_LEN]
    jae .start
    mov eax, edx
    shl rax, 5
    mov ecx, [r8 + rax - 32 + GI_CLUSTER]
    cmp ecx, [r8 + rax + GI_CLUSTER]
    jne .start
    inc edx
    jmp .end_more
.start:
    mov eax, esi
    shl rax, 5
    cmp r9d, [r8 + rax + GI_CLUSTER]
    je .out_side
.start_more:
    cmp [r15 + S_IDX], esi
    jae .out_side
    mov eax, esi
    shl rax, 5
    mov ecx, [r8 + rax - 32 + GI_CLUSTER]
    cmp ecx, [r8 + rax + GI_CLUSTER]
    jne .out_side
    dec esi
    jmp .start_more
.out_side:
    ; started where the output ends: continue there
    cmp [r15 + S_IDX], esi
    jne .set
    mov eax, esi
    shl rax, 5
    mov r10d, [r8 + rax + GI_CLUSTER]
    cmp r10d, r9d
    je .set
    xor ecx, ecx
    cmp byte [r15 + S_HAVEOUT], 0
    je .set
    mov ecx, [r15 + S_OUTLEN]
    mov r11, [r15 + S_OUT]
.out_loop:
    test ecx, ecx
    jz .set
    mov eax, ecx
    shl rax, 5
    cmp [r11 + rax - 32 + GI_CLUSTER], r10d
    jne .set
    mov [r11 + rax - 32 + GI_CLUSTER], r9d
    dec ecx
    jmp .out_loop
.set:
    cmp esi, edx
    jae .done
    mov eax, esi
    shl rax, 5
    mov [r8 + rax + GI_CLUSTER], r9d
    inc esi
    jmp .set
.done:
    ret

; ----------------------------------------------------------------------------
; buf_merge_out_clusters — esi = start, edx = end (output positions)
; ----------------------------------------------------------------------------
global buf_merge_out_clusters
buf_merge_out_clusters:
    mov eax, edx
    sub eax, esi
    cmp eax, 2
    jl .done
    mov r8, [r15 + S_OUT]
    mov ecx, esi
    shl rcx, 5
    mov r9d, [r8 + rcx + GI_CLUSTER]
    lea ecx, [rsi + 1]
.min:
    cmp ecx, edx
    jae .have_min
    mov eax, ecx
    shl rax, 5
    mov eax, [r8 + rax + GI_CLUSTER]
    cmp eax, r9d
    jae .min_next
    mov r9d, eax
.min_next:
    inc ecx
    jmp .min
.have_min:
.start_more:
    test esi, esi
    jz .end_more
    mov eax, esi
    shl rax, 5
    mov ecx, [r8 + rax - 32 + GI_CLUSTER]
    cmp ecx, [r8 + rax + GI_CLUSTER]
    jne .end_more
    dec esi
    jmp .start_more
.end_more:
    cmp edx, [r15 + S_OUTLEN]
    jae .in_side
    mov eax, edx
    shl rax, 5
    mov ecx, [r8 + rax - 32 + GI_CLUSTER]
    cmp ecx, [r8 + rax + GI_CLUSTER]
    jne .in_side
    inc edx
    jmp .end_more
.in_side:
    cmp edx, [r15 + S_OUTLEN]
    jne .set
    mov eax, edx
    shl rax, 5
    mov r10d, [r8 + rax - 32 + GI_CLUSTER]
    mov r11, [r15 + S_INFO]
    mov ecx, [r15 + S_IDX]
.in_loop:
    cmp ecx, [r15 + S_LEN]
    jae .set
    mov eax, ecx
    shl rax, 5
    cmp [r11 + rax + GI_CLUSTER], r10d
    jne .set
    mov [r11 + rax + GI_CLUSTER], r9d
    inc ecx
    jmp .in_loop
.set:
    cmp esi, edx
    jae .done
    mov eax, esi
    shl rax, 5
    mov [r8 + rax + GI_CLUSTER], r9d
    inc esi
    jmp .set
.done:
    ret

; ----------------------------------------------------------------------------
; buf_sort — esi = start, edx = end, ecx = offset of a u8 key: input records
;   sorted by it, stably (insertion), clusters merged over what moves
; ----------------------------------------------------------------------------
global buf_sort
buf_sort:
    push rbx
    push r12
    push r13
    push r14
    mov r12d, esi                       ; start
    mov r13d, edx                       ; end
    mov r14d, ecx                       ; key
    lea ebx, [r12 + 1]                  ; i
.outer:
    cmp ebx, r13d
    jae .done
    mov r8, [r15 + S_INFO]
    mov eax, ebx
    shl rax, 5
    add rax, r14
    movzx r9d, byte [r8 + rax]          ; key of i
    mov ecx, ebx                        ; j
.inner:
    cmp ecx, r12d
    jbe .placed
    mov eax, ecx
    shl rax, 5
    add rax, r14
    movzx eax, byte [r8 + rax - 32]
    cmp eax, r9d
    jbe .placed
    dec ecx
    jmp .inner
.placed:
    cmp ecx, ebx
    je .next
    push rcx
    mov esi, ecx
    lea edx, [rbx + 1]
    call buf_merge_clusters
    pop rcx
    mov r8, [r15 + S_INFO]
    ; info[i] to j, the rest up one
    mov eax, ebx
    shl rax, 5
    movdqu xmm2, [r8 + rax]
    movdqu xmm3, [r8 + rax + 16]
    mov edx, ebx
.shift:
    cmp edx, ecx
    jbe .put
    mov eax, edx
    shl rax, 5
    movdqu xmm0, [r8 + rax - 32]
    movdqu xmm1, [r8 + rax - 16]
    movdqu [r8 + rax], xmm0
    movdqu [r8 + rax + 16], xmm1
    dec edx
    jmp .shift
.put:
    mov eax, ecx
    shl rax, 5
    movdqu [r8 + rax], xmm2
    movdqu [r8 + rax + 16], xmm3
.next:
    inc ebx
    jmp .outer
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ----------------------------------------------------------------------------
; buf_move_record — esi = from, edx = to (input positions): the record moves
;   there, those between shift by one (no cluster change)
; ----------------------------------------------------------------------------
global buf_move_record
buf_move_record:
    mov r8, [r15 + S_INFO]
    mov eax, esi
    shl rax, 5
    movdqu xmm2, [r8 + rax]
    movdqu xmm3, [r8 + rax + 16]
    cmp esi, edx
    je .put
    jb .up
.down:                                  ; from > to: the rest move up
    cmp esi, edx
    jbe .put
    mov eax, esi
    shl rax, 5
    movdqu xmm0, [r8 + rax - 32]
    movdqu xmm1, [r8 + rax - 16]
    movdqu [r8 + rax], xmm0
    movdqu [r8 + rax + 16], xmm1
    dec esi
    jmp .down
.up:                                    ; from < to: the rest move down
    cmp esi, edx
    jae .put
    mov eax, esi
    shl rax, 5
    movdqu xmm0, [r8 + rax + 32]
    movdqu xmm1, [r8 + rax + 48]
    movdqu [r8 + rax], xmm0
    movdqu [r8 + rax + 16], xmm1
    inc esi
    jmp .up
.put:
    mov eax, edx
    shl rax, 5
    movdqu [r8 + rax], xmm2
    movdqu [r8 + rax + 16], xmm3
    ret

; ----------------------------------------------------------------------------
; buf_reverse — esi = start, edx = end: input records reversed
; ----------------------------------------------------------------------------
global buf_reverse
buf_reverse:
    mov r8, [r15 + S_INFO]
    dec edx
.loop:
    cmp esi, edx
    jge .done
    mov eax, esi
    shl rax, 5
    mov ecx, edx
    shl rcx, 5
    movdqu xmm0, [r8 + rax]
    movdqu xmm1, [r8 + rax + 16]
    movdqu xmm2, [r8 + rcx]
    movdqu xmm3, [r8 + rcx + 16]
    movdqu [r8 + rax], xmm2
    movdqu [r8 + rax + 16], xmm3
    movdqu [r8 + rcx], xmm0
    movdqu [r8 + rcx + 16], xmm1
    inc esi
    dec edx
    jmp .loop
.done:
    ret
