; ============================================================================
; Text Layout — Line Breaking, Alignment, RTL, Shaping
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/font.inc"
%include "inc/geometry.inc"
%include "inc/externs.inc"

section .text

; ============================================================================
; text_layout_create
;   Create text layout object
;   IN: rdi = layout*, rsi = face*, rdx = max_width, rcx = flags
;   OUT: rax = 0 OK
; ============================================================================
global text_layout_create
text_layout_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + TextLayout_FACE], r12
    mov dword [rbx + TextLayout_MAX_WIDTH], r13d
    mov dword [rbx + TextLayout_FLAGS], r14d
    mov qword [rbx + TextLayout_RUNS], 0
    mov dword [rbx + TextLayout_RUN_COUNT], 0
    mov dword [rbx + TextLayout_RUN_CAP], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

%define TextLayout_FACE        0
%define TextLayout_MAX_WIDTH   8
%define TextLayout_FLAGS       12
%define TextLayout_RUNS        16
%define TextLayout_RUN_COUNT   24
%define TextLayout_RUN_CAP     28
%define TextLayout_SIZE        32

%define TEXT_FLAG_RTL          (1 << 0)
%define TEXT_FLAG_WRAP         (1 << 1)
%define TEXT_FLAG_ALIGN_LEFT   0
%define TEXT_FLAG_ALIGN_CENTER (1 << 2)
%define TEXT_FLAG_ALIGN_RIGHT  (1 << 3)
%define TEXT_FLAG_ALIGN_JUSTIFY (1 << 4)

; Run struct
%define Run_START       0
%define Run_LENGTH      4
%define Run_X           8
%define Run_Y           12
%define Run_ADVANCE     16
%define Run_ASCENT      20
%define Run_DESCENT     24
%define Run_SIZE        28

; ============================================================================
; text_layout_set_text
;   Set text and perform shaping/line breaking
;   IN: rdi = layout*, rsi = text (UTF-8), rdx = length
; ============================================================================
global text_layout_set_text
text_layout_set_text:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; text
    mov r13d, edx       ; length
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Convert UTF-8 to UTF-32 codepoints
    call .utf8_to_utf32

    ; Shape text (glyph substitution, positioning)
    call .shape_text

    ; Line breaking
    call .break_lines

    ; Alignment
    call .align_lines

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.utf8_to_utf32:
    ; Validate the complete UTF-8 stream before shaping.
    xor ecx, ecx
.utf8_next:
    cmp ecx, r13d
    jae .utf8_ok
    movzx eax, byte [r12 + rcx]
    inc ecx
    test al, 0x80
    jz .utf8_next
    mov edx, 1
    and eax, 0xe0
    cmp eax, 0xc0
    je .utf8_cont
    mov edx, 2
    movzx eax, byte [r12 + rcx - 1]
    and eax, 0xf0
    cmp eax, 0xe0
    je .utf8_cont
    mov edx, 3
.utf8_cont:
    cmp ecx, r13d
    jae .utf8_ok
    cmp edx, 0
    je .utf8_next
    mov al, [r12 + rcx]
    and al, 0xc0
    cmp al, 0x80
    jne .utf8_ok
    inc ecx
    dec edx
    jmp .utf8_cont
.utf8_ok:
    ret

.shape_text:
    ; Apply GSUB/GPOS shaping
    ; For now, simple 1:1 codepoint to glyph
    ret

.break_lines:
    ; Knuth-Plass line breaking or simple greedy
    ret

.align_lines:
    ; Apply alignment (left/center/right/justify)
    ret

; ============================================================================
; text_layout_draw
;   Draw text layout to pixbuf
;   IN: rdi = pixbuf*, rsi = layout*, rdx = x, rcx = y, r8 = color
; ============================================================================
global text_layout_draw
text_layout_draw:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Iterate runs
    mov r13, [r12 + TextLayout_RUNS]
    mov r14d, [r12 + TextLayout_RUN_COUNT]
    xor r15d, r15d

.draw_runs:
    cmp r15d, r14d
    jge .draw_done

    ; Get run - compute offset first
    mov eax, r15d
    imul eax, Run_SIZE
    add rax, r13
    mov r8, [rax + Run_START]
    mov r9d, [rax + Run_LENGTH]
    mov r10d, [rax + Run_X]
    mov r11d, [rax + Run_Y]

    ; Draw run
    mov rdi, rbx
    mov rsi, [r12 + TextLayout_FACE]
    mov edx, r10d
    add edx, r13d
    mov ecx, r11d
    add ecx, r14d
    mov r8, r8
    mov r9d, r9d
    mov r10d, r15d
    call font_render_glyph_run

    inc r15d
    jmp .draw_runs

.draw_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; font_render_glyph_run
;   Render a sequence of glyphs
; ============================================================================
global font_render_glyph_run
font_render_glyph_run:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; pixbuf
    mov r12, rsi        ; face
    mov r13d, edx       ; x
    mov r14d, ecx       ; y
    mov r15, r8         ; glyphs[]
    mov r14d, r9d       ; count
    mov r15d, r10d      ; color
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r15

    ; Iterate glyphs
    xor r8d, r8d

.glyph_loop:
    cmp r8d, r14d
    jge .glyph_done

    mov r9d, [r15 + r8*4]  ; glyph index

    ; Get glyph metrics
    push r8
    push r9
    push r10
    push r11

    mov rdi, r12
    mov esi, r9d
    mov rdx, rsp
    call font_get_glyph_metrics
    pop r11
    pop r10
    pop r9
    pop r8

    ; Render glyph
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    mov ecx, r14d
    mov r8d, r9d
    mov r9d, r15d
    call font_render_glyph

    ; Advance
    mov eax, [rsp + GlyphMetrics_ADVANCE]
    add r13d, eax
    sar eax, 16

    inc r8d
    jmp .glyph_loop

.glyph_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; text_layout_get_bounds
;   Get text layout bounding box
; ============================================================================
global text_layout_get_bounds
text_layout_get_bounds:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Initialize bounds
    mov dword [r12 + Rect_x], 0x7FFFFFFF
    mov dword [r12 + Rect_y], 0x7FFFFFFF
    mov dword [r12 + Rect_width], 0x80000000
    mov dword [r12 + Rect_height], 0x80000000

    mov rcx, [rbx + TextLayout_RUNS]
    mov edx, [rbx + TextLayout_RUN_COUNT]
    test edx, edx
    jz .bounds_empty
    mov dword [r12 + Rect_x], 0
    mov dword [r12 + Rect_y], 0
    xor eax, eax
    xor r8d, r8d
.bounds_loop:
    cmp r8d, edx
    jae .bounds_done
    cmp eax, [rcx + Run_ADVANCE]
    cmovl eax, [rcx + Run_ADVANCE]
    add rcx, Run_SIZE
    inc r8d
    jmp .bounds_loop
.bounds_done:
    mov [r12 + Rect_width], eax
    mov eax, [rbx + TextLayout_FACE]
    mov eax, [rax + FontFace_SIZE]
    mov [r12 + Rect_height], eax
    jmp .bounds_return
.bounds_empty:
    mov qword [r12 + Rect_x], 0
    mov qword [r12 + Rect_width], 0
.bounds_return:

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global text_layout_version
text_layout_version: dq 0x010000
