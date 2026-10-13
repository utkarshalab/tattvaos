; ============================================================================
; Golden Frame Test — Deterministic Scene Rendering + Checksum Comparison
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/test.inc"

extern pixbuf_create
extern pixbuf_destroy
extern fill_solid
extern blend_dispatch
extern region_init
extern region_add_rect
extern arena_init
extern arena_alloc
extern tv_time_now_ns
extern crc32

section .text

; ---------------------------------------------------------------------------
; golden_run_scene
;   Run a golden scene and compare with expected checksum
;   IN:  rdi = scene_id, rsi = arena, rdx = expected_crc32
;   OUT: rax = 0 pass, 1 fail
; ---------------------------------------------------------------------------
global golden_run_scene
golden_run_scene:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi        ; scene_id
    mov r12, rsi        ; arena
    mov r13, rdx        ; expected_crc32
    ASSERT_PTR r12

    ; Create 800x600 framebuffer
    mov rdi, r12
    mov rsi, 800
    mov rdx, 600
    mov rcx, DRM_FORMAT_BGRA8888
    call pixbuf_create
    test rax, rax
    jz .oom
    mov r14, rax        ; framebuffer

    ; Dispatch to scene
    cmp rbx, 1
    je .scene_rects
    cmp rbx, 2
    je .scene_alpha
    cmp rbx, 3
    je .scene_bitmap_text
    cmp rbx, 4
    je .scene_two_windows
    cmp rbx, 5
    je .scene_subsurfaces
    cmp rbx, 6
    je .scene_damage_partial
    cmp rbx, 7
    je .scene_rotation
    cmp rbx, 8
    je .scene_scale_fractional
    cmp rbx, 9
    je .scene_decorations
    cmp rbx, 10
    je .scene_png_cursor
    cmp rbx, 11
    je .scene_ttf_text
    cmp rbx, 12
    je .scene_multi_output

    jmp .unknown_scene

.scene_rects:
    call golden_scene_rects
    jmp .check_crc

.scene_alpha:
    call golden_scene_alpha
    jmp .check_crc

.scene_bitmap_text:
    call golden_scene_bitmap_text
    jmp .check_crc

.scene_two_windows:
    call golden_scene_two_windows
    jmp .check_crc

.scene_subsurfaces:
    call golden_scene_subsurfaces
    jmp .check_crc

.scene_damage_partial:
    call golden_scene_damage_partial
    jmp .check_crc

.scene_rotation:
    call golden_scene_rotation
    jmp .check_crc

.scene_scale_fractional:
    call golden_scene_scale_fractional
    jmp .check_crc

.scene_decorations:
    call golden_scene_decorations
    jmp .check_crc

.scene_png_cursor:
    call golden_scene_png_cursor
    jmp .check_crc

.scene_ttf_text:
    call golden_scene_ttf_text
    jmp .check_crc

.scene_multi_output:
    call golden_scene_multi_output
    jmp .check_crc

.unknown_scene:
    mov rax, 1
    jmp .done

.check_crc:
    ; Compute CRC32 of framebuffer
    mov rdi, [r14 + 32]     ; data ptr
    mov rsi, [r14 + 40]     ; size
    call crc32
    cmp rax, r13
    je .pass
    mov rax, 1
    jmp .done

.pass:
    xor rax, rax

.done:
    ; Cleanup
    test r14, r14
    jz .skip_free
    mov rdi, r14
    call pixbuf_destroy
.skip_free:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; Scene Implementations
; ---------------------------------------------------------------------------

golden_scene_rects:
    ; Scene 1: Colored rectangles
    PROLOGUE
    ; Clear to black
    mov rdi, [r14 + 32]
    mov rsi, COLOR_BLACK
    mov rdx, 800
    mov rcx, 600
    mov r8, 3200
    call fill_solid

    ; Red rect (100,100) 200x150
    mov rdi, [r14 + 32]
    add rdi, 100 * 4 + 100 * 3200
    mov rsi, COLOR_RED
    mov rdx, 200
    mov rcx, 150
    mov r8, 3200
    call fill_solid

    ; Green rect (400,200) 150x200
    mov rdi, [r14 + 32]
    add rdi, 400 * 4 + 200 * 3200
    mov rsi, COLOR_GREEN
    mov rdx, 150
    mov rcx, 200
    mov r8, 3200
    call fill_solid

    ; Blue rect (200,350) 300x100
    mov rdi, [r14 + 32]
    add rdi, 200 * 4 + 350 * 3200
    mov rsi, COLOR_BLUE
    mov rdx, 300
    mov rcx, 100
    mov r8, 3200
    call fill_solid
    leave
    ret

golden_scene_alpha:
    ; Scene 2: Alpha blending
    PROLOGUE
    ; Clear to white
    mov rdi, [r14 + 32]
    mov rsi, COLOR_WHITE
    mov rdx, 800
    mov rcx, 600
    mov r8, 3200
    call fill_solid

    ; Semi-transparent red over white
    mov rdi, [r14 + 32]
    add rdi, 200 * 4 + 150 * 3200
    mov rsi, 0x80FF0000      ; 50% red
    mov rdx, 200
    mov rcx, 200
    mov r8, 3200
    call blend_dispatch

    ; Semi-transparent blue over that
    mov rdi, [r14 + 32]
    add rdi, 300 * 4 + 200 * 3200
    mov rsi, 0x800000FF      ; 50% blue
    mov rdx, 200
    mov rcx, 200
    mov r8, 3200
    call blend_dispatch
    leave
    ret

golden_scene_bitmap_text:
    ; Scene 3: Bitmap font text
    PROLOGUE
    ; Clear to dark gray
    mov rdi, [r14 + 32]
    mov rsi, COLOR_DARK_GRAY
    mov rdx, 800
    mov rcx, 600
    mov r8, 3200
    call fill_solid

    ; Draw "Canvas" at (50,50) in white
    ; TODO: bitmap font draw
    leave
    ret

golden_scene_two_windows:
    ; Scene 4: Two overlapping windows
    PROLOGUE
    ; Window 1 background
    mov rdi, [r14 + 32]
    add rdi, 100 * 4 + 100 * 3200
    mov rsi, 0xFF303050
    mov rdx, 400
    mov rcx, 300
    mov r8, 3200
    call fill_solid

    ; Window 2 background (overlapping)
    mov rdi, [r14 + 32]
    add rdi, 300 * 4 + 200 * 3200
    mov rsi, 0xFF503030
    mov rdx, 400
    mov rcx, 300
    mov r8, 3200
    call fill_solid
    leave
    ret

golden_scene_subsurfaces:
    ; Scene 5: Subsurfaces
    PROLOGUE
    leave
    ret

golden_scene_damage_partial:
    ; Scene 6: Partial damage
    PROLOGUE
    leave
    ret

golden_scene_rotation:
    ; Scene 7: 90° rotation
    PROLOGUE
    leave
    ret

golden_scene_scale_fractional:
    ; Scene 8: 1.5x scale
    PROLOGUE
    leave
    ret

golden_scene_decorations:
    ; Scene 9: Window decorations
    PROLOGUE
    leave
    ret

golden_scene_png_cursor:
    ; Scene 10: PNG cursor
    PROLOGUE
    leave
    ret

golden_scene_ttf_text:
    ; Scene 11: TrueType text
    PROLOGUE
    leave
    ret

golden_scene_multi_output:
    ; Scene 12: Multi-output
    PROLOGUE
    leave
    ret

section .data
global golden_version
golden_version: dq 0x010000
