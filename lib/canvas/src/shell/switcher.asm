; ============================================================================
; Switcher — Alt+Tab
; ============================================================================
; Alt+Tab takes the windows of the workspace shown, minimized ones too, in
; the order they last had the keyboard (Window.focus_seq), and selects the
; one before the current; each further Tab moves on, Esc gives up, letting go
; of Alt activates the one selected. While it runs the compositor draws it
; over everything (switcher_render): a tile per window, its title on it, the
; selected one bright. One seat, one switch at a time.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/render.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/ui_text.inc"

extern rect_intersect
extern region_add_rect
extern sw_render_rect
extern ui_text_draw
extern window_activate

%define SWITCHER_MAX    16
%define TILE_W          120
%define TILE_H          64
%define TILE_GAP        8
%define BOX_COLOR       0xFF181C28
%define TILE_COLOR      0xFF2C3248
%define SELECTED_COLOR  0xFF3E4C78
%define TITLE_COLOR     0xD0D4E0
%define TITLE_SIZE      13

section .text

; ---------------------------------------------------------------------------
; switcher_next
;   Alt+Tab: start, or move to the next window
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global switcher_next
switcher_next:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    cmp dword [rel active], 0
    je .start
    mov eax, [rel selected]             ; on to the next, round again
    inc eax
    xor edx, edx
    div dword [rel count]
    mov [rel selected], edx
    jmp .shown
.start:
    ; The workspace's windows, the latest to have the keyboard first
    mov dword [rel count], 0
    mov r12, [rbx + Server.windows]
.collect:
    test r12, r12
    jz .collected
    mov eax, [r12 + Window.workspace]
    cmp eax, [rbx + Server.workspace]
    jne .skip
    mov ecx, [rel count]
    cmp ecx, SWITCHER_MAX
    jae .collected
    ; insertion: later ones down until this one's place
    mov r13d, [r12 + Window.focus_seq]
    lea r14, [rel windows]
.place:
    test ecx, ecx
    jz .put
    mov rax, [r14 + rcx * 8 - 8]
    mov rax, [rax + Surface.window]
    cmp [rax + Window.focus_seq], r13d
    jae .put
    mov rax, [r14 + rcx * 8 - 8]
    mov [r14 + rcx * 8], rax
    dec ecx
    jmp .place
.put:
    mov rax, [r12 + Window.surface]
    mov [r14 + rcx * 8], rax
    inc dword [rel count]
.skip:
    mov r12, [r12 + Window.next]
    jmp .collect
.collected:
    cmp dword [rel count], 0
    je .out                             ; nothing to switch to
    mov dword [rel selected], 0
    cmp dword [rel count], 1
    je .one
    mov dword [rel selected], 1         ; the one before the current
.one:
    mov dword [rel active], 1
    mov [rel server_p], rbx
    call place_box
.shown:
    call damage_box
.out:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; switcher_finish
;   Alt let go: the window selected is activated
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global switcher_finish
switcher_finish:
    cmp dword [rel active], 0
    je .none
    push rbx
    mov rbx, rdi
    call switcher_cancel
    mov ecx, [rel selected]
    lea rax, [rel windows]
    mov rsi, [rax + rcx * 8]
    mov rdi, rbx
    call window_activate
    pop rbx
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; switcher_cancel
;   Esc: the switch ends, nothing changes
; ---------------------------------------------------------------------------
global switcher_cancel
switcher_cancel:
    cmp dword [rel active], 0
    je .none
    sub rsp, 8                          ; 16-byte aligned
    call damage_box
    mov dword [rel active], 0
    add rsp, 8
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; switcher_forget
;   A window going leaves the switch; with none left the switch ends
;   IN:  rdi = surface*
; ---------------------------------------------------------------------------
global switcher_forget
switcher_forget:
    cmp dword [rel active], 0
    je .none
    lea rax, [rel windows]
    xor ecx, ecx
.find:
    cmp ecx, [rel count]
    jae .none
    cmp [rax + rcx * 8], rdi
    je .found
    inc ecx
    jmp .find
.found:
    push rcx                            ; 16-byte aligned
    call damage_box                     ; it will be narrower
    pop rcx
    lea rax, [rel windows]
.close_up:
    mov edx, ecx
    inc edx
    cmp edx, [rel count]
    jae .closed
    mov r8, [rax + rdx * 8]
    mov [rax + rcx * 8], r8
    mov ecx, edx
    jmp .close_up
.closed:
    dec dword [rel count]
    jz .ended
    mov eax, [rel selected]
    cmp eax, [rel count]
    jb .placed
    mov dword [rel selected], 0
.placed:
    sub rsp, 8
    call place_box
    call damage_box
    add rsp, 8
    jmp .none
.ended:
    mov dword [rel active], 0
.none:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; switcher_selected
;   IN:  -
;   OUT: rax = the surface* selected, 0 when no switch is running
; ---------------------------------------------------------------------------
global switcher_selected
switcher_selected:
    xor eax, eax
    cmp dword [rel active], 0
    je .out
    mov ecx, [rel selected]
    lea rax, [rel windows]
    mov rax, [rax + rcx * 8]
