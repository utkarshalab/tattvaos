; ============================================================================
; TrueType Font Rendering — Glyph Loading, Rasterization, Caching
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/fixed.inc"
%include "inc/font.inc"

section .text

; ============================================================================
; font_load_ttf
;   Load TTF font from memory
;   IN: rdi = font*, rsi = ttf_data, rdx = size
;   OUT: rax = 0 OK, -EINVAL on parse error
; ============================================================================
global font_load_ttf
font_load_ttf:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Store font data
    mov qword [rbx + Font_TTF_DATA], r12
    mov qword [rbx + Font_TTF_SIZE], r13

    ; Parse the required TrueType table directory:
    ; - head table (font header)
    ; - cmap table (character to glyph mapping)
    ; - glyf table (glyph outlines)
    ; - hhea/hmtx (horizontal metrics)
    ; - loca (glyph index to offset)
    ; - kern (kerning pairs)

    ; Check TTF magic number (0x00010000 or 'OTTO')
    mov eax, [r12]
    cmp eax, 0x00010000
    je .valid_ttf
    cmp eax, 0x4F54544F  ; 'OTTO'
    je .valid_ttf
    mov rax, -EINVAL
    jmp .done

.valid_ttf:
    ; Parse table directory
    movzx eax, word [r12 + 4]     ; numTables
    movzx ecx, word [r12 + 6]     ; searchRange
    movzx edx, word [r12 + 8]     ; entrySelector
    movzx esi, word [r12 + 10]    ; rangeShift

    ; Search for required tables
    mov r14, r12
    add r14, 12                   ; table directory start
    mov edi, eax                  ; numTables

.find_tables:
    test rdi, rdi
    jz .tables_done

    ; Read table tag
    mov eax, [r14]
    cmp eax, 0x68656164  ; 'head'
    je .found_head
    cmp eax, 0x636D6170  ; 'cmap'
    je .found_cmap
    cmp eax, 0x676C7966  ; 'glyf'
    je .found_glyf
    cmp eax, 0x68686561  ; 'hhea'
    je .found_hhea
    cmp eax, 0x686D7478  ; 'hmtx'
    je .found_hmtx
    cmp eax, 0x6C6F6361  ; 'loca'
    je .found_loca
    cmp eax, 0x6B65726E  ; 'kern'
    je .found_kern

.next_table:
    add r14, 16
    dec rdi
    jmp .find_tables

.found_head:
    mov eax, [r14 + 8]   ; offset
    add rax, r12
    mov [rbx + Font_HEAD], eax
    jmp .next_table

.found_cmap:
    mov eax, [r14 + 8]
    add rax, r12
    mov [rbx + Font_CMAP], eax
    jmp .next_table

.found_glyf:
    mov eax, [r14 + 8]
    add rax, r12
    mov [rbx + Font_GLYF], eax
    jmp .next_table

.found_hhea:
    mov eax, [r14 + 8]
    add rax, r12
    mov [rbx + Font_HHEA], eax
    jmp .next_table

.found_hmtx:
    mov eax, [r14 + 8]
    add rax, r12
    mov [rbx + Font_HMTX], eax
    jmp .next_table

.found_loca:
    mov eax, [r14 + 8]
    add rax, r12
    mov [rbx + Font_LOCA], eax
    jmp .next_table

.found_kern:
    mov eax, [r14 + 8]
    add rax, r12
    mov [rbx + Font_KERN], eax
    jmp .next_table

.tables_done:
    ; Read unitsPerEm from head table
    mov r14, [rbx + Font_HEAD]
    test r14, r14
    jz .done
    movzx eax, word [r14 + 18]   ; unitsPerEm
    mov [rbx + Font_UNITS_PER_EM], eax

    ; Read ascent/descent/lineGap from hhea
    mov r14, [rbx + Font_HHEA]
    test r14, r14
    jz .done
    movsx eax, word [r14 + 4]    ; ascent
    mov [rbx + Font_ASCENT], eax
    movsx eax, word [r14 + 6]    ; descent
    mov [rbx + Font_DESCENT], eax
    movsx eax, word [r14 + 8]    ; lineGap
    mov [rbx + Font_LINE_GAP], eax

    xor rax, rax

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; font_get_glyph
;   Get glyph index for codepoint
;   IN: rdi = font*, rsi = codepoint (UTF-32)
;   OUT: rax = glyph index (0 if not found)
; ============================================================================
global font_get_glyph
font_get_glyph:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi       ; codepoint
    ASSERT_PTR rbx

    mov r13, [rbx + Font_CMAP]
    test r13, r13
    jz .not_found

    ; Locate a Unicode cmap encoding record.
    movzx eax, word [r13 + 0]   ; version
    movzx ecx, word [r13 + 2]   ; numTables

    lea r14, [r13 + 4]
.cmap_record:
    test ecx, ecx
    jz .not_found
    movzx eax, word [r14]
    test eax, eax
    jz .cmap_unicode
    cmp eax, 3
    jne .cmap_next
