; =============================================================================
; Utkarsha OS — lib/ugfx/2d/svg_syntax.asm
; =============================================================================
; The small grammars inside SVG attributes, for 2d/svg.asm:
;
;   ugfx_svg_number(p, end)        -> xmm0, rax = after it (0 = none)
;   ugfx_svg_colour(p, end)        -> eax = kind, edx = straight BGRA
;   ugfx_svg_transform(p, end, m)  m = m x each transform in the list
;   ugfx_svg_path_data(p, end, path)   SVG path data (all commands)
;   ugfx_svg_points(p, end, path, close)   polyline / polygon points
;
; Numbers: [ws ,]* [+-] digits [. digits] [(e|E) [+-] digits]; up to 18
; significant digits make an integer that one multiply or divide by an
; exact power of ten turns into the double (correctly rounded while the
; integer stays below 2^53 and the power within 10^22).
; Colours: none, currentColor, inherit, #rgb, #rgba, #rrggbb, #rrggbbaa,
; rgb() / rgba() (numbers or percentages), the CSS basic colour keywords
; (any case), url(...) with an optional fallback colour (else none).
; Transforms: matrix, translate, scale, rotate (degrees, optional centre),
; skewX, skewY; an invalid list leaves m unchanged.
; Path data: M L H V C S Q T A Z in both cases, implicit repeats, S / T
; reflection, arcs through umath_arc_svg_to_cubics; drawing stops at the
; first error, keeping what came before (SVG error handling).
; =============================================================================

%include "ugfx.inc"

extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_quad_to
extern ugfx_path_cubic_to
extern ugfx_path_close
extern umath_affine2_multiply
extern umath_affine2_rotate
extern umath_arc_svg_to_cubics
extern umath_tan_f64

%define SVG_KIND_NONE       0
%define SVG_KIND_COLOUR     1
%define SVG_KIND_CURRENT    2
%define SVG_KIND_INHERIT    3
%define SVG_KIND_INVALID    -1

section .rodata
align 8
syn_pow10:
    dq 1e0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10, 1e11
    dq 1e12, 1e13, 1e14, 1e15, 1e16, 1e17, 1e18, 1e19, 1e20, 1e21, 1e22
syn_deg:            dq 0x3F91DF46A2529D39   ; pi / 180
syn_hundredth:      dq 0.01
syn_255:            dq 255.0
syn_half:           dq 0.5
syn_one:            dq 1.0
syn_two:            dq 2.0
align 16
syn_sign_mask:      dq 0x8000000000000000, 0

; colour keywords: length, name, 0xRRGGBB
%macro KEYWORD 2
    db %strlen(%1), %1
    dd %2
%endmacro
syn_keywords:
    KEYWORD "black",   0x000000
    KEYWORD "white",   0xFFFFFF
    KEYWORD "red",     0xFF0000
    KEYWORD "lime",    0x00FF00
    KEYWORD "green",   0x008000
    KEYWORD "blue",    0x0000FF
    KEYWORD "yellow",  0xFFFF00
    KEYWORD "cyan",    0x00FFFF
    KEYWORD "aqua",    0x00FFFF
    KEYWORD "magenta", 0xFF00FF
    KEYWORD "fuchsia", 0xFF00FF
    KEYWORD "gray",    0x808080
    KEYWORD "grey",    0x808080
    KEYWORD "silver",  0xC0C0C0
    KEYWORD "maroon",  0x800000
    KEYWORD "olive",   0x808000
    KEYWORD "navy",    0x000080
    KEYWORD "purple",  0x800080
    KEYWORD "teal",    0x008080
    KEYWORD "orange",  0xFFA500
    db 0

section .text

; rdi = p, rsi = end -> rdi past [ws ,]*
syn_skip:
    cmp rdi, rsi
    jae .done
    movzx eax, byte [rdi]
    cmp al, ' '
    je .next
    cmp al, ','
    je .next
    cmp al, 9
    je .next
    cmp al, 10
    je .next
    cmp al, 13
    je .next
.done:
    ret
.next:
    inc rdi
    jmp syn_skip

; rdi = p, rsi = end -> rdi past whitespace only
syn_skip_ws:
    cmp rdi, rsi
    jae .done
    movzx eax, byte [rdi]
    cmp al, ' '
    je .next
    cmp al, 9
    je .next
    cmp al, 10
    je .next
    cmp al, 13
    je .next
.done:
    ret
.next:
    inc rdi
    jmp syn_skip_ws

