; =============================================================================
; Utkarsha OS — lib/ufont/sfnt/sfnt.asm
; =============================================================================
; TrueType fonts (glyf outlines): reading them for drawing text through
; lib/ugfx paths.
;
;   ufont_open(arena, data, length)         -> UfontFont* or 0
;   ufont_glyph(font, code point)           -> glyph id (0: none)
;   ufont_advance(font, glyph)              -> advance width (font units)
;   ufont_metrics(font)                     -> units per em, ascent, descent
;   ufont_extents(font, glyph)              -> its box (bearing from hmtx); 0 without glyf
;   ufont_outline(font, glyph, path, scale, arena)
;                                           -> 0, -EINVAL, -ENOMEM
;       (outlines are kept per font once decoded: a glyph's contours in
;       font units, replayed at any scale; not shared between threads)
;
; A font is the file's bytes as they are (kept by the caller) and an index
; of its tables; every table, glyph and offset is checked against the data
; before it is read. cmap: format 12 (Unicode full repertoire) when there
; is one, else format 4 (Unicode BMP); platform 3 encodings 10 / 1 and
; platform 0. Metrics: hhea ascender / descender. Outlines: simple glyphs
; (quadratic contours, implied on-curve points between off-curve ones)
; and composite glyphs (x / y offsets, a scale, x and y scales or a 2 x 2
; matrix in F2Dot14, scaled offsets when the flag asks; components placed
; by matching points are taken at offset 0), nested 6 deep at most. The
; outline goes into a ugfx path at scale (pixels per font unit), y down,
; the origin on the baseline. Hinting instructions are not run.
; =============================================================================

%include "ugfx.inc"
%include "ufont.inc"

extern arena_alloc
extern ugfx_path_init
extern ugfx_path_move_to
extern ugfx_path_line_to
extern ugfx_path_quad_to
extern ugfx_path_close
extern umath_affine2_multiply

%define UFONT_MAX_DEPTH  6
%define UFONT_MAX_POINTS 16384

section .rodata
align 8
sf_half:            dq 0.5
sf_one:             dq 1.0
sf_f2dot14:         dq 0x3F10000000000000   ; 1 / 16384
sf_identity:        dq 1.0, 0.0, 0.0, 1.0, 0.0, 0.0

section .text

; a big-endian u16, zero-extended
%macro BE16 2                           ; %1 = 32-bit reg, %2 = address
    movzx %1, word %2
    bswap %1
    shr %1, 16
%endmacro

; ----------------------------------------------------------------------------
; ufont_open — rdi = arena, rsi = data, rdx = length -> rax = UfontFont* (0:
;   not a TrueType font with glyf outlines, damaged, or out of memory)
; ----------------------------------------------------------------------------
global ufont_open
ufont_open:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r15, rdi                        ; arena
    mov r12, rsi                        ; data
    mov r13, rdx                        ; length
    cmp r13, 12
    jb .bad
    mov eax, [r12]
    cmp eax, 0x00000100                 ; 00 01 00 00
    je .version
    cmp eax, 'true'
    jne .bad
.version:
    mov rdi, r15
    mov esi, UfontFont_SIZE
    call arena_alloc
    test rax, rax
    jz .bad
    mov rbx, rax
    mov rdi, rbx
    xor eax, eax
    mov ecx, UfontFont_SIZE
    rep stosb
    mov [rbx + UfontFont_data], r12
    mov [rbx + UfontFont_len], r13
    mov [rbx + UfontFont_arena], r15
    ; the table directory
    BE16 r14d, [r12 + 4]                ; numTables
    lea rax, [r14 * 8]
    lea rax, [rax * 2 + 12]
    cmp rax, r13
    ja .bad
    lea r15, [r12 + 12]
.table:
    test r14d, r14d
    jz .tables_done
    dec r14d
    mov eax, [r15 + 8]
    bswap eax                           ; offset
    mov ecx, [r15 + 12]
    bswap ecx                           ; length
    lea rdx, [rax + rcx]
    cmp rdx, r13
    ja .next_table                      ; out of the file: as if absent
    lea rdx, [r12 + rax]                ; the table
    mov eax, [r15]
    cmp eax, 'head'
    je .head
    cmp eax, 'maxp'
    je .maxp
    cmp eax, 'hhea'
    je .hhea
    cmp eax, 'hmtx'
    je .hmtx
    cmp eax, 'loca'
    je .loca
    cmp eax, 'glyf'
    je .glyf
    cmp eax, 'GDEF'
    je .gdef
    cmp eax, 'GSUB'
    je .gsub
    cmp eax, 'GPOS'
    je .gpos
    cmp eax, 'kern'
    je .kern
    cmp eax, 'cmap'
    jne .next_table
    mov [rbx + UfontFont_cmapt], rdx
    mov [rbx + UfontFont_cmapt_len], rcx
    jmp .next_table
.head:
    cmp ecx, 54
    jb .bad
    BE16 eax, [rdx + 18]
    mov [rbx + UfontFont_upem], eax
    BE16 eax, [rdx + 50]
    mov [rbx + UfontFont_loca_fmt], eax
    or byte [rbx + UfontFont_have], 1
    jmp .next_table
.maxp:
    cmp ecx, 6
    jb .bad
    BE16 eax, [rdx + 4]
    mov [rbx + UfontFont_nglyphs], eax
    or byte [rbx + UfontFont_have], 2
    jmp .next_table
