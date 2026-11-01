; ============================================================================
; Compositor Core — Main Composition Loop, Render List, Output Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/compositor.inc"
%include "inc/externs.inc"
%include "inc/backend.inc"

section .text

; ============================================================================
; compositor_init
;   Initialize compositor
; ============================================================================
global compositor_init
compositor_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi  ; server
    mov r13, rdx  ; arena
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    mov qword [rbx + Compositor.outputs], 0
    mov [rbx + Compositor.damage], r12
    mov qword [rbx + Compositor.render_list], 0
    mov dword [rbx + Compositor.bg_color], 0xFF000000  ; black
    mov qword [rbx + Compositor.cursor], 0
    mov dword [rbx + Compositor.cursor_x], 0
    mov dword [rbx + Compositor.cursor_y], 0

    ; Create frame clock
    lea rdi, [rbx + Compositor.frame_clock]
    call frame_clock_init

    ; Allocate render list buffer
    mov rdi, r13
    mov rsi, 8 + 1024 * RENDER_ENTRY_SIZE
    call arena_alloc
    test rax, rax
    jnz .ok
    mov rax, -ENOMEM
    EPILOGUE_RESTORE rbx
    ret

.ok:
    mov [rbx + Compositor.render_list], rax
    mov qword [rax], 0
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; compositor_destroy
;   Cleanup compositor
; ============================================================================
global compositor_destroy
compositor_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Destroy outputs
    mov rax, [rbx + Compositor.outputs]
.output_loop:
    test rax, rax
    jz .outputs_done
    push rax
    call output_destroy
    pop rax
    mov rax, [rax + Output.next]
    jmp .output_loop

.outputs_done:
    ; Free render list
    ; Arena handles it

    xor rax, rax
    leave
    ret

; ============================================================================
; compositor_add_output
;   Add output to compositor
; ============================================================================
global compositor_add_output
compositor_add_output:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi  ; output*
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Link into output list
    mov rax, [rbx + Compositor.outputs]
    mov [r12 + Output.next], rax
    mov [rbx + Compositor.outputs], r12

    xor rax, rax
    leave
    ret

; ============================================================================
; compositor_remove_output
;   Remove output from compositor
; ============================================================================
global compositor_remove_output
compositor_remove_output:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Unlink from list
    mov rax, [rbx + Compositor.outputs]
    test rax, rax
    jz .done

    cmp rax, r12
    jne .find_prev
    mov rax, [r12 + Output.next]
    mov [rbx + Compositor.outputs], rax
    jmp .done

.find_prev:
    mov r13, rax
.prev_loop:
    mov rax, [r13 + Output.next]
    test rax, rax
    jz .done
    cmp rax, r12
    je .unlink
    mov r13, rax
    jmp .prev_loop

.unlink:
    mov rax, [r12 + Output.next]
    mov [r13 + Output.next], rax

.done:
    xor rax, rax
    leave
    ret

; ============================================================================
; compositor_composite
;   Main composition pass - render all outputs
; ============================================================================
global compositor_composite
compositor_composite:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Build render list
    call .build_render_list

    ; Iterate outputs
    mov r12, [rbx + Compositor.outputs]
.output_loop:
    test r12, r12
    jz .done

    ; Composite this output
    mov rdi, rbx
    mov rsi, r12
    call .composite_output

    mov r12, [r12 + Output.next]
    jmp .output_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; .composite_output - Composite single output
; ============================================================================
.composite_output:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi  ; compositor
    mov r12, rsi  ; output
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Get output framebuffer
    mov r15, [r12 + Output.framebuffer]
    test r15, r15
    jz .output_done

    ; Get damage region
    lea rdi, [r12 + OUTPUT_DAMAGE]
    call damage_get_rects

    ; Clear framebuffer to background
    mov rdi, rbx
    mov rsi, r12
    call .clear_output

    ; Iterate render list for this output
    mov r14, [rbx + Compositor.render_list]
    mov r13d, [r14]
    add r14, 8

.render_loop:
    test r13d, r13d
    jz .render_done

    ; Render entry
    mov rdi, r14
    mov rsi, r15
    call .render_entry
    add r14, RENDER_ENTRY_SIZE
    dec r13d
    jmp .render_loop

.render_done:
    ; Flip/output framebuffer
    mov rdi, r12
    call .flip_output