; -----------------------------------------------------------------------------
; ugfx_svg_number — rdi = p, rsi = end -> xmm0 = value, rax = the byte after
;   it (0 if there is no number; xmm0 = 0). Leading whitespace and commas
;   are skipped.
; -----------------------------------------------------------------------------
global ugfx_svg_number
ugfx_svg_number:
    push rbx
    push r12
    call syn_skip
    xor r8d, r8d                        ; mantissa
    xor r9d, r9d                        ; significant digits
    xor r10d, r10d                      ; decimal exponent
    xor r11d, r11d                      ; digits seen
    xor ebx, ebx                        ; negative
    cmp rdi, rsi
    jae .none
    movzx eax, byte [rdi]
    cmp al, '-'
    jne .plus
    mov ebx, 1
    inc rdi
    jmp .int
.plus:
    cmp al, '+'
    jne .int
    inc rdi
.int:
    cmp rdi, rsi
    jae .ended
    movzx eax, byte [rdi]
    sub eax, '0'
    cmp eax, 9
    ja .dot
    inc rdi
    inc r11d
    call .digit
    jmp .int
.dot:
    cmp byte [rdi], '.'
    jne .ended
    lea rcx, [rdi + 1]
.frac:
    cmp rcx, rsi
    jae .frac_end
    movzx eax, byte [rcx]
    sub eax, '0'
    cmp eax, 9
    ja .frac_end
    inc rcx
    inc r11d
    cmp r9d, 18
    jae .frac
    test r8, r8
    jnz .frac_digit
    test eax, eax
    jz .frac_zero                       ; leading zeros: exponent only
.frac_digit:
    imul r8, r8, 10
    add r8, rax
    inc r9d
.frac_zero:
    dec r10d
    jmp .frac
.frac_end:
    mov rdi, rcx
.ended:
    test r11d, r11d
    jz .none
    ; exponent: e / E, then an optional sign and at least one digit
    cmp rdi, rsi
    jae .value
    movzx eax, byte [rdi]
    or al, 0x20
    cmp al, 'e'
    jne .value
    lea rcx, [rdi + 1]
    xor r12d, r12d                      ; exponent negative
    cmp rcx, rsi
    jae .value
    movzx eax, byte [rcx]
    cmp al, '-'
    jne .exp_plus
    mov r12d, 1
    inc rcx
    jmp .exp_first
.exp_plus:
    cmp al, '+'
    jne .exp_first
    inc rcx
.exp_first:
    cmp rcx, rsi
    jae .value
    movzx eax, byte [rcx]
    sub eax, '0'
    cmp eax, 9
    ja .value                           ; "1em": no exponent
    xor edx, edx
.exp_digit:
    cmp rcx, rsi
    jae .exp_done
    movzx eax, byte [rcx]
    sub eax, '0'
    cmp eax, 9
    ja .exp_done
    inc rcx
    cmp edx, 10000
    jae .exp_digit
    imul edx, edx, 10
    add edx, eax
    jmp .exp_digit
.exp_done:
    mov rdi, rcx
    test r12d, r12d
    jz .exp_add
    neg edx
.exp_add:
    add r10d, edx
.value:
    cvtsi2sd xmm0, r8
    ; clamp the exponent to +-400, then scale by powers of ten
    cmp r10d, 400
    jle .clamp_low
    mov r10d, 400
.clamp_low:
    cmp r10d, -400
    jge .scale
    mov r10d, -400
.scale:
    lea rdx, [rel syn_pow10]
    test r10d, r10d
    js .divide
.mul_big:
    cmp r10d, 22
    jle .mul_last
    mulsd xmm0, [rdx + 22 * 8]
    sub r10d, 22
    jmp .mul_big
.mul_last:
    mulsd xmm0, [rdx + r10 * 8]
    jmp .sign
.divide:
    neg r10d
.div_big:
    cmp r10d, 22
    jle .div_last
    divsd xmm0, [rdx + 22 * 8]
    sub r10d, 22
    jmp .div_big
.div_last:
    divsd xmm0, [rdx + r10 * 8]
.sign:
    test ebx, ebx
    jz .out
    xorpd xmm0, [rel syn_sign_mask]
.out:
    mov rax, rdi
    pop r12
    pop rbx
    ret
.none:
    xorpd xmm0, xmm0
    xor eax, eax
    pop r12
    pop rbx
    ret
; one integer-part digit (eax)
.digit:
    cmp r9d, 18
    jae .digit_drop
    test r8, r8
    jnz .digit_take
    test eax, eax
    jz .digit_done                      ; leading zero
.digit_take:
    imul r8, r8, 10
    add r8, rax
    inc r9d
.digit_done:
    ret
.digit_drop:
    inc r10d                            ; beyond 18 digits: scale instead
    ret

; rdi = p, rsi = end, rdx = keyword, ecx = its length -> ZF = matched (any
;   case), rdi past it when matched
syn_keyword:
    mov rax, rsi
    sub rax, rdi
    cmp rax, rcx
    jb .no
    xor r8d, r8d
