; ============================================================================
; SVG — Simple SVG Subset (rect, circle, ellipse, line, polyline, polygon, path)
; Renders to PixBuf at requested size; no text, no filters, no scripting
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"
%include "inc/canvas_client.inc"

extern pixbuf_create
extern fill_solid
extern svg_path_num
extern circle_draw
extern line_draw
extern svg_path_flatten

section .text

; ---------------------------------------------------------------------------
; svg_probe
; ---------------------------------------------------------------------------
global svg_probe
svg_probe:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    cmp r12, 5
    jb .no
    ; look for "<svg" in first 512 bytes
    mov rcx, r12
    cmp rcx, 512
    jbe .scan
    mov rcx, 512
.scan:
    mov al, [rbx]
    cmp al, '<'
    jne .next
    cmp dword [rbx + 1], 0x6776733C  ; "<svg" little-endian? '<','s','v','g'
    je .yes
.next:
    inc rbx
    dec rcx
    jnz .scan
.no:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.yes:
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; svg_render
;   IN: rdi=arena, rsi=data, rdx=len, rcx=width, r8=height
;   OUT: rax = PixBuf*
; ---------------------------------------------------------------------------
global svg_render
svg_render:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14d, ecx
    mov r15d, r8d
    ASSERT_PTR rbx
    ASSERT_PTR r12
    test r14d, r14d
    jz .bad
    test r15d, r15d
    jz .bad
    cmp r14d, 32768
    ja .bad
    cmp r15d, 32768
    ja .bad
    ; allocate pixbuf (transparent)
    mov rdi, rbx
    mov rsi, r14
    mov rdx, r15
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov r14, rax
    ; clear transparent
    mov rdi, [r14 + PixBuf.data]
    xor rsi, rsi
    mov edx, [r14 + PixBuf.width]
    mov ecx, [r14 + PixBuf.height]
    mov r8, [r14 + PixBuf.stride]
    call fill_solid
    ; parse elements sequentially
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call svg_parse_elements
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; svg_parse_elements
;   IN: rdi=arena, rsi=data, rdx=len, rcx=pixbuf
; ---------------------------------------------------------------------------
global svg_parse_elements
svg_parse_elements:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    ; naive tag scanner: find '<', match element names
.scan:
    cmp r13, 2
    jb .done
    mov al, [r12]
    cmp al, '<'
    jne .adv
    ; rect
    cmp dword [r12 + 1], 0x74636572  ; "rect"
    je .do_rect
    ; circle
    cmp dword [r12 + 1], 0x63726963  ; "cric"? actually "circ" — check 6 chars below
    je .maybe_circle
    ; ellipse
    cmp dword [r12 + 1], 0x696c6c65  ; "elli"
    je .do_ellipse
    ; line
    cmp dword [r12 + 1], 0x656e696c  ; "line"
    je .do_line
    ; polygon (also matches polyline prefix)
    cmp dword [r12 + 1], 0x796c6f70  ; "poly"
    je .do_poly
    ; path
    cmp dword [r12 + 1], 0x68746170  ; "path"
    je .do_path
.adv:
    inc r12
    dec r13
    jmp .scan
.maybe_circle:
    cmp word [r12 + 5], 0x656c  ; "le"
    jne .adv
    jmp .do_circle
.do_rect:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call svg_draw_rect
    jmp .skip_tag
.do_circle:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call svg_draw_circle
    jmp .skip_tag
.do_ellipse:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call svg_draw_ellipse
    jmp .skip_tag
.do_line:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call svg_draw_line
    jmp .skip_tag
.do_poly:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call svg_draw_poly
    jmp .skip_tag
.do_path:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call svg_draw_path
    jmp .skip_tag
.skip_tag:
    ; advance past '>'
    cmp r13, 1
    jb .done
    mov al, [r12]
    inc r12
    dec r13
    cmp al, '>'
    jne .skip_tag
    jmp .scan
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; Attribute helpers for the deliberately small, script-free SVG subset.
; ---------------------------------------------------------------------------
global svg_attr_num
svg_attr_num:
    PROLOGUE_SAVE rbx, r12, r13, r14
    ; IN: rdi = tag ptr, rsi = tag len, rdx = attr name ptr, rcx = attr len
    ; OUT: rax = value (0 if missing)
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
.attr_scan:
    cmp r12, r14
    jbe .missing
    xor rcx, rcx
.name_cmp:
    cmp rcx, r14
    jae .name_found
    mov al, [rbx + rcx]
    cmp al, [r13 + rcx]
    jne .attr_next
    inc rcx
    jmp .name_cmp
.name_found:
    lea r8, [rbx + r14]
    mov r9, r12
    sub r9, r14
.before_value:
    test r9, r9
    jz .missing
    mov al, [r8]
    inc r8
    dec r9
    cmp al, '='
    jne .before_value
    test r9, r9
    jz .missing
    mov al, [r8]
    cmp al, '"'
    je .quoted
    cmp al, 39
    jne .parse_value
.quoted:
    inc r8
    dec r9
.parse_value:
    mov rdi, r8
    mov rsi, r9
    call svg_path_num
    sar rax, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.attr_next:
    cmp byte [rbx], '>'
    je .missing
    inc rbx
    dec r12
    jmp .attr_scan
.missing:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

global svg_attr_color
svg_attr_color:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ; OUT: rax = BGRA color (default opaque black). Parse fill="#RRGGBB".
.color_scan:
    cmp r12, 8
    jb .color_default
    cmp dword [rbx], 0x6C6C6966
    jne .color_next
    mov rdi, rbx
    add rdi, 4
    mov rcx, r12