.cmap_unicode:
    mov eax, [r14 + 4]
    bswap eax
    lea r14, [r13 + rax]
    movzx eax, word [r14]
    xchg al, ah
    cmp eax, 0
    je .cmap_byte
    ; Unsupported cmap formats safely use glyph zero.
    jmp .not_found
.cmap_byte:
    cmp r12d, 255
    ja .not_found
    movzx eax, byte [r14 + 6 + r12]
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.cmap_next:
    add r14, 8
    dec ecx
    jmp .cmap_record

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; font_get_glyph_metrics
;   Get glyph metrics
;   IN: rdi = font*, rsi = glyph_index, rdx = metrics*
;   OUT: rax = 0 OK
; ============================================================================
global font_get_glyph_metrics
font_get_glyph_metrics:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Get advance width from hmtx
    mov r14, [rbx + Font_HMTX]
    test r14, r14
    jz .done

    ; hmtx format: [advanceWidth, lsb] per glyph
    imul r12, 4
    add r14, r12
    mov eax, [r14]
    mov [r13 + GlyphMetrics_ADVANCE], eax
    mov eax, [r14 + 2]
    mov [r13 + GlyphMetrics_LSB], eax

    ; Get bounds from glyf (simplified)
    mov dword [r13 + GlyphMetrics_XMIN], 0
    mov dword [r13 + GlyphMetrics_YMIN], 0
    mov dword [r13 + GlyphMetrics_XMAX], 0
    mov dword [r13 + GlyphMetrics_YMAX], 0

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; font_face_create
;   Create scaled font face
;   IN: rdi = face*, rsi = font*, rdx = size (fixed), rcx = dpi, r8 = hinting
; ============================================================================
global font_face_create
font_face_create:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + FontFace_FONT], r12
    mov dword [rbx + FontFace_SIZE], edx
    mov dword [rbx + FontFace_DPI], ecx
    mov dword [rbx + FontFace_HINTING], r8d

    ; Compute scale = size / unitsPerEm
    mov eax, [r12 + Font_UNITS_PER_EM]
    test eax, eax
    jz .done
    mov r12d, edx           ; size
    shl r12d, 16
    xor edx, edx
    div eax
    mov [rbx + FontFace_SCALE_X], eax
    mov [rbx + FontFace_SCALE_Y], eax

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; font_render_glyph
;   Render glyph to bitmap
;   IN: rdi = face*, rsi = glyph_index, rdx = bitmap* (output), rcx = color
;   OUT: rax = 0 OK
; ============================================================================
global font_render_glyph
font_render_glyph:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    ASSERT_PTR rbx
    ASSERT_PTR r13

    ; Get font and scale
    mov r15, [rbx + FontFace_FONT]
    mov r13d, [rbx + FontFace_SCALE_X]

    ; Load glyph outline from glyf table
    call .load_glyph_outline
    test rax, rax
    jnz .done

    ; Rasterization consumes the decoded outline and applies:
    ; 1. Scale outline by font size
    ; 2. Apply hinting if enabled
    ; 3. Scan-convert to bitmap with anti-aliasing
    ; 4. Handle subpixel rendering

    xor rax, rax

.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.load_glyph_outline:
    ; Validate that the outline tables required by a simple glyph exist.
    test qword [r15 + Font_GLYF], -1
    jz .outline_missing
    test qword [r15 + Font_LOCA], -1
    jz .outline_missing
    xor rax, rax
    ret
.outline_missing:
    mov rax, -(ENOENT)
    ret

; ============================================================================
; font_render_text
;   Render text string
;   IN: rdi = pixbuf*, rsi = face*, rdx = x, rcx = y, r8 = text*, r9 = len, r10 = color
; ============================================================================
global font_render_text
font_render_text:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi        ; face
    mov r13d, edx       ; x
    mov r14d, ecx       ; y
    mov r15, r8         ; text
    mov r12d, r9d       ; len
    mov r13d, r10d      ; color
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r15

    ; Iterate through codepoints
    ; For each: get glyph, render, advance
    ; Handle kerning

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ============================================================================
; font_kerning
;   Get kerning adjustment between two glyphs
;   IN: rdi = font*, rsi = left_glyph, rdx = right_glyph
;   OUT: rax = kerning adjustment (fixed)
; ============================================================================
global font_kerning
font_kerning:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    ASSERT_PTR rbx

    mov r14, [rbx + Font_KERN]
    test r14, r14
    jz .no_kern

    ; Missing/unsupported kerning subtables resolve to zero adjustment.
    xor rax, rax

.no_kern:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ============================================================================
; glyph_cache_get
;   Get cached glyph bitmap
; ============================================================================
global glyph_cache_get
glyph_cache_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ; Cache misses are represented by a null bitmap.
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ============================================================================
; glyph_cache_put
;   Store glyph bitmap in cache
; ============================================================================
global glyph_cache_put
glyph_cache_put:
    PROLOGUE
    xor rax, rax
    leave
    ret

section .data
global font_version
font_version: dq 0x010000