.hhea:
    cmp ecx, 36
    jb .bad
    BE16 eax, [rdx + 4]
    movsx eax, ax
    mov [rbx + UfontFont_ascent], eax
    BE16 eax, [rdx + 6]
    movsx eax, ax
    neg eax
    mov [rbx + UfontFont_descent], eax
    BE16 eax, [rdx + 34]
    mov [rbx + UfontFont_nhm], eax
    or byte [rbx + UfontFont_have], 4
    jmp .next_table
.hmtx:
    mov [rbx + UfontFont_hmtx], rdx
    mov [rbx + UfontFont_hmtx_len], rcx
    or byte [rbx + UfontFont_have], 8
    jmp .next_table
.loca:
    mov [rbx + UfontFont_loca], rdx
    mov [rbx + UfontFont_loca_len], rcx
    or byte [rbx + UfontFont_have], 16
    jmp .next_table
.glyf:
    mov [rbx + UfontFont_glyf], rdx
    mov [rbx + UfontFont_glyf_len], rcx
    or byte [rbx + UfontFont_have], 32
    jmp .next_table
.gdef:
    mov [rbx + UfontFont_gdef], rdx
    mov [rbx + UfontFont_gdef_len], rcx
    jmp .next_table
.gsub:
    mov [rbx + UfontFont_gsub], rdx
    mov [rbx + UfontFont_gsub_len], rcx
    jmp .next_table
.gpos:
    mov [rbx + UfontFont_gpos], rdx
    mov [rbx + UfontFont_gpos_len], rcx
    jmp .next_table
.kern:
    mov [rbx + UfontFont_kern], rdx
    mov [rbx + UfontFont_kern_len], rcx
.next_table:
    add r15, 16
    jmp .table
.tables_done:
    cmp byte [rbx + UfontFont_have], 63
    jne .bad
    cmp qword [rbx + UfontFont_cmapt], 0
    je .bad
    ; sizes the other tables need
    mov eax, [rbx + UfontFont_upem]
    cmp eax, 16
    jb .bad
    cmp eax, 16384
    ja .bad
    mov eax, [rbx + UfontFont_loca_fmt]
    cmp eax, 1
    ja .bad
    mov eax, [rbx + UfontFont_nhm]
    test eax, eax
    jz .bad
    cmp eax, [rbx + UfontFont_nglyphs]
    ja .bad
    shl rax, 2
    cmp rax, [rbx + UfontFont_hmtx_len]
    ja .bad
    mov eax, [rbx + UfontFont_nglyphs]
    test eax, eax
    jz .bad
    inc rax
    mov ecx, [rbx + UfontFont_loca_fmt]
    inc ecx
    shl rax, cl                         ; (n + 1) x 2 or 4
    cmp rax, [rbx + UfontFont_loca_len]
    ja .bad
    call uf_pick_cmap
    test eax, eax
    jz .bad
    mov rax, rbx
    jmp .out
.bad:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; rbx = font: its cmap subtable (format 12 Unicode over format 4) -> eax =
;   1 found, 0 none
uf_pick_cmap:
    push r12
    push r13
    push r14
    mov r12, [rbx + UfontFont_cmapt]
    mov r13, [rbx + UfontFont_cmapt_len]
    cmp r13, 4
    jb .none
    BE16 r14d, [r12 + 2]                ; records
    lea rax, [r14 * 8 + 4]
    cmp rax, r13
    ja .none
    xor r8d, r8d                        ; the best score so far
    lea r9, [r12 + 4]
.record:
    test r14d, r14d
    jz .done
    dec r14d
    BE16 eax, [r9]                      ; platform
    BE16 ecx, [r9 + 2]                  ; encoding
    mov edx, [r9 + 4]
    bswap edx                           ; offset
    add r9, 8
    ; variation sequences: platform 0 encoding 5, format 14
    test eax, eax
    jnz .not14
    cmp ecx, 5
    jne .unicode
    lea rax, [rdx + 10]
    cmp rax, r13
    ja .record
    lea rsi, [r12 + rdx]
    BE16 eax, [rsi]
    cmp eax, 14
    jne .record
    mov ecx, [rsi + 2]
    bswap ecx                           ; length
    lea rax, [rdx + rcx]
    cmp rax, r13
    jbe .fits14
    mov rcx, r13
    sub rcx, rdx
.fits14:
    mov [rbx + UfontFont_cmap14], rsi
    mov [rbx + UfontFont_cmap14_len], rcx
    jmp .record
.not14:
    ; a Unicode encoding: platform 0, or 3 with 1 / 10
    cmp eax, 3
    jne .record
    cmp ecx, 1
    je .unicode
    cmp ecx, 10
    jne .record
.unicode:
    lea rax, [rdx + 8]
    cmp rax, r13
    ja .record
    lea rsi, [r12 + rdx]
    BE16 eax, [rsi]                     ; format
    cmp eax, 4
    je .format4
    cmp eax, 12
    jne .record
    mov ecx, [rsi + 4]
    bswap ecx                           ; length
    mov r10d, 2
    jmp .score
.format4:
    BE16 ecx, [rsi + 2]
    mov r10d, 1
.score:
    lea rax, [rdx + rcx]
    cmp rax, r13
    jbe .fits
    mov rcx, r13                        ; clipped to the table
    sub rcx, rdx
.fits:
    cmp r10d, r8d
    jbe .record
    mov r8d, r10d
    mov [rbx + UfontFont_cmap], rsi
    mov [rbx + UfontFont_cmap_len], rcx
    mov eax, 4
    cmp r10d, 1
    je .fmt
    mov eax, 12
