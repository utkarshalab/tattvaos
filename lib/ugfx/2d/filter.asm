; =============================================================================
; Utkarsha OS — lib/ugfx/2d/filter.asm
; =============================================================================
; Filter effects: a graph of primitives run in device space over a layer's
; pixels (premultiplied BGRA), the SVG / CSS filter model.
;
;   ugfx_filter_run(filter, io, pool)   io: the layer, filtered in place;
;                                       pool: FE_POOL PixBufs the size of io
;
; Each primitive (UgfxFe) reads its inputs - SourceGraphic (io), SourceAlpha,
; transparent black, or an earlier primitive's result - and writes its own
; result, all clipped to the filter region and to its subregion; pixels
; outside count as transparent. With linear set it works in linearRGB:
; inputs are converted (8-bit tables, on unpremultiplied colour) and its
; result is kept so; the last result, back in sRGB, replaces io inside the
; region, and io is cleared outside it.
;
; Primitives (parameters p0.. in UgfxFe_p, lists in var):
;   FLOOD      p0 colour (straight ARGB, sRGB)
;   OFFSET     p0, p1 dx, dy (device pixels, rounded)
;   BLUR       p0, p1 standard deviation x, y (device pixels): three box
;              blurs per axis, d = floor(s 3 sqrt(2 pi) / 4 + 0.5); for even
;              d two of size d off centre and one of d + 1; s <= 0 or d < 2
;              leaves that axis
;   MERGE      var: the inputs, source-over in order
;   BLEND      p0 mode: 0 normal 1 multiply 2 screen 3 darken 4 lighten (in
;              over in2)
;   COMPOSITE  p0 operator: 0 over 1 in 2 out 3 atop 4 xor 5 arithmetic
;              (p1..p4 = k1..k4 on premultiplied values in [0, 1])
;   COLORMATRIX var: 20 values (rows R G B A of [r g b a 1]), unpremultiplied
;   TRANSFER   var: per channel R G B A: type (0 identity 1 table 2 discrete
;              3 linear 4 gamma), slope, intercept, amplitude, exponent,
;              offset, n, n table values
;   MORPHOLOGY p0 0 erode / 1 dilate, p1, p2 radius x, y (device pixels);
;              a radius <= 0 passes the input through
;   TILE       the input's subregion repeated
;
; x / 255 rounds exactly: (t + 128 + ((t + 128) >> 8)) >> 8; unpremultiply
; is min(255, (c 255 + a / 2) / a); floats round as (int)(v 255 + 0.5)
; after clamping to [0, 1].
; =============================================================================

%include "ugfx.inc"

extern umath_pow_f64

; pool slots: 0..15 results, then
%define FS_ALPHA    16                  ; SourceAlpha
%define FS_IN1      17                  ; inputs converted to another colour space
%define FS_IN2      18
%define FS_ZERO     19                  ; transparent black
%define FS_BLUR     20                  ; a pass's other buffer

; frame (rbx)
%define FR_F        0                   ; UgfxFilter*
%define FR_IO       8
%define FR_POOL     16
%define FR_R        24                  ; i32 x0, y0, x1, y1: the region on io
%define FR_SUB      40                  ; i32 x0, y0, x1, y1: the primitive's
%define FR_I        56                  ; u32 the primitive
%define FR_PRIM     64
%define FR_OUT      72
%define FR_IN1      80
%define FR_IN2      88
%define FR_TAG      96                  ; u8[16] results in linearRGB
%define FR_SA       112                 ; u32 SourceAlpha made
%define FR_ZEROED   116                 ; u32 the zero buffer cleared
%define FR_W        120                 ; u64
%define FR_H        128
%define FR_LUT      136                 ; u8[4][256]: transfer functions
%define FR_T        1160                ; scratch: f64[8]
%define FR_SIZE     1232

%macro DIV255 1                         ; %1 = t (<= 255 x 255) -> %1 = round(t / 255)
    add %1, 128
    mov r11d, %1
    shr r11d, 8
    add %1, r11d
    shr %1, 8
%endmacro

section .rodata
align 8
fe_blur_k:          dq 1.8799712059732503   ; 3 sqrt(2 pi) / 4
fe_half:            dq 0.5
fe_one:             dq 1.0
fe_255:             dq 255.0
fe_inv255:          dq 255.0                ; (divided by, kept exact)
fe_max_box:         dq 2048.0
; sRGB <-> linearRGB, 8-bit, rounded (tools: the formulas in filter_ref.py)
fe_to_linear:
    db 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1
    db 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3
    db 4, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 6, 6, 7, 7, 7
    db 8, 8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 12, 12, 12, 13
    db 13, 13, 14, 14, 15, 15, 16, 16, 17, 17, 17, 18, 18, 19, 19, 20
    db 20, 21, 22, 22, 23, 23, 24, 24, 25, 25, 26, 27, 27, 28, 29, 29
    db 30, 30, 31, 32, 32, 33, 34, 35, 35, 36, 37, 37, 38, 39, 40, 41
    db 41, 42, 43, 44, 45, 45, 46, 47, 48, 49, 50, 51, 51, 52, 53, 54
    db 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70
    db 71, 72, 73, 74, 76, 77, 78, 79, 80, 81, 82, 84, 85, 86, 87, 88
    db 90, 91, 92, 93, 95, 96, 97, 99, 100, 101, 103, 104, 105, 107, 108, 109
    db 111, 112, 114, 115, 116, 118, 119, 121, 122, 124, 125, 127, 128, 130, 131, 133
    db 134, 136, 138, 139, 141, 142, 144, 146, 147, 149, 151, 152, 154, 156, 157, 159
    db 161, 163, 164, 166, 168, 170, 171, 173, 175, 177, 179, 181, 183, 184, 186, 188
    db 190, 192, 194, 196, 198, 200, 202, 204, 206, 208, 210, 212, 214, 216, 218, 220
    db 222, 224, 226, 229, 231, 233, 235, 237, 239, 242, 244, 246, 248, 250, 253, 255
fe_to_srgb:
    db 0, 13, 22, 28, 34, 38, 42, 46, 50, 53, 56, 59, 61, 64, 66, 69
    db 71, 73, 75, 77, 79, 81, 83, 85, 86, 88, 90, 92, 93, 95, 96, 98
    db 99, 101, 102, 104, 105, 106, 108, 109, 110, 112, 113, 114, 115, 117, 118, 119
    db 120, 121, 122, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136
    db 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 148, 149, 150, 151
    db 152, 153, 154, 155, 155, 156, 157, 158, 159, 159, 160, 161, 162, 163, 163, 164
    db 165, 166, 167, 167, 168, 169, 170, 170, 171, 172, 173, 173, 174, 175, 175, 176
    db 177, 178, 178, 179, 180, 180, 181, 182, 182, 183, 184, 185, 185, 186, 187, 187
    db 188, 189, 189, 190, 190, 191, 192, 192, 193, 194, 194, 195, 196, 196, 197, 197
    db 198, 199, 199, 200, 200, 201, 202, 202, 203, 203, 204, 205, 205, 206, 206, 207
    db 208, 208, 209, 209, 210, 210, 211, 212, 212, 213, 213, 214, 214, 215, 215, 216
    db 216, 217, 218, 218, 219, 219, 220, 220, 221, 221, 222, 222, 223, 223, 224, 224
    db 225, 226, 226, 227, 227, 228, 228, 229, 229, 230, 230, 231, 231, 232, 232, 233
    db 233, 234, 234, 235, 235, 236, 236, 237, 237, 238, 238, 238, 239, 239, 240, 240
    db 241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 246, 247, 247, 248
    db 248, 249, 249, 250, 250, 251, 251, 251, 252, 252, 253, 253, 254, 254, 255, 255