.output_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; .clear_output - Clear output to background color
; ============================================================================
.clear_output:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi  ; compositor
    mov r12, rsi  ; output
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov eax, [rbx + Compositor.bg_color]
    mov rdi, [r12 + Output.framebuffer]
    mov r13d, [r12 + Output.width]
    imul r13d, [r12 + Output.height]
    mov ecx, r13d
    rep stosd

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; .render_entry - Render single entry
; ============================================================================
.render_entry:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi  ; entry
    mov r12, rsi  ; output framebuffer
    ASSERT_PTR rbx

    mov r13, [rbx + RENDER_ENTRY_SURFACE]
    mov r14d, [rbx + RENDER_ENTRY_X]
    mov r15d, [rbx + RENDER_ENTRY_Y]
    mov r13d, [rbx + RENDER_ENTRY_Z]

    ; Get surface buffer
    mov r13, [rbx + RENDER_ENTRY_SURFACE]
    mov r13, [r13 + Surface.buffer]
    test r13, r13
    jz .entry_done

    ; Blit surface to output
    call .blit_surface

.entry_done:
    EPILOGUE_RESTORE rbx
    ret

.blit_surface:
    ; Blit surface buffer to output at position
    ; Using blit_copy with clipping
    ret

; ============================================================================
; .flip_output - Present framebuffer to display
; ============================================================================
.flip_output:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi  ; output
    ASSERT_PTR rbx

    ; Call backend flip
    mov rdi, [rbx + Output.backend]
    mov rsi, [rbx + Output.crtc_index]
    mov rdx, [rbx + Output.framebuffer]
    call backend_flip

    ; Schedule next vblank
    mov rdi, rbx
    add rdi, OUTPUT_FRAME_CLOCK
    call frame_clock_schedule_vblank

    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ============================================================================
; .build_render_list - Build render list from surfaces
; ============================================================================
.build_render_list:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rbx + Compositor.render_list]
    mov qword [r12], 0
    mov rdi, [rbx + Compositor.damage]
    lea rsi, [rel .append_surface]
    mov rdx, r12
    call zorder_iterate
    EPILOGUE_RESTORE rbx, r12
    ret

.append_surface:
    mov rax, [rsi]
    cmp rax, 1024
    jae .append_full
    imul rdx, rax, RENDER_ENTRY_SIZE
    lea rdx, [rsi + rdx + 8]
    mov [rdx + RENDER_ENTRY_SURFACE], rdi
    mov qword [rdx + RENDER_ENTRY_X], 0
    mov qword [rdx + RENDER_ENTRY_Y], 0
    mov dword [rdx + RENDER_ENTRY_Z], eax
    mov dword [rdx + RENDER_ENTRY_ALPHA], 0x3f800000
    mov qword [rdx + RENDER_ENTRY_TRANSFORM], 0
    mov qword [rdx + RENDER_ENTRY_CLIP], 0
    mov qword [rdx + RENDER_ENTRY_NEXT], 0
    inc qword [rsi]
    xor eax, eax
    ret
.append_full:
    mov rax, -(ENOSPC)
    ret

; ============================================================================
; compositor_set_cursor
;   Set cursor image and position
; ============================================================================
global compositor_set_cursor
compositor_set_cursor:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi  ; cursor*
    mov r13d, edx ; x
    mov r14d, ecx ; y
    ASSERT_PTR rbx

    mov [rbx + Compositor.cursor], r12
    mov dword [rbx + Compositor.cursor_x], r13d
    mov dword [rbx + Compositor.cursor_y], r14d

    ; Damage old and new cursor positions
    ; ...

    xor rax, rax
    leave
    ret

; ============================================================================
; compositor_move_cursor
;   Move cursor
; ============================================================================
global compositor_move_cursor
compositor_move_cursor:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov dword [rbx + Compositor.cursor_x], esi
    mov dword [rbx + Compositor.cursor_y], edx

    ; Damage old and new positions
    ; ...

    xor rax, rax
    leave
    ret

; ============================================================================
; compositor_set_background
;   Set background color
; ============================================================================
global compositor_set_background
compositor_set_background:
    PROLOGUE
    mov dword [rdi + Compositor.bg_color], esi
    xor rax, rax
    leave
    ret

section .data
global compositor_version
compositor_version: dq 0x010000