.fmt:
    mov [rbx + UfontFont_cmap_fmt], eax
    jmp .record
.done:
    xor eax, eax
    test r8d, r8d
    setnz al
    jmp .out
.none:
    xor eax, eax
.out:
    pop r14
    pop r13
    pop r12
    ret

; ----------------------------------------------------------------------------
; ufont_glyph — rdi = UfontFont*, esi = code point -> eax = its glyph (0: the
;   font has none)
; ----------------------------------------------------------------------------
global ufont_glyph
ufont_glyph:
    push rbx
    mov r8, [rdi + UfontFont_cmap]
    mov r9, [rdi + UfontFont_cmap_len]
    cmp dword [rdi + UfontFont_cmap_fmt], 12
    je .format12
    ; format 4: segments (end, start, delta, range offset)
    cmp esi, 0xFFFF
    ja .none
    cmp r9, 14
    jb .none
    BE16 ecx, [r8 + 6]                  ; 2 x segments
    lea rax, [rcx * 4 + 16]
    cmp rax, r9
    ja .none
    xor edx, edx                        ; 2 x segment
.segment:
    cmp edx, ecx
    jae .none
    BE16 eax, [r8 + 14 + rdx]           ; end
    cmp esi, eax
    jbe .found4
    add edx, 2
    jmp .segment
.found4:
    lea r10, [r8 + 16 + rcx]            ; starts
    BE16 eax, [r10 + rdx]
    cmp esi, eax
    jb .none
    mov r11d, esi
    sub r11d, eax                       ; cp - start
    lea r10, [r10 + rcx]                ; deltas
    BE16 ebx, [r10 + rdx]
    lea r10, [r10 + rcx]                ; range offsets
    BE16 eax, [r10 + rdx]
    test eax, eax
    jnz .ranged
    lea eax, [rsi + rbx]
    movzx eax, ax
    jmp .check
.ranged:
    ; &rangeOffset[i] + rangeOffset + 2 (cp - start)
    lea r10, [r10 + rdx]
    add r10, rax
    lea r10, [r10 + r11 * 2]
    lea rax, [r10 + 2]
    sub rax, r8
    cmp rax, r9
    ja .none
    BE16 eax, [r10]
    test eax, eax
    jz .none
    add eax, ebx
    movzx eax, ax
    jmp .check
.format12:
    cmp r9, 16
    jb .none
    mov ecx, [r8 + 12]
    bswap ecx                           ; groups
    mov rax, rcx
    imul rax, rax, 12
    add rax, 16
    cmp rax, r9
    ja .none
    lea r10, [r8 + 16]
.group:
    test ecx, ecx
    jz .none
    dec ecx
    mov eax, [r10]
    bswap eax                           ; start
    mov edx, [r10 + 4]
    bswap edx                           ; end
    add r10, 12
    cmp esi, eax
    jb .group
    cmp esi, edx
    ja .group
    mov edx, [r10 - 4]
    bswap edx                           ; its first glyph
    sub esi, eax
    lea eax, [rdx + rsi]
.check:
    cmp eax, [rdi + UfontFont_nglyphs]
    jb .out
.none:
    xor eax, eax
.out:
    pop rbx
    ret

; ----------------------------------------------------------------------------
; ufont_advance — rdi = UfontFont*, esi = glyph -> eax = its advance (font
;   units; past the metrics' end, the last one's)
; ----------------------------------------------------------------------------
global ufont_advance
ufont_advance:
    mov ecx, [rdi + UfontFont_nhm]
    dec ecx
    cmp esi, ecx
    jbe .have
    mov esi, ecx
.have:
    mov rdx, [rdi + UfontFont_hmtx]
    BE16 eax, [rdx + rsi * 4]
    ret

; ----------------------------------------------------------------------------
; ufont_extents — rdi = UfontFont*, esi = glyph -> eax 1 (0: no such glyph),
;   ecx = x bearing (the hmtx left side bearing), edx = y bearing (top),
;   r8d = width, r9d = height (negative); font units, y up; all 0 for an
;   empty glyph
; ----------------------------------------------------------------------------
global ufont_extents
ufont_extents:
    xor eax, eax
    cmp qword [rdi + UfontFont_glyf], 0
    je .out
    cmp esi, [rdi + UfontFont_nglyphs]
    jae .out
    mov r8, [rdi + UfontFont_loca]
    cmp dword [rdi + UfontFont_loca_fmt], 0
    jne .long
    BE16 eax, [r8 + rsi * 2]
    BE16 ecx, [r8 + rsi * 2 + 2]
    add rax, rax
    add rcx, rcx
    jmp .located
.long:
    mov eax, [r8 + rsi * 4]
    bswap eax
    mov ecx, [r8 + rsi * 4 + 4]
    bswap ecx
.located:
    lea rdx, [rax + 10]
    cmp rax, rcx
    jae .empty
    cmp rdx, rcx
    ja .empty
    cmp rcx, [rdi + UfontFont_glyf_len]
    ja .empty
    mov r10, [rdi + UfontFont_glyf]
    add r10, rax
    cmp word [r10], 0                   ; no contours
    je .empty
    ; the box: xMin, yMin, xMax, yMax
    movzx eax, word [r10 + 2]
    xchg al, ah
    movsx eax, ax
    movzx ecx, word [r10 + 6]
    xchg cl, ch
    movsx ecx, cx
    cmp eax, ecx
    jle .x_sorted
    xchg eax, ecx