section .text

; -----------------------------------------------------------------------------
; ugfx_filter_run — rdi = const UgfxFilter*, rsi = PixBuf* (the layer), rdx =
;   PixBuf*[FE_POOL] the same size -> rax = 0, -EINVAL (more than 16
;   primitives, or a bad input index)
; -----------------------------------------------------------------------------
global ugfx_filter_run
ugfx_filter_run:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, FR_SIZE + 8
    mov rbx, rsp
    mov [rbx + FR_F], rdi
    mov [rbx + FR_IO], rsi
    mov [rbx + FR_POOL], rdx
    mov dword [rbx + FR_SA], 0
    mov dword [rbx + FR_ZEROED], 0
    mov rax, [rsi + PixBuf_width]
    mov [rbx + FR_W], rax
    mov rax, [rsi + PixBuf_height]
    mov [rbx + FR_H], rax
    ; the region, clamped to io
    lea rsi, [rdi + UgfxFilter_region]
    lea rdi, [rbx + FR_R]
    call fe_clamp_rect
    mov rax, [rbx + FR_F]
    mov ecx, [rax + UgfxFilter_count]
    cmp ecx, 16
    ja .bad
    test ecx, ecx
    jz .final                           ; no primitives: nothing shows
    mov dword [rbx + FR_I], 0
.prim:
    mov rax, [rbx + FR_F]
    mov ecx, [rbx + FR_I]
    cmp ecx, [rax + UgfxFilter_count]
    jae .final
    imul rdx, rcx, UgfxFe_SIZE
    add rdx, [rax + UgfxFilter_prims]
    mov [rbx + FR_PRIM], rdx
    ; its subregion, clamped to the region
    lea rsi, [rdx + UgfxFe_sub]
    lea rdi, [rbx + FR_SUB]
    call fe_clamp_sub
    ; its result, cleared over the region
    mov rax, [rbx + FR_POOL]
    mov ecx, [rbx + FR_I]
    mov rdi, [rax + rcx * 8]
    mov [rbx + FR_OUT], rdi
    lea rsi, [rbx + FR_R]
    call fe_clear
    ; the inputs, in its colour space
    mov rdx, [rbx + FR_PRIM]
    mov edi, [rdx + UgfxFe_in1]
    mov esi, FS_IN1
    call fe_input
    test rax, rax
    jz .bad
    mov [rbx + FR_IN1], rax
    mov rdx, [rbx + FR_PRIM]
    mov edi, [rdx + UgfxFe_in2]
    mov esi, FS_IN2
    call fe_input
    test rax, rax
    jz .bad
    mov [rbx + FR_IN2], rax
    mov rdx, [rbx + FR_PRIM]
    mov eax, [rdx + UgfxFe_type]
    cmp eax, FE_TILE
    ja .bad
    lea rcx, [rel fe_ops]
    call [rcx + rax * 8]
    test rax, rax
    jnz .out
    ; its colour space
    mov rdx, [rbx + FR_PRIM]
    mov eax, [rdx + UgfxFe_linear]
    mov ecx, [rbx + FR_I]
    mov [rbx + FR_TAG + rcx], al
    inc dword [rbx + FR_I]
    jmp .prim
.final:
    call fe_finish
    xor eax, eax
    jmp .out
.bad:
    mov rax, -(EINVAL)
.out:
    add rsp, FR_SIZE + 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; rsi = i32 x0, y0, x1, y1, rdi = out, rbx = frame: clamped to io (empty:
;   x1 = x0)
fe_clamp_rect:
    xor ecx, ecx
    mov r8, [rbx + FR_W]
    mov r9, [rbx + FR_H]
    call fe_clamp_to
    ret
; the same, to the region
fe_clamp_sub:
    mov ecx, 1
fe_clamp_to:
    ; ecx = 0: to (0, 0, r8, r9); 1: to FR_R
    xor r10d, r10d
    xor r11d, r11d
    test ecx, ecx
    jz .limits
    mov r10d, [rbx + FR_R]
    mov r11d, [rbx + FR_R + 4]
    movsxd r8, dword [rbx + FR_R + 8]
    movsxd r9, dword [rbx + FR_R + 12]
.limits:
    mov eax, [rsi]
    cmp eax, r10d
    jge .x0
    mov eax, r10d
.x0:
    mov [rdi], eax
    mov eax, [rsi + 4]
    cmp eax, r11d
    jge .y0
    mov eax, r11d
.y0:
    mov [rdi + 4], eax
    movsxd rax, dword [rsi + 8]
    cmp rax, r8
    jle .x1
    mov rax, r8
.x1:
    cmp eax, [rdi]
    jge .x1_ok
    mov eax, [rdi]
.x1_ok:
    mov [rdi + 8], eax
    movsxd rax, dword [rsi + 12]
    cmp rax, r9
    jle .y1
    mov rax, r9
.y1:
    cmp eax, [rdi + 4]
    jge .y1_ok
    mov eax, [rdi + 4]
.y1_ok:
    mov [rdi + 12], eax
    ret

; rdi = PixBuf*, esi = y -> rax = its row
%macro ROW 3                            ; %1 = out reg, %2 = PixBuf* reg, %3 = y reg (64)
    mov %1, %3
    imul %1, [%2 + PixBuf_stride]
    add %1, [%2 + PixBuf_data]
%endmacro

; rdi = PixBuf*, rsi = rect (i32 x4): zeroed
fe_clear:
    push r12
    push r13
    movsxd r12, dword [rsi + 4]
    movsxd r13, dword [rsi + 12]
    movsxd r8, dword [rsi]
    movsxd r9, dword [rsi + 8]
.row:
    cmp r12, r13
    jge .done
    ROW rax, rdi, r12
    mov rcx, r8
.px:
    cmp rcx, r9
    jge .next
    mov dword [rax + rcx * 4], 0
    inc rcx
    jmp .px
.next:
    inc r12
    jmp .row
