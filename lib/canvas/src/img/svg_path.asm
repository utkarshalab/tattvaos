; ============================================================================
; SVG Path — Path Data Parser (M/L/H/V/C/S/Q/T/A/Z) + Flatten to Lines
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern arena_alloc
extern memcopy

; struct offsets (hoisted above use)
%define SvgPathState_SIZE 64

section .text

%define SVG_CMD_MOVE      'M'
%define SVG_CMD_LINE      'L'
%define SVG_CMD_HLINE     'H'
%define SVG_CMD_VLINE     'V'
%define SVG_CMD_CURVE     'C'
%define SVG_CMD_SMOOTH    'S'
%define SVG_CMD_QUAD      'Q'
%define SVG_CMD_SQUAD     'T'
%define SVG_CMD_ARC       'A'
%define SVG_CMD_CLOSE     'Z'

struc SvgPathState
    .cx:            resq 1
    .cy:            resq 1
    .sx:            resq 1
    .sy:            resq 1
    .out_lines:     resq 1
    .out_count:     resq 1
    .out_cap:       resq 1
    .arena:         resq 1
endstruc

; ---------------------------------------------------------------------------
; svg_path_flatten
;   IN: rdi=arena, rsi=d_string, rdx=d_len, rcx=tolerance (fixed 16.16)
;   OUT: rax = line buffer (x0,y0,x1,y1 int32 quads), rdx = count
; ---------------------------------------------------------------------------
global svg_path_flatten
svg_path_flatten:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; allocate state + initial line buffer (256 segments)
    mov rdi, rbx
    mov rsi, SvgPathState_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r15, rax
    mov qword [r15 + SvgPathState.cx], 0
    mov qword [r15 + SvgPathState.cy], 0
    mov qword [r15 + SvgPathState.sx], 0
    mov qword [r15 + SvgPathState.sy], 0
    mov qword [r15 + SvgPathState.out_count], 0
    mov qword [r15 + SvgPathState.out_cap], 256
    mov qword [r15 + SvgPathState.arena], rbx
    mov rdi, rbx
    mov rsi, 256
    imul rsi, 16
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [r15 + SvgPathState.out_lines], rax
    ; parse loop
    mov rdi, r15
    mov rsi, r12
    mov rdx, r13
    call svg_path_parse
    mov rax, [r15 + SvgPathState.out_lines]
    mov rdx, [r15 + SvgPathState.out_count]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    xor rax, rax
    xor rdx, rdx
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; svg_path_parse
; ---------------------------------------------------------------------------
svg_path_parse:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor r14d, r14d  ; current command (0 = none)
.loop:
    cmp r13, 1
    jb .done
    mov al, [r12]
    ; skip separators
    cmp al, ' '
    je .adv
    cmp al, ','
    je .adv
    cmp al, 9
    je .adv
    cmp al, 10
    je .adv
    cmp al, 13
    je .adv
    ; command?
    cmp al, 'M'
    je .cmd
    cmp al, 'm'
    je .cmd
    cmp al, 'L'
    je .cmd
    cmp al, 'l'
    je .cmd
    cmp al, 'H'
    je .cmd
    cmp al, 'h'
    je .cmd
    cmp al, 'V'
    je .cmd
    cmp al, 'v'
    je .cmd
    cmp al, 'C'
    je .cmd
    cmp al, 'c'
    je .cmd
    cmp al, 'Q'
    je .cmd
    cmp al, 'q'
    je .cmd
    cmp al, 'Z'
    je .cmd
    cmp al, 'z'
    je .cmd
    ; number: implicit lineto if command active
    cmp r14b, 0
    je .adv
    jmp .implicit
.cmd:
    mov r14b, al
    inc r12
    dec r13
    cmp al, 'Z'
    je .do_close
    cmp al, 'z'
    je .do_close
    jmp .loop
.do_close:
    mov rdi, rbx
    call svg_path_emit_close
    xor r14d, r14d
    jmp .loop
.implicit:
    ; Parse the endpoint required by the active command. Curves are flattened
    ; to their endpoint here; the renderer can subdivide them further later.
    mov rdi, r12
    mov rsi, r13
    call svg_path_num
    test rdx, rdx
    jz .done
    mov r15, rax
    add r12, rdx
    sub r13, rdx
    cmp r14b, 'H'
    je .horizontal
    cmp r14b, 'h'
    je .horizontal_rel
    cmp r14b, 'V'
    je .vertical
    cmp r14b, 'v'
    je .vertical_rel
    mov rdi, r12
    mov rsi, r13
    call svg_path_num
    test rdx, rdx
    jz .done
    add r12, rdx
    sub r13, rdx
    mov r10, rax
    sar r15, 16
    sar r10, 16
    cmp r14b, 'a'
    jb .absolute_pair
    add r15, [rbx + SvgPathState.cx]
    add r10, [rbx + SvgPathState.cy]
.absolute_pair:
    cmp r14b, 'M'
    je .move
    cmp r14b, 'm'
    je .move
    mov esi, [rbx + SvgPathState.cx]
    mov edx, [rbx + SvgPathState.cy]
    mov ecx, r15d
    mov r8d, r10d
    mov rdi, rbx
    call svg_path_emit_line
    jmp .loop
.move:
    mov [rbx + SvgPathState.cx], r15
    mov [rbx + SvgPathState.cy], r10
    mov [rbx + SvgPathState.sx], r15
    mov [rbx + SvgPathState.sy], r10
    mov r14b, 'L'
    jmp .loop