.x_sorted:
    mov r8d, ecx
    sub r8d, eax                        ; width
    mov r11d, eax                       ; min x: the bearing without hmtx
    movzx eax, word [r10 + 4]
    xchg al, ah
    movsx eax, ax
    movzx ecx, word [r10 + 8]
    xchg cl, ch
    movsx ecx, cx
    cmp eax, ecx
    jle .y_sorted
    xchg eax, ecx
.y_sorted:
    mov edx, ecx                        ; top
    mov r9d, eax
    sub r9d, ecx                        ; height (negative)
    ; the left side bearing from hmtx
    mov ecx, r11d
    mov r10, [rdi + UfontFont_hmtx]
    mov eax, [rdi + UfontFont_nhm]
    cmp esi, eax
    jae .lsb_array
    lea r11, [rsi * 4 + 4]
    cmp r11, [rdi + UfontFont_hmtx_len]
    ja .have
    movzx ecx, word [r10 + rsi * 4 + 2]
    jmp .lsb
.lsb_array:
    mov r11d, esi
    sub r11d, eax
    add r11d, r11d
    lea r11, [r11 + rax * 4]
    lea rax, [r11 + 2]
    cmp rax, [rdi + UfontFont_hmtx_len]
    ja .have
    movzx ecx, word [r10 + r11]
.lsb:
    xchg cl, ch
    movsx ecx, cx
.have:
    mov eax, 1
.out:
    ret
.empty:
    xor ecx, ecx
    xor edx, edx
    xor r8d, r8d
    xor r9d, r9d
    mov eax, 1
    ret

; ----------------------------------------------------------------------------
; ufont_metrics — rdi = UfontFont* -> eax = units per em, edx = ascent, ecx =
;   descent (font units, both positive for a usual font)
; ----------------------------------------------------------------------------
global ufont_metrics
ufont_metrics:
    mov eax, [rdi + UfontFont_upem]
    mov edx, [rdi + UfontFont_ascent]
    mov ecx, [rdi + UfontFont_descent]
    ret

; ----------------------------------------------------------------------------
; ufont_outline — rdi = UfontFont*, esi = glyph, rdx = UgfxPath*, xmm0 =
;   scale (pixels per font unit), rcx = arena (scratch) -> rax = 0, -EINVAL
;   (damaged), -ENOMEM; the contours appended. The first time a glyph is
;   asked for its outline is decoded at scale 1 (y already down) and kept
;   in the font's arena; then and later it is replayed times the scale -
;   the same numbers a direct decode at the scale gives.
; ----------------------------------------------------------------------------
%define OC_SCALE    0                   ; f64
%define OC_PATH     8                   ; UgfxPath: the glyph at scale 1
%define OC_SIZE     64

; a record: u32 verbs, u32 points, the verbs (padded to 8), the points
%define OR_VERBS    0
%define OR_POINTS   4
%define OR_DATA     8

global ufont_outline
ufont_outline:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, OC_SIZE
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14, rcx
    movsd [rsp + OC_SCALE], xmm0
    cmp r12d, [rbx + UfontFont_nglyphs]
    jae .bad
    ; the table of records
    mov r15, [rbx + UfontFont_cache]
    test r15, r15
    jnz .table
    mov rdi, [rbx + UfontFont_arena]
    mov esi, [rbx + UfontFont_nglyphs]
    shl esi, 3
    call arena_alloc
    test rax, rax
    jz .direct                          ; no room for it: decode each time
    mov r15, rax
    mov rdi, rax
    mov ecx, [rbx + UfontFont_nglyphs]
    xor eax, eax
    rep stosq
    mov [rbx + UfontFont_cache], r15
.table:
    mov rax, [r15 + r12 * 8]
    test rax, rax
    jnz .replay
    ; decoded once at scale 1, into a record
    lea rdi, [rsp + OC_PATH]
    mov rsi, r14
    call ugfx_path_init
    test rax, rax
    jnz .out
    mov rdi, rbx
    mov esi, r12d
    lea rdx, [rsp + OC_PATH]
    movsd xmm0, [rel sf_one]
    mov rcx, r14
    call uf_decode
    test rax, rax
    jnz .out
    mov ecx, [rsp + OC_PATH + UgfxPath_verb_count]
    add ecx, 7
    and ecx, -8
    mov eax, [rsp + OC_PATH + UgfxPath_point_count]
    shl eax, 4
    lea esi, [rcx + rax + OR_DATA]
    mov rdi, [rbx + UfontFont_arena]
    call arena_alloc
    test rax, rax
    jz .unkept
    mov rdx, rax
    mov ecx, [rsp + OC_PATH + UgfxPath_verb_count]
    mov [rdx + OR_VERBS], ecx
    mov eax, [rsp + OC_PATH + UgfxPath_point_count]
    mov [rdx + OR_POINTS], eax
    lea rdi, [rdx + OR_DATA]
    mov rsi, [rsp + OC_PATH + UgfxPath_verbs]
    rep movsb
    mov ecx, [rdx + OR_VERBS]
    add ecx, 7
    and ecx, -8
    lea rdi, [rdx + OR_DATA + rcx]
    mov rsi, [rsp + OC_PATH + UgfxPath_points]
    mov ecx, [rdx + OR_POINTS]
    shl ecx, 4
    rep movsb
    mov [r15 + r12 * 8], rdx
    mov rax, rdx