.done:
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; fe_input — edi = an input (-1 SourceGraphic, -2 SourceAlpha, -3 nothing,
;   >= 0 a result), esi = the slot for a converted copy, rbx = frame ->
;   rax = a PixBuf in the primitive's colour space (0: a bad index)
; -----------------------------------------------------------------------------
fe_input:
    push r12
    push r13
    push r14
    mov r12d, esi
    mov rax, [rbx + FR_PRIM]
    mov r13d, [rax + UgfxFe_linear]
    cmp edi, -1
    je .source
    cmp edi, -2
    je .alpha
    cmp edi, -3
    je .zero
    cmp edi, [rbx + FR_I]
    jae .bad
    mov rax, [rbx + FR_POOL]
    mov r14, [rax + rdi * 8]
    movzx eax, byte [rbx + FR_TAG + rdi]
    jmp .space
.source:
    mov r14, [rbx + FR_IO]
    xor eax, eax                        ; sRGB
.space:
    cmp eax, r13d
    je .have
    ; into the slot, converted
    mov rax, [rbx + FR_POOL]
    mov rdi, [rax + r12 * 8]
    mov rsi, r14
    mov edx, r13d                       ; 1: to linear
    call fe_convert
    mov rax, [rbx + FR_POOL]
    mov rax, [rax + r12 * 8]
    jmp .out
.have:
    mov rax, r14
    jmp .out
.alpha:
    mov rax, [rbx + FR_POOL]
    mov r14, [rax + FS_ALPHA * 8]
    cmp dword [rbx + FR_SA], 0
    jne .have
    mov dword [rbx + FR_SA], 1
    mov rdi, r14
    mov rsi, [rbx + FR_IO]
    call fe_source_alpha
    jmp .have
.zero:
    mov rax, [rbx + FR_POOL]
    mov r14, [rax + FS_ZERO * 8]
    cmp dword [rbx + FR_ZEROED], 0
    jne .have
    mov dword [rbx + FR_ZEROED], 1
    mov rdi, r14
    lea rsi, [rbx + FR_R]
    call fe_clear
    jmp .have
.bad:
    xor eax, eax
.out:
    pop r14
    pop r13
    pop r12
    ret

; rdi = out, rsi = io, rbx = frame: the region's alpha (colour 0)
fe_source_alpha:
    push r12
    movsxd r12, dword [rbx + FR_R + 4]
.row:
    movsxd rax, dword [rbx + FR_R + 12]
    cmp r12, rax
    jge .done
    ROW r8, rdi, r12
    ROW r9, rsi, r12
    movsxd rcx, dword [rbx + FR_R]
.px:
    movsxd rax, dword [rbx + FR_R + 8]
    cmp rcx, rax
    jge .next
    mov eax, [r9 + rcx * 4]
    and eax, 0xFF000000
    mov [r8 + rcx * 4], eax
    inc rcx
    jmp .px
.next:
    inc r12
    jmp .row
.done:
    pop r12
    ret

; rdi = out, rsi = in, edx = 1 to linear / 0 to sRGB, rbx = frame: over the
;   region, each pixel unpremultiplied, through the table, premultiplied
fe_convert:
    push r12
    push r13
    push r14
    push r15
    lea r15, [rel fe_to_srgb]
    test edx, edx
    jz .table
    lea r15, [rel fe_to_linear]
.table:
    movsxd r12, dword [rbx + FR_R + 4]
.row:
    movsxd rax, dword [rbx + FR_R + 12]
    cmp r12, rax
    jge .done
    ROW r13, rdi, r12
    ROW r14, rsi, r12
    movsxd rcx, dword [rbx + FR_R]
.px:
    movsxd rax, dword [rbx + FR_R + 8]
    cmp rcx, rax
    jge .next
    mov eax, [r14 + rcx * 4]
    call fe_px_convert
    mov [r13 + rcx * 4], eax
    inc rcx
    jmp .px
.next:
    inc r12
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; eax = premultiplied pixel, r15 = a 256-byte table -> eax = converted
;   (rcx kept)
fe_px_convert:
    push rcx
    push rbx
    mov r8d, eax
    shr r8d, 24                         ; a
    test r8d, r8d
    jz .zero
    mov r10d, r8d
    shl r10d, 24
    xor ecx, ecx
.channel:
    mov edx, eax
    shr edx, cl
    and edx, 255
    call fe_unpremul                    ; edx -> unpremultiplied
    movzx edx, byte [r15 + rdx]
    imul edx, r8d
    DIV255 edx
    shl edx, cl
    or r10d, edx
    add ecx, 8
    cmp ecx, 24
    jb .channel
    mov eax, r10d
    pop rbx
    pop rcx
    ret
.zero:
    xor eax, eax
    pop rbx
    pop rcx
    ret

; edx = premultiplied channel, r8d = alpha (> 0) -> edx = min(255, (c 255 +
;   a / 2) / a) (r9, rbx clobbered)
fe_unpremul:
    push rax
    mov eax, edx
    imul eax, 255
    mov r9d, r8d
    shr r9d, 1
    add eax, r9d
    xor edx, edx
    div r8d
    cmp eax, 255
    jbe .ok
    mov eax, 255
.ok:
    mov edx, eax
    pop rax
    ret

; -----------------------------------------------------------------------------
; fe_finish — rbx = frame: the last result (in sRGB) into io inside the
;   region, io cleared outside it
; -----------------------------------------------------------------------------
fe_finish:
    push r12
    push r13
    push r14
    push r15
    mov rax, [rbx + FR_F]
    mov ecx, [rax + UgfxFilter_count]
    xor r14d, r14d                      ; no result: io becomes empty
    xor r15d, r15d
    test ecx, ecx
    jz .rows
    dec ecx
    mov rax, [rbx + FR_POOL]
    mov r14, [rax + rcx * 8]
    movzx r15d, byte [rbx + FR_TAG + rcx]
.rows:
    mov rdi, [rbx + FR_IO]
    xor r12d, r12d
.row:
    cmp r12, [rbx + FR_H]
    jae .done
    ROW r13, rdi, r12
    xor ecx, ecx
.px:
    cmp rcx, [rbx + FR_W]
    jae .next
    xor eax, eax
    test r14, r14
    jz .store
    movsxd rdx, dword [rbx + FR_R + 4]
    cmp r12, rdx
    jl .store
    movsxd rdx, dword [rbx + FR_R + 12]
    cmp r12, rdx
    jge .store
    movsxd rdx, dword [rbx + FR_R]
    cmp rcx, rdx
    jl .store
    movsxd rdx, dword [rbx + FR_R + 8]
    cmp rcx, rdx
    jge .store
    ROW rax, r14, r12
    mov eax, [rax + rcx * 4]
    test r15d, r15d
    jz .store
    push r15
    lea r15, [rel fe_to_srgb]
    call fe_px_convert
    pop r15
.store:
    mov [r13 + rcx * 4], eax
    inc rcx
    jmp .px
.next:
    inc r12
    jmp .row