.byte:
    cmp r8d, ecx
    jae .yes
    movzx eax, byte [rdi + r8]
    movzx r9d, byte [rdx + r8]
    or eax, 0x20
    or r9d, 0x20
    cmp eax, r9d
    jne .no
    inc r8d
    jmp .byte
.yes:
    add rdi, rcx
    xor eax, eax                        ; ZF = 1
    ret
.no:
    or eax, 1                           ; ZF = 0
    ret

%macro IS_KEYWORD 1
    jmp %%skip
%%text: db %1
%%skip:
    lea rdx, [rel %%text]
    mov ecx, %strlen(%1)
    call syn_keyword
%endmacro

; al = character -> eax = hex value or -1
syn_hex:
    movzx eax, al
    sub eax, '0'
    cmp eax, 9
    jbe .ok
    movzx eax, byte [rdi]
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 5
    ja .bad
    add eax, 10
.ok:
    ret
.bad:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_colour — rdi = p, rsi = end -> eax = 0 none, 1 colour, 2
;   currentColor, 3 inherit, -1 not a colour; edx = colour (straight BGRA,
;   0xAARRGGBB) for kind 1
; -----------------------------------------------------------------------------
global ugfx_svg_colour
ugfx_svg_colour:
    push rbx
    push r12
    push r13
    sub rsp, 32
    call syn_skip_ws
    cmp rdi, rsi
    jae .invalid
    IS_KEYWORD "none"
    je .none
    IS_KEYWORD "transparent"
    je .none
    IS_KEYWORD "currentColor"
    je .current
    IS_KEYWORD "inherit"
    je .inherit
    IS_KEYWORD "url("
    je .url
    IS_KEYWORD "rgba("
    je .rgb
    IS_KEYWORD "rgb("
    je .rgb
    cmp byte [rdi], '#'
    je .hash
    ; keywords
    lea rbx, [rel syn_keywords]
.kw:
    movzx ecx, byte [rbx]
    test ecx, ecx
    jz .invalid
    lea rdx, [rbx + 1]
    push rdi
    call syn_keyword
    pop rax
    jne .kw_next
    ; a keyword must end the token
    cmp rdi, rsi
    jae .kw_hit
    movzx eax, byte [rdi]
    or eax, 0x20
    sub eax, 'a'
    cmp eax, 25
    jbe .kw_miss
.kw_hit:
    movzx ecx, byte [rbx]
    mov edx, [rbx + 1 + rcx]
    or edx, 0xFF000000
    jmp .colour
.kw_miss:
    mov rdi, rax
.kw_next:
    mov rdi, rax
    movzx ecx, byte [rbx]
    lea rbx, [rbx + rcx + 5]
    jmp .kw
.hash:
    inc rdi
    xor r12d, r12d                      ; value
    xor r13d, r13d                      ; digits
.hash_digit:
    cmp rdi, rsi
    jae .hash_done
    mov al, [rdi]
    call syn_hex
    test eax, eax
    js .hash_done
    shl r12d, 4
    or r12d, eax
    inc r13d
    inc rdi
    cmp r13d, 8
    jb .hash_digit
.hash_done:
    cmp r13d, 3
    je .hash3
    cmp r13d, 4
    je .hash4
    cmp r13d, 6
    je .hash6
    cmp r13d, 8
    je .hash8
    jmp .invalid
.hash3:
    shl r12d, 4
    or r12d, 15                         ; #rgb -> #rgbf
.hash4:
    ; #rgba -> 0xAARRGGBB, each digit doubled
    xor edx, edx
    mov ecx, 12
.h4_digit:
    mov eax, r12d
    shr eax, cl
    and eax, 15
    imul eax, eax, 17
    shl edx, 8
    or edx, eax
    sub ecx, 4
    jns .h4_digit
    ; edx = RRGGBBAA
    jmp .rgba_to_argb
.hash6:
    mov edx, r12d
    or edx, 0xFF000000
    jmp .colour
.hash8:
    mov edx, r12d
.rgba_to_argb:
    ror edx, 8                          ; RRGGBBAA -> AARRGGBB
    jmp .colour
.rgb:
    ; up to four numbers (percent allowed), then ')'
    mov dword [rsp], 0
    mov dword [rsp + 4], 0
    mov dword [rsp + 8], 0
    mov dword [rsp + 12], 255
    xor r12d, r12d
.rgb_arg:
    cmp r12d, 4
    jae .rgb_close
    push rsi
    call ugfx_svg_number
    pop rsi
    test rax, rax
    jz .rgb_close
    mov rdi, rax
    cmp r12d, 3
    je .rgb_alpha
    ; channel: n, or n% of 255
    cmp rdi, rsi
    jae .rgb_round
    cmp byte [rdi], '%'
    jne .rgb_round
    inc rdi
    mulsd xmm0, [rel syn_hundredth]
    mulsd xmm0, [rel syn_255]
    jmp .rgb_round