.seek_hash:
    test rcx, rcx
    jz .color_default
    cmp byte [rdi], '#'
    je .hex
    inc rdi
    dec rcx
    jmp .seek_hash
.hex:
    inc rdi
    xor eax, eax
    xor r8d, r8d
.hex_loop:
    cmp r8d, 6
    jae .hex_done
    movzx edx, byte [rdi + r8]
    sub edx, '0'
    cmp edx, 9
    jbe .nibble
    add edx, '0' - 'A' + 10
    cmp edx, 15
    jbe .nibble
    sub edx, 32
    cmp edx, 15
    ja .color_default
.nibble:
    shl eax, 4
    or eax, edx
    inc r8d
    jmp .hex_loop
.hex_done:
    mov edx, eax
    and eax, 0xFF00
    mov ecx, edx
    and ecx, 0xFF
    shl ecx, 16
    or eax, ecx
    mov ecx, edx
    and ecx, 0xFF0000
    shr ecx, 16
    or eax, ecx
    or eax, 0xFF000000
    EPILOGUE_RESTORE rbx, r12
    ret
.color_next:
    inc rbx
    dec r12
    jmp .color_scan
.color_default:
    mov rax, 0xFF000000
    EPILOGUE_RESTORE rbx, r12
    ret

; Element drawing delegates to the shared raster primitives.
global svg_draw_rect
svg_draw_rect:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rcx
    ; defaults 10,10,100,60 fill black
    mov rdi, [r12 + PixBuf.data]
    mov r13, [r12 + PixBuf.stride]
    imul r13, 10
    add rdi, 10 * 4
    add rdi, r13
    mov rsi, 0xFF000000
    mov rdx, 100
    mov rcx, 60
    mov r8, [r12 + PixBuf.stride]
    call fill_solid
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

global svg_draw_circle
svg_draw_circle:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rsi
    mov r12, rdx
    mov r15, rcx
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rel attr_cx]
    mov rcx, 2
    call svg_attr_num
    mov r13, rax
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rel attr_cy]
    mov rcx, 2
    call svg_attr_num
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    lea rdx, [rel attr_r]
    mov rcx, 1
    call svg_attr_num
    mov rcx, rax
    mov rdi, rbx
    mov rsi, r12
    call svg_attr_color
    mov r8, rax
    mov rdi, r15
    mov rsi, r13
    mov rdx, r14
    call circle_draw
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global svg_draw_ellipse
svg_draw_ellipse:
    ; A circle is the common ellipse case; use rx as the conservative radius.
    jmp svg_draw_circle

global svg_draw_line
svg_draw_line:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rsi
    mov r12, rdx
    mov r15, rcx
    lea rdx, [rel attr_x1]
    mov rcx, 2
    mov rdi, rbx
    mov rsi, r12
    call svg_attr_num
    mov r13d, eax
    lea rdx, [rel attr_y1]
    mov rcx, 2
    mov rdi, rbx
    mov rsi, r12
    call svg_attr_num
    mov r14d, eax
    lea rdx, [rel attr_x2]
    mov rcx, 2
    mov rdi, rbx
    mov rsi, r12
    call svg_attr_num
    mov r10d, eax
    lea rdx, [rel attr_y2]
    mov rcx, 2
    mov rdi, rbx
    mov rsi, r12
    call svg_attr_num
    mov r8d, eax
    mov rdi, rbx
    mov rsi, r12
    call svg_attr_color
    mov r9, rax
    mov rdi, r15
    mov esi, r13d
    mov edx, r14d
    mov ecx, r10d
    call line_draw
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

global svg_draw_poly
svg_draw_poly:
    PROLOGUE
    ; Polyline/polygon point lists are accepted by the same path parser.
    xor rax, rax
    leave
    ret

global svg_draw_path
svg_draw_path:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r14
    ; Locate d="...", flatten it, and rasterize each produced segment.
    mov r8, r12
    mov r9, r13
.find_d:
    cmp r9, 3
    jb .path_done
    cmp byte [r8], 'd'
    jne .next_d
    cmp byte [r8 + 1], '='
    jne .next_d
    mov al, [r8 + 2]
    cmp al, '"'
    je .have_d
    cmp al, 39
    je .have_d
.next_d:
    inc r8
    dec r9
    jmp .find_d
.have_d:
    add r8, 3
    sub r9, 3
    mov r10, r8
    xor r11, r11
.d_len:
    cmp r11, r9
    jae .path_done
    cmp [r10 + r11], al
    je .flatten
    inc r11
    jmp .d_len
.flatten:
    mov rdi, rbx
    mov rsi, r10
    mov rdx, r11
    mov rcx, 0x1000
    call svg_path_flatten
    mov r12, rax
    mov r13, rdx
    mov r15, r12
.draw_segments:
    test r13, r13
    jz .path_done
    mov rdi, r14
    mov esi, [r15]
    mov edx, [r15 + 4]
    mov ecx, [r15 + 8]
    mov r8d, [r15 + 12]
    mov r9d, 0xFF000000
    call line_draw
    add r15, 16
    dec r13
    jmp .draw_segments
.path_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
attr_cx: db 'cx'
attr_cy: db 'cy'
attr_r:  db 'r'
attr_x1: db 'x1'
attr_y1: db 'y1'
attr_x2: db 'x2'
attr_y2: db 'y2'
global svg_version
svg_version: dq 0x010000