.done:
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; -----------------------------------------------------------------------------
; The primitives: rbx = frame (FR_OUT cleared over the region, FR_IN1 / IN2,
;   FR_SUB, FR_PRIM) -> rax = 0 or an error. A helper loops over the
;   subregion: fe_each(fn) calls fn with rdi = x (r14), r12 = y, r13 = the
;   output row, eax = in1's pixel, edx = in2's pixel; fn returns eax.
; -----------------------------------------------------------------------------
fe_each:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r15, rdi                        ; the function
    movsxd r12, dword [rbx + FR_SUB + 4]
.row:
    movsxd rax, dword [rbx + FR_SUB + 12]
    cmp r12, rax
    jge .done
    mov rdi, [rbx + FR_OUT]
    ROW r13, rdi, r12
    movsxd r14, dword [rbx + FR_SUB]
.px:
    movsxd rax, dword [rbx + FR_SUB + 8]
    cmp r14, rax
    jge .next
    mov rdi, [rbx + FR_IN1]
    ROW rax, rdi, r12
    mov eax, [rax + r14 * 4]
    mov rdi, [rbx + FR_IN2]
    ROW rdx, rdi, r12
    mov edx, [rdx + r14 * 4]
    call r15
    mov [r13 + r14 * 4], eax
    inc r14
    jmp .px
.next:
    inc r12
    jmp .row