.replay:
    ; rax = the record: each verb with its points times the scale
    mov r15, rax
    mov ecx, [r15 + OR_VERBS]
    lea r12, [r15 + OR_DATA]            ; the verbs
    add ecx, 7
    and ecx, -8
    lea r14, [r15 + OR_DATA + rcx]      ; the points
    mov r15d, [r15 + OR_VERBS]
.verb:
    test r15d, r15d
    jz .done
    dec r15d
    movzx eax, byte [r12]
    inc r12
    cmp eax, PATH_VERB_CLOSE
    je .close
    movsd xmm0, [r14]
    mulsd xmm0, [rsp + OC_SCALE]
    movsd xmm1, [r14 + 8]
    mulsd xmm1, [rsp + OC_SCALE]
    add r14, 16
    mov rdi, r13
    cmp eax, PATH_VERB_MOVE
    je .move
    cmp eax, PATH_VERB_LINE
    je .line
    movsd xmm2, [r14]
    mulsd xmm2, [rsp + OC_SCALE]
    movsd xmm3, [r14 + 8]
    mulsd xmm3, [rsp + OC_SCALE]
    add r14, 16
    call ugfx_path_quad_to
    jmp .verb_done
.move:
    call ugfx_path_move_to
    jmp .verb_done
.line:
    call ugfx_path_line_to
    jmp .verb_done
.close:
    mov rdi, r13
    call ugfx_path_close
.verb_done:
    test rax, rax
    jnz .out
    jmp .verb
.done:
    xor eax, eax
    jmp .out
.unkept:
    ; no room to keep it: drawn from this decode instead
    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    movsd xmm0, [rsp + OC_SCALE]
    mov rcx, r14
    call uf_decode
    jmp .out
.direct:
    mov rdi, rbx
    mov esi, r12d
    mov rdx, r13
    movsd xmm0, [rsp + OC_SCALE]
    mov rcx, r14
    call uf_decode
    jmp .out
.bad:
    mov rax, -EINVAL
.out:
    add rsp, OC_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; uf_decode — as ufont_outline, decoding the glyph every time
%define OL_FONT     0
%define OL_PATH     8
%define OL_ARENA    16
%define OL_SCALE    24                  ; f64
%define OL_SIZE     32

uf_decode:
    push rbx
    sub rsp, OL_SIZE
    mov [rsp + OL_FONT], rdi
    mov [rsp + OL_PATH], rdx
    mov [rsp + OL_ARENA], rcx
    movsd [rsp + OL_SCALE], xmm0
    mov rbx, rsp                        ; the context
    lea rdx, [rel sf_identity]
    xor ecx, ecx                        ; depth
    call uf_glyph_emit
    add rsp, OL_SIZE
    pop rbx
    ret

; rbx = context, esi = glyph, rdx = f64[6] font units -> font units here,
;   ecx = depth -> rax = 0 or -errno
%define GE_M        0                   ; f64[6] this glyph's transform
%define GE_C        48                  ; f64[6] a component's
%define GE_DATA     96                  ; its bytes
%define GE_END      104
%define GE_DEPTH    112                 ; u32
%define GE_T        120                 ; f64[6] the component's in all
%define GE_SIZE     168

uf_glyph_emit:
    push r12
    push r13
    push r14
    push r15
    sub rsp, GE_SIZE
    mov [rsp + GE_DEPTH], ecx
    mov rax, [rdx]
    mov [rsp + GE_M], rax
    mov rax, [rdx + 8]
    mov [rsp + GE_M + 8], rax
    mov rax, [rdx + 16]
    mov [rsp + GE_M + 16], rax
    mov rax, [rdx + 24]
    mov [rsp + GE_M + 24], rax
    mov rax, [rdx + 32]
    mov [rsp + GE_M + 32], rax
    mov rax, [rdx + 40]
    mov [rsp + GE_M + 40], rax
    ; where its bytes are (loca)
    mov rdi, [rbx + OL_FONT]
    cmp esi, [rdi + UfontFont_nglyphs]
    jae .bad
    mov r8, [rdi + UfontFont_loca]
    cmp dword [rdi + UfontFont_loca_fmt], 0
    jne .long
    BE16 eax, [r8 + rsi * 2]
    BE16 ecx, [r8 + rsi * 2 + 2]
    add rax, rax
    add rcx, rcx
    jmp .located
.long:
    mov eax, [r8 + rsi * 4]
    bswap eax
    mov ecx, [r8 + rsi * 4 + 4]
    bswap ecx
.located:
    cmp rax, rcx
    jae .empty                          ; no outline (or a backward entry)
    cmp rcx, [rdi + UfontFont_glyf_len]
    ja .bad
    mov r12, [rdi + UfontFont_glyf]
    lea r13, [r12 + rcx]                ; its end
    add r12, rax                        ; its start
    lea rax, [r12 + 10]
    cmp rax, r13
    ja .bad
    mov [rsp + GE_DATA], r12
    mov [rsp + GE_END], r13
    BE16 eax, [r12]
    movsx eax, ax                       ; contours
    test eax, eax
    js .composite
    jz .empty
    mov ecx, eax
    lea rdx, [rsp + GE_M]
    mov rdi, r12
    mov rsi, r13
    call uf_simple
    jmp .out
.composite:
    cmp dword [rsp + GE_DEPTH], UFONT_MAX_DEPTH
    jae .bad
    add r12, 10