.rgb_alpha:
    cmp rdi, rsi
    jae .rgb_alpha_scale
    cmp byte [rdi], '%'
    jne .rgb_alpha_scale
    inc rdi
    mulsd xmm0, [rel syn_hundredth]
.rgb_alpha_scale:
    mulsd xmm0, [rel syn_255]
.rgb_round:
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    minsd xmm0, [rel syn_255]
    addsd xmm0, [rel syn_half]
    cvttsd2si eax, xmm0
    mov [rsp + r12 * 4], eax
    inc r12d
    jmp .rgb_arg
.rgb_close:
    call syn_skip
    cmp rdi, rsi
    jae .invalid
    cmp byte [rdi], ')'
    jne .invalid
    inc rdi
    cmp r12d, 3
    jb .invalid
    mov edx, [rsp + 12]
    shl edx, 8
    or edx, [rsp]
    shl edx, 8
    or edx, [rsp + 4]
    shl edx, 8
    or edx, [rsp + 8]
    jmp .colour
.url:
    ; url(...) [fallback]
.url_skip:
    cmp rdi, rsi
    jae .none
    inc rdi
    cmp byte [rdi - 1], ')'
    jne .url_skip
    call syn_skip_ws
    cmp rdi, rsi
    jae .none
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    jmp ugfx_svg_colour                 ; the fallback
.colour:
    mov eax, SVG_KIND_COLOUR
    jmp .out
.none:
    xor eax, eax
    jmp .out
.current:
    mov eax, SVG_KIND_CURRENT
    jmp .out
.inherit:
    mov eax, SVG_KIND_INHERIT
    jmp .out
.invalid:
    mov eax, SVG_KIND_INVALID
.out:
    add rsp, 32
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_transform — rdi = p, rsi = end, rdx = double m[6] (in/out)
;   -> rax = 0, -EINVAL (m unchanged)
; -----------------------------------------------------------------------------
%define T_M         0                   ; the result so far
%define T_T         48                  ; one transform
%define T_ARGS      96                  ; f64[6]
%define T_OUT       144                 ; the caller's m
%define T_END       152
%define T_SIZE      176                 ; keeps calls 16-byte aligned

global ugfx_svg_transform
ugfx_svg_transform:
    push rbx
    push r12
    push r13
    sub rsp, T_SIZE
    mov [rsp + T_OUT], rdx
    mov [rsp + T_END], rsi
    mov r12, rdi
    ; work on a copy
    xor ecx, ecx