.done:
    xor eax, eax
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; FLOOD: the colour (in the primitive's space), premultiplied
fe_flood:
    mov rdx, [rbx + FR_PRIM]
    cvttsd2si rax, qword [rdx + UgfxFe_p]
    mov r8d, eax
    shr r8d, 24                         ; a
    mov r10d, r8d
    shl r10d, 24
    xor ecx, ecx
.channel:
    mov edx, eax
    shr edx, cl
    and edx, 255
    mov r9, [rbx + FR_PRIM]
    cmp dword [r9 + UgfxFe_linear], 0
    je .plain
    lea r9, [rel fe_to_linear]
    movzx edx, byte [r9 + rdx]
.plain:
    imul edx, r8d
    DIV255 edx
    shl edx, cl
    or r10d, edx
    add ecx, 8
    cmp ecx, 24
    jb .channel
    mov [rbx + FR_T], r10d
    lea rdi, [rel .fill]
    jmp fe_each
.fill:
    mov eax, [rbx + FR_T]
    ret

; OFFSET: in1 moved by (dx, dy); from outside the region: nothing
fe_offset:
    mov rdx, [rbx + FR_PRIM]
    cvtsd2si rax, qword [rdx + UgfxFe_p]
    mov [rbx + FR_T], rax
    cvtsd2si rax, qword [rdx + UgfxFe_p + 8]
    mov [rbx + FR_T + 8], rax
    lea rdi, [rel .moved]
    jmp fe_each
.moved:
    mov rax, r14
    sub rax, [rbx + FR_T]               ; source x
    mov rcx, r12
    sub rcx, [rbx + FR_T + 8]           ; source y
    jmp fe_at_in1

; rax = x, rcx = y -> eax = in1 there, 0 outside the region
fe_at_in1:
    movsxd rdx, dword [rbx + FR_R]
    cmp rax, rdx
    jl .none
    movsxd rdx, dword [rbx + FR_R + 8]
    cmp rax, rdx
    jge .none
    movsxd rdx, dword [rbx + FR_R + 4]
    cmp rcx, rdx
    jl .none
    movsxd rdx, dword [rbx + FR_R + 12]
    cmp rcx, rdx
    jge .none
    mov rdi, [rbx + FR_IN1]
    imul rcx, [rdi + PixBuf_stride]
    add rcx, [rdi + PixBuf_data]
    mov eax, [rcx + rax * 4]
    ret
.none:
    xor eax, eax
    ret

; MERGE: each input, source-over, in order
fe_merge:
    push r12
    push r13
    sub rsp, 8
    mov rdx, [rbx + FR_PRIM]
    xor r12d, r12d
.input:
    mov rdx, [rbx + FR_PRIM]
    cmp r12d, [rdx + UgfxFe_nvar]
    jae .done
    mov rax, [rdx + UgfxFe_var]
    cvttsd2si rdi, qword [rax + r12 * 8]
    mov esi, FS_IN1
    call fe_input
    test rax, rax
    jz .bad
    mov [rbx + FR_IN1], rax
    lea rdi, [rel .over]
    call fe_each
    inc r12d
    jmp .input
.bad:
    mov rax, -(EINVAL)
    jmp .out
.done:
    xor eax, eax
.out:
    add rsp, 8
    pop r13
    pop r12
    ret
.over:
    mov edx, [r13 + r14 * 4]            ; what is there
    jmp fe_px_over

; eax = source, edx = backdrop (premultiplied) -> eax = source over it
fe_px_over:
    mov r8d, eax
    shr r8d, 24
    mov r9d, 255
    sub r9d, r8d                        ; 255 - as
    xor r10d, r10d
    xor ecx, ecx
.channel:
    mov r8d, edx
    shr r8d, cl
    and r8d, 255
    imul r8d, r9d
    DIV255 r8d
    push rax
    shr eax, cl
    and eax, 255
    add r8d, eax
    pop rax
    cmp r8d, 255
    jbe .clamped
    mov r8d, 255
.clamped:
    shl r8d, cl
    or r10d, r8d
    add ecx, 8
    cmp ecx, 32
    jb .channel
    mov eax, r10d
    ret

; BLEND: in over in2 by mode, alpha as + ab - as ab
fe_blend:
    mov rdx, [rbx + FR_PRIM]
    cvttsd2si rax, qword [rdx + UgfxFe_p]
    mov [rbx + FR_T], eax
    lea rdi, [rel .pixel]
    jmp fe_each
.pixel:
    ; eax = source (cs, as), edx = backdrop (cb, ab)
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12d, eax
    mov r13d, edx
    mov r14d, eax
    shr r14d, 24                        ; as
    mov r15d, edx
    shr r15d, 24                        ; ab
    mov esi, [rbx + FR_T]               ; mode
    xor edi, edi                        ; result
    xor ecx, ecx
.channel:
    mov eax, r12d
    shr eax, cl
    and eax, 255                        ; cs
    mov edx, r13d
    shr edx, cl
    and edx, 255                        ; cb
    ; s1 = cs (255 - ab) / 255, s2 = cb (255 - as) / 255
    mov r8d, 255
    sub r8d, r15d
    imul r8d, eax
    DIV255 r8d
    mov r9d, 255
    sub r9d, r14d
    imul r9d, edx
    DIV255 r9d
    mov r10d, eax
    imul r10d, edx
    DIV255 r10d                         ; cs cb / 255
    cmp esi, 1
    je .multiply
    cmp esi, 2
    je .screen
    cmp esi, 3
    je .darken
    cmp esi, 4
    je .lighten
    ; normal: cs + s2
    add eax, r9d
    jmp .channel_done
.multiply:
    lea eax, [r8 + r9]
    add eax, r10d
    jmp .channel_done
.screen:
    add eax, edx
    sub eax, r10d
    jmp .channel_done
.darken:
    add eax, r9d                        ; cs + s2
    add edx, r8d                        ; cb + s1
    cmp eax, edx
    jbe .channel_done
    mov eax, edx
    jmp .channel_done
.lighten:
    add eax, r9d
    add edx, r8d
    cmp eax, edx
    jae .channel_done
    mov eax, edx
.channel_done:
    cmp eax, 255
    jbe .clamped
    mov eax, 255
.clamped:
    shl eax, cl
    or edi, eax
    add ecx, 8
    cmp ecx, 24
    jb .channel
    ; alpha: as + ab - as ab / 255
    mov eax, r14d
    imul eax, r15d
    DIV255 eax
    mov edx, r14d
    add edx, r15d
    sub edx, eax
    shl edx, 24
    or edi, edx
    mov eax, edi
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; COMPOSITE: Porter-Duff on in (A) and in2 (B), or arithmetic
fe_composite:
    mov rdx, [rbx + FR_PRIM]
    cvttsd2si rax, qword [rdx + UgfxFe_p]
    mov [rbx + FR_T], eax
    lea rdi, [rel .pixel]
    cmp eax, 5
    jne fe_each
    lea rdi, [rel .arith]
    jmp fe_each
.pixel:
    ; A x fa + B x fb per channel (alpha too): over (1, 1 - aA), in (aB, 0),
    ; out (1 - aB, 0), atop (aB, 1 - aA), xor (1 - aB, 1 - aA)
    push rbx
    push r12
    push r13
    mov r12d, eax
    mov r13d, edx
    mov esi, [rbx + FR_T]
    mov r8d, eax
    shr r8d, 24                         ; aA
    mov r9d, edx
    shr r9d, 24                         ; aB
    ; fa
    mov eax, 255
    cmp esi, 1
    jne .fa_out
    mov eax, r9d
.fa_out:
    cmp esi, 2
    je .fa_inv
    cmp esi, 4
    jne .fa_atop
.fa_inv:
    mov eax, 255
    sub eax, r9d
.fa_atop:
    cmp esi, 3
    jne .fa_done
    mov eax, r9d
.fa_done:
    ; fb
    xor edx, edx
    cmp esi, 0
    je .fb_inv
    cmp esi, 3
    je .fb_inv
    cmp esi, 4
    jne .fb_done
.fb_inv:
    mov edx, 255
    sub edx, r8d
.fb_done:
    mov r8d, eax
    mov r9d, edx
    xor edi, edi
    xor ecx, ecx
.c_channel:
    mov eax, r12d
    shr eax, cl
    and eax, 255
    imul eax, r8d
    DIV255 eax
    mov edx, r13d
    shr edx, cl
    and edx, 255
    imul edx, r9d
    DIV255 edx
    add eax, edx
    cmp eax, 255
    jbe .c_clamped
    mov eax, 255
.c_clamped:
    shl eax, cl
    or edi, eax
    add ecx, 8
    cmp ecx, 32
    jb .c_channel
    mov eax, edi
    pop r13
    pop r12
    pop rbx
    ret
.arith:
    ; k1 i1 i2 + k2 i1 + k3 i2 + k4, per channel on [0, 1], colour <= alpha
    push r12
    push r13
    mov r12d, eax
    mov r13d, edx
    mov rsi, [rbx + FR_PRIM]
    xor edi, edi
    mov ecx, 24
.a_channel:
    mov eax, r12d
    shr eax, cl
    and eax, 255
    cvtsi2sd xmm0, eax
    divsd xmm0, [rel fe_255]            ; i1
    mov eax, r13d
    shr eax, cl
    and eax, 255
    cvtsi2sd xmm1, eax
    divsd xmm1, [rel fe_255]            ; i2
    movsd xmm2, [rsi + UgfxFe_p + 8]
    mulsd xmm2, xmm0
    mulsd xmm2, xmm1                    ; k1 i1 i2
    movsd xmm3, [rsi + UgfxFe_p + 16]
    mulsd xmm3, xmm0
    addsd xmm2, xmm3                    ; + k2 i1
    movsd xmm3, [rsi + UgfxFe_p + 24]
    mulsd xmm3, xmm1
    addsd xmm2, xmm3                    ; + k3 i2
    addsd xmm2, [rsi + UgfxFe_p + 32]   ; + k4
    movapd xmm0, xmm2
    call fe_byte
    cmp ecx, 24
    je .a_alpha
    cmp eax, r8d                        ; colour <= alpha
    jbe .a_set
    mov eax, r8d
    jmp .a_set
.a_alpha:
    mov r8d, eax
.a_set:
    shl eax, cl
    or edi, eax
    sub ecx, 8
    jns .a_channel
    mov eax, edi
    pop r13
    pop r12
    ret

; xmm0 = a value in [0, 1] (clamped) -> eax = (int)(v 255 + 0.5)
fe_byte:
    xorpd xmm1, xmm1
    maxsd xmm0, xmm1
    minsd xmm0, [rel fe_one]
    mulsd xmm0, [rel fe_255]
    addsd xmm0, [rel fe_half]
    cvttsd2si eax, xmm0
    ret

; COLORMATRIX: [r g b a 1] x the rows, unpremultiplied
fe_colormatrix:
    mov rdx, [rbx + FR_PRIM]
    cmp dword [rdx + UgfxFe_nvar], 20
    jb .identity
    lea rdi, [rel .pixel]
    jmp fe_each
.identity:
    lea rdi, [rel .copy]
    jmp fe_each
.copy:
    ret
.pixel:
    push r12
    push r13
    mov r12d, eax
    call fe_unpremul_px                 ; [rbx + FR_T]: r g b a in [0, 1]
    mov rsi, [rbx + FR_PRIM]
    mov rsi, [rsi + UgfxFe_var]
    xor r13d, r13d                      ; the row
.cm_row:
    imul rax, r13, 40
    movsd xmm0, [rsi + rax]
    mulsd xmm0, [rbx + FR_T]
    movsd xmm1, [rsi + rax + 8]
    mulsd xmm1, [rbx + FR_T + 8]
    addsd xmm0, xmm1
    movsd xmm1, [rsi + rax + 16]
    mulsd xmm1, [rbx + FR_T + 16]
    addsd xmm0, xmm1
    movsd xmm1, [rsi + rax + 24]
    mulsd xmm1, [rbx + FR_T + 24]
    addsd xmm0, xmm1
    addsd xmm0, [rsi + rax + 32]
    call fe_byte
    mov [rbx + FR_T + 32 + r13 * 4], eax
    inc r13d
    cmp r13d, 4
    jb .cm_row
    call fe_premul_out
    pop r13
    pop r12
    ret

; r12d = a premultiplied pixel -> [rbx + FR_T] = r, g, b, a in [0, 1]
;   (unpremultiplied by fe_unpremul)
fe_unpremul_px:
    mov r8d, r12d
    shr r8d, 24
    xor ecx, ecx                        ; 0 r, 1 g, 2 b
.channel:
    xor edx, edx
    test r8d, r8d
    jz .value
    mov eax, 16
    lea eax, [rcx * 8]
    neg eax
    add eax, 16                         ; shift: 16 r, 8 g, 0 b
    push rcx
    mov ecx, eax
    mov edx, r12d
    shr edx, cl
    pop rcx
    and edx, 255
    call fe_unpremul
.value:
    cvtsi2sd xmm0, edx
    divsd xmm0, [rel fe_255]
    movsd [rbx + FR_T + rcx * 8], xmm0
    inc ecx
    cmp ecx, 3
    jb .channel
    cvtsi2sd xmm0, r8d
    divsd xmm0, [rel fe_255]
    movsd [rbx + FR_T + 24], xmm0
    ret

; [rbx + FR_T + 32] = u32 r, g, b, a (straight bytes) -> eax = premultiplied
fe_premul_out:
    mov r8d, [rbx + FR_T + 44]          ; a
    mov eax, r8d
    shl eax, 24
    mov edx, [rbx + FR_T + 32]
    imul edx, r8d
    DIV255 edx
    shl edx, 16
    or eax, edx
    mov edx, [rbx + FR_T + 36]
    imul edx, r8d
    DIV255 edx
    shl edx, 8
    or eax, edx
    mov edx, [rbx + FR_T + 40]
    imul edx, r8d
    DIV255 edx
    or eax, edx
    ret

; TRANSFER: a table per channel (R G B A) from the functions, on
;   unpremultiplied values
fe_transfer:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rdx, [rbx + FR_PRIM]
    mov r12, [rdx + UgfxFe_var]
    mov r13d, [rdx + UgfxFe_nvar]
    lea r13, [r12 + r13 * 8]            ; the end
    xor r14d, r14d                      ; the channel
.func:
    cmp r14d, 4
    jae .apply
    ; type, slope, intercept, amplitude, exponent, offset, n, table
    lea rax, [r12 + 56]
    cmp rax, r13
    ja .identity_rest
    cvttsd2si r15, qword [r12 + 48]     ; n
    test r15, r15
    js .identity_rest
    lea rax, [r12 + 56 + r15 * 8]
    cmp rax, r13
    ja .identity_rest
    xor ecx, ecx
.entry:
    cmp ecx, 256
    jae .next_func
    push rcx
    sub rsp, 8
    cvtsi2sd xmm0, ecx
    divsd xmm0, [rel fe_255]            ; C
    mov rdi, r12
    call fe_func
    call fe_byte
    add rsp, 8
    pop rcx
    mov edx, r14d
    shl edx, 8
    add edx, ecx
    mov [rbx + FR_LUT + rdx], al
    inc ecx
    jmp .entry
.next_func:
    lea r12, [r12 + 56 + r15 * 8]
    inc r14d
    jmp .func
.identity_rest:
    ; missing functions: identity
    cmp r14d, 4
    jae .apply
    xor ecx, ecx
.id_entry:
    mov edx, r14d
    shl edx, 8
    add edx, ecx
    mov [rbx + FR_LUT + rdx], cl
    inc ecx
    cmp ecx, 256
    jb .id_entry
    inc r14d
    jmp .identity_rest
.apply:
    lea rdi, [rel .pixel]
    call fe_each
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.pixel:
    push r12
    mov r12d, eax
    mov r8d, eax
    shr r8d, 24
    xor ecx, ecx
.t_channel:
    ; r g b: unpremultiplied (0 where a = 0), through their tables
    xor edx, edx
    test r8d, r8d
    jz .t_value
    mov eax, 16
    lea eax, [rcx * 8]
    neg eax
    add eax, 16
    push rcx
    mov ecx, eax
    mov edx, r12d
    shr edx, cl
    pop rcx
    and edx, 255
    call fe_unpremul
.t_value:
    mov eax, ecx
    shl eax, 8
    add eax, edx
    movzx eax, byte [rbx + FR_LUT + rax]
    mov [rbx + FR_T + 32 + rcx * 4], eax
    inc ecx
    cmp ecx, 3
    jb .t_channel
    movzx eax, byte [rbx + FR_LUT + 3 * 256 + r8]
    mov [rbx + FR_T + 44], eax
    call fe_premul_out
    pop r12
    ret

; rdi = a function (type, slope, intercept, amplitude, exponent, offset, n,
;   table), xmm0 = C in [0, 1] -> xmm0 = its value (unclamped)
fe_func:
    push r12
    push r13
    sub rsp, 24
    mov r12, rdi
    movsd [rsp], xmm0
    cvttsd2si eax, qword [r12]
    cvttsd2si r13, qword [r12 + 48]     ; n
    cmp eax, 1
    je .table
    cmp eax, 2
    je .discrete
    cmp eax, 3
    je .linear
    cmp eax, 4
    je .gamma
    jmp .out                            ; identity
.table:
    test r13, r13
    jz .out
    ; k = floor(C (n - 1)); v_k + (C (n - 1) - k)(v_k+1 - v_k)
    lea rax, [r13 - 1]
    cvtsi2sd xmm1, rax
    mulsd xmm1, xmm0
    cvttsd2si rcx, xmm1
    cmp rcx, rax
    jl .between
    movsd xmm0, [r12 + 56 + rax * 8]
    jmp .out
.between:
    cvtsi2sd xmm2, rcx
    subsd xmm1, xmm2
    movsd xmm2, [r12 + 64 + rcx * 8]
    subsd xmm2, [r12 + 56 + rcx * 8]
    mulsd xmm1, xmm2
    movsd xmm0, [r12 + 56 + rcx * 8]
    addsd xmm0, xmm1
    jmp .out
.discrete:
    test r13, r13
    jz .out
    cvtsi2sd xmm1, r13
    mulsd xmm1, xmm0
    cvttsd2si rcx, xmm1
    cmp rcx, r13
    jl .step
    lea rcx, [r13 - 1]
.step:
    movsd xmm0, [r12 + 56 + rcx * 8]
    jmp .out
.linear:
    mulsd xmm0, [r12 + 8]
    addsd xmm0, [r12 + 16]
    jmp .out
.gamma:
    movsd xmm1, [r12 + 32]
    call umath_pow_f64
    mulsd xmm0, [r12 + 24]
    addsd xmm0, [r12 + 40]
.out:
    add rsp, 24
    pop r13
    pop r12
    ret

; MORPHOLOGY: erode (min) / dilate (max) over (2 rx + 1) x (2 ry + 1);
;   outside the region counts as transparent
fe_morphology:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rdx, [rbx + FR_PRIM]
    cvtsd2si rax, qword [rdx + UgfxFe_p + 8]
    mov [rbx + FR_T], rax               ; rx
    cvtsd2si rax, qword [rdx + UgfxFe_p + 16]
    mov [rbx + FR_T + 8], rax           ; ry
    cvttsd2si rax, qword [rdx + UgfxFe_p]
    mov [rbx + FR_T + 16], rax          ; 1 dilate
    cmp qword [rbx + FR_T], 0
    jle .through
    cmp qword [rbx + FR_T + 8], 0
    jle .through
    lea rdi, [rel .pixel]
    call fe_each
    jmp .out
.through:
    lea rdi, [rel .copy]
    call fe_each
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret
.copy:
    ret
.pixel:
    ; r14 = x, r12 = y: each channel's min / max over the window
    push r13
    push r14
    push r15
    push rbx
    sub rsp, 8
    mov r15, [rbx + FR_T + 16]
    xor edi, edi                        ; result
    mov ecx, 0
.m_channel:
    ; start: 255 for erode, 0 for dilate
    xor esi, esi
    test r15, r15
    jnz .m_start
    mov esi, 255
.m_start:
    mov r10, r12
    sub r10, [rbx + FR_T + 8]           ; y from
.m_y:
    mov rax, r12
    add rax, [rbx + FR_T + 8]
    cmp r10, rax
    jg .m_done
    mov r11, r14
    sub r11, [rbx + FR_T]               ; x from
.m_x:
    mov rax, r14
    add rax, [rbx + FR_T]
    cmp r11, rax
    jg .m_next_y
    ; the value there (0 outside the region)
    xor eax, eax
    movsxd rdx, dword [rbx + FR_R]
    cmp r11, rdx
    jl .m_have
    movsxd rdx, dword [rbx + FR_R + 8]
    cmp r11, rdx
    jge .m_have
    movsxd rdx, dword [rbx + FR_R + 4]
    cmp r10, rdx
    jl .m_have
    movsxd rdx, dword [rbx + FR_R + 12]
    cmp r10, rdx
    jge .m_have
    mov rdx, [rbx + FR_IN1]
    mov r9, r10
    imul r9, [rdx + PixBuf_stride]
    add r9, [rdx + PixBuf_data]
    mov eax, [r9 + r11 * 4]
    shr eax, cl
    and eax, 255
.m_have:
    test r15, r15
    jnz .m_max
    cmp eax, esi
    jae .m_step
    mov esi, eax
    jmp .m_step
.m_max:
    cmp eax, esi
    jbe .m_step
    mov esi, eax
.m_step:
    inc r11
    jmp .m_x
.m_next_y:
    inc r10
    jmp .m_y
.m_done:
    shl esi, cl
    or edi, esi
    add ecx, 8
    cmp ecx, 32
    jb .m_channel
    mov eax, edi
    add rsp, 8
    pop rbx
    pop r15
    pop r14
    pop r13
    ret

; TILE: in1's subregion repeated over this one
fe_tile:
    ; in1's own subregion (the region for a source)
    mov rdx, [rbx + FR_PRIM]
    mov eax, [rdx + UgfxFe_in1]
    lea rsi, [rbx + FR_R]
    test eax, eax
    js .have
    mov rcx, [rbx + FR_F]
    imul rax, rax, UgfxFe_SIZE
    add rax, [rcx + UgfxFilter_prims]
    lea rsi, [rax + UgfxFe_sub]
.have:
    lea rdi, [rbx + FR_T + 32]
    push rsi
    call fe_clamp_sub
    pop rsi
    movsxd rax, dword [rbx + FR_T + 40]
    movsxd rcx, dword [rbx + FR_T + 32]
    sub rax, rcx
    jle .empty
    mov [rbx + FR_T], rax               ; tile w
    movsxd rax, dword [rbx + FR_T + 44]
    movsxd rcx, dword [rbx + FR_T + 36]
    sub rax, rcx
    jle .empty
    mov [rbx + FR_T + 8], rax           ; tile h
    lea rdi, [rel .pixel]
    jmp fe_each
.empty:
    xor eax, eax
    ret
.pixel:
    ; x' = x0 + (x - x0) mod w (a non-negative remainder), the same for y
    movsxd rcx, dword [rbx + FR_T + 32]
    mov rax, r14
    sub rax, rcx
    cqo
    idiv qword [rbx + FR_T]
    test rdx, rdx
    jns .x_mod
    add rdx, [rbx + FR_T]
.x_mod:
    add rdx, rcx
    mov r8, rdx
    movsxd rcx, dword [rbx + FR_T + 36]
    mov rax, r12
    sub rax, rcx
    cqo
    idiv qword [rbx + FR_T + 8]
    test rdx, rdx
    jns .y_mod
    add rdx, [rbx + FR_T + 8]
.y_mod:
    add rdx, rcx
    mov rcx, rdx
    mov rax, r8
    jmp fe_at_in1

; BLUR: box passes over the region (out and the blur slot), then cut to the
;   subregion
fe_blur:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    ; out = in1 over the whole region (the subregion is kept aside)
    mov rax, [rbx + FR_SUB]
    mov [rbx + FR_T + 48], rax
    mov rax, [rbx + FR_SUB + 8]
    mov [rbx + FR_T + 56], rax
    mov rax, [rbx + FR_R]
    mov [rbx + FR_SUB], rax
    mov rax, [rbx + FR_R + 8]
    mov [rbx + FR_SUB + 8], rax
    lea rdi, [rel .copy]
    call fe_each
    ; x, then y
    xor r15d, r15d
.axis:
    cmp r15d, 2
    jae .cut
    mov rdx, [rbx + FR_PRIM]
    movsd xmm0, [rdx + UgfxFe_p + r15 * 8]
    xorpd xmm1, xmm1
    ucomisd xmm0, xmm1
    jbe .next_axis                      ; (NaN too)
    mulsd xmm0, [rel fe_blur_k]
    addsd xmm0, [rel fe_half]
    minsd xmm0, [rel fe_max_box]
    cvttsd2si r12, xmm0                 ; d
    cmp r12, 2
    jl .next_axis
    mov r13, r12
    shr r13, 1
    test r12, 1
    jz .even
    ; odd: three centred boxes of d
    mov r14d, 3
.odd_pass:
    mov rsi, r13
    mov rdx, r13
    mov rcx, r12
    call .pass
    dec r14d
    jnz .odd_pass
    jmp .next_axis
.even:
    ; d / 2 left, d / 2 right, then d + 1 centred
    mov rsi, r13
    lea rdx, [r13 - 1]
    mov rcx, r12
    call .pass
    lea rsi, [r13 - 1]
    mov rdx, r13
    mov rcx, r12
    call .pass
    mov rsi, r13
    mov rdx, r13
    lea rcx, [r12 + 1]
    call .pass
.next_axis:
    inc r15d
    jmp .axis
.cut:
    mov rax, [rbx + FR_T + 48]
    mov [rbx + FR_SUB], rax
    mov rax, [rbx + FR_T + 56]
    mov [rbx + FR_SUB + 8], rax
    call fe_cut
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    xor eax, eax
    ret
.copy:
    ret
; one box along r15's axis: rsi = lo, rdx = hi (the window i - lo .. i +
;   hi), rcx = d (the divisor); out -> the blur slot, then copied back
.pass:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    mov [rsp], rsi
    mov [rsp + 8], rdx
    mov [rsp + 16], rcx
    ; the axis: inner steps along it, outer across
    mov rdi, [rbx + FR_OUT]
    mov rax, [rbx + FR_POOL]
    mov r8, [rax + FS_BLUR * 8]
    mov [rsp + 24], r8                  ; dst
    test r15d, r15d
    jnz .vertical
    mov rax, [rdi + PixBuf_stride]
    mov [rsp + 32], rax                 ; outer step (bytes)
    mov qword [rsp + 40], 4             ; inner step
    movsxd rax, dword [rbx + FR_R + 4]
    mov [rsp + 48], rax                 ; outer from
    movsxd rax, dword [rbx + FR_R + 12]
    mov [rsp + 56], rax                 ; outer to
    movsxd r14, dword [rbx + FR_R]      ; inner from
    movsxd r15, dword [rbx + FR_R + 8]  ; inner to
    jmp .lines