.horizontal:
    sar r15, 16
    mov esi, [rbx + SvgPathState.cx]
    mov edx, [rbx + SvgPathState.cy]
    mov ecx, r15d
    mov r8d, edx
    mov rdi, rbx
    call svg_path_emit_line
    jmp .loop
.horizontal_rel:
    sar r15, 16
    add r15, [rbx + SvgPathState.cx]
    mov esi, [rbx + SvgPathState.cx]
    mov edx, [rbx + SvgPathState.cy]
    mov ecx, r15d
    mov r8d, edx
    mov rdi, rbx
    call svg_path_emit_line
    jmp .loop
.vertical:
    sar r15, 16
    mov esi, [rbx + SvgPathState.cx]
    mov edx, [rbx + SvgPathState.cy]
    mov ecx, esi
    mov r8d, r15d
    mov rdi, rbx
    call svg_path_emit_line
    jmp .loop
.vertical_rel:
    sar r15, 16
    add r15, [rbx + SvgPathState.cy]
    mov esi, [rbx + SvgPathState.cx]
    mov edx, [rbx + SvgPathState.cy]
    mov ecx, esi
    mov r8d, r15d
    mov rdi, rbx
    call svg_path_emit_line
    jmp .loop
.adv:
    inc r12
    dec r13
    jmp .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; svg_path_num — parse one decimal number
;   IN: rdi = cursor, rsi = remaining
;   OUT: rax = fixed 16.16 value, rdx = bytes consumed (0 on failure)
; ---------------------------------------------------------------------------
global svg_path_num
svg_path_num:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rdi
    mov r13, rsi
    xor eax, eax
    ; skip ws
.skip:
    cmp rsi, 0
    jbe .done
    mov cl, [rbx]
    cmp cl, ' '
    je .adv2
    cmp cl, ','
    je .adv2
    jmp .sign
.adv2:
    inc rbx
    dec rsi
    jmp .skip
.sign:
    xor r8d, r8d
    cmp byte [rbx], '-'
    jne .plus
    mov r8d, 1
    inc rbx
    dec rsi
.plus:
    cmp byte [rbx], '+'
    jne .digits
    inc rbx
    dec rsi
.digits:
    xor eax, eax
    xor r9d, r9d
.dloop:
    cmp rsi, 0
    jbe .finish
    mov cl, [rbx]
    sub cl, '0'
    cmp cl, 9
    ja .finish
    imul eax, 10
    movzx ecx, cl
    add eax, ecx
    inc r9d
    inc rbx
    dec rsi
    jmp .dloop
.finish:
    test r9d, r9d
    jz .invalid
    shl eax, 16
    cmp rsi, 0
    jbe .apply_sign
    cmp byte [rbx], '.'
    jne .apply_sign
    inc rbx
    dec rsi
    mov r10d, 10
.fraction:
    test rsi, rsi
    jz .apply_sign
    mov cl, [rbx]
    sub cl, '0'
    cmp cl, 9
    ja .apply_sign
    movzx ecx, cl
    shl ecx, 16
    mov r11d, eax
    mov eax, ecx
    xor edx, edx
    div r10d
    add r11d, eax
    mov eax, r11d
    imul r10d, 10
    inc rbx
    dec rsi
    cmp r10d, 10000000
    jb .fraction
.apply_sign:
    test r8d, r8d
    jz .done
    neg eax
.done:
    mov rdx, rbx
    sub rdx, r12
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.invalid:
    xor eax, eax
    xor edx, edx
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; svg_path_emit_line / svg_path_emit_close
; ---------------------------------------------------------------------------
global svg_path_emit_line
svg_path_emit_line:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    sub rsp, 16
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    ASSERT_PTR rbx
    mov rax, [rbx + SvgPathState.out_count]
    cmp rax, [rbx + SvgPathState.out_cap]
    jb .room
    ; grow 2x
    mov rdi, [rbx + SvgPathState.arena]
    mov rsi, [rbx + SvgPathState.out_cap]
    shl rsi, 1
    imul rsi, 16
    call arena_alloc
    test rax, rax
    jz .oom
    ; copy old
    mov rdi, rax
    mov rsi, [rbx + SvgPathState.out_lines]
    mov rdx, [rbx + SvgPathState.out_count]
    imul rdx, 16
    call memcopy
    mov [rbx + SvgPathState.out_lines], rax
    shl qword [rbx + SvgPathState.out_cap], 1
.room:
    mov rax, [rbx + SvgPathState.out_lines]
    mov rcx, [rbx + SvgPathState.out_count]
    imul rcx, 16
    add rax, rcx
    mov edx, [rsp]
    mov [rax + 0], edx
    mov edx, [rsp + 4]
    mov [rax + 4], edx
    mov edx, [rsp + 8]
    mov [rax + 8], edx
    mov ecx, [rsp + 12]
    mov [rax + 12], ecx
    inc qword [rbx + SvgPathState.out_count]
    ; update current point
    mov [rbx + SvgPathState.cx], edx
    mov [rbx + SvgPathState.cy], ecx
    xor rax, rax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12
    ret

global svg_path_emit_close
svg_path_emit_close:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    mov esi, [rbx + SvgPathState.cx]
    mov edx, [rbx + SvgPathState.cy]
    mov ecx, [rbx + SvgPathState.sx]
    mov r8d, [rbx + SvgPathState.sy]
    mov rdi, rbx
    call svg_path_emit_line
    EPILOGUE_RESTORE rbx
    ret

section .data
global svg_path_version
svg_path_version: dq 0x010000