.component:
    lea rax, [r12 + 4]
    cmp rax, r13
    ja .bad
    BE16 r14d, [r12]                    ; flags
    BE16 r15d, [r12 + 2]                ; glyph
    add r12, 4
    ; the offsets (or matched points: taken as 0)
    test r14d, 1
    jz .byte_args
    lea rax, [r12 + 4]
    cmp rax, r13
    ja .bad
    BE16 eax, [r12]
    movsx eax, ax
    BE16 ecx, [r12 + 2]
    movsx ecx, cx
    add r12, 4
    jmp .args
.byte_args:
    lea rax, [r12 + 2]
    cmp rax, r13
    ja .bad
    movsx eax, byte [r12]
    movsx ecx, byte [r12 + 1]
    add r12, 2
.args:
    test r14d, 2
    jnz .xy
    xor eax, eax
    xor ecx, ecx
.xy:
    cvtsi2sd xmm4, eax
    cvtsi2sd xmm5, ecx
    ; the matrix: identity, a scale, x and y scales, or 2 x 2
    movsd xmm0, [rel sf_identity]
    xorpd xmm1, xmm1
    xorpd xmm2, xmm2
    movsd xmm3, xmm0
    test r14d, 0x0008
    jz .not_scale
    lea rax, [r12 + 2]
    cmp rax, r13
    ja .bad
    call .f2dot14
    movsd xmm3, xmm0
    jmp .matrix
.not_scale:
    test r14d, 0x0040
    jz .not_xy_scale
    lea rax, [r12 + 4]
    cmp rax, r13
    ja .bad
    call .f2dot14
    movsd xmm6, xmm0
    call .f2dot14
    movsd xmm3, xmm0
    movsd xmm0, xmm6
    jmp .matrix
.not_xy_scale:
    test r14d, 0x0080
    jz .matrix
    lea rax, [r12 + 8]
    cmp rax, r13
    ja .bad
    call .f2dot14
    movsd xmm6, xmm0                    ; xscale
    call .f2dot14
    movsd xmm1, xmm0                    ; scale01
    call .f2dot14
    movsd xmm2, xmm0                    ; scale10
    call .f2dot14
    movsd xmm3, xmm0                    ; yscale
    movsd xmm0, xmm6
.matrix:
    movsd [rsp + GE_C], xmm0
    movsd [rsp + GE_C + 8], xmm1
    movsd [rsp + GE_C + 16], xmm2
    movsd [rsp + GE_C + 24], xmm3
    test r14d, 0x0800                   ; SCALED_COMPONENT_OFFSET
    jz .offset
    ; the offset through the matrix
    movsd xmm6, xmm0
    mulsd xmm6, xmm4
    movsd xmm7, xmm2
    mulsd xmm7, xmm5
    addsd xmm6, xmm7
    mulsd xmm1, xmm4
    mulsd xmm3, xmm5
    addsd xmm1, xmm3
    movsd xmm4, xmm6
    movsd xmm5, xmm1
.offset:
    movsd [rsp + GE_C + 32], xmm4
    movsd [rsp + GE_C + 40], xmm5
    ; this one's transform after ours: M x C
    lea rdi, [rsp + GE_T]
    lea rsi, [rsp + GE_M]
    lea rdx, [rsp + GE_C]
    call umath_affine2_multiply
    mov esi, r15d
    lea rdx, [rsp + GE_T]
    mov ecx, [rsp + GE_DEPTH]
    inc ecx
    call uf_glyph_emit
    test rax, rax
    jnz .out
    test r14d, 0x0020                   ; MORE_COMPONENTS
    jnz .component
.empty:
    xor eax, eax
    jmp .out
.bad:
    mov rax, -EINVAL
.out:
    add rsp, GE_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    ret
; r12 -> xmm0 = the F2Dot14 there, r12 past it
.f2dot14:
    BE16 eax, [r12]
    movsx eax, ax
    cvtsi2sd xmm0, eax
    mulsd xmm0, [rel sf_f2dot14]
    add r12, 2
    ret

; rdi / rsi = a simple glyph's bytes, ecx = contours, rdx = f64[6] its
;   transform, rbx = context -> rax = 0 or -errno: its points decoded, its
;   contours appended
%define SG_M        0                   ; f64[6]
%define SG_ENDS     48                  ; the endPts array
%define SG_N        56                  ; u32 points
%define SG_C        60                  ; u32 contours
%define SG_X        64                  ; i32[n]
%define SG_Y        72                  ; i32[n]
%define SG_F        80                  ; u8[n] flags
%define SG_K        88                  ; u32 the contour
%define SG_FIRST    92                  ; u32 its first point
%define SG_START    96                  ; f64 x, y: where it starts
%define SG_CTRL     112                 ; f64 x, y: a pending control point
%define SG_HAVE     128                 ; u32 one is pending
%define SG_I        132                 ; u32 the step through it
%define SG_SIZE     136

uf_simple:
    push r12
    push r13
    push r14
    push r15
    sub rsp, SG_SIZE
    mov r12, rdi
    mov r13, rsi
    mov [rsp + SG_C], ecx
    mov rax, [rdx]
    mov [rsp + SG_M], rax
    mov rax, [rdx + 8]
    mov [rsp + SG_M + 8], rax
    mov rax, [rdx + 16]
    mov [rsp + SG_M + 16], rax
    mov rax, [rdx + 24]
    mov [rsp + SG_M + 24], rax
    mov rax, [rdx + 32]
    mov [rsp + SG_M + 32], rax
    mov rax, [rdx + 40]
    mov [rsp + SG_M + 40], rax
    ; endPts (increasing), instructions skipped
    lea r14, [r12 + 10]
    mov [rsp + SG_ENDS], r14
    lea rax, [r14 + rcx * 2 + 2]
    cmp rax, r13
    ja .bad
    mov edx, -1
    xor r8d, r8d