.vertical:
    mov qword [rsp + 32], 4
    mov rax, [rdi + PixBuf_stride]
    mov [rsp + 40], rax
    movsxd rax, dword [rbx + FR_R]
    mov [rsp + 48], rax
    movsxd rax, dword [rbx + FR_R + 8]
    mov [rsp + 56], rax
    movsxd r14, dword [rbx + FR_R + 4]
    movsxd r15, dword [rbx + FR_R + 12]
.lines:
    mov r12, [rsp + 48]
.line:
    cmp r12, [rsp + 56]
    jge .copy_back
    ; the line's base in src and dst
    mov rdi, [rbx + FR_OUT]
    mov rax, r12
    imul rax, [rsp + 32]
    mov r13, [rdi + PixBuf_data]
    add r13, rax                        ; src base
    mov rdi, [rsp + 24]
    mov rcx, [rdi + PixBuf_data]
    add rcx, rax
    mov [rsp + 64], rcx                 ; dst base
    ; sums of the window at the first position: k in [from - lo, from + hi]
    pxor xmm4, xmm4                     ; four u32 channel sums
    mov rcx, r14
    sub rcx, [rsp]
.init:
    mov rax, r14
    add rax, [rsp + 8]
    cmp rcx, rax
    jg .slide
    cmp rcx, r14
    jl .init_next
    cmp rcx, r15
    jge .init_next
    call .add_at