.out:
    ret

; ---------------------------------------------------------------------------
; switcher_render
;   The switch over everything, inside a clip
;   IN:  rdi = frame context, rsi = clip rect*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global switcher_render
switcher_render:
    cmp dword [rel active], 0
    je .idle
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 32 + UiText_size           ; a tile, the clipped part, a title
    mov rbx, rdi
    mov r12, rsi
    mov rax, [rel output]
    cmp [rbx + FrameCtx.output], rax
    jne .out                            ; another output's frame
    lea rdi, [rel box]
    mov esi, BOX_COLOR
    call paint
    xor r13d, r13d
.tile:
    cmp r13d, [rel count]
    jae .out
    imul eax, r13d, TILE_W + TILE_GAP
    add eax, [rel box]
    add eax, TILE_GAP
    mov [rsp], eax
    mov eax, [rel box + 4]
    add eax, TILE_GAP
    mov [rsp + 4], eax
    mov dword [rsp + 8], TILE_W
    mov dword [rsp + 12], TILE_H
    mov esi, TILE_COLOR
    cmp r13d, [rel selected]
    jne .colour
    mov esi, SELECTED_COLOR
.colour:
    mov rdi, rsp
    call paint
    call title
    inc r13d
    jmp .tile
.out:
    add rsp, 32 + UiText_size
    EPILOGUE_RESTORE rbx, r12, r13, r14
.idle:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; The box: centred on the first output, a tile per window.
place_box:
    mov rax, [rel server_p]
    mov rax, [rax + Server.outputs]
    mov [rel output], rax
    test rax, rax
    jz .out
    imul ecx, dword [rel count], TILE_W + TILE_GAP
    add ecx, TILE_GAP
    mov [rel box + 8], ecx
    mov dword [rel box + 12], TILE_H + 2 * TILE_GAP
    mov edx, [rax + Output.width]
    sub edx, ecx
    sar edx, 1
    mov [rel box], edx
    mov edx, [rax + Output.height]
    sub edx, TILE_H + 2 * TILE_GAP
    sar edx, 1
    mov [rel box + 4], edx
.out:
    ret

; The box into its output's damage.
damage_box:
    mov rax, [rel output]
    test rax, rax
    jz .out
    mov rdi, [rax + Output.damage]
    lea rsi, [rel box]
    jmp region_add_rect
.out:
    ret

; A rectangle of one colour, the part inside the clip; switcher_render's
; frame: rbx = frame context, r12 = clip, the clipped part at its rsp + 16.
; rdi = rect, esi = colour
paint:
    push r14                            ; 16-byte aligned again
    mov r14d, esi
    mov rsi, rdi
    lea rdi, [rsp + 16 + 16]            ; past r14 and the return address
    mov rdx, r12
    call rect_intersect
    test rax, rax
    jnz .out
    mov rdi, rbx
    lea rsi, [rsp + 16 + 16]
    mov edx, r14d
    call sw_render_rect
.out:
    pop r14
    ret

; Tile r13's window's title on the tile at switcher_render's rsp; its UiText
; at that rsp + 32.
%define AT      (8 + 32)                ; past the return address
title:
    lea rax, [rel windows]
    mov rax, [rax + r13 * 8]
    mov rax, [rax + Surface.window]
    mov ecx, [rax + Window.title_len]
    test ecx, ecx
    jz .done
    lea rdx, [rsp + AT]
    mov [rdx + UiText.length], ecx
    lea rcx, [rax + Window.title]
    mov [rdx + UiText.text], rcx
    mov rax, [rbx + FrameCtx.framebuffer]
    mov [rdx + UiText.pixels], rax
    mov rax, [rbx + FrameCtx.stride]
    mov [rdx + UiText.stride], rax
    mov eax, [rsp + 8]                  ; the tile, less a margin
    add eax, TILE_GAP
    mov [rdx + UiText.x], eax
    mov eax, [rsp + 8 + 4]
    mov [rdx + UiText.y], eax
    mov dword [rdx + UiText.width], TILE_W - 2 * TILE_GAP
    mov dword [rdx + UiText.height], TILE_H
    mov eax, [r12]
    mov [rdx + UiText.clip_x], eax
    mov eax, [r12 + 4]
    mov [rdx + UiText.clip_y], eax
    mov eax, [r12 + 8]
    mov [rdx + UiText.clip_w], eax
    mov eax, [r12 + 12]
    mov [rdx + UiText.clip_h], eax
    mov dword [rdx + UiText.size], TITLE_SIZE
    mov dword [rdx + UiText.colour], TITLE_COLOR
    mov rdi, rdx
    sub rsp, 8                          ; 16-byte aligned
    call ui_text_draw
    add rsp, 8
.done:
    ret

section .bss
alignb 8
server_p:       resq 1
output:         resq 1                  ; where the box is drawn
windows:        resq SWITCHER_MAX       ; their surfaces, latest first
box:            resd 4                  ; x, y, width, height
active:         resd 1
selected:       resd 1
count:          resd 1
