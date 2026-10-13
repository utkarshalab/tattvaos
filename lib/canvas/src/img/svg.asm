; ============================================================================
; SVG — Simple SVG Subset (rect, circle, ellipse, line, polyline, polygon, path)
; Renders to PixBuf at requested size; no text, no filters, no scripting
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/image.inc"

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
; attribute helpers (parse name="num" within tag, stub-grade: defaults)
; ---------------------------------------------------------------------------
global svg_attr_num
svg_attr_num:
    PROLOGUE
    ; IN: rdi = tag ptr, rsi = tag len, rdx = attr name ptr, rcx = attr len
    ; OUT: rax = value (0 if missing)
    xor rax, rax
    leave
    ret

global svg_attr_color
svg_attr_color:
    PROLOGUE
    ; OUT: rax = BGRA color (default opaque black)
    mov rax, 0xFF000000
    leave
    ret

; element draw stubs: rect filled, others delegate to path rasterizer
global svg_draw_rect
svg_draw_rect:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rcx
    ; defaults 10,10,100,60 fill black
    mov rdi, [r12 + PixBuf.data]
    add rdi, 10 * 4 + 10 * [r12 + PixBuf.stride]
    mov rsi, 0xFF000000
    mov rdx, 100
    mov rcx, 60
    mov r8, [r12 + PixBuf.stride]
    call fill_solid
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

global svg_draw_circle
svg_draw_circle:
    PROLOGUE
    ; TODO: midpoint circle fill
    xor rax, rax
    leave
    ret

global svg_draw_ellipse
svg_draw_ellipse:
    PROLOGUE
    xor rax, rax
    leave
    ret

global svg_draw_line
svg_draw_line:
    PROLOGUE
    ; TODO: bresenham
    xor rax, rax
    leave
    ret

global svg_draw_poly
svg_draw_poly:
    PROLOGUE
    ; TODO: scanline polygon fill
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
    ; extract d="..." and flatten via svg_path
    ; TODO: find d attribute
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

section .data
global svg_version
svg_version: dq 0x010000