.init_next:
    inc rcx
    jmp .init
.slide:
    mov r11, r14                        ; i
.step:
    cmp r11, r15
    jge .next_line
    ; dst[i] = (sum + d / 2) / d per channel
    movd eax, xmm4
    call .channel_div
    mov r8d, eax
    pshufd xmm5, xmm4, 0x39
    movd eax, xmm5
    call .channel_div
    shl eax, 8
    or r8d, eax
    pshufd xmm5, xmm4, 0x4E
    movd eax, xmm5
    call .channel_div
    shl eax, 16
    or r8d, eax
    pshufd xmm5, xmm4, 0x93
    movd eax, xmm5
    call .channel_div
    shl eax, 24
    or r8d, eax
    mov rax, r11
    imul rax, [rsp + 40]
    add rax, [rsp + 64]
    mov [rax], r8d
    ; slide: add i + hi + 1, remove i - lo
    mov rcx, r11
    add rcx, [rsp + 8]
    inc rcx
    cmp rcx, r15
    jge .no_add
    call .add_at
.no_add:
    mov rcx, r11
    sub rcx, [rsp]
    cmp rcx, r14
    jl .no_sub
    call .sub_at
.no_sub:
    inc r11
    jmp .step
.next_line:
    inc r12
    jmp .line
.copy_back:
    ; the blur slot back into out, over the region
    mov rsi, [rsp + 24]
    mov rdi, [rbx + FR_OUT]
    movsxd r12, dword [rbx + FR_R + 4]