.ends:
    cmp r8d, ecx
    jae .ends_done
    BE16 eax, [r14 + r8 * 2]
    cmp eax, edx
    jle .bad
    mov edx, eax
    inc r8d
    jmp .ends
.ends_done:
    inc edx
    cmp edx, UFONT_MAX_POINTS
    ja .bad
    mov [rsp + SG_N], edx
    lea r14, [r14 + rcx * 2]
    BE16 eax, [r14]
    lea r14, [r14 + rax + 2]            ; the flags
    cmp r14, r13
    ja .bad
    ; scratch: x, y, flags
    mov rax, [rbx + OL_ARENA]
    mov rdi, rax
    mov esi, edx
    imul esi, esi, 9
    add esi, 8
    call arena_alloc
    test rax, rax
    jz .nomem
    mov [rsp + SG_X], rax
    mov ecx, [rsp + SG_N]
    lea rdx, [rax + rcx * 4]
    mov [rsp + SG_Y], rdx
    lea rdx, [rdx + rcx * 4]
    mov [rsp + SG_F], rdx
    ; flags, with repeats
    mov r15, rdx
    xor r8d, r8d
.flag:
    cmp r8d, ecx
    jae .flags_done
    cmp r14, r13
    jae .bad
    movzx eax, byte [r14]
    inc r14
    mov [r15 + r8], al
    inc r8d
    test al, 8
    jz .flag
    cmp r14, r13
    jae .bad
    movzx r9d, byte [r14]
    inc r14
.repeat:
    test r9d, r9d
    jz .flag
    cmp r8d, ecx
    jae .bad
    mov [r15 + r8], al
    inc r8d
    dec r9d
    jmp .repeat
.flags_done:
    ; x then y: short (sign in bit 4 / 5), same, or a 16-bit delta
    mov rdi, [rsp + SG_X]
    mov r9d, 0x02                       ; short
    mov r10d, 0x10                      ; same / positive
    call .coords
    test eax, eax
    jnz .bad
    mov rdi, [rsp + SG_Y]
    mov r9d, 0x04
    mov r10d, 0x20
    call .coords
    test eax, eax
    jnz .bad
    ; the contours
    mov dword [rsp + SG_K], 0
    mov dword [rsp + SG_FIRST], 0
.contour:
    mov eax, [rsp + SG_K]
    cmp eax, [rsp + SG_C]
    jae .done
    mov rdx, [rsp + SG_ENDS]
    BE16 r14d, [rdx + rax * 2]
    inc r14d                            ; its end (exclusive)
    mov r15d, [rsp + SG_FIRST]          ; its first
    mov [rsp + SG_FIRST], r14d
    inc dword [rsp + SG_K]
    mov r12d, r14d
    sub r12d, r15d                      ; points in it
    jz .contour
    call .emit_contour
    test rax, rax
    jnz .out
    jmp .contour
.done:
    xor eax, eax
    jmp .out
.nomem:
    mov rax, -ENOMEM
    jmp .out
.bad:
    mov rax, -EINVAL
.out:
    add rsp, SG_SIZE
    pop r15
    pop r14
    pop r13
    pop r12
    ret
; rdi = i32[n] out, r9d = the short flag, r10d = the same / positive flag,
;   r14 = the bytes (moved on) -> eax = 0, 1 if they run out (frame at
;   rsp + 8)
.coords:
    mov r11, [rsp + 8 + SG_F]
    mov ecx, [rsp + 8 + SG_N]
    xor r8d, r8d
    xor edx, edx                        ; the running value
.c_next:
    cmp r8d, ecx
    jae .c_ok
    movzx eax, byte [r11 + r8]
    test eax, r9d
    jz .c_long
    cmp r14, r13
    jae .c_bad
    movzx esi, byte [r14]
    inc r14
    test eax, r10d
    jnz .c_add
    neg esi
.c_add:
    add edx, esi
    jmp .c_store
.c_long:
    test eax, r10d
    jnz .c_store                        ; the same as before
    lea rsi, [r14 + 2]
    cmp rsi, r13
    ja .c_bad
    BE16 esi, [r14]
    movsx esi, si
    add r14, 2
    add edx, esi
.c_store:
    mov [rdi + r8 * 4], edx
    inc r8d
    jmp .c_next
.c_ok:
    xor eax, eax
    ret
.c_bad:
    mov eax, 1
    ret
; r15d = a contour's first point, r12d = its count: moved to its start, its
;   quadratic pieces, closed (frame at rsp + 8)
.emit_contour:
    ; the start: the first point if on the curve, else the last if it is,
    ; else between them; the points after it in order
    mov r11, [rsp + 8 + SG_F]
    mov eax, r15d
    test byte [r11 + rax], 1
    jz .start_last
    call .point                         ; xmm0, xmm1 of point eax
    mov r13d, r15d
    inc r13d                            ; next to visit
    lea r14d, [r12 - 1]                 ; how many
    jmp .started