.copy_in:
    mov rax, [rdx + rcx * 8]
    mov [rsp + T_M + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .copy_in
.next:
    mov rdi, r12
    mov rsi, [rsp + T_END]
    call syn_skip
    mov r12, rdi
    cmp rdi, rsi
    jae .done
    ; the name
    mov ebx, 0
    IS_KEYWORD "matrix"
    je .named
    mov ebx, 1
    IS_KEYWORD "translate"
    je .named
    mov ebx, 2
    IS_KEYWORD "scale"
    je .named
    mov ebx, 3
    IS_KEYWORD "rotate"
    je .named
    mov ebx, 4
    IS_KEYWORD "skewX"
    je .named
    mov ebx, 5
    IS_KEYWORD "skewY"
    je .named
    jmp .bad
.named:
    call syn_skip_ws
    cmp rdi, rsi
    jae .bad
    cmp byte [rdi], '('
    jne .bad
    inc rdi
    xor r13d, r13d                      ; arguments
.arg:
    cmp r13d, 6
    jae .args_done
    push rsi
    push rdi
    call ugfx_svg_number
    pop rdi
    pop rsi
    test rax, rax
    jz .args_done
    mov rdi, rax
    movsd [rsp + T_ARGS + r13 * 8], xmm0
    inc r13d
    jmp .arg
.args_done:
    call syn_skip
    cmp rdi, rsi
    jae .bad
    cmp byte [rdi], ')'
    jne .bad
    inc rdi
    mov r12, rdi
    ; build T: identity, then by kind and argument count
    movsd xmm0, [rel syn_one]
    xorpd xmm1, xmm1
    movsd [rsp + T_T], xmm0
    movsd [rsp + T_T + 8], xmm1
    movsd [rsp + T_T + 16], xmm1
    movsd [rsp + T_T + 24], xmm0
    movsd [rsp + T_T + 32], xmm1
    movsd [rsp + T_T + 40], xmm1
    cmp ebx, 0
    je .t_matrix
    cmp ebx, 1
    je .t_translate
    cmp ebx, 2
    je .t_scale
    cmp ebx, 3
    je .t_rotate
    ; skewX / skewY: one angle in degrees
    cmp r13d, 1
    jne .bad
    movsd xmm0, [rsp + T_ARGS]
    mulsd xmm0, [rel syn_deg]
    call umath_tan_f64
    cmp ebx, 4
    jne .t_skew_y
    movsd [rsp + T_T + 16], xmm0        ; c = tan a
    jmp .apply
.t_skew_y:
    movsd [rsp + T_T + 8], xmm0         ; b = tan a
    jmp .apply
.t_matrix:
    cmp r13d, 6
    jne .bad
    xor ecx, ecx
.t_matrix_copy:
    mov rax, [rsp + T_ARGS + rcx * 8]
    mov [rsp + T_T + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .t_matrix_copy
    jmp .apply
.t_translate:
    cmp r13d, 1
    jb .bad
    cmp r13d, 2
    ja .bad
    movsd xmm0, [rsp + T_ARGS]
    movsd [rsp + T_T + 32], xmm0
    cmp r13d, 2
    jne .apply
    movsd xmm0, [rsp + T_ARGS + 8]
    movsd [rsp + T_T + 40], xmm0
    jmp .apply
.t_scale:
    cmp r13d, 1
    jb .bad
    cmp r13d, 2
    ja .bad
    movsd xmm0, [rsp + T_ARGS]
    movsd [rsp + T_T], xmm0
    movsd [rsp + T_T + 24], xmm0        ; sy = sx unless given
    cmp r13d, 2
    jne .apply
    movsd xmm0, [rsp + T_ARGS + 8]
    movsd [rsp + T_T + 24], xmm0
    jmp .apply
.t_rotate:
    cmp r13d, 1
    je .t_rotate_plain
    cmp r13d, 3
    jne .bad
    ; rotate(a, cx, cy) = translate(c) rotate(a) translate(-c)
    movsd xmm0, [rsp + T_ARGS + 8]
    movsd [rsp + T_T + 32], xmm0
    movsd xmm0, [rsp + T_ARGS + 16]
    movsd [rsp + T_T + 40], xmm0
    lea rdi, [rsp + T_M]
    mov rsi, rdi
    lea rdx, [rsp + T_T]
    call umath_affine2_multiply
    lea rdi, [rsp + T_T]
    movsd xmm0, [rsp + T_ARGS]
    mulsd xmm0, [rel syn_deg]
    call umath_affine2_rotate
    lea rdi, [rsp + T_M]
    mov rsi, rdi
    lea rdx, [rsp + T_T]
    call umath_affine2_multiply
    movsd xmm0, [rel syn_one]
    xorpd xmm1, xmm1
    movsd [rsp + T_T], xmm0
    movsd [rsp + T_T + 8], xmm1
    movsd [rsp + T_T + 16], xmm1
    movsd [rsp + T_T + 24], xmm0
    xorpd xmm0, xmm0
    subsd xmm0, [rsp + T_ARGS + 8]
    movsd [rsp + T_T + 32], xmm0
    xorpd xmm0, xmm0
    subsd xmm0, [rsp + T_ARGS + 16]
    movsd [rsp + T_T + 40], xmm0
    jmp .apply
.t_rotate_plain:
    lea rdi, [rsp + T_T]
    movsd xmm0, [rsp + T_ARGS]
    mulsd xmm0, [rel syn_deg]
    call umath_affine2_rotate
.apply:
    lea rdi, [rsp + T_M]
    mov rsi, rdi
    lea rdx, [rsp + T_T]
    call umath_affine2_multiply
    jmp .next
.done:
    mov rdx, [rsp + T_OUT]
    xor ecx, ecx
.copy_out:
    mov rax, [rsp + T_M + rcx * 8]
    mov [rdx + rcx * 8], rax
    inc ecx
    cmp ecx, 6
    jb .copy_out
    xor eax, eax
    jmp .out
.bad:
    mov rax, -(EINVAL)
.out:
    add rsp, T_SIZE
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_path_data — rdi = p, rsi = end, rdx = UgfxPath* -> rax = 0 or the
;   first path error (-ENOMEM). Syntax errors end the path quietly.
; -----------------------------------------------------------------------------
%define D_PATH      0
%define D_END       8
%define D_CMD       16                  ; u32 current command letter
%define D_PREV      20                  ; u32 previous command letter
%define D_CX        24                  ; current point
%define D_CY        32
%define D_SX        40                  ; subpath start
%define D_SY        48
%define D_LX        56                  ; last control point
%define D_LY        64
%define D_ARGS      72                  ; f64[7]
%define D_ARC       128                 ; f64[24]
%define D_N         320
%define D_I         328
%define D_SIZE      352                 ; keeps calls 16-byte aligned

global ugfx_svg_path_data
ugfx_svg_path_data:
    push rbx
    push r12
    push r13
    sub rsp, D_SIZE
    mov [rsp + D_PATH], rdx
    mov [rsp + D_END], rsi
    mov r12, rdi
    mov dword [rsp + D_CMD], 0
    mov dword [rsp + D_PREV], 0
    xorpd xmm0, xmm0
    movsd [rsp + D_CX], xmm0
    movsd [rsp + D_CY], xmm0
    movsd [rsp + D_SX], xmm0
    movsd [rsp + D_SY], xmm0
    movsd [rsp + D_LX], xmm0
    movsd [rsp + D_LY], xmm0
.next:
    mov rdi, r12
    mov rsi, [rsp + D_END]
    call syn_skip
    mov r12, rdi
    cmp rdi, rsi
    jae .done
    movzx eax, byte [rdi]
    mov ecx, eax
    or ecx, 0x20                        ; lower case
    cmp ecx, 'z'
    je .close
    lea rdx, [rel pd_letters]
.letter:
    movzx r8d, byte [rdx]
    test r8d, r8d
    jz .repeat
    cmp ecx, r8d
    je .new_command
    inc rdx
    jmp .letter
.new_command:
    mov [rsp + D_CMD], eax
    inc r12
    jmp .arguments
.repeat:
    ; a number repeats the command (after M / m: L / l)
    mov eax, [rsp + D_CMD]
    test eax, eax
    jz .done
    cmp eax, 'z'
    je .done
    cmp eax, 'Z'
    je .done
    cmp eax, 'M'
    jne .repeat_lower
    mov dword [rsp + D_CMD], 'L'
    jmp .arguments
.repeat_lower:
    cmp eax, 'm'
    jne .arguments
    mov dword [rsp + D_CMD], 'l'
    jmp .arguments
.arguments:
    mov eax, [rsp + D_CMD]
    mov ebx, eax
    or ebx, 0x20
    ; argument count
    mov r13d, 2
    cmp ebx, 'h'
    je .one
    cmp ebx, 'v'
    je .one
    cmp ebx, 'c'
    je .six
    cmp ebx, 's'
    je .four
    cmp ebx, 'q'
    je .four
    cmp ebx, 'a'
    je .arc_args
    jmp .read
.one:
    mov r13d, 1
    jmp .read
.four:
    mov r13d, 4
    jmp .read
.six:
    mov r13d, 6
.read:
    xor ecx, ecx
.read_one:
    cmp ecx, r13d
    jae .have_args
    push rcx
    mov rdi, r12
    mov rsi, [rsp + 8 + D_END]
    call ugfx_svg_number
    pop rcx
    test rax, rax
    jz .done
    mov r12, rax
    movsd [rsp + D_ARGS + rcx * 8], xmm0
    inc ecx
    jmp .read_one
.arc_args:
    ; rx ry rotation large sweep x y; the flags are single 0 / 1 digits
    xor ecx, ecx
.arc_one:
    cmp ecx, 7
    jae .have_args
    cmp ecx, 3
    je .arc_flag
    cmp ecx, 4
    je .arc_flag
    push rcx
    mov rdi, r12
    mov rsi, [rsp + 8 + D_END]
    call ugfx_svg_number
    pop rcx
    test rax, rax
    jz .done
    mov r12, rax
    movsd [rsp + D_ARGS + rcx * 8], xmm0
    inc ecx
    jmp .arc_one
.arc_flag:
    mov rdi, r12
    mov rsi, [rsp + D_END]
    push rcx
    call syn_skip
    pop rcx
    cmp rdi, rsi
    jae .done
    movzx eax, byte [rdi]
    sub eax, '0'
    cmp eax, 1
    ja .done
    inc rdi
    mov r12, rdi
    cvtsi2sd xmm0, eax
    movsd [rsp + D_ARGS + rcx * 8], xmm0
    inc ecx
    jmp .arc_one
.have_args:
    ; relative commands: offset by the current point
    mov eax, [rsp + D_CMD]
    cmp eax, 'a'
    jb .absolute                        ; upper case
    cmp ebx, 'h'
    je .rel_h
    cmp ebx, 'v'
    je .rel_v
    cmp ebx, 'a'
    je .rel_a
    xor ecx, ecx
.rel_pair:
    cmp ecx, r13d
    jae .absolute
    movsd xmm0, [rsp + D_ARGS + rcx * 8]
    addsd xmm0, [rsp + D_CX]
    movsd [rsp + D_ARGS + rcx * 8], xmm0
    movsd xmm0, [rsp + D_ARGS + rcx * 8 + 8]
    addsd xmm0, [rsp + D_CY]
    movsd [rsp + D_ARGS + rcx * 8 + 8], xmm0
    add ecx, 2
    jmp .rel_pair
.rel_h:
    movsd xmm0, [rsp + D_ARGS]
    addsd xmm0, [rsp + D_CX]
    movsd [rsp + D_ARGS], xmm0
    jmp .absolute
.rel_v:
    movsd xmm0, [rsp + D_ARGS]
    addsd xmm0, [rsp + D_CY]
    movsd [rsp + D_ARGS], xmm0
    jmp .absolute
.rel_a:
    movsd xmm0, [rsp + D_ARGS + 40]
    addsd xmm0, [rsp + D_CX]
    movsd [rsp + D_ARGS + 40], xmm0
    movsd xmm0, [rsp + D_ARGS + 48]
    addsd xmm0, [rsp + D_CY]
    movsd [rsp + D_ARGS + 48], xmm0
.absolute:
    cmp ebx, 'm'
    je .do_move
    cmp ebx, 'l'
    je .do_line
    cmp ebx, 'h'
    je .do_h
    cmp ebx, 'v'
    je .do_v
    cmp ebx, 'c'
    je .do_cubic
    cmp ebx, 's'
    je .do_smooth
    cmp ebx, 'q'
    je .do_quad
    cmp ebx, 't'
    je .do_smooth_quad
    jmp .do_arc
.do_move:
    movsd xmm0, [rsp + D_ARGS]
    movsd xmm1, [rsp + D_ARGS + 8]
    movsd [rsp + D_SX], xmm0
    movsd [rsp + D_SY], xmm1
    mov rdi, [rsp + D_PATH]
    call ugfx_path_move_to
    jmp .to_point
.do_h:
    movsd xmm0, [rsp + D_CY]
    movsd [rsp + D_ARGS + 8], xmm0
    jmp .do_line
.do_v:
    movsd xmm0, [rsp + D_ARGS]
    movsd [rsp + D_ARGS + 8], xmm0
    movsd xmm0, [rsp + D_CX]
    movsd [rsp + D_ARGS], xmm0
.do_line:
    movsd xmm0, [rsp + D_ARGS]
    movsd xmm1, [rsp + D_ARGS + 8]
    mov rdi, [rsp + D_PATH]
    call ugfx_path_line_to
.to_point:
    ; the end point (args 0, 1) becomes current; no control point
    movsd xmm0, [rsp + D_ARGS]
    movsd xmm1, [rsp + D_ARGS + 8]
    jmp .set_point_plain
.do_smooth:
    ; c1 = reflection of the last control point after C / S, else current
    call .reflect_cubic
    jmp .do_cubic_shifted
.do_cubic:
    movsd xmm0, [rsp + D_ARGS]
    movsd xmm1, [rsp + D_ARGS + 8]
    movsd xmm2, [rsp + D_ARGS + 16]
    movsd xmm3, [rsp + D_ARGS + 24]
    movsd xmm4, [rsp + D_ARGS + 32]
    movsd xmm5, [rsp + D_ARGS + 40]
    jmp .emit_cubic
.do_cubic_shifted:
    ; args: x2 y2 x y in 0..3, reflected c1 in xmm6 / xmm7
    movapd xmm0, xmm6
    movapd xmm1, xmm7
    movsd xmm2, [rsp + D_ARGS]
    movsd xmm3, [rsp + D_ARGS + 8]
    movsd xmm4, [rsp + D_ARGS + 16]
    movsd xmm5, [rsp + D_ARGS + 24]
.emit_cubic:
    movsd [rsp + D_LX], xmm2
    movsd [rsp + D_LY], xmm3
    movsd [rsp + D_ARGS], xmm4
    movsd [rsp + D_ARGS + 8], xmm5
    mov rdi, [rsp + D_PATH]
    call ugfx_path_cubic_to
    movsd xmm0, [rsp + D_ARGS]
    movsd xmm1, [rsp + D_ARGS + 8]
    jmp .set_point
.do_smooth_quad:
    call .reflect_quad
    movsd xmm2, [rsp + D_ARGS]
    movsd xmm3, [rsp + D_ARGS + 8]
    movapd xmm0, xmm6
    movapd xmm1, xmm7
    jmp .emit_quad
.do_quad:
    movsd xmm0, [rsp + D_ARGS]
    movsd xmm1, [rsp + D_ARGS + 8]
    movsd xmm2, [rsp + D_ARGS + 16]
    movsd xmm3, [rsp + D_ARGS + 24]
.emit_quad:
    movsd [rsp + D_LX], xmm0
    movsd [rsp + D_LY], xmm1
    movsd [rsp + D_ARGS], xmm2
    movsd [rsp + D_ARGS + 8], xmm3
    mov rdi, [rsp + D_PATH]
    call ugfx_path_quad_to
    movsd xmm0, [rsp + D_ARGS]
    movsd xmm1, [rsp + D_ARGS + 8]
    jmp .set_point
.do_arc:
    lea rdi, [rsp + D_ARC]
    movsd xmm0, [rsp + D_CX]
    movsd xmm1, [rsp + D_CY]
    movsd xmm2, [rsp + D_ARGS + 40]
    movsd xmm3, [rsp + D_ARGS + 48]
    movsd xmm4, [rsp + D_ARGS]
    movsd xmm5, [rsp + D_ARGS + 8]
    movsd xmm6, [rsp + D_ARGS + 16]
    mulsd xmm6, [rel syn_deg]
    cvttsd2si esi, qword [rsp + D_ARGS + 24]    ; large
    cvttsd2si eax, qword [rsp + D_ARGS + 32]    ; sweep
    shl eax, 1
    or esi, eax
    call umath_arc_svg_to_cubics
    mov [rsp + D_N], rax
    mov qword [rsp + D_I], 0
.arc_piece:
    mov rax, [rsp + D_I]
    cmp rax, [rsp + D_N]
    jae .arc_end
    imul rax, rax, 48
    lea rax, [rsp + D_ARC + rax]
    movsd xmm0, [rax]
    movsd xmm1, [rax + 8]
    movsd xmm2, [rax + 16]
    movsd xmm3, [rax + 24]
    movsd xmm4, [rax + 32]
    movsd xmm5, [rax + 40]
    mov rdi, [rsp + D_PATH]
    call ugfx_path_cubic_to
    test rax, rax
    jnz .failed
    inc qword [rsp + D_I]
    jmp .arc_piece
.arc_end:
    xor eax, eax
    movsd xmm0, [rsp + D_ARGS + 40]
    movsd xmm1, [rsp + D_ARGS + 48]
.set_point_plain:
    ; no control point to reflect: it is the current point
    movsd [rsp + D_LX], xmm0
    movsd [rsp + D_LY], xmm1
.set_point:
    test rax, rax
    jnz .failed
    movsd [rsp + D_CX], xmm0
    movsd [rsp + D_CY], xmm1
    mov eax, [rsp + D_CMD]
    or eax, 0x20
    mov [rsp + D_PREV], eax
    jmp .next
.close:
    inc r12
    mov dword [rsp + D_CMD], 'z'
    mov dword [rsp + D_PREV], 'z'
    mov rdi, [rsp + D_PATH]
    call ugfx_path_close
    test rax, rax
    jnz .failed
    movsd xmm0, [rsp + D_SX]
    movsd xmm1, [rsp + D_SY]
    movsd [rsp + D_CX], xmm0
    movsd [rsp + D_CY], xmm1
    movsd [rsp + D_LX], xmm0
    movsd [rsp + D_LY], xmm1
    jmp .next
.done:
    xor eax, eax
.failed:
    add rsp, D_SIZE
    pop r13
    pop r12
    pop rbx
    ret
; -> xmm6 / xmm7 = the reflected cubic control point (frame at rsp + 8)
.reflect_cubic:
    movsd xmm6, [rsp + 8 + D_CX]
    movsd xmm7, [rsp + 8 + D_CY]
    mov eax, [rsp + 8 + D_PREV]
    cmp eax, 'c'
    je .reflect
    cmp eax, 's'
    je .reflect
    ret
.reflect_quad:
    movsd xmm6, [rsp + 8 + D_CX]
    movsd xmm7, [rsp + 8 + D_CY]
    mov eax, [rsp + 8 + D_PREV]
    cmp eax, 'q'
    je .reflect
    cmp eax, 't'
    je .reflect
    ret
.reflect:
    ; 2 current - last control
    addsd xmm6, xmm6
    subsd xmm6, [rsp + 8 + D_LX]
    addsd xmm7, xmm7
    subsd xmm7, [rsp + 8 + D_LY]
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_points — rdi = p, rsi = end, rdx = UgfxPath*, ecx = 1 to close
;   (polygon) -> rax = 0 or a path error. An odd last number is ignored.
; -----------------------------------------------------------------------------
global ugfx_svg_points
ugfx_svg_points:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 24
    mov r12, rdi
    mov r13, rsi
    mov rbx, rdx
    mov r14d, ecx
    mov dword [rsp + 16], 0             ; points so far
.pair:
    mov rdi, r12
    mov rsi, r13
    call ugfx_svg_number
    test rax, rax
    jz .end
    movsd [rsp], xmm0
    mov rdi, rax
    mov rsi, r13
    call ugfx_svg_number
    test rax, rax
    jz .end
    mov r12, rax
    movapd xmm1, xmm0
    movsd xmm0, [rsp]
    mov rdi, rbx
    cmp dword [rsp + 16], 0
    jne .line
    call ugfx_path_move_to
    jmp .added
.line:
    call ugfx_path_line_to
.added:
    test rax, rax
    jnz .out
    inc dword [rsp + 16]
    jmp .pair
.end:
    xor eax, eax
    test r14d, r14d
    jz .out
    cmp dword [rsp + 16], 0
    je .out
    mov rdi, rbx
    call ugfx_path_close
.out:
    add rsp, 24
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
pd_letters:         db "mlhvcsqta", 0