.back_row:
    movsxd rax, dword [rbx + FR_R + 12]
    cmp r12, rax
    jge .pass_done
    ROW r8, rsi, r12
    ROW r9, rdi, r12
    movsxd rcx, dword [rbx + FR_R]
.back_px:
    movsxd rax, dword [rbx + FR_R + 8]
    cmp rcx, rax
    jge .back_next
    mov eax, [r8 + rcx * 4]
    mov [r9 + rcx * 4], eax
    inc rcx
    jmp .back_px
.back_next:
    inc r12
    jmp .back_row
.pass_done:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    ret
; rcx = an index on the line -> its pixel's channels added to / taken from
;   xmm4 (.pass's frame at rsp + 8)
.add_at:
    mov rax, rcx
    imul rax, [rsp + 8 + 40]
    movd xmm5, [r13 + rax]
    pxor xmm6, xmm6
    punpcklbw xmm5, xmm6
    punpcklwd xmm5, xmm6
    paddd xmm4, xmm5
    ret
.sub_at:
    mov rax, rcx
    imul rax, [rsp + 8 + 40]
    movd xmm5, [r13 + rax]
    pxor xmm6, xmm6
    punpcklbw xmm5, xmm6
    punpcklwd xmm5, xmm6
    psubd xmm4, xmm5
    ret
; eax = a channel's sum -> eax = (sum + d / 2) / d (d at the .pass frame)
.channel_div:
    push rdx
    push rcx
    mov rcx, [rsp + 16 + 8 + 16]        ; d
    mov rdx, rcx
    shr rdx, 1
    add eax, edx
    xor edx, edx
    div ecx
    pop rcx
    pop rdx
    ret

; rbx = frame: out cleared inside the region but outside the subregion
fe_cut:
    push r12
    mov rdi, [rbx + FR_OUT]
    movsxd r12, dword [rbx + FR_R + 4]
.row:
    movsxd rax, dword [rbx + FR_R + 12]
    cmp r12, rax
    jge .done
    ROW r8, rdi, r12
    movsxd rcx, dword [rbx + FR_R]
.px:
    movsxd rax, dword [rbx + FR_R + 8]
    cmp rcx, rax
    jge .next
    movsxd rax, dword [rbx + FR_SUB + 4]
    cmp r12, rax
    jl .clear
    movsxd rax, dword [rbx + FR_SUB + 12]
    cmp r12, rax
    jge .clear
    movsxd rax, dword [rbx + FR_SUB]
    cmp rcx, rax
    jl .clear
    movsxd rax, dword [rbx + FR_SUB + 8]
    cmp rcx, rax
    jl .keep
.clear:
    mov dword [r8 + rcx * 4], 0
.keep:
    inc rcx
    jmp .px
.next:
    inc r12
    jmp .row
.done:
    pop r12
    ret

section .rodata
align 8
fe_ops:
    dq fe_flood, fe_offset, fe_blur, fe_merge, fe_blend
    dq fe_composite, fe_colormatrix, fe_transfer, fe_morphology, fe_tile

section .data
global ugfx_filter_version
ugfx_filter_version: dq 0x010000