.start_last:
    lea eax, [r15 + r12 - 1]
    test byte [r11 + rax], 1
    jz .start_mid
    call .point
    mov r13d, r15d
    lea r14d, [r12 - 1]
    jmp .started
.start_mid:
    mov eax, r15d
    call .point
    movsd xmm6, xmm0
    movsd xmm7, xmm1
    lea eax, [r15 + r12 - 1]
    call .point
    addsd xmm0, xmm6
    mulsd xmm0, [rel sf_half]
    addsd xmm1, xmm7
    mulsd xmm1, [rel sf_half]
    mov r13d, r15d
    mov r14d, r12d
.started:
    movsd [rsp + 8 + SG_START], xmm0
    movsd [rsp + 8 + SG_START + 8], xmm1
    mov dword [rsp + 8 + SG_HAVE], 0
    call .emit_move
    test rax, rax
    jnz .ec_out
.ec_point:
    test r14d, r14d
    jz .ec_close
    dec r14d
    mov eax, r13d
    inc r13d
    mov r11, [rsp + 8 + SG_F]
    movzx ecx, byte [r11 + rax]
    mov [rsp + 8 + SG_I], ecx
    call .point
    test dword [rsp + 8 + SG_I], 1
    jz .ec_off
    ; on the curve: a line, or the quad a pending control point makes
    cmp dword [rsp + 8 + SG_HAVE], 0
    je .ec_line
    mov dword [rsp + 8 + SG_HAVE], 0
    movsd xmm2, xmm0
    movsd xmm3, xmm1
    movsd xmm0, [rsp + 8 + SG_CTRL]
    movsd xmm1, [rsp + 8 + SG_CTRL + 8]
    call .emit_quad
    jmp .ec_next
.ec_line:
    call .emit_line
    jmp .ec_next
.ec_off:
    cmp dword [rsp + 8 + SG_HAVE], 0
    je .ec_pend
    ; two off the curve: the quad to the point between them
    movsd xmm6, xmm0
    movsd xmm7, xmm1
    movsd xmm2, xmm0
    addsd xmm2, [rsp + 8 + SG_CTRL]
    mulsd xmm2, [rel sf_half]
    movsd xmm3, xmm1
    addsd xmm3, [rsp + 8 + SG_CTRL + 8]
    mulsd xmm3, [rel sf_half]
    movsd xmm0, [rsp + 8 + SG_CTRL]
    movsd xmm1, [rsp + 8 + SG_CTRL + 8]
    movsd [rsp + 8 + SG_CTRL], xmm6
    movsd [rsp + 8 + SG_CTRL + 8], xmm7
    call .emit_quad
    jmp .ec_next
.ec_pend:
    movsd [rsp + 8 + SG_CTRL], xmm0
    movsd [rsp + 8 + SG_CTRL + 8], xmm1
    mov dword [rsp + 8 + SG_HAVE], 1
    xor eax, eax
.ec_next:
    test rax, rax
    jnz .ec_out
    jmp .ec_point
.ec_close:
    cmp dword [rsp + 8 + SG_HAVE], 0
    je .ec_closed
    movsd xmm0, [rsp + 8 + SG_CTRL]
    movsd xmm1, [rsp + 8 + SG_CTRL + 8]
    movsd xmm2, [rsp + 8 + SG_START]
    movsd xmm3, [rsp + 8 + SG_START + 8]
    call .emit_quad
    test rax, rax
    jnz .ec_out
.ec_closed:
    mov rdi, [rbx + OL_PATH]
    sub rsp, 8
    call ugfx_path_close
    add rsp, 8
.ec_out:
    ret
; eax = a point -> xmm0, xmm1 = it through the transform (font units)
;   (frame at rsp + 16)
.point:
    mov rdx, [rsp + 16 + SG_X]
    cvtsi2sd xmm2, dword [rdx + rax * 4]
    mov rdx, [rsp + 16 + SG_Y]
    cvtsi2sd xmm3, dword [rdx + rax * 4]
    movsd xmm0, [rsp + 16 + SG_M]
    mulsd xmm0, xmm2
    movsd xmm4, [rsp + 16 + SG_M + 16]
    mulsd xmm4, xmm3
    addsd xmm0, xmm4
    addsd xmm0, [rsp + 16 + SG_M + 32]
    movsd xmm1, [rsp + 16 + SG_M + 8]
    mulsd xmm1, xmm2
    movsd xmm4, [rsp + 16 + SG_M + 24]
    mulsd xmm4, xmm3
    addsd xmm1, xmm4
    addsd xmm1, [rsp + 16 + SG_M + 40]
    ret
; font units -> pixels, y down: x s, 0 - y s (xmm0 / xmm1)
%macro TO_PIXELS 2
    mulsd %1, [rbx + OL_SCALE]
    mulsd %2, [rbx + OL_SCALE]
    xorpd xmm5, xmm5
    subsd xmm5, %2
    movsd %2, xmm5
%endmacro
.emit_move:
    TO_PIXELS xmm0, xmm1
    mov rdi, [rbx + OL_PATH]
    call ugfx_path_move_to
    ret
.emit_line:
    TO_PIXELS xmm0, xmm1
    mov rdi, [rbx + OL_PATH]
    call ugfx_path_line_to
    ret
.emit_quad:
    TO_PIXELS xmm0, xmm1
    TO_PIXELS xmm2, xmm3
    mov rdi, [rbx + OL_PATH]
    call ugfx_path_quad_to
    ret

section .data
global ufont_sfnt_version
ufont_sfnt_version: dq 0x010000
